export type FilterValue = string | number | boolean | null | undefined | Array<string | number>

export type Filters = Record<string, FilterValue>

/**
 * Supabase / PostgREST 常用操作符全集
 */
export type Op =
  | 'eq'
  | 'neq'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'like'
  | 'ilike'
  | 'is'
  | 'in'
  | 'contains'
  | 'containedBy'
  | 'overlaps'
  | 'textSearch'

export type FilterSpec = {
  col: string
  op?: Op
  val: FilterValue
}

/** camelCase → snake_case */
export function camelToSnake(str: string) {
  return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}

/** shallow object camelCase → snake_case */
export function convertKeysToSnake<T extends Record<string, any>>(obj: T): Record<string, any> {
  const out: Record<string, any> = {}
  Object.entries(obj || {}).forEach(([k, v]) => {
    out[camelToSnake(k)] = v
  })
  return out
}

/** 内部使用：数组 specs 时转换 col */
function normalizeSpecArray(specs: FilterSpec[], camelToSnake: boolean): FilterSpec[] {
  if (!camelToSnake) return specs
  return specs.map((spec) => ({
    ...spec,
    col: camelToSnakeStr(spec.col)
  }))
}

/** Apply eq filters（保留你的原函数） */
export function applyEqFilters(
  query: any,
  filters: Filters,
  opts: { skipEmpty?: boolean; camelToSnake?: boolean } = {}
) {
  const { skipEmpty = true, camelToSnake: toSnake = true } = opts
  const useFilters = toSnake ? convertKeysToSnake(filters as any) : filters

  Object.entries(useFilters || {}).forEach(([col, val]) => {
    if (val === undefined || val === null) return
    if (skipEmpty && typeof val === 'string' && val.trim() === '') return
    query = query.eq(col, val)
  })

  return query
}

/** Op → Supabase Query 映射表（工程化核心） */
const opHandlers: Record<Op, (query: any, col: string, val: any) => any> = {
  eq: (q, c, v) => q.eq(c, v),
  neq: (q, c, v) => q.neq(c, v),
  gt: (q, c, v) => q.gt(c, v),
  gte: (q, c, v) => q.gte(c, v),
  lt: (q, c, v) => q.lt(c, v),
  lte: (q, c, v) => q.lte(c, v),
  like: (q, c, v) => q.like(c, String(v)),
  ilike: (q, c, v) => q.ilike(c, String(v)),
  is: (q, c, v) => q.is(c, v),
  in: (q, c, v) => q.in(c, Array.isArray(v) ? v : [v]),
  contains: (q, c, v) => q.contains(c, v),
  containedBy: (q, c, v) => q.containedBy(c, v),
  overlaps: (q, c, v) => q.overlaps(c, v),
  textSearch: (q, c, v) => q.textSearch(c, String(v))
}

/**
 * Apply filters（核心入口）
 */
export function applyFilters(
  query: any,
  specs: FilterSpec[] | Record<string, any>,
  opts: { skipEmpty?: boolean; camelToSnake?: boolean } = {}
) {
  const { skipEmpty = true, camelToSnake: toSnake = true } = opts

  let specArray: FilterSpec[] = []

  if (Array.isArray(specs)) {
    // ✅ 数组 specs 也支持 camelToSnake
    specArray = normalizeSpecArray(specs, toSnake)
  } else {
    const raw = toSnake ? convertKeysToSnake(specs as any) : (specs as Record<string, any>)
    specArray = Object.entries(raw).map(([col, payload]) => {
      if (payload && typeof payload === 'object' && ('op' in payload || 'val' in payload)) {
        return {
          col,
          op: payload.op as Op | undefined,
          val: payload.val
        }
      }
      return { col, op: 'eq', val: payload }
    })
  }

  specArray.forEach(({ col, op = 'eq', val }) => {
    if (val === undefined || val === null) return
    if (skipEmpty && typeof val === 'string' && val.trim() === '') return

    const handler = opHandlers[op] ?? opHandlers.eq
    query = handler(query, col, val)
  })

  return query
}

/**
 * 根据 filters + ops 生成 FilterSpec[]
 */
export function buildSpecsFromMap(
  filters: Filters,
  ops?: Record<string, Op>,
  camelToSnake = true
): FilterSpec[] {
  const snakeFilters = camelToSnake
    ? convertKeysToSnake(filters as any)
    : (filters as Record<string, any>)

  const snakeOps: Record<string, Op> = {}
  if (ops) {
    Object.entries(ops).forEach(([k, v]) => {
      const key = camelToSnake ? camelToSnakeStr(k) : k
      snakeOps[key] = v
    })
  }

  return Object.entries(snakeFilters).map(([col, val]) => ({
    col,
    op: snakeOps[col] ?? 'eq',
    val
  }))
}

/** 内部 snake 转换 */
function camelToSnakeStr(s: string) {
  return s.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}
