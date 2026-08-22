import { useSupabase } from '@/hooks'
import { normalizeBooleanFilter, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Driver = Api.Tms.BasicData.Driver
type DriverSearchParams = Api.Tms.BasicData.DriverSearchParams
type DriverOption = Api.Tms.BasicData.DriverOption
type DriverAssignedVehicle = Api.Tms.BasicData.DriverAssignedVehicle
type DriverEmployeeOption = Api.Tms.BasicData.DriverEmployeeOption

interface DriverOptionParams extends Partial<
  Pick<DriverOption, 'carrierId' | 'driverName' | 'driverType'>
> {
  ids?: string[]
  includeDisabled?: boolean
  maxRows?: number
}

interface SecureListPayload<TRecord, TAccess extends Record<string, string>> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

interface DriverEmployeeOptionParams {
  keyword?: string
  from?: number
  to?: number
}

interface DriverEmployeeOptionPayload {
  records: DriverEmployeeOption[]
  total: number
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i

const DRIVER_PAYLOAD_KEYS = [
  'employeeId',
  'carrierId',
  'driverName',
  'phone',
  'gender',
  'idCardNo',
  'licenseType',
  'driverType',
  'licenseExpireDate',
  'homeAddress',
  'emergencyContactName',
  'emergencyContactPhone',
  'enabled',
  'idCardFrontUrl',
  'idCardBackUrl',
  'driverLicenseFrontUrl',
  'driverLicenseBackUrl',
  'remark'
] as const satisfies readonly (keyof Driver)[]

export async function fetchDriverEmployeeOptions(
  params: DriverEmployeeOptionParams,
  options?: ApiRequestOptions
) {
  const from = Math.max(params.from ?? 0, 0)
  const result = await responseHandle<DriverEmployeeOptionPayload>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_driver_employee_options_secure', {
          p_from: from,
          p_to: Math.max(params.to ?? from + 9, from),
          p_keyword: String(params.keyword ?? '').trim() || null
        }),
        options
      ),
    { showErrorMessage: true }
  )

  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

const pickPayload = <TRecord extends object, TKey extends Extract<keyof TRecord, string>>(
  record: TRecord,
  keys: readonly TKey[]
): Record<string, unknown> =>
  Object.fromEntries(
    keys.filter((key) => record[key] !== undefined).map((key) => [key, record[key]])
  )

const toDriverListRpcParams = (
  params: DriverSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_record_id: params.recordId || null,
    p_carrier_id: params.carrierId || null,
    p_driver_type: params.driverType || null,
    p_gender: params.gender || null,
    p_enabled: normalizeBooleanFilter(params.enabled) ?? null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_create_time_from: params.createTimeRange?.[0]
      ? `${params.createTimeRange[0]}T00:00:00`
      : null,
    p_create_time_to: params.createTimeRange?.[1]
      ? `${params.createTimeRange[1]}T23:59:59.999`
      : null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchDriverList(params: DriverSearchParams, options?: ApiRequestOptions) {
  const result = await responseHandle<
    SecureListPayload<Driver, Api.Tms.BasicData.DriverFieldAccessMap>
  >(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_drivers_secure', toDriverListRpcParams(params, 'list')),
        options
      ),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportDriverList(
  params: DriverSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<Driver, Api.Tms.BasicData.DriverFieldAccessMap>
  >(() => supabase.rpc('tms_list_drivers_secure', toDriverListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchDriverDetail(id: string) {
  return await responseHandle<Driver | null>(
    () => supabase.rpc('tms_get_driver_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchDriverOptions(
  params: DriverOptionParams = {},
  options?: ApiRequestOptions
) {
  const { carrierId, driverName, driverType, ids, includeDisabled = false, maxRows = 200 } = params
  return await responseHandle<DriverOption[]>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_driver_options_secure', {
          p_carrier_id: carrierId || null,
          p_driver_name: String(driverName ?? '').trim() || null,
          p_driver_type: driverType || null,
          p_ids: ids?.length ? ids : null,
          p_include_disabled: includeDisabled,
          p_max_rows: maxRows
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

export async function fetchDriverListByCarrierId(carrierId: string) {
  return await responseHandle<Driver[]>(
    () => supabase.rpc('tms_list_drivers_by_carrier_secure', { p_carrier_id: carrierId }),
    { showErrorMessage: true }
  )
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
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_driver_secure', {
        p_payload: keysToSnakeDeep(pickPayload(params, DRIVER_PAYLOAD_KEYS))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editDriver(params: Driver) {
  const { id, ...data } = params
  if (!id) throw new Error('司机 ID 不能为空')
  return await responseHandle<Driver>(
    () =>
      supabase.rpc('tms_update_driver_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(pickPayload(data, DRIVER_PAYLOAD_KEYS))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteDriver(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_driver_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteDriverBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_drivers_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
