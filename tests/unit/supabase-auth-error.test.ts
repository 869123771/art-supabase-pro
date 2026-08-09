import assert from 'node:assert/strict'
import test from 'node:test'
import { AuthApiError, AuthRetryableFetchError } from '@supabase/supabase-js'
import { getSupabaseAuthErrorMessage } from '../../src/utils/supabase-auth-error'

test('translates a banned Supabase Auth user into a clear Chinese message', () => {
  const error = new AuthApiError('User is banned', 400, 'user_banned')

  assert.equal(getSupabaseAuthErrorMessage(error), '账号已被禁用，请联系管理员')
})

test('does not reveal whether an account exists for invalid login credentials', () => {
  const error = new AuthApiError('Invalid login credentials', 400, 'invalid_credentials')

  assert.equal(getSupabaseAuthErrorMessage(error), '邮箱或密码错误，请重新输入')
})

test('returns a Chinese message for retryable authentication failures', () => {
  const error = new AuthRetryableFetchError('fetch failed', 503)

  assert.equal(getSupabaseAuthErrorMessage(error), '认证服务连接失败，请检查网络后重试')
})

test('uses a safe Chinese fallback for unknown authentication errors', () => {
  assert.equal(
    getSupabaseAuthErrorMessage({ code: 'future_auth_error' }),
    '认证服务暂时不可用，请稍后重试'
  )
})
