import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import {
  applyDateRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike as SupabaseProviderQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'
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
const VEHICLE_MILEAGE_TABLE = 'vehicle_mileage_record'

const getVehicleMileageSearchFilters = (params: VehicleMileageSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined }
]

export async function fetchVehicleMileageList(
  params: VehicleMileageSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, drivingTimeRange } = params
  let query = supabase
    .from(VEHICLE_MILEAGE_TABLE)
    .select('*', { count: 'exact' })
    .order('start_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'start_time', drivingTimeRange)
  query = applyFilters(query, getVehicleMileageSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleMileageRecord[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleMileageList(
  params: VehicleMileageSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, drivingTimeRange } = params
  let query = supabase
    .from(VEHICLE_MILEAGE_TABLE)
    .select('*')
    .order('start_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'start_time', drivingTimeRange)
    query = applyFilters(query, getVehicleMileageSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleMileageRecord[]>(
    () => query as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

// 车辆违章
const VEHICLE_VIOLATION_TABLE = 'vehicle_violation_record'

const getVehicleViolationSearchFilters = (params: VehicleViolationSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  { col: 'driverName', op: 'ilike', val: params.driverName ? `%${params.driverName}%` : undefined },
  {
    col: 'violationBehavior',
    op: 'ilike',
    val: params.violationBehavior ? `%${params.violationBehavior}%` : undefined
  },
  { col: 'processed', op: 'eq', val: normalizeBooleanFilter(params.processed) }
]

export async function fetchVehicleViolationList(
  params: VehicleViolationSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, violationTimeRange } = params
  let query = supabase
    .from(VEHICLE_VIOLATION_TABLE)
    .select('*', { count: 'exact' })
    .order('violation_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'violation_time', violationTimeRange)
  query = applyFilters(query, getVehicleViolationSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleViolationRecord[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleViolationList(
  params: VehicleViolationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, violationTimeRange } = params
  let query = supabase
    .from(VEHICLE_VIOLATION_TABLE)
    .select('*')
    .order('violation_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'violation_time', violationTimeRange)
    query = applyFilters(query, getVehicleViolationSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleViolationRecord[]>(
    () => query as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

// 车辆事故
const VEHICLE_ACCIDENT_TABLE = 'vehicle_accident_record'

const getVehicleAccidentSearchFilters = (params: VehicleAccidentSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  { col: 'driverName', op: 'ilike', val: params.driverName ? `%${params.driverName}%` : undefined },
  { col: 'processed', op: 'eq', val: normalizeBooleanFilter(params.processed) },
  { col: 'dataSource', op: 'eq', val: params.dataSource }
]

export async function fetchVehicleAccidentList(
  params: VehicleAccidentSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, accidentTimeRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ACCIDENT_TABLE)
    .select('*', { count: 'exact' })
    .order('accident_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'accident_time', accidentTimeRange)
  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleAccidentSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleAccidentRecord[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleAccidentList(
  params: VehicleAccidentSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, accidentTimeRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ACCIDENT_TABLE)
    .select('*')
    .order('accident_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'accident_time', accidentTimeRange)
    query = applyDateRange(query, 'create_time', createTimeRange)
    query = applyFilters(query, getVehicleAccidentSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleAccidentRecord[]>(
    () => query as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchVehicleAccidentDetail(id: string) {
  return await responseHandle<VehicleAccidentRecord>(
    () =>
      supabase
        .from(VEHICLE_ACCIDENT_TABLE)
        .select('*')
        .eq('id', id)
        .single() as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleAccident(params: VehicleAccidentRecord) {
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ACCIDENT_TABLE)
        .insert(keysToSnakeDeep(params)) as unknown as SupabaseProviderQueryLike,
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehicleAccident(params: VehicleAccidentRecord) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ACCIDENT_TABLE)
        .update(keysToSnakeDeep(data), { count: 'exact' })
        .eq('id', id) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleAccident(id: string) {
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ACCIDENT_TABLE)
        .delete({ count: 'exact' })
        .eq('id', id) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleAccidentBatch(ids: string[]) {
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ACCIDENT_TABLE)
        .delete({ count: 'exact' })
        .in('id', ids) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}
