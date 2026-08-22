import { useSupabase } from '@/hooks'
import { normalizeBooleanFilter, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import {
  type VehicleMileageRecord,
  type VehicleMileageSearchParams,
  type VehicleViolationRecord,
  type VehicleViolationSearchParams,
  type VehicleAccidentRecord,
  type VehicleAccidentSearchParams
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 车辆里程
interface SecureVehicleMileagePayload {
  records: VehicleMileageRecord[]
  total: number
  fieldAccess?: Api.Vms.VehicleManage.VehicleMileageFieldAccessMap
}

const mileageStartOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const mileageEndOfDay = (value?: string): string | null => (value ? `${value}T23:59:59.999` : null)

const createVehicleMileageRpcParams = (
  params: VehicleMileageSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_vehicle_id: params.vehicleId || null,
    p_company_name: String(params.companyName ?? '').trim() || null,
    p_plate_no: String(params.plateNo ?? '').trim() || null,
    p_start_time_from: mileageStartOfDay(params.drivingTimeRange?.[0]),
    p_start_time_to: mileageEndOfDay(params.drivingTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehicleMileageList(
  params: VehicleMileageSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehicleMileagePayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_mileage_secure',
          createVehicleMileageRpcParams(params, 'list')
        ),
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

export async function exportVehicleMileageList(
  params: VehicleMileageSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehicleMileagePayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_mileage_secure',
        createVehicleMileageRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

// 车辆违章
interface SecureVehicleViolationPayload {
  records: VehicleViolationRecord[]
  total: number
  fieldAccess?: Api.Vms.VehicleManage.VehicleViolationFieldAccessMap
}

const violationStartOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const violationEndOfDay = (value?: string): string | null =>
  value ? `${value}T23:59:59.999` : null

const createVehicleViolationRpcParams = (
  params: VehicleViolationSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_vehicle_id: params.vehicleId || null,
    p_company_name: String(params.companyName ?? '').trim() || null,
    p_plate_no: String(params.plateNo ?? '').trim() || null,
    p_driver_name: String(params.driverName ?? '').trim() || null,
    p_violation_behavior: String(params.violationBehavior ?? '').trim() || null,
    p_processed: normalizeBooleanFilter(params.processed) ?? null,
    p_violation_time_from: violationStartOfDay(params.violationTimeRange?.[0]),
    p_violation_time_to: violationEndOfDay(params.violationTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehicleViolationList(
  params: VehicleViolationSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehicleViolationPayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_violations_secure',
          createVehicleViolationRpcParams(params, 'list')
        ),
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

export async function exportVehicleViolationList(
  params: VehicleViolationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehicleViolationPayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_violations_secure',
        createVehicleViolationRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

// 车辆事故
interface SecureVehicleAccidentPayload {
  records: VehicleAccidentRecord[]
  total: number
  fieldAccess?: Api.Vms.VehicleManage.VehicleAccidentFieldAccessMap
}

const accidentStartOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const accidentEndOfDay = (value?: string): string | null => (value ? `${value}T23:59:59.999` : null)

const createVehicleAccidentRpcParams = (
  params: VehicleAccidentSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_vehicle_id: params.vehicleId || null,
    p_company_name: String(params.companyName ?? '').trim() || null,
    p_plate_no: String(params.plateNo ?? '').trim() || null,
    p_driver_name: String(params.driverName ?? '').trim() || null,
    p_processed: normalizeBooleanFilter(params.processed) ?? null,
    p_data_source: String(params.dataSource ?? '').trim() || null,
    p_accident_time_from: accidentStartOfDay(params.accidentTimeRange?.[0]),
    p_accident_time_to: accidentEndOfDay(params.accidentTimeRange?.[1]),
    p_create_time_from: accidentStartOfDay(params.createTimeRange?.[0]),
    p_create_time_to: accidentEndOfDay(params.createTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehicleAccidentList(
  params: VehicleAccidentSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehicleAccidentPayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_accidents_secure',
          createVehicleAccidentRpcParams(params, 'list')
        ),
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

export async function exportVehicleAccidentList(
  params: VehicleAccidentSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehicleAccidentPayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_accidents_secure',
        createVehicleAccidentRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

export async function fetchVehicleAccidentDetail(id: string) {
  return await responseHandle<VehicleAccidentRecord | null>(
    () => supabase.rpc('vms_get_vehicle_accident_secure', { p_id: id }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleAccident(params: VehicleAccidentRecord) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('vms_create_vehicle_accident_secure', { p_payload: keysToSnakeDeep(params) }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editVehicleAccident(params: VehicleAccidentRecord) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少车辆事故 ID')
  return await responseHandle<VehicleAccidentRecord>(
    () =>
      supabase.rpc('vms_update_vehicle_accident_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(data)
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteVehicleAccident(id: string) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_accident_secure', { p_ids: [id] }),
    { showMessage: true, message: '删除成功', breakReturn: true }
  )
}

export async function deleteVehicleAccidentBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_accident_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
