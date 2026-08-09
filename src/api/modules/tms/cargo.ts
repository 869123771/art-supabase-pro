import { useSupabase } from '@/hooks'
import {
  applyCreateTimeRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Cargo = Api.Tms.BasicData.Cargo
type CargoSearchParams = Api.Tms.BasicData.CargoSearchParams

interface WriteOptions {
  showMessage?: boolean
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const applyCargoFilters = (
  query: SupabaseQueryLike,
  params: CargoSearchParams
): SupabaseQueryLike => {
  const { unit, enabled, keyword, createTimeRange, recordId } = params
  if (recordId) query = query.eq('id', recordId)
  if (unit) query = query.eq('unit', unit)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `cargo_name.ilike.%${keyword}%,cargo_code.ilike.%${keyword}%,unit.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
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
  return await responseHandle(
    () => supabase.from('tms_cargo').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCargoBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_cargo').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
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
