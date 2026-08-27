import type { QueryResult } from '@/types/api/response'

export interface SupabaseRange {
  from: number
  to: number
}

interface FetchAllRangePagesOptions {
  pageSize?: number
}

const DEFAULT_PAGE_SIZE = 500

export async function fetchAllRangePages<T>(
  fetchPage: (range: SupabaseRange) => Promise<QueryResult<T[]>>,
  options: FetchAllRangePagesOptions = {}
): Promise<QueryResult<T[]>> {
  const pageSize = options.pageSize ?? DEFAULT_PAGE_SIZE

  if (!Number.isInteger(pageSize) || pageSize < 1) {
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

    rows.push(...page.data)

    if (page.data.length < pageSize) {
      return { data: rows, error: null, total: rows.length }
    }
  }
}
