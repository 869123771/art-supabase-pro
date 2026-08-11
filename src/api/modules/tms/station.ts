import { useSupabase } from '@/hooks'
import {
  applyCreateTimeRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type StationRecord = Api.Tms.Station.StationRecord
type StationSearchParams = Api.Tms.Station.StationSearchParams
type StationOptionSearchParams = Api.Tms.Station.StationOptionSearchParams
type StationSavePayload = Api.Tms.Station.StationSavePayload

interface WriteOptions {
  showMessage?: boolean
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const stationSelect = (withRoleFilter: boolean, fields = '*'): string => `
  ${fields},
  stationRoles:tms_station_role(role_type)
  ${withRoleFilter ? ', stationRoleFilter:tms_station_role!inner(role_type)' : ''}
`

const applyStationFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: StationSearchParams
): TQuery => {
  const { stationType, enabled, keyword, createTimeRange } = params
  if (stationType) query = query.eq('stationRoleFilter.role_type', stationType)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `station_code.ilike.%${keyword}%,station_name.ilike.%${keyword}%,region_code.ilike.%${keyword}%,manager_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchStationList(params: StationSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_station')
    .select(stationSelect(Boolean(params.stationType)), { count: 'exact' })
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .range(from, to)

  query = applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportStationList(
  params: StationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const withRoleFilter = !ids?.length && Boolean(params.stationType)
  let query = supabase
    .from('tms_station')
    .select(stationSelect(withRoleFilter))
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchStationOptions(
  params: StationOptionSearchParams = {},
  options?: ApiRequestOptions
) {
  const withRoleFilter = Boolean(params.stationType)
  let query = supabase
    .from('tms_station')
    .select(
      stationSelect(withRoleFilter, 'id, station_code, station_name, station_type, region_code')
    )
    .eq('enabled', true)
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(1000)

  if (params.stationType) query = query.eq('stationRoleFilter.role_type', params.stationType)
  if (params.keyword) {
    query = query.or(
      `station_code.ilike.%${params.keyword}%,station_name.ilike.%${params.keyword}%,region_code.ilike.%${params.keyword}%`
    )
  }

  return await responseHandle<Api.Tms.Order.StationOption[]>(
    () => withRequestOptions(query, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

const createSaveRpcParams = (params: StationSavePayload) => {
  const { stationTypes, ...station } = params
  return {
    p_station: keysToSnakeDeep(station),
    p_role_types: stationTypes
  }
}

export async function addStation(params: StationSavePayload, options: WriteOptions = {}) {
  return await responseHandle<StationRecord>(
    () => supabase.rpc('save_tms_station', createSaveRpcParams(params)),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function editStation(params: StationSavePayload) {
  return await responseHandle<StationRecord>(
    () => supabase.rpc('save_tms_station', createSaveRpcParams(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function updateStationEnabled(id: string, enabled: boolean) {
  return await responseHandle(() => supabase.from('tms_station').update({ enabled }).eq('id', id), {
    showMessage: true,
    breakReturn: true
  })
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

export async function importStations(rows: StationSavePayload[]) {
  return await responseHandle(
    () => supabase.rpc('import_tms_stations', { p_rows: keysToSnakeDeep(rows) }),
    { showMessage: true, breakReturn: true }
  )
}
