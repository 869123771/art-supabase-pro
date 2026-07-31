import { useSupabase } from '@/hooks'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/modules/tms/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Driver = Api.Tms.BasicData.Driver
type DriverSearchParams = Api.Tms.BasicData.DriverSearchParams
type DriverOption = Api.Tms.BasicData.DriverOption

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const DRIVER_SELECT = `
  *,
  carrier:tms_carrier!tms_driver_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  )
`

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyDateRange = (query: SupabaseQueryLike, dateRange?: string[]): SupabaseQueryLike => {
  if (dateRange?.[0]) query = query.gte('create_time', `${dateRange[0]}T00:00:00`)
  if (dateRange?.[1]) query = query.lte('create_time', `${dateRange[1]}T23:59:59.999`)
  return query
}

const applyDriverFilters = (
  query: SupabaseQueryLike,
  params: DriverSearchParams
): SupabaseQueryLike => {
  const { carrierId, driverType, gender, enabled, keyword, createTimeRange } = params
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (driverType) query = query.eq('driver_type', driverType)
  if (gender) query = query.eq('gender', gender)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `driver_name.ilike.%${keyword}%,phone.ilike.%${keyword}%,id_card_no.ilike.%${keyword}%,home_address.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchDriverList(params: DriverSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyDriverFilters(query, params)
  return await responseHandle<Driver[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportDriverList(
  params: DriverSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike

  query = ids?.length ? query.in('id', ids) : applyDriverFilters(query, params)
  return await responseHandle<Driver[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchDriverOptions(
  params: Partial<Pick<DriverOption, 'carrierId' | 'driverName' | 'driverType'>> = {},
  options?: ApiRequestOptions
) {
  const { carrierId, driverName, driverType } = params
  let query = supabase
    .from('tms_driver')
    .select('id, carrier_id, driver_name, phone, driver_type, license_type, enabled')
    .eq('enabled', true)
    .order('driver_name', { ascending: true })
    .limit(200)

  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (driverType) query = query.eq('driver_type', driverType)
  if (driverName) {
    query = query.or(`driver_name.ilike.%${driverName}%,phone.ilike.%${driverName}%`)
  }

  return await responseHandle<DriverOption[]>(
    () => withRequestOptions(query as unknown as SupabaseQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchDriverListByCarrierId(carrierId: string) {
  return await responseHandle<Driver[]>(
    () =>
      supabase
        .from('tms_driver')
        .select(DRIVER_SELECT)
        .eq('carrier_id', carrierId)
        .order('create_time', { ascending: false })
        .limit(1000),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function addDriver(params: Driver) {
  return await responseHandle(() => supabase.from('tms_driver').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

export async function editDriver(params: Driver) {
  const { id } = params
  const data = { ...params }
  delete data.id
  delete data.carrier
  return await responseHandle(
    () => supabase.from('tms_driver').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteDriver(id: string) {
  return await responseHandle(() => supabase.from('tms_driver').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteDriverBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_driver').delete().in('id', ids), {
    showMessage: true
  })
}
