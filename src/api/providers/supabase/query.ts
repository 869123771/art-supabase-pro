import type { ApiRequestOptions } from '@/types/api/request'

interface SupabaseQueryResponse {
  data?: unknown
  error?: unknown
  count?: number | null
  response?: {
    json?: () => Promise<unknown>
  }
}

export interface SupabaseQueryLike extends PromiseLike<SupabaseQueryResponse> {
  abortSignal(signal: AbortSignal): this
  eq(column: string, value: unknown): this
  gte(column: string, value: unknown): this
  in(column: string, values: readonly unknown[]): this
  limit(count: number): this
  lte(column: string, value: unknown): this
  neq(column: string, value: unknown): this
  not(column: string, operator: string, value: unknown): this
  or(filters: string): this
  order(column: string, options?: Record<string, unknown>): this
  range(from: number, to: number): this
}

export const withRequestOptions = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  options?: ApiRequestOptions
): TQuery => (options?.signal ? query.abortSignal(options.signal) : query)

export const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

interface DateRangeOptions {
  endOfDay?: boolean
  startOfDay?: boolean
}

export const applyDateRange = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  column: string,
  dateRange?: readonly string[],
  options: DateRangeOptions = {}
): TQuery => {
  const [startDate, endDate] = dateRange ?? []
  let nextQuery: SupabaseQueryLike = query

  if (startDate) {
    nextQuery = nextQuery.gte(column, options.startOfDay ? `${startDate}T00:00:00` : startDate)
  }
  if (endDate) {
    nextQuery = nextQuery.lte(column, options.endOfDay ? `${endDate}T23:59:59.999` : endDate)
  }

  return nextQuery as TQuery
}

export const applyCreateTimeRange = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  dateRange?: readonly string[]
): TQuery =>
  applyDateRange(query, 'create_time', dateRange, {
    startOfDay: true,
    endOfDay: true
  })
