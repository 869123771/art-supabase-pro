import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { applyDateRange, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase'
import {
  type VehicleMaintenanceRecord,
  type VehicleMaintenanceSearchParams,
  type VehiclePartUsage,
  type VehiclePartUsageSearchParams
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 车辆保养维修
const VEHICLE_MAINTENANCE_TABLE = 'vehicle_maintenance_record'

const getVehicleMaintenanceSearchFilters = (
  params: VehicleMaintenanceSearchParams
): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'maintenanceNo',
    op: 'ilike',
    val: params.maintenanceNo ? `%${params.maintenanceNo}%` : undefined
  },
  { col: 'maintenanceType', op: 'eq', val: params.maintenanceType }
]

export async function fetchVehicleMaintenanceList(
  params: VehicleMaintenanceSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_MAINTENANCE_TABLE)
    .select('*', { count: 'exact' })
    .order('start_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleMaintenanceSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleMaintenanceRecord[]>(
    () => withRequestOptions(query, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleMaintenanceList(
  params: VehicleMaintenanceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_MAINTENANCE_TABLE)
    .select('*')
    .order('start_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'create_time', createTimeRange)
    query = applyFilters(query, getVehicleMaintenanceSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleMaintenanceRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleMaintenanceDetail(id: string) {
  return await responseHandle<VehicleMaintenanceRecord>(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).select('*').eq('id', id).single(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleMaintenance(params: VehicleMaintenanceRecord) {
  return await responseHandle(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehicleMaintenance(params: VehicleMaintenanceRecord) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_MAINTENANCE_TABLE)
        .update(keysToSnakeDeep(data), { count: 'exact' })
        .eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleMaintenance(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleMaintenanceBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 车辆零部件使用
const VEHICLE_PART_USAGE_TABLE = 'vehicle_part_usage'

const getVehiclePartUsageSearchFilters = (params: VehiclePartUsageSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  { col: 'partType', op: 'eq', val: params.partType },
  {
    col: 'partName',
    op: 'ilike',
    val: params.partName ? `%${params.partName}%` : undefined
  },
  { col: 'categoryId', op: 'eq', val: params.categoryId },
  { col: 'rfidTag', op: 'ilike', val: params.rfidTag ? `%${params.rfidTag}%` : undefined },
  { col: 'status', op: 'eq', val: params.status }
]

export async function fetchVehiclePartUsageList(
  params: VehiclePartUsageSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_PART_USAGE_TABLE)
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehiclePartUsageSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehiclePartUsage[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehiclePartUsageDetail(id: string) {
  return await responseHandle<VehiclePartUsage>(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).select('*').eq('id', id).single(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehiclePartUsage(params: VehiclePartUsage) {
  return await responseHandle(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehiclePartUsage(params: VehiclePartUsage) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_PART_USAGE_TABLE)
        .update(keysToSnakeDeep(data), { count: 'exact' })
        .eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehiclePartUsage(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehiclePartUsageBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}
