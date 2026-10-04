import type { QueryResult } from '@/types/api/response'

export interface SupabaseRange {
  from: number
  to: number
}

interface FetchAllRangePagesOptions {
  pageSize?: number
}

const DEFAULT_PAGE_SIZE = 500

/** Keep inclusive RPC bounds ordered after clamping the offset to zero. */
export function buildSupabaseRpcRange(from: number, to: number): { p_from: number; p_to: number } {
  if (!Number.isSafeInteger(from) || !Number.isSafeInteger(to)) {
    throw new RangeError('分页范围无效，请刷新后重试')
  }
  const start = Math.max(from, 0)
  return { p_from: start, p_to: Math.max(to, start) }
}

export async function fetchAllRangePages<T>(
  fetchPage: (range: SupabaseRange) => Promise<QueryResult<T[]>>,
  options: FetchAllRangePagesOptions = {}
): Promise<QueryResult<T[]>> {
  const pageSize = options.pageSize ?? DEFAULT_PAGE_SIZE

  if (!Number.isSafeInteger(pageSize) || pageSize < 1) {
    throw new RangeError('Supabase 分页大小必须是正整数')
  }

  const rows: T[] = []

  for (let from = 0; ; from += pageSize) {
    const page = await fetchPage({ from, to: from + pageSize - 1 })

    if (page.error) {
      return { data: null, error: page.error, total: rows.length }
    }
    if (!page.data) {
      return {
        data: null,
        error: new Error('分页查询未返回数据，请稍后重试'),
        total: rows.length
      }
    }

    for (const row of page.data) rows.push(row)

    if (page.data.length < pageSize) {
      return { data: rows, error: null, total: rows.length }
    }
  }
}
