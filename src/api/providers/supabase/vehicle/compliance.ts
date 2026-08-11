import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { applyDateRange, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase'
import {
  type VehicleInsurance,
  type VehicleInsuranceSearchParams,
  type VehicleInspection,
  type VehicleInspectionSearchParams,
  type VehicleRoutineInspectionRecord,
  type VehicleRoutineInspectionSearchParams
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 车辆保险
const VEHICLE_INSURANCE_TABLE = 'vehicle_insurance'

const getVehicleInsuranceSearchFilters = (params: VehicleInsuranceSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'commercialPolicyNo',
    op: 'ilike',
    val: params.commercialPolicyNo ? `%${params.commercialPolicyNo}%` : undefined
  },
  {
    col: 'compulsoryPolicyNo',
    op: 'ilike',
    val: params.compulsoryPolicyNo ? `%${params.compulsoryPolicyNo}%` : undefined
  }
]

export async function fetchVehicleInsuranceList(
  params: VehicleInsuranceSearchParams,
  options?: ApiRequestOptions
) {
  const {
    from = 0,
    to = 9,
    commercialExpireDateRange,
    compulsoryExpireDateRange,
    createTimeRange
  } = params
  let query = supabase
    .from(VEHICLE_INSURANCE_TABLE)
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'commercial_expire_date', commercialExpireDateRange)
  query = applyDateRange(query, 'compulsory_expire_date', compulsoryExpireDateRange)
  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleInsuranceSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleInsurance[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleInsuranceList(
  params: VehicleInsuranceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const {
    ids,
    maxRows = 10000,
    commercialExpireDateRange,
    compulsoryExpireDateRange,
    createTimeRange
  } = params
  let query = supabase
    .from(VEHICLE_INSURANCE_TABLE)
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'commercial_expire_date', commercialExpireDateRange)
    query = applyDateRange(query, 'compulsory_expire_date', compulsoryExpireDateRange)
    query = applyDateRange(query, 'create_time', createTimeRange)
    query = applyFilters(query, getVehicleInsuranceSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleInsurance[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleInsuranceDetail(id: string) {
  return await responseHandle<VehicleInsurance>(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).select('*').eq('id', id).single(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleInsurance(params: VehicleInsurance) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehicleInsurance(params: VehicleInsurance) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_INSURANCE_TABLE)
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

export async function deleteVehicleInsurance(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleInsuranceBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 车辆年检
const VEHICLE_INSPECTION_TABLE = 'vehicle_inspection'

const getVehicleInspectionSearchFilters = (params: VehicleInspectionSearchParams): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'inspectionNo',
    op: 'ilike',
    val: params.inspectionNo ? `%${params.inspectionNo}%` : undefined
  }
]

export async function fetchVehicleInspectionList(
  params: VehicleInspectionSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, expireDateRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_INSPECTION_TABLE)
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'expire_date', expireDateRange)
  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleInspectionSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleInspection[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleInspectionList(
  params: VehicleInspectionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, expireDateRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_INSPECTION_TABLE)
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'expire_date', expireDateRange)
    query = applyDateRange(query, 'create_time', createTimeRange)
    query = applyFilters(query, getVehicleInspectionSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleInspection[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleInspectionDetail(id: string) {
  return await responseHandle<VehicleInspection>(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).select('*').eq('id', id).single(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}
export async function addVehicleInspection(params: VehicleInspection) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehicleInspection(params: VehicleInspection) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_INSPECTION_TABLE)
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

export async function deleteVehicleInspection(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleInspectionBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 车辆例行检查
const VEHICLE_ROUTINE_INSPECTION_TABLE = 'vehicle_routine_inspection_record'

const getVehicleRoutineInspectionSearchFilters = (
  params: VehicleRoutineInspectionSearchParams
): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  { col: 'inspectionType', op: 'eq', val: params.inspectionType },
  { col: 'checkResult', op: 'eq', val: params.checkResult }
]

export async function fetchVehicleRoutineInspectionList(
  params: VehicleRoutineInspectionSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, inspectionTimeRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ROUTINE_INSPECTION_TABLE)
    .select('*', { count: 'exact' })
    .order('inspection_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'inspection_time', inspectionTimeRange)
  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleRoutineInspectionSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleRoutineInspectionRecord[]>(
    () => withRequestOptions(query, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleRoutineInspectionList(
  params: VehicleRoutineInspectionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, inspectionTimeRange, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ROUTINE_INSPECTION_TABLE)
    .select('*')
    .order('inspection_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyDateRange(query, 'inspection_time', inspectionTimeRange)
    query = applyDateRange(query, 'create_time', createTimeRange)
    query = applyFilters(query, getVehicleRoutineInspectionSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleRoutineInspectionRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleRoutineInspectionDetail(id: string) {
  return await responseHandle<VehicleRoutineInspectionRecord>(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).select('*').eq('id', id).single(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleRoutineInspection(params: VehicleRoutineInspectionRecord) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editVehicleRoutineInspection(params: VehicleRoutineInspectionRecord) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ROUTINE_INSPECTION_TABLE)
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

export async function deleteVehicleRoutineInspection(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleRoutineInspectionBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}
