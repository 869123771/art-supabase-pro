import { useSupabase } from '@/hooks'
import { formatSupabaseAuthErrorMessage } from '@/utils/supabase'
import type { QueryResult } from '@/types/api/response'
import { isAuthError, isAuthSessionMissingError } from '@supabase/supabase-js'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

interface AuthSessionResponse {
  session: {
    accessToken?: string
    refreshToken?: string
  } | null
}

interface CurrentAuthTokens {
  accessToken: string
  refreshToken: string
}

export type CurrentAuthSessionRecovery =
  ({ status: 'valid' } & CurrentAuthTokens) | { status: 'expired' }

interface CurrentUserInfoResult extends QueryResult<Api.SystemManage.UserListItem> {
  session: CurrentAuthTokens
}

const EXPIRED_AUTH_ERROR_CODES = new Set([
  'bad_jwt',
  'refresh_token_already_used',
  'refresh_token_not_found',
  'session_not_found'
])

function isExpiredAuthSessionError(error: unknown): boolean {
  if (isAuthSessionMissingError(error)) return true
  if (!isAuthError(error)) return false

  return (
    error.status === 401 ||
    error.status === 403 ||
    (typeof error.code === 'string' && EXPIRED_AUTH_ERROR_CODES.has(error.code))
  )
}

/**
 * 验证并刷新浏览器中的 Supabase 会话。
 *
 * 仅把明确缺失、过期或无效的凭证判定为 expired；网络及服务异常继续抛出，
 * 避免因为临时故障误退出仍然有效的账号。
 */
export async function recoverCurrentAuthSession(): Promise<CurrentAuthSessionRecovery> {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession()
  if (sessionError) {
    if (isExpiredAuthSessionError(sessionError)) return { status: 'expired' }
    throw new Error('登录状态检查失败', { cause: sessionError })
  }
  if (!sessionData.session) return { status: 'expired' }

  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims()
  if (claimsError) {
    if (isExpiredAuthSessionError(claimsError)) return { status: 'expired' }
    throw new Error('登录身份验证失败', { cause: claimsError })
  }
  if (!claimsData?.claims.sub) return { status: 'expired' }

  const { data: refreshedSessionData, error: refreshedSessionError } =
    await supabase.auth.getSession()
  if (refreshedSessionError) {
    if (isExpiredAuthSessionError(refreshedSessionError)) return { status: 'expired' }
    throw new Error('登录状态刷新失败', { cause: refreshedSessionError })
  }
  if (!refreshedSessionData.session) return { status: 'expired' }

  return {
    status: 'valid',
    accessToken: refreshedSessionData.session.access_token,
    refreshToken: refreshedSessionData.session.refresh_token
  }
}

export async function register(payload: Api.Auth.RegisterParams) {
  const invokeResp = () =>
    supabase.functions.invoke('register-and-sync-user', {
      body: payload
    })
  return await responseHandle(invokeResp, {
    showMessage: true,
    message: '注册成功,请前往登录',
    ignoreCheck: true
  })
}
/**
 * 登录
 * @param params 登录参数
 * @returns 登录响应
 */
export async function login(params: Api.Auth.RegisterParams) {
  const { email, password, captchaToken } = params
  const invokeResp = () =>
    supabase.functions.invoke('check_user_status', {
      body: {
        email
      }
    })
  await responseHandle(invokeResp, {
    ignoreCheck: true,
    breakReturn: true,
    showErrorMessage: true
  })
  return await responseHandle<AuthSessionResponse>(
    () =>
      supabase.auth.signInWithPassword({
        email,
        password,
        options: captchaToken ? { captchaToken } : undefined
      }),
    {
      showMessage: true,
      message: '登录成功',
      ignoreCheck: true,
      formatErrorMessage: formatSupabaseAuthErrorMessage
    }
  )
}

