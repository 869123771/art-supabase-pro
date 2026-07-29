interface SupabaseQueryResponse {
  data?: unknown
  error?: unknown
  count?: number | null
  response?: {
    json?: () => Promise<unknown>
  }
}

export interface SupabaseQueryLike extends PromiseLike<SupabaseQueryResponse> {
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

export const applyCreateTimeRange = (
  query: SupabaseQueryLike,
  dateRange?: string[]
): SupabaseQueryLike => {
  if (dateRange?.[0]) query = query.gte('create_time', `${dateRange[0]}T00:00:00`)
  if (dateRange?.[1]) query = query.lte('create_time', `${dateRange[1]}T23:59:59.999`)
  return query
}
