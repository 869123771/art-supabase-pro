import assert from 'node:assert/strict'
import test from 'node:test'
import { AuthApiError, AuthRetryableFetchError } from '@supabase/supabase-js'
import {
  formatSupabaseAuthErrorMessage,
  getFriendlySupabaseErrorMessage,
  normalizeSupabaseFunctionError
} from '../../src/utils/supabase'

class AuthApiErrorFixture extends Error {
  code = 'invalid_credentials'
  status = 400
}

test('converts AuthApiError class instances into a friendly login message', () => {
  const error = new AuthApiErrorFixture('Invalid login credentials')

  assert.equal(getFriendlySupabaseErrorMessage(error), '邮箱或密码错误，请重新输入')
})

test('uses stable Supabase and Postgres error codes before technical messages', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage({ code: '23505', message: 'duplicate key value' }),
    '相同数据已存在，请勿重复提交'
  )
  assert.equal(
    getFriendlySupabaseErrorMessage({ code: '42501', message: 'permission denied' }),
    '当前账号没有此操作权限'
  )
  assert.equal(
    getFriendlySupabaseErrorMessage({ code: '23503', message: 'foreign key violation' }),
    '该数据正在被其他业务使用，暂时不能修改或删除'
  )
})

test('parses serialized errors without exposing JSON to the user', () => {
  const error = JSON.stringify({
    name: 'AuthApiError',
    message: 'Invalid login credentials',
    status: 400,
    code: 'invalid_credentials'
  })

  assert.equal(getFriendlySupabaseErrorMessage(error), '邮箱或密码错误，请重新输入')
})

test('preserves an existing Chinese business error', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage({ message: '该车辆已关联运单，暂时不能删除' }),
    '该车辆已关联运单，暂时不能删除'
  )
})

test('hides unknown English implementation details behind the caller fallback', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage(
      new Error('Unexpected internal provider response'),
      '登录失败，请稍后重试'
    ),
    '登录失败，请稍后重试'
  )
})

test('converts common network failures into actionable guidance', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage(new TypeError('Failed to fetch')),
    '网络连接异常，请检查网络后重试'
  )
})

test('keeps the existing friendly messages for Supabase Auth error classes', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage(new AuthApiError('User is banned', 400, 'user_banned')),
    '账号已被禁用，请联系管理员'
  )
  assert.equal(
    getFriendlySupabaseErrorMessage(new AuthRetryableFetchError('fetch failed', 503)),
    '认证服务连接失败，请检查网络后重试'
  )
  assert.equal(
    formatSupabaseAuthErrorMessage({ code: 'future_auth_error' }),
    '认证服务暂时不可用，请稍后重试'
  )
})

test('normalizes an Edge Function response body before creating the user message', async () => {
  const rawError = {
    name: 'FunctionsHttpError',
    message: 'Edge Function returned a non-2xx status code',
    context: new Response(
      JSON.stringify({ code: 'BUSINESS_BLOCKED', message: '当前记录不允许提交' }),
      {
        status: 409,
        headers: { 'content-type': 'application/json' }
      }
    )
  }

  const normalized = await normalizeSupabaseFunctionError(rawError)

  assert.equal(getFriendlySupabaseErrorMessage(normalized), '当前记录不允许提交')
})

test('does not expose long or technical Chinese provider details', () => {
  assert.equal(
    getFriendlySupabaseErrorMessage(
      { message: 'Supabase SQLSTATE 42P01：relation sys_user 不存在，select * from sys_user' },
      '数据加载失败，请稍后重试'
    ),
    '数据加载失败，请稍后重试'
  )
})
