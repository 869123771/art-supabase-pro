import { supabase } from '@/plugins/supabase'
import { isBoolean } from 'lodash-es'
import { ElMessage } from 'element-plus'

export type SupabaseAction = 'select' | 'insert' | 'update' | 'delete' | 'rpc'

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
  action?: SupabaseAction
  breakReturn?: boolean //打断返回
  ignoreCheck?: boolean // 👈 是否忽略检查当前角色有写入权限 默认insert update delete 都检查，查询忽略
}

/**
 * 标准返回类型
 */
export type QueryResult<T> = {
  data: T | null
  error: unknown | null
  total?: number
}

type QueryFactory<T> = () => Promise<Api.Common.PaginatedResponse>

export function useSupabase() {
  /** convert snake_case string to camelCase */
  const toCamel = (s: string) => s.replace(/_([a-z0-9])/g, (_, c) => (c ? c.toUpperCase() : ''))

  /** convert camelCase or PascalCase to snake_case */
  const toSnake = (s: string) =>
    s
      .replace(/([A-Z])/g, '_$1')
      .replace(/^_/, '')
      .toLowerCase()

  function isPlainObject(x: any): x is Record<string, any> {
    return x !== null && typeof x === 'object' && x.constructor === Object
  }

  /** Recursively convert object keys to camelCase */
  function keysToCamelDeep<T = any>(obj: any): T {
    if (Array.isArray(obj)) {
      return obj.map(keysToCamelDeep) as unknown as T
    }
    if (isPlainObject(obj)) {
      const res: Record<string, any> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toCamel(k)] = keysToCamelDeep(v)
      }
      return res as T
    }
    return obj as T
  }

  /** Only convert top-level object keys to camelCase */
  function keysToCamelShallow<T = any>(obj: any): T {
    if (Array.isArray(obj)) {
      return obj as unknown as T
    }
    if (isPlainObject(obj)) {
      const res: Record<string, any> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toCamel(k)] = v
      }
      return res as T
    }
    return obj as T
  }

  /** Recursively convert object keys to snake_case */
  function keysToSnakeDeep<T = any>(obj: any): T {
    if (Array.isArray(obj)) {
      return obj.map(keysToSnakeDeep) as unknown as T
    }
    if (isPlainObject(obj)) {
      const res: Record<string, any> = {}
      for (const [k, v] of Object.entries(obj)) {
        res[toSnake(k)] = keysToSnakeDeep(v)
      }
      return res as T
    }
    return obj as T
  }

  /**
   * 通用 query wrapper：可单独导入使用
   * 用法：
   *   import { runQuery } from '@/composables/useSupabase'
   *   const { data, error } = await runQuery<MyType[]>(supabase.from('app_users').select(), { showMessage: true })
   */

  async function responseHandle<T = any>(
    queryFactory: QueryFactory<T>,
    options: RunQueryOptions = {
      showMessage: false,
      showErrorMessage: false,
      convertToCamel: true,
      convertToCamelShadow: false,
      returnRawError: false,
      breakReturn: false,
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
      ignoreCheck = false
    } = options ?? {}
    //对用户角色 | 用户邮箱检查是否有写入权限
    if (!ignoreCheck) {
    }

    const { data, error, count, response } = await queryFactory()
    if (error) {
      const responseJson = await response?.json?.()
      const message = String(
        (responseJson?.error || (error as any)?.message) ?? JSON.stringify(error)
      )
      if (showMessage || showErrorMessage) {
        ElMessage.error(message)
      }
      if (breakReturn) {
        throw new Error(message)
      }
      return {
        data: null,
        error: returnRawError && responseJson ? keysToCamelDeep(responseJson) : error
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
    keysToSnakeDeep
  }
}
