import type { FunctionInvokeOptions } from '@supabase/supabase-js'
import { supabase } from '@/plugins/supabase'

type SupabaseFunctionResponse<T> = {
  data: T | null
  error: unknown | null
}

let refreshSessionPromise: Promise<boolean> | null = null

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object'
}

function getResponseStatus(error: unknown): number | undefined {
  if (error instanceof Response) return error.status
  if (!isRecord(error)) return undefined

  const context = error.context
  if (context instanceof Response) return context.status

  const status = error.status ?? error.statusCode
  return typeof status === 'number' ? status : undefined
}

async function refreshSessionOnce(): Promise<boolean> {
  if (!refreshSessionPromise) {
    refreshSessionPromise = supabase.auth
      .refreshSession()
      .then(({ error }) => !error)
      .catch(() => false)
      .finally(() => {
        refreshSessionPromise = null
      })
  }
  return refreshSessionPromise
}

/**
 * 调用需要登录态的 Edge Function；遇到过期访问令牌时只恢复一次会话并重试。
 * 多个页面同时初始化时共用同一个刷新 Promise，避免 refresh token 竞争。
 */
export async function invokeSupabaseFunctionWithSessionRecovery<T>(
  functionName: string,
  options: FunctionInvokeOptions = {}
): Promise<SupabaseFunctionResponse<T>> {
  const invoke = (): Promise<SupabaseFunctionResponse<T>> =>
    supabase.functions.invoke<T>(functionName, options)

  let response = await invoke()
  if (getResponseStatus(response.error) !== 401) return response
  if (!(await refreshSessionOnce())) return response

  response = await invoke()
  return response
}