/*忘记密码*/
export async function forgetPassword(params: Api.Auth.ForgetPwdParams) {
  const { email, redirectTo } = params
  return await responseHandle(
    () =>
      supabase.auth.resetPasswordForEmail(email, {
        redirectTo
      }),
    {
      ignoreCheck: true,
      breakReturn: true,
      showErrorMessage: true,
      formatErrorMessage: formatSupabaseAuthErrorMessage
    }
  )
}

/*重置密码*/
export async function resetPassword(params: Api.Auth.ResetPwdParams) {
  const { password, accessToken, refreshToken } = params

  // 设置访问 token
  await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken || ''
  })

  return await responseHandle(
    () =>
      supabase.auth.updateUser({
        password
      }),
    {
      ignoreCheck: true,
      breakReturn: true,
      showErrorMessage: true,
      formatErrorMessage: formatSupabaseAuthErrorMessage
    }
  )
}

/**
 * 获取用户信息
 * @returns 用户信息
 */
export async function fetchGetUserInfo(signal?: AbortSignal): Promise<CurrentUserInfoResult> {
  // 让 Supabase 从自身会话中取令牌，以便 SDK 在验证前自动刷新即将过期的会话。
  // 显式传入 Pinia 中持久化的 JWT 会跳过这个刷新步骤，导致刷新页面后误进 500。
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims()
  if (claimsError || !claimsData) {
    throw new Error('当前登录身份校验失败', { cause: claimsError })
  }

  const uid = claimsData.claims.sub
  if (!uid) {
    throw new Error('当前登录身份缺少用户标识')
  }

  const { data: sessionData, error: sessionError } = await supabase.auth.getSession()
  if (sessionError || !sessionData.session) {
    throw new Error('当前登录会话已失效', { cause: sessionError })
  }

  const profileQueryBuilder = supabase
    .from('sys_user')
    .select('*, tenant:sys_tenant!sys_user_tenant_id_fkey(tenant_code, tenant_name, builtin_type)')
    .eq('auth_user_id', uid)
    .is('deleted_at', null)
  const profileQuery = (
    signal ? profileQueryBuilder.abortSignal(signal) : profileQueryBuilder
  ).single()
  const superQuery = supabase.rpc('current_is_super')

  const [profileResult, superResult] = await Promise.all([
    responseHandle<Api.SystemManage.UserListItem>(() => profileQuery, {
      ignoreCheck: true
    }),
    responseHandle<boolean>(() => (signal ? superQuery.abortSignal(signal) : superQuery), {
      ignoreCheck: true
    })
  ])

  if (profileResult.data && typeof superResult.data === 'boolean') {
    Object.assign(profileResult.data, { platformSuper: superResult.data })
  }

  return {
    ...profileResult,
    session: {
      accessToken: sessionData.session.access_token,
      refreshToken: sessionData.session.refresh_token
    }
  }
}

export async function updateCurrentUserProfile(params: Api.Auth.UserInfo) {
  const { userId, ...rest } = params
  return await responseHandle(
    () =>
      supabase.from('sys_user').update(keysToSnakeDeep(rest), { count: 'exact' }).eq('id', userId),
    {
      showMessage: true,
      message: '个人资料保存成功',
      breakReturn: true,
      requireAffected: true,
      ignoreCheck: true
    }
  )
}

export async function updateCurrentUserPassword(currentPassword: string, newPassword: string) {
  const session = await supabase.auth.getSession()
  const email = session.data.session?.user.email
  if (!email) throw new Error('当前账号未绑定登录邮箱')

  await responseHandle(
    () => supabase.auth.signInWithPassword({ email, password: currentPassword }),
    {
      showErrorMessage: true,
      breakReturn: true,
      ignoreCheck: true,
      formatErrorMessage: formatSupabaseAuthErrorMessage
    }
  )

  return await responseHandle(() => supabase.auth.updateUser({ password: newPassword }), {
    showMessage: true,
    message: '密码修改成功',
    breakReturn: true,
    ignoreCheck: true,
    formatErrorMessage: formatSupabaseAuthErrorMessage
  })
}

export async function logout() {
  await supabase.auth.signOut()
}
