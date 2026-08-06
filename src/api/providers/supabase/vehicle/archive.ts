import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import {
  withRequestOptions,
  type SupabaseQueryLike as SupabaseProviderQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'
import { VEHICLE_REMINDER_VIEWS, fetchVehicleReminderViewList } from './reminders'
import {
  type VehicleArchive,
  type VehicleArchiveSearchParams,
  type VehicleArchiveAuditStatus,
  type VehicleArchiveWritePayload,
  type VehicleArchiveDeleteRelatedCount,
  type VehicleArchiveDeletePreview,
  type VehicleArchiveDeleteBase,
  type VehicleReminderSearchParams,
  type VehicleReminderCompanyOption
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 车辆档案
const VEHICLE_ARCHIVE_TABLE = 'vehicle_archive'

const VEHICLE_ARCHIVE_SELECT = `
  *,
  carrier:tms_carrier!vehicle_archive_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  ),
  primary_driver:tms_driver!vehicle_archive_primary_driver_id_fkey(
    id,
    carrier_id,
    driver_name,
    phone,
    driver_type,
    license_type,
    enabled
  ),
  secondary_driver:tms_driver!vehicle_archive_secondary_driver_id_fkey(
    id,
    carrier_id,
    driver_name,
    phone,
    driver_type,
    license_type,
    enabled
  )
`

const VEHICLE_ARCHIVE_RELATED_DELETE_ITEMS = [
  { tableName: 'vehicle_insurance', label: '保险记录' },
  { tableName: 'vehicle_inspection', label: '年检记录' },
  { tableName: 'vehicle_maintenance_record', label: '保养维修记录' },
  { tableName: 'vehicle_routine_inspection_record', label: '例行检查记录' },
  { tableName: 'vehicle_mileage_record', label: '里程记录' },
  { tableName: 'vehicle_part_usage', label: '零部件使用记录' },
  { tableName: 'vehicle_accident_record', label: '事故记录' },
  { tableName: 'vehicle_violation_record', label: '违章记录' },
  { tableName: 'tms_carrier_price', label: '承运商车辆报价' }
] as const

const countRowsByVehicleIds = async (
  tableName: string,
  columnName: string,
  ids: string[]
): Promise<number> => {
  if (!ids.length) return 0

  const query =
    ids.length === 1
      ? supabase.from(tableName).select('id', { count: 'exact', head: true }).eq(columnName, ids[0])
      : supabase.from(tableName).select('id', { count: 'exact', head: true }).in(columnName, ids)

  const result = await responseHandle(() => query as unknown as SupabaseProviderQueryLike, {
    ignoreCheck: true,
    showErrorMessage: true,
    breakReturn: true
  })

  return result.total ?? 0
}

const fetchVehicleArchiveDeleteRelatedCounts = async (
  ids: string[]
): Promise<VehicleArchiveDeleteRelatedCount[]> => {
  const counts = await Promise.all(
    VEHICLE_ARCHIVE_RELATED_DELETE_ITEMS.map(async (item) => ({
      ...item,
      count: await countRowsByVehicleIds(item.tableName, 'vehicle_id', ids)
    }))
  )

  return counts
}

const fetchVehicleArchiveCarrierIds = async (ids: string[]): Promise<string[]> => {
  if (!ids.length) return []

  const query =
    ids.length === 1
      ? supabase.from(VEHICLE_ARCHIVE_TABLE).select('carrier_id').eq('id', ids[0])
      : supabase.from(VEHICLE_ARCHIVE_TABLE).select('carrier_id').in('id', ids)

  const result = await responseHandle<VehicleArchiveDeleteBase[]>(
    () => query as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true,
      breakReturn: true
    }
  )

  return Array.from(
    new Set((result.data ?? []).map((item) => item.carrierId).filter((id): id is string => !!id))
  )
}

const assertVehicleArchiveNoWaybill = async (ids: string[]): Promise<void> => {
  const waybillCount = await countRowsByVehicleIds('tms_waybill', 'vehicle_id', ids)

  if (waybillCount > 0) {
    throw new Error(`该车辆已关联 ${waybillCount} 条运单，禁止删除`)
  }
}

const deleteRowsByVehicleIds = async (tableName: string, ids: string[]): Promise<void> => {
  if (!ids.length) return

  const query =
    ids.length === 1
      ? supabase.from(tableName).delete({ count: 'exact' }).eq('vehicle_id', ids[0])
      : supabase.from(tableName).delete({ count: 'exact' }).in('vehicle_id', ids)

  await responseHandle(() => query as unknown as SupabaseProviderQueryLike, {
    showErrorMessage: true,
    breakReturn: true
  })
}

const refreshCarrierVehicleCounts = async (carrierIds: string[]): Promise<void> => {
  const uniqueCarrierIds = Array.from(new Set(carrierIds.filter(Boolean)))
  if (!uniqueCarrierIds.length) return

  await Promise.all(
    uniqueCarrierIds.map(async (carrierId) => {
      const count = await countRowsByVehicleIds(VEHICLE_ARCHIVE_TABLE, 'carrier_id', [carrierId])

      await responseHandle(
        () =>
          supabase
            .from('tms_carrier')
            .update({ vehicle_count: count }, { count: 'exact' })
            .eq('id', carrierId) as unknown as SupabaseProviderQueryLike,
        {
          showErrorMessage: true,
          breakReturn: true
        }
      )
    })
  )
}

const getVehicleArchiveSearchFilters = (params: VehicleArchiveSearchParams): FilterSpec[] => [
  { col: 'carrierId', op: 'eq', val: params.carrierId },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'vehicleType', op: 'eq', val: params.vehicleType },
  {
    col: 'manufacturer',
    op: 'ilike',
    val: params.manufacturer ? `%${params.manufacturer}%` : undefined
  },
  { col: 'vin', op: 'ilike', val: params.vin ? `%${params.vin}%` : undefined },
  { col: 'operationStatus', op: 'eq', val: params.operationStatus },
  { col: 'auditStatus', op: 'eq', val: params.auditStatus },
  { col: 'auditStatus', op: 'in', val: params.auditStatuses }
]

