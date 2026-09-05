import { supabase } from '@/plugins/supabase'
import { isBoolean } from 'lodash-es'
import { ElMessage } from 'element-plus'
import type { QueryResult } from '@/types/api/response'
import {
  getFriendlySupabaseErrorMessage,
  isSupabaseSessionFailure,
  normalizeSupabaseFunctionError
} from '@/utils/supabase'
import {
  notifySupabaseSessionExpired,
  refreshSupabaseSessionOnce,
  SUPABASE_SESSION_EXPIRED_MESSAGE
} from '@/utils/supabase/session'

export type SupabaseAction = 'select' | 'insert' | 'update' | 'delete' | 'rpc'
export const WRITE_PERMISSION_DENIED_MESSAGE = '当前账号没有该数据的维护权限'

/**
 * Options for runQuery
 */
export interface RunQueryOptions {
  showMessage?: boolean // 是否显示提示，默认 false
  showErrorMessage?: boolean // 是否显示错误提示，默认 false
  convertToCamel?: boolean // 是否将返回字段从 snake_case 转为 camelCase，默认 true
  convertToCamelShadow?: boolean // 是否只转换最外层的驼峰命名，默认 false（深层转换）
  returnRawError?: boolean // 是否返回原生错误字段，默认 false
  message?: string
  errorMessage?: string // 未识别技术异常的用户友好兜底提示
  noAffectedMessage?: string
  formatErrorMessage?: (error: unknown, responseBody?: unknown) => string
  action?: SupabaseAction
  breakReturn?: boolean //打断返回
  requireAffected?: boolean // 写操作是否要求至少影响一行，用于识别 RLS 导致的 0 行更新/删除
  /** @deprecated Kept for API compatibility. Database authorization is enforced by Supabase RLS. */
  ignoreCheck?: boolean
}

/**
 * 标准返回类型
 */
interface QueryResponse {
  data?: unknown
  error?: unknown
  count?: number | null
  status?: number
  response?: {
    json?: () => Promise<unknown>
  }
}

type QueryFactory = () => PromiseLike<QueryResponse>

