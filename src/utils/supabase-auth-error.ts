import { isAuthError } from '@supabase/supabase-js'

const AUTH_ERROR_MESSAGES: Record<string, string> = {
  user_banned: '账号已被禁用，请联系管理员',
  invalid_credentials: '邮箱或密码错误，请重新输入',
  user_not_found: '邮箱或密码错误，请重新输入',
  email_not_confirmed: '邮箱尚未验证，请先完成邮箱验证',
  captcha_failed: '人机验证失败，请重新验证',
  over_request_rate_limit: '登录尝试过于频繁，请稍后再试',
  request_timeout: '登录请求超时，请稍后重试',
  provider_disabled: '登录服务暂不可用，请联系管理员',
  email_provider_disabled: '邮箱登录暂不可用，请联系管理员',
  weak_password: '密码不符合安全要求，请按提示重新设置',
  same_password: '新密码不能与当前密码相同',
  reauthentication_needed: '身份验证已失效，请重新登录',
  reauthentication_not_valid: '身份验证已失效，请重新登录',
  session_expired: '登录状态已过期，请重新登录',
  session_not_found: '登录状态已失效，请重新登录',
  refresh_token_not_found: '登录状态已失效，请重新登录',
  refresh_token_already_used: '登录状态已失效，请重新登录',
  otp_expired: '验证链接或验证码已过期，请重新获取',
  email_address_invalid: '邮箱格式不正确',
  email_address_not_authorized: '当前邮箱不允许使用',
  signup_disabled: '系统暂未开放注册',
  user_already_exists: '该邮箱已经注册',
  email_exists: '该邮箱已经注册'
}

const AUTH_ERROR_NAME_MESSAGES: Record<string, string> = {
  AuthInvalidCredentialsError: '邮箱或密码错误，请重新输入',
  AuthRetryableFetchError: '认证服务连接失败，请检查网络后重试',
  AuthSessionMissingError: '登录状态已失效，请重新登录',
  AuthWeakPasswordError: '密码不符合安全要求，请按提示重新设置'
}

interface AuthErrorLike {
  code?: unknown
  name?: unknown
}

const toAuthErrorLike = (error: unknown): AuthErrorLike | undefined => {
  if (isAuthError(error)) return error
  return error !== null && typeof error === 'object' ? (error as AuthErrorLike) : undefined
}

export const getSupabaseAuthErrorMessage = (error: unknown): string => {
  const authError = toAuthErrorLike(error)
  const code = typeof authError?.code === 'string' ? authError.code : ''
  const name = typeof authError?.name === 'string' ? authError.name : ''

  return (
    AUTH_ERROR_MESSAGES[code] || AUTH_ERROR_NAME_MESSAGES[name] || '认证服务暂时不可用，请稍后重试'
  )
}
