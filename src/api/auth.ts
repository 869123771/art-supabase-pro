import { useSupabase } from '@/hooks'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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
  return await responseHandle(
    () =>
      supabase.auth.signInWithPassword({
        email,
        password,
        options: captchaToken ? { captchaToken } : undefined
      }),
    {
      showMessage: true,
      message: '登录成功',
      ignoreCheck: true
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
      showErrorMessage: true
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
      showErrorMessage: true
    }
  )
}

/**
 * 获取用户信息
 * @returns 用户信息
 */
export async function fetchGetUserInfo() {
  const session = await supabase.auth.getSession()
  const uid = session?.data?.session?.user?.id

  return await responseHandle(
    () =>
      supabase
        .from('sys_user')
        .select('*, tenant:sys_tenant!sys_user_tenant_id_fkey(tenant_code, tenant_name)')
        .eq('auth_user_id', uid)
        .single(),
    {
      ignoreCheck: true
    }
  )
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
      ignoreCheck: true
    }
  )

  return await responseHandle(() => supabase.auth.updateUser({ password: newPassword }), {
    showMessage: true,
    message: '密码修改成功',
    breakReturn: true,
    ignoreCheck: true
  })
}

export async function logout() {
  await supabase.auth.signOut()
}
