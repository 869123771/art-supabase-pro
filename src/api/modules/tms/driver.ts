import { useSupabase } from '@/hooks'
import { uniqBy } from 'lodash-es'
import {
  applyCreateTimeRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Driver = Api.Tms.BasicData.Driver
type DriverSearchParams = Api.Tms.BasicData.DriverSearchParams
type DriverOption = Api.Tms.BasicData.DriverOption
type DriverAssignedVehicle = Api.Tms.BasicData.DriverAssignedVehicle

interface DriverRecord extends Driver {
  primaryVehicles?: DriverAssignedVehicle[]
  secondaryVehicles?: DriverAssignedVehicle[]
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const DRIVER_SELECT = `
  *,
  carrier:tms_carrier!tms_driver_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  ),
  primary_vehicles:vehicle_archive!vehicle_archive_primary_driver_id_fkey(
    id,
    carrier_id,
    plate_no
  ),
  secondary_vehicles:vehicle_archive!vehicle_archive_secondary_driver_id_fkey(
    id,
    carrier_id,
    plate_no
  )
`

const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i

const normalizeDriverRecord = (record: DriverRecord): Driver => {
  const { primaryVehicles = [], secondaryVehicles = [], ...driver } = record
  const assignedVehicles = uniqBy([...primaryVehicles, ...secondaryVehicles], 'id')
    .filter((vehicle) => vehicle.carrierId === record.carrierId)
    .sort((first, second) => first.plateNo.localeCompare(second.plateNo, 'zh-CN'))

  return { ...driver, assignedVehicles }
}

const normalizeDriverRecords = (records: DriverRecord[] | null): Driver[] | null =>
  records?.map(normalizeDriverRecord) ?? null

const applyDriverFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: DriverSearchParams
): TQuery => {
  const { carrierId, driverType, gender, enabled, keyword, createTimeRange, recordId } = params
  if (recordId) query = query.eq('id', recordId)
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
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchDriverList(params: DriverSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDriverFilters(query, params)
  const result = await responseHandle<DriverRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return { ...result, data: normalizeDriverRecords(result.data) }
}

export async function exportDriverList(
  params: DriverSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyDriverFilters(query, params)
  const result = await responseHandle<DriverRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return { ...result, data: normalizeDriverRecords(result.data) }
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

  return await responseHandle<DriverOption[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchDriverListByCarrierId(carrierId: string) {
  const result = await responseHandle<DriverRecord[]>(
    () =>
      supabase
        .from('tms_driver')
        .select(DRIVER_SELECT)
        .eq('carrier_id', carrierId)
        .order('create_time', { ascending: false })
        .limit(1000),
    { ignoreCheck: true, showErrorMessage: true }
  )

  return { ...result, data: normalizeDriverRecords(result.data) }
}

export async function fetchDriverAssignedVehicles(
  params: { driverId: string; carrierId: string },
  options?: ApiRequestOptions
) {
  const { driverId, carrierId } = params
  if (!UUID_PATTERN.test(driverId)) {
    throw new Error('司机标识无效，请刷新页面后重试')
  }

  const query = supabase
    .from('vehicle_archive')
    .select('id, carrier_id, plate_no')
    .eq('carrier_id', carrierId)
    .or(`primary_driver_id.eq.${driverId},secondary_driver_id.eq.${driverId}`)
    .order('plate_no', { ascending: true })
    .limit(200)

  return await responseHandle<DriverAssignedVehicle[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
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
  return await responseHandle(
    () => supabase.from('tms_driver').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteDriverBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_driver').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}
