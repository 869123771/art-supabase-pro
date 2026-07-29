export type FilterValue = string | number | boolean | null | undefined | Array<string | number>

export type Filters = Record<string, FilterValue>
type FilterPayload = FilterValue | { op?: Op; val?: FilterValue }

interface FilterQueryLike {
  containedBy(column: string, value: unknown): this
  contains(column: string, value: unknown): this
  eq(column: string, value: unknown): this
  gt(column: string, value: unknown): this
  gte(column: string, value: unknown): this
  ilike(column: string, value: string): this
  in(column: string, values: readonly unknown[]): this
  is(column: string, value: unknown): this
  like(column: string, value: string): this
  lt(column: string, value: unknown): this
  lte(column: string, value: unknown): this
  neq(column: string, value: unknown): this
  overlaps(column: string, value: unknown): this
  textSearch(column: string, value: string): this
}

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

type LooseFilterSpec = {
  col: string
  op?: Op | string
  val: FilterValue
}

/** camelCase → snake_case */
export function camelToSnake(str: string) {
  return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}

/** shallow object camelCase → snake_case */
export function convertKeysToSnake<TValue>(obj: Record<string, TValue>): Record<string, TValue> {
  const out: Record<string, TValue> = {}
  Object.entries(obj || {}).forEach(([k, v]) => {
    out[camelToSnake(k)] = v
  })
  return out
}

/** 内部使用：数组 specs 时转换 col */
function toOp(value: Op | string | undefined): Op | undefined {
  return value && value in opHandlers ? (value as Op) : undefined
}

function isFilterDescriptor(payload: FilterPayload): payload is { op?: Op; val?: FilterValue } {
  return !Array.isArray(payload) && typeof payload === 'object' && payload !== null
}

function normalizeSpecArray(specs: LooseFilterSpec[], camelToSnake: boolean): FilterSpec[] {
  const normalized = specs.map((spec) => ({
    col: spec.col,
    op: toOp(spec.op),
    val: spec.val
  }))
  if (!camelToSnake) return normalized
  return normalized.map((spec) => ({
    ...spec,
    col: camelToSnakeStr(spec.col)
  }))
}

/** Apply eq filters（保留你的原函数） */
export function applyEqFilters<TQuery extends FilterQueryLike>(
  query: TQuery,
  filters: Filters,
  opts: { skipEmpty?: boolean; camelToSnake?: boolean } = {}
): TQuery {
  const { skipEmpty = true, camelToSnake: toSnake = true } = opts
  const useFilters = toSnake ? convertKeysToSnake(filters) : filters

  Object.entries(useFilters || {}).forEach(([col, val]) => {
    if (val === undefined || val === null) return
    if (skipEmpty && typeof val === 'string' && val.trim() === '') return
    query = query.eq(col, val)
  })

  return query
}

/** Op → Supabase Query 映射表（工程化核心） */
const opHandlers: Record<
  Op,
  <TQuery extends FilterQueryLike>(query: TQuery, col: string, val: FilterValue) => TQuery
> = {
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
export function applyFilters<TQuery extends FilterQueryLike>(
  query: TQuery,
  specs: LooseFilterSpec[] | Record<string, FilterPayload>,
  opts: { skipEmpty?: boolean; camelToSnake?: boolean } = {}
): TQuery {
  const { skipEmpty = true, camelToSnake: toSnake = true } = opts

  const specArray: FilterSpec[] = Array.isArray(specs)
    ? normalizeSpecArray(specs, toSnake)
    : Object.entries(toSnake ? convertKeysToSnake(specs) : specs).map(([col, payload]) => {
        if (isFilterDescriptor(payload)) {
          return { col, op: toOp(payload.op), val: payload.val }
        }
        return { col, op: 'eq', val: payload }
      })

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
  const snakeFilters: Filters = camelToSnake ? convertKeysToSnake(filters) : filters

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
