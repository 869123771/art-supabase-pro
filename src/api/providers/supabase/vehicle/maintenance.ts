import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import {
  type VehicleMaintenanceRecord,
  type VehicleMaintenanceSearchParams,
  type VehiclePartUsage,
  type VehiclePartUsageSearchParams
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 车辆保养维修
interface SecureVehicleMaintenancePayload {
  records: VehicleMaintenanceRecord[]
  total: number
  fieldAccess?: Api.Vms.VehicleManage.VehicleMaintenanceFieldAccessMap
}

const maintenanceStartOfDay = (value?: string): string | null =>
  value ? `${value}T00:00:00` : null
const maintenanceEndOfDay = (value?: string): string | null =>
  value ? `${value}T23:59:59.999` : null

const createVehicleMaintenanceRpcParams = (
  params: VehicleMaintenanceSearchParams & { ids?: string[]; maxRows?: number },
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
    p_maintenance_no: String(params.maintenanceNo ?? '').trim() || null,
    p_maintenance_type: String(params.maintenanceType ?? '').trim() || null,
    p_create_time_from: maintenanceStartOfDay(params.createTimeRange?.[0]),
    p_create_time_to: maintenanceEndOfDay(params.createTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehicleMaintenanceList(
  params: VehicleMaintenanceSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehicleMaintenancePayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_maintenance_secure',
          createVehicleMaintenanceRpcParams(params, 'list')
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

export async function exportVehicleMaintenanceList(
  params: VehicleMaintenanceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehicleMaintenancePayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_maintenance_secure',
        createVehicleMaintenanceRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

export async function fetchVehicleMaintenanceDetail(id: string) {
  return await responseHandle<VehicleMaintenanceRecord | null>(
    () => supabase.rpc('vms_get_vehicle_maintenance_secure', { p_id: id }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleMaintenance(params: VehicleMaintenanceRecord) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('vms_create_vehicle_maintenance_secure', {
        p_payload: keysToSnakeDeep(params)
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editVehicleMaintenance(params: VehicleMaintenanceRecord) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少车辆维修保养 ID')
  return await responseHandle<VehicleMaintenanceRecord>(
    () =>
      supabase.rpc('vms_update_vehicle_maintenance_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(data)
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteVehicleMaintenance(id: string) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_maintenance_secure', { p_ids: [id] }),
    { showMessage: true, message: '删除成功', breakReturn: true }
  )
}

export async function deleteVehicleMaintenanceBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_maintenance_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

// 车辆零部件使用
interface SecureVehiclePartUsagePayload {
  records: VehiclePartUsage[]
  total: number
  fieldAccess?: Api.Vms.VehicleManage.VehiclePartUsageFieldAccessMap
}

const partUsageStartOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const partUsageEndOfDay = (value?: string): string | null =>
  value ? `${value}T23:59:59.999` : null

const createVehiclePartUsageRpcParams = (
  params: VehiclePartUsageSearchParams & { ids?: string[]; maxRows?: number },
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
    p_part_type: String(params.partType ?? '').trim() || null,
    p_part_name: String(params.partName ?? '').trim() || null,
    p_category_id: params.categoryId || null,
    p_rfid_tag: String(params.rfidTag ?? '').trim() || null,
    p_status: String(params.status ?? '').trim() || null,
    p_create_time_from: partUsageStartOfDay(params.createTimeRange?.[0]),
    p_create_time_to: partUsageEndOfDay(params.createTimeRange?.[1]),
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchVehiclePartUsageList(
  params: VehiclePartUsageSearchParams,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureVehiclePartUsagePayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_part_usages_secure',
          createVehiclePartUsageRpcParams(params, 'list')
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

export async function exportVehiclePartUsageList(
  params: VehiclePartUsageSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureVehiclePartUsagePayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_part_usages_secure',
        createVehiclePartUsageRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

export async function fetchVehiclePartUsageDetail(id: string) {
  return await responseHandle<VehiclePartUsage | null>(
    () => supabase.rpc('vms_get_vehicle_part_usage_secure', { p_id: id }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehiclePartUsage(params: VehiclePartUsage) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('vms_create_vehicle_part_usage_secure', { p_payload: keysToSnakeDeep(params) }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editVehiclePartUsage(params: VehiclePartUsage) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少车辆配件使用记录 ID')
  return await responseHandle<VehiclePartUsage>(
    () =>
      supabase.rpc('vms_update_vehicle_part_usage_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(data)
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteVehiclePartUsage(id: string) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_part_usages_secure', { p_ids: [id] }),
    { showMessage: true, message: '删除成功', breakReturn: true }
  )
}

export async function deleteVehiclePartUsageBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_part_usages_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
