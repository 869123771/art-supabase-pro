import { useSupabase } from '@/hooks'
import { applyCreateTimeRange, type SupabaseQueryLike } from '@/api/modules/tms/query'

type StationRecord = Api.Tms.Station.StationRecord
type StationSearchParams = Api.Tms.Station.StationSearchParams
type StationOptionSearchParams = Api.Tms.Station.StationOptionSearchParams

interface WriteOptions {
  showMessage?: boolean
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyStationFilters = (
  query: SupabaseQueryLike,
  params: StationSearchParams
): SupabaseQueryLike => {
  const { stationType, enabled, keyword, createTimeRange } = params
  if (stationType) query = query.eq('station_type', stationType)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `station_code.ilike.%${keyword}%,station_name.ilike.%${keyword}%,region_code.ilike.%${keyword}%,manager_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchStationList(params: StationSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_station')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportStationList(
  params: StationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_station')
    .select('*')
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(maxRows) as unknown as SupabaseQueryLike

  query = ids?.length ? query.in('id', ids) : applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchStationOptions(params: StationOptionSearchParams = {}) {
  let query = supabase
    .from('tms_station')
    .select('id, station_code, station_name, station_type, region_code')
    .eq('enabled', true)
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(1000) as unknown as SupabaseQueryLike

  if (params.stationType) query = query.eq('station_type', params.stationType)
  if (params.keyword) {
    query = query.or(
      `station_code.ilike.%${params.keyword}%,station_name.ilike.%${params.keyword}%,region_code.ilike.%${params.keyword}%`
    )
  }

  return await responseHandle<Api.Tms.Order.StationOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addStation(params: StationRecord, options: WriteOptions = {}) {
  return await responseHandle<StationRecord>(
    () => supabase.from('tms_station').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function editStation(params: StationRecord) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_station').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteStation(id: string) {
  return await responseHandle(() => supabase.from('tms_station').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteStationBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_station').delete().in('id', ids), {
    showMessage: true
  })
}

export async function importStations(rows: StationRecord[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_station')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,station_code' }),
    { showMessage: true, breakReturn: true }
  )
}