export function useSupabase() {
  /** convert snake_case string to camelCase */
  const toCamel = (s: string) => s.replace(/_([a-z0-9])/g, (_, c) => (c ? c.toUpperCase() : ''))

  /** convert camelCase or PascalCase to snake_case */
  const toSnake = (s: string) =>
    s
      .replace(/([A-Z])/g, '_$1')
      .replace(/^_/, '')
      .toLowerCase()

  function isPlainObject(x: unknown): x is Record<string, unknown> {
    return x !== null && typeof x === 'object' && x.constructor === Object
  }

  // Key conversion preserves values but TypeScript cannot derive the transformed key shape.
  // Keep the unavoidable generic assertion at this single serialization boundary.
  function asKeyTransformResult<T>(value: unknown): T {
    return value as T
  }

  /** Recursively convert object keys to camelCase */
  function keysToCamelDeep<T>(obj: unknown): T {
    if (Array.isArray(obj)) {
      return asKeyTransformResult<T>(obj.map(keysToCamelDeep))
    }
    if (isPlainObject(obj)) {
      const res: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toCamel(k)] = keysToCamelDeep(v)
      }
      return asKeyTransformResult<T>(res)
    }
    return asKeyTransformResult<T>(obj)
  }

  /** Only convert top-level object keys to camelCase */
  function keysToCamelShallow<T>(obj: unknown): T {
    if (Array.isArray(obj)) {
      return asKeyTransformResult<T>(obj)
    }
    if (isPlainObject(obj)) {
      const res: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toCamel(k)] = v
      }
      return asKeyTransformResult<T>(res)
    }
    return asKeyTransformResult<T>(obj)
  }

  /** Recursively convert object keys to snake_case */
  function keysToSnakeDeep<T>(obj: T): T {
    if (Array.isArray(obj)) {
      return asKeyTransformResult<T>(obj.map(keysToSnakeDeep))
    }
    if (isPlainObject(obj)) {
      const res: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toSnake(k)] = keysToSnakeDeep(v)
      }
      return asKeyTransformResult<T>(res)
    }
    return asKeyTransformResult<T>(obj)
  }

  /**
   * 通用 query wrapper：可单独导入使用
   * 用法：
   *   import { runQuery } from '@/composables/useSupabase'
   *   const { data, error } = await runQuery<MyType[]>(supabase.from('sys_user').select(), { showMessage: true })
   */

  async function responseHandle<T = unknown>(
    queryFactory: QueryFactory,
    options: RunQueryOptions = {
      showMessage: false,
      showErrorMessage: false,
      convertToCamel: true,
      convertToCamelShadow: false,
      returnRawError: false,
      breakReturn: false,
      requireAffected: false,
      ignoreCheck: false
    }
  ): Promise<QueryResult<T>> {
    const {
      showMessage = false,
      showErrorMessage = false,
      breakReturn = false,
      convertToCamel = true,
      convertToCamelShadow = false,
      returnRawError = false,
      requireAffected = false,
      ignoreCheck = false
    } = options ?? {}
    // Frontend checks are not an authorization boundary. Supabase RLS owns data access control.
    void ignoreCheck

    let queryResponse = await queryFactory()
    let sessionFailure = isSupabaseSessionFailure(queryResponse, queryResponse.error)
    let sessionFailureHandled = false

    if (sessionFailure) {
      const refreshedSession = await refreshSupabaseSessionOnce()
      if (refreshedSession) {
        queryResponse = await queryFactory()
        sessionFailure = isSupabaseSessionFailure(queryResponse, queryResponse.error)
      }

      if (sessionFailure) {
        sessionFailureHandled = await notifySupabaseSessionExpired()
      }
    }

    const { data, error, count, response } = queryResponse
    if (error) {
      let responseJson: unknown
      try {
        responseJson = await response?.json?.()
      } catch {
        // 部分 SDK 响应体已被消费；继续从异常 context 中读取。
      }
      const normalizedError = await normalizeSupabaseFunctionError(error)
      const responseBody = responseJson ?? (normalizedError !== error ? normalizedError : undefined)
      const responseError = isPlainObject(responseBody) ? responseBody : undefined
      const queryError = isPlainObject(error) ? error : undefined
      const message = sessionFailure
        ? SUPABASE_SESSION_EXPIRED_MESSAGE
        : options.formatErrorMessage?.(error, responseBody) ||
          getFriendlySupabaseErrorMessage(
            [responseError, queryError, normalizedError, error],
            options.errorMessage
          )
      if ((showMessage || showErrorMessage) && !sessionFailureHandled) {
        ElMessage.error(message)
      }
      if (breakReturn) {
        throw new Error(message, { cause: error })
      }
      return {
        data: null,
        error: returnRawError && responseBody ? keysToCamelDeep(responseBody) : normalizedError
      }
    }

    if (requireAffected && count === 0) {
      const message = options.noAffectedMessage || '当前账号没有权限操作该数据，或数据不存在'
      if (showMessage || showErrorMessage) {
        ElMessage.error(message)
      }
      if (breakReturn) {
        throw new Error(message)
      }
      return {
        data: null,
        error: new Error(message)
      }
    }

    if (showMessage) {
      ElMessage.closeAll()
      ElMessage.success(options.message || '操作成功')
    }
    let out: T
    if (isBoolean(convertToCamel) && !convertToCamel) {
      out = data as T
    } else if (convertToCamelShadow) {
      out = keysToCamelShallow<T>(data)
    } else {
      out = keysToCamelDeep<T>(data)
    }
    return { data: out, total: count ?? 0, error: null }
  }

  return {
    supabase,
    responseHandle,
    keysToCamelDeep,
    keysToSnakeDeep
  }
}
