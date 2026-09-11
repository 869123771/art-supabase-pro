/**
 * 表格工具函数模块
 *
 * 提供表格数据处理和请求管理的核心工具函数
 *
 * ## 主要功能
 *
 * - 多格式 API 响应自动适配和标准化
 * - 表格数据提取和转换
 * - 分页信息自动更新和校验
 * - 智能防抖函数（支持取消和立即执行）
 * - 统一的错误处理机制
 * - 嵌套数据结构解析
 *
 * ## 使用场景
 *
 * - useTable 组合式函数的底层工具
 * - 适配各种后端接口响应格式
 * - 表格数据的标准化处理
 * - 请求防抖和性能优化
 * - 错误统一处理和日志记录
 *
 * ## 支持的响应格式
 *
 * 1. 直接数组: [item1, item2, ...]
 * 2. 标准对象: { records: [], total: 100 }
 * 3. 嵌套data: { data: { list: [], total: 100 } }
 * 4. 多种字段名: list/data/records/items/result/rows
 *
 * ## 核心功能
 *
 * - defaultResponseAdapter: 智能识别和转换响应格式
 * - extractTableData: 提取表格数据数组
 * - updatePaginationFromResponse: 更新分页信息
 * - createSmartDebounce: 创建可控的防抖函数
 * - createErrorHandler: 生成错误处理器
 *
 * @module utils/table/tableUtils
 * @author Art Design Pro Team
 */

import { debounce } from 'lodash-es'
import type { ApiResponse } from './tableCache'
import { tableConfig } from './tableConfig'

// 请求参数基础接口，扩展分页参数
export interface BaseRequestParams extends Api.Common.PaginationParams {
  [key: string]: unknown
}

// 错误处理接口
export interface TableError {
  code: string
  message: string
  details?: unknown
}

// Empty arrays are valid results; absence is represented separately.
function extractRecords<T>(obj: Record<string, unknown>): T[] | undefined {
  for (const field of tableConfig.recordFields) {
    if (Array.isArray(obj[field])) return obj[field] as T[]
  }
}

function extractNumber(
  sources: Record<string, unknown>[],
  fields: string[],
  minimum: number
): number | undefined {
  for (const source of sources) {
    for (const field of fields) {
      const value = source[field]
      if (typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum) {
        return value
      }
    }
  }
}

/** Normalize supported list envelopes with one field policy at both levels. */
export const defaultResponseAdapter = <T>(response: unknown): ApiResponse<T> => {
  if (Array.isArray(response)) return { records: response, total: response.length }
  if (!response || typeof response !== 'object') return { records: [], total: 0 }

  const outer = response as Record<string, unknown>
  const direct = extractRecords<T>(outer)
  const nested =
    outer.data && typeof outer.data === 'object' && !Array.isArray(outer.data)
      ? (outer.data as Record<string, unknown>)
      : undefined
  const source = direct === undefined && nested ? nested : outer
  const records = direct ?? extractRecords<T>(source) ?? []
  const sources = source === outer ? [outer] : [source, outer]
  const result: ApiResponse<T> = {
    records,
    total: extractNumber(sources, tableConfig.totalFields, 0) ?? records.length
  }
  // Envelope pagination wins over nested pagination, preserving the public contract.
  const paginationSources = source === outer ? [outer] : [outer, source]
  const current = extractNumber(paginationSources, tableConfig.currentFields, 1)
  const size = extractNumber(paginationSources, tableConfig.sizeFields, 1)
  if (current !== undefined) result.current = current
  if (size !== undefined) result.size = size
  return result
}

/**
 * 从标准化的API响应中提取表格数据
 */
export const extractTableData = <T>(response: ApiResponse<T>): T[] => {
  const data = response.records || response.data || []
  return Array.isArray(data) ? data : []
}

/**
 * 根据API响应更新分页信息
 */
export const updatePaginationFromResponse = <T>(
  pagination: Api.Common.PaginationParams,
  response: ApiResponse<T>
): void => {
  pagination.total = response.total ?? pagination.total ?? 0

  if (response.current !== undefined) {
    pagination.current = response.current
  }

  const maxPage = Math.max(1, Math.ceil(pagination.total / (pagination.size || 1)))
  if (pagination.current > maxPage) {
    pagination.current = maxPage
  }
}

/**
 * 合并等待中的调用，全部返回最后一组参数的执行结果。
 * cancel 以 undefined 结束尚未执行的调用；已开始的请求不受影响。
 * flush 立即执行等待批次，业务失败仍以原始错误拒绝。
 */
export const createSmartDebounce = <TArgs extends unknown[], TResult>(
  fn: (...args: TArgs) => Promise<TResult>,
  delay: number
): ((...args: TArgs) => Promise<TResult | void>) & {
  cancel: () => void
  flush: () => Promise<TResult | void>
} => {
  type Waiter = {
    resolve: (value: TResult | void) => void
    reject: (reason: unknown) => void
  }
  let pending: Waiter[] = []

  const execute = async (args: TArgs): Promise<TResult> => {
    // Detach before awaiting: an older request must never clear a newer batch.
    const batch = pending
    pending = []
    try {
      const result = await fn(...args)
      batch.forEach(({ resolve }) => resolve(result))
      return result
    } catch (error) {
      batch.forEach(({ reject }) => reject(error))
      throw error
    }
  }
  const scheduled = debounce((args: TArgs) => {
    const execution = execute(args)
    // Timer callbacks have no consumer; callers and flush still receive the rejection.
    void execution.catch(() => {})
    return execution
  }, delay)

  const debouncedFn = (...args: TArgs): Promise<TResult | void> =>
    new Promise((resolve, reject) => {
      pending.push({ resolve, reject })
      scheduled(args)
    })

  debouncedFn.cancel = (): void => {
    scheduled.cancel()
    const batch = pending
    pending = []
    batch.forEach(({ resolve }) => resolve())
  }
  debouncedFn.flush = async (): Promise<TResult | void> => {
    if (pending.length) return scheduled.flush()
  }
  return debouncedFn
}

/**
 * 生成错误处理函数
 */
export const createErrorHandler = (
  onError?: (error: TableError) => void,
  enableLog: boolean = false
) => {
  const logger = {
    error: (message: string, ...args: unknown[]) => {
      if (enableLog) console.error(`[useTable] ${message}`, ...args)
    }
  }

  return (err: unknown, context: string): TableError => {
    const tableError: TableError = {
      code: 'UNKNOWN_ERROR',
      message: '未知错误',
      details: err
    }

    if (err instanceof Error) {
      tableError.message = err.message
      tableError.code = err.name
    } else if (typeof err === 'string') {
      tableError.message = err
    }

    logger.error(`${context}:`, err)
    onError?.(tableError)
    return tableError
  }
}

/**
 * 适配 supabase 分页数据
 */
export const pageInfoHandler = (page: { current: number; size: number }) => {
  const { current, size } = page
  return {
    from: (current - 1) * size,
    to: current * size - 1
  }
}
