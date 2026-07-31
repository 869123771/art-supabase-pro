import { useSupabase } from '@/hooks'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/modules/tms/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Cargo = Api.Tms.BasicData.Cargo
type CargoSearchParams = Api.Tms.BasicData.CargoSearchParams

interface WriteOptions {
  showMessage?: boolean
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyCargoFilters = (
  query: SupabaseQueryLike,
  params: CargoSearchParams
): SupabaseQueryLike => {
  const { unit, enabled, keyword, createTimeRange } = params
  if (unit) query = query.eq('unit', unit)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `cargo_name.ilike.%${keyword}%,cargo_code.ilike.%${keyword}%,unit.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  if (createTimeRange?.[0]) query = query.gte('create_time', `${createTimeRange[0]}T00:00:00`)
  if (createTimeRange?.[1]) {
    query = query.lte('create_time', `${createTimeRange[1]}T23:59:59.999`)
  }
  return query
}

export async function fetchCargoList(params: CargoSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_cargo')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyCargoFilters(query, params)
  return await responseHandle<Cargo[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCargoList(
  params: CargoSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_cargo')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyCargoFilters(query, params)
  return await responseHandle<Cargo[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCargo(params: Cargo, options: WriteOptions = {}) {
  return await responseHandle<Cargo>(
    () => supabase.from('tms_cargo').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function editCargo(params: Cargo) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_cargo').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCargo(id: string) {
  return await responseHandle(() => supabase.from('tms_cargo').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCargoBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_cargo').delete().in('id', ids), {
    showMessage: true
  })
}

export async function importCargoes(rows: Cargo[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_cargo')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,cargo_name' }),
    { showMessage: true, breakReturn: true }
  )
}