export async function fetchVehicleArchiveList(
  params: VehicleArchiveSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ARCHIVE_TABLE)
    .select(VEHICLE_ARCHIVE_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  const [startTime, endTime] = createTimeRange ?? []
  if (startTime) query = query.gte('create_time', startTime)
  if (endTime) query = query.lte('create_time', endTime)

  query = applyFilters(query, getVehicleArchiveSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleArchive[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function exportVehicleArchiveList(
  params: VehicleArchiveSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, createTimeRange } = params
  let query = supabase
    .from(VEHICLE_ARCHIVE_TABLE)
    .select(VEHICLE_ARCHIVE_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    const [startTime, endTime] = createTimeRange ?? []
    if (startTime) query = query.gte('create_time', startTime)
    if (endTime) query = query.lte('create_time', endTime)
    query = applyFilters(query, getVehicleArchiveSearchFilters(params), {
      skipEmpty: true,
      camelToSnake: true
    })
  }

  return await responseHandle<VehicleArchive[]>(
    () => query as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchVehicleArchiveDetail(id: string) {
  return await responseHandle<VehicleArchive>(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .select(VEHICLE_ARCHIVE_SELECT)
        .eq('id', id)
        .single() as unknown as SupabaseProviderQueryLike,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleArchive(params: VehicleArchiveWritePayload) {
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .insert(keysToSnakeDeep(params)) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

export async function editVehicleArchive(params: VehicleArchiveWritePayload) {
  const { id, ...payload } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function fetchVehicleArchiveDeletePreview(id: string) {
  const ids = [id]
  const [waybillCount, relatedCounts] = await Promise.all([
    countRowsByVehicleIds('tms_waybill', 'vehicle_id', ids),
    fetchVehicleArchiveDeleteRelatedCounts(ids)
  ])
  const relatedTotal = relatedCounts.reduce((total, item) => total + item.count, 0)

  return {
    data: {
      waybillCount,
      relatedCounts,
      relatedTotal
    } satisfies VehicleArchiveDeletePreview,
    total: 0,
    error: null
  }
}

export async function deleteVehicleArchive(id: string) {
  const ids = [id]
  const carrierIds = await fetchVehicleArchiveCarrierIds(ids)
  const preview = await fetchVehicleArchiveDeletePreview(id)

  if (preview.data.waybillCount > 0) {
    throw new Error(`该车辆已关联 ${preview.data.waybillCount} 条运单，禁止删除`)
  }

  await Promise.all(
    VEHICLE_ARCHIVE_RELATED_DELETE_ITEMS.map((item) => deleteRowsByVehicleIds(item.tableName, ids))
  )

  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .delete({ count: 'exact' })
        .eq('id', id) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      message:
        preview.data.relatedTotal > 0
          ? `删除成功，已清理 ${preview.data.relatedTotal} 条关联附属记录`
          : '删除成功',
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  ).finally(() => refreshCarrierVehicleCounts(carrierIds))
}

export async function deleteVehicleArchiveBatch(ids: string[]) {
  await assertVehicleArchiveNoWaybill(ids)
  const carrierIds = await fetchVehicleArchiveCarrierIds(ids)

  await Promise.all(
    VEHICLE_ARCHIVE_RELATED_DELETE_ITEMS.map((item) => deleteRowsByVehicleIds(item.tableName, ids))
  )

  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .delete({ count: 'exact' })
        .in('id', ids) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  ).finally(() => refreshCarrierVehicleCounts(carrierIds))
}

export async function auditVehicleArchive(params: {
  id: string
  auditStatus: VehicleArchiveAuditStatus
  auditRemark?: string
}) {
  const { id, auditStatus, auditRemark = '' } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .update(
          keysToSnakeDeep({
            auditStatus,
            auditRemark,
            auditTime: new Date().toISOString()
          }),
          { count: 'exact' }
        )
        .eq('id', id) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function auditVehicleArchiveBatch(params: {
  ids: string[]
  auditStatus: VehicleArchiveAuditStatus
  auditRemark?: string
}) {
  const { ids, auditStatus, auditRemark = '' } = params
  return await responseHandle(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .update(
          keysToSnakeDeep({
            auditStatus,
            auditRemark,
            auditTime: new Date().toISOString()
          }),
          { count: 'exact' }
        )
        .in('id', ids) as unknown as SupabaseProviderQueryLike,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 车辆管理选项
export async function fetchVehicleArchiveOptions(
  params: Partial<Pick<VehicleArchive, 'carrierId' | 'plateNo' | 'companyName'>> = {},
  options?: ApiRequestOptions
) {
  const { carrierId, plateNo, companyName } = params
  const filters: FilterSpec[] = [
    { col: 'carrierId', op: 'eq', val: carrierId },
    { col: 'plateNo', op: 'ilike', val: plateNo ? `%${plateNo}%` : undefined },
    { col: 'companyName', op: 'ilike', val: companyName ? `%${companyName}%` : undefined }
  ]

  let query = supabase
    .from(VEHICLE_ARCHIVE_TABLE)
    .select('id, plate_no, company_name, vin, self_no, carrier_id, vehicle_type')
    .order('plate_no', { ascending: true })
    .limit(200)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle<Api.VehicleMgtSys.VehicleManage.VehicleOption[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchVehicleReminderCompanyOptions() {
  const results = await Promise.all(
    VEHICLE_REMINDER_VIEWS.map((viewName) =>
      responseHandle<VehicleReminderCompanyOption[]>(
        () =>
          supabase
            .from(viewName)
            .select('company_name')
            .not('company_name', 'is', null)
            .neq('company_name', '')
            .order('company_name', { ascending: true }) as unknown as SupabaseProviderQueryLike,
        { ignoreCheck: true, showErrorMessage: true }
      )
    )
  )

  const companyNames = new Set<string>()
  results.forEach((result) => {
    const rows = result.data ?? []
    rows.forEach((item) => {
      if (item.companyName) companyNames.add(item.companyName)
    })
  })

  return {
    data: [...companyNames]
      .sort((first, second) => first.localeCompare(second, 'zh-CN'))
      .map((companyName) => ({ companyName })),
    error: null
  }
}

export async function fetchVehicleReminderInsuranceExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_insurance_expiry',
    'insurance',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderInspectionExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_inspection_expiry',
    'inspection',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderVehicleServiceLifeList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_vehicle_service_life',
    'vehicle',
    params,
    'days',
    options
  )
}

export async function fetchVehicleReminderMaintenanceExpiryList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_maintenance_expiry',
    'maintenance',
    params,
    'expired',
    options
  )
}

export async function fetchVehicleReminderPartServiceLifeList(
  params: VehicleReminderSearchParams,
  options?: ApiRequestOptions
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_part_service_life',
    'part',
    params,
    'expired',
    options
  )
}

export async function fetchInsuranceCompanyOptions(_params?: unknown, options?: ApiRequestOptions) {
  const query = supabase
    .from('vehicle_insurance_company')
    .select('id, company_name, contact_person, contact_phone')
    .order('company_name', { ascending: true })
    .limit(200)

  return await responseHandle<Api.VehicleMgtSys.VehicleManage.InsuranceCompanyOption[]>(
    () => withRequestOptions(query as unknown as SupabaseProviderQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}
