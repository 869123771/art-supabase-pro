import { useSupabase } from '@/hooks'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

export async function register(payload: Api.Auth.RegisterParams) {
  const invokeResp = (await supabase.functions.invoke('register-and-sync-user', {
    body: payload
  })) as any
  return await responseHandle(() => invokeResp, {
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
  const invokeResp = (await supabase.functions.invoke('check_user_status', {
    body: {
      email: params.email
    }
  })) as any
  await responseHandle(() => invokeResp, {
    ignoreCheck: true,
    breakReturn: true,
    showErrorMessage: true
  })
  return await responseHandle(
    () => supabase.auth.signInWithPassword(keysToSnakeDeep(params)) as any,
    {
      showMessage: true,
      message: '登录成功',
      ignoreCheck: true
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
    () => supabase.from('app_users').select('*').eq('auth_user_id', uid).single() as any,
    {
      ignoreCheck: true
    }
  )
}

export async function logout() {
  await supabase.auth.signOut()
}
