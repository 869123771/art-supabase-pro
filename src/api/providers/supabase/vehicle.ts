import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
type InsuranceCompanySearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
type SupplierSearchParams = Api.VehicleMgtSys.BasicInfo.SupplierSearchParams
type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
type PartsCategorySearchParams = Api.VehicleMgtSys.BasicInfo.PartsCategorySearchParams
type Parts = Api.VehicleMgtSys.BasicInfo.Parts
type PartsSearchParams = Api.VehicleMgtSys.BasicInfo.PartsSearchParams
type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
type VehicleArchiveSearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
type VehicleArchiveAuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus
type VehicleArchiveWritePayload = Record<string, unknown> & { id?: string }
interface VehicleArchiveDeleteRelatedCount {
  tableName: string
  label: string
  count: number
}

interface VehicleArchiveDeletePreview {
  waybillCount: number
  relatedCounts: VehicleArchiveDeleteRelatedCount[]
  relatedTotal: number
}

interface VehicleArchiveDeleteBase {
  carrierId?: string | null
}

type VehicleInsurance = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
type VehicleInsuranceSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleInsuranceSearchParams
type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
type VehicleInspectionSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleInspectionSearchParams
type VehicleRoutineInspectionRecord = Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionRecord
type VehicleRoutineInspectionSearchParams =
  Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionSearchParams
type VehicleMileageRecord = Api.VehicleMgtSys.VehicleManage.VehicleMileageRecord
type VehicleMileageSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleMileageSearchParams
type VehicleViolationRecord = Api.VehicleMgtSys.VehicleManage.VehicleViolationRecord
type VehicleViolationSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleViolationSearchParams
type VehicleAccidentRecord = Api.VehicleMgtSys.VehicleManage.VehicleAccidentRecord
type VehicleAccidentSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleAccidentSearchParams
type VehicleMaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
type VehicleMaintenanceSearchParams = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceSearchParams
type VehiclePartUsage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
type VehiclePartUsageSearchParams = Api.VehicleMgtSys.VehicleManage.VehiclePartUsageSearchParams
type VehicleReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow
type VehicleReminderSearchParams = Api.VehicleMgtSys.ReminderManage.VehicleReminderSearchParams

interface VehicleReminderCompanyOption {
  companyName: string
}

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

const VEHICLE_REMINDER_VIEWS = [
  'vehicle_reminder_insurance_expiry',
  'vehicle_reminder_inspection_expiry',
  'vehicle_reminder_maintenance_expiry',
  'vehicle_reminder_part_service_life',
  'vehicle_reminder_vehicle_service_life'
] as const

type VehicleReminderViewName = (typeof VEHICLE_REMINDER_VIEWS)[number]

const getVehicleReminderSearchFilters = (
  params: VehicleReminderSearchParams,
  mode: 'days' | 'expired'
): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'expired',
    op: 'eq',
    val: mode === 'expired' ? normalizeBooleanFilter(params.expired) : undefined
  }
]

async function fetchVehicleReminderViewList(
  viewName: VehicleReminderViewName,
  params: VehicleReminderSearchParams,
  mode: 'days' | 'expired'
) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from(viewName)
    .select('*', { count: 'exact' })
    .order('remaining_days', { ascending: true })
    .range(from, to)

  if (mode === 'days' && params.reminderDays !== null && params.reminderDays !== undefined) {
    query = query.lte('remaining_days', Number(params.reminderDays))
  }

  query = applyFilters(query, getVehicleReminderSearchFilters(params, mode), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleReminderRow[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 保险公司
export async function fetchInsuranceCompanyList(params: InsuranceCompanySearchParams) {
  const { companyName, contactPerson, contactPhone, from = 0, to = 9 } = params
  const filters: FilterSpec[] = [
    { col: 'companyName', op: 'ilike', val: companyName ? `%${companyName}%` : undefined },
    { col: 'contactPerson', op: 'ilike', val: contactPerson ? `%${contactPerson}%` : undefined },
    { col: 'contactPhone', op: 'ilike', val: contactPhone ? `%${contactPhone}%` : undefined }
  ]

  let query: any = supabase
    .from('vehicle_insurance_company')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportInsuranceCompanyList(
  params: InsuranceCompanySearchParams & { ids?: string[]; maxRows?: number }
) {
  const { companyName, contactPerson, contactPhone, ids, maxRows = 10000 } = params
  const filters: FilterSpec[] = [
    { col: 'companyName', op: 'ilike', val: companyName ? `%${companyName}%` : undefined },
    { col: 'contactPerson', op: 'ilike', val: contactPerson ? `%${contactPerson}%` : undefined },
    { col: 'contactPhone', op: 'ilike', val: contactPhone ? `%${contactPhone}%` : undefined }
  ]

  let query: any = supabase
    .from('vehicle_insurance_company')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addInsuranceCompany(params: InsuranceCompany) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editInsuranceCompany(params: InsuranceCompany) {
  const { id, ...data } = params
  return await responseHandle(
    () =>
      supabase.from('vehicle_insurance_company').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteInsuranceCompany(id: string) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deleteInsuranceCompanyBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

export async function importInsuranceCompanies(rows: InsuranceCompany[]) {
  return await responseHandle(
    () =>
      supabase
        .from('vehicle_insurance_company')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'company_name' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

// 供应厂商
export async function fetchSupplierList(params: SupplierSearchParams) {
  const { supplierName, contactPerson, contactPhone, from = 0, to = 9 } = params
  const filters: FilterSpec[] = [
    { col: 'supplierName', op: 'ilike', val: supplierName ? `%${supplierName}%` : undefined },
    { col: 'contactPerson', op: 'ilike', val: contactPerson ? `%${contactPerson}%` : undefined },
    { col: 'contactPhone', op: 'ilike', val: contactPhone ? `%${contactPhone}%` : undefined }
  ]

  let query: any = supabase
    .from('vehicle_supplier')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportSupplierList(
  params: SupplierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { supplierName, contactPerson, contactPhone, ids, maxRows = 10000 } = params
  const filters: FilterSpec[] = [
    { col: 'supplierName', op: 'ilike', val: supplierName ? `%${supplierName}%` : undefined },
    { col: 'contactPerson', op: 'ilike', val: contactPerson ? `%${contactPerson}%` : undefined },
    { col: 'contactPhone', op: 'ilike', val: contactPhone ? `%${contactPhone}%` : undefined }
  ]

  let query: any = supabase
    .from('vehicle_supplier')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addSupplier(params: Supplier) {
  return await responseHandle(
    () => supabase.from('vehicle_supplier').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editSupplier(params: Supplier) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_supplier').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteSupplier(id: string) {
  return await responseHandle(
    () => supabase.from('vehicle_supplier').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deleteSupplierBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('vehicle_supplier').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

export async function importSuppliers(rows: Supplier[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_supplier').upsert(keysToSnakeDeep(rows), {
        onConflict: 'create_by,supplier_name'
      }) as any,
    { showMessage: true, breakReturn: true }
  )
}

// 零部件类别
export async function fetchPartsCategoryList(params: PartsCategorySearchParams) {
  const { parentId, categoryName, categoryCode, status, from = 0, to = 9 } = params
  const filters: FilterSpec[] = [
    { col: 'categoryName', op: 'ilike', val: categoryName ? `%${categoryName}%` : undefined },
    { col: 'categoryCode', op: 'ilike', val: categoryCode ? `%${categoryCode}%` : undefined },
    { col: 'status', op: 'eq', val: status }
  ]

  let query: any = supabase
    .from('vehicle_parts_category')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('create_time', { ascending: false })
    .range(from, to)

  query =
    parentId === null || parentId === undefined || parentId === ''
      ? query.is('parent_id', null)
      : query.eq('parent_id', parentId)
  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchPartsCategoryTree(
  params: Partial<Pick<PartsCategory, 'categoryName'>> = {}
) {
  const { categoryName } = params
  let query: any = supabase
    .from('vehicle_parts_category')
    .select('*')
    .order('sort', { ascending: true })
    .order('create_time', { ascending: false })

  if (categoryName) {
    query = query.ilike('category_name', `%${categoryName}%`)
  }

  return await responseHandle<PartsCategory[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportPartsCategoryList(
  params: PartsCategorySearchParams & { ids?: string[]; maxRows?: number }
) {
  const { parentId, categoryName, categoryCode, status, ids, maxRows = 10000 } = params
  const filters: FilterSpec[] = [
    { col: 'categoryName', op: 'ilike', val: categoryName ? `%${categoryName}%` : undefined },
    { col: 'categoryCode', op: 'ilike', val: categoryCode ? `%${categoryCode}%` : undefined },
    { col: 'status', op: 'eq', val: status }
  ]

  let query: any = supabase
    .from('vehicle_parts_category')
    .select('*')
    .order('sort', { ascending: true })
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query =
      parentId === null || parentId === undefined || parentId === ''
        ? query.is('parent_id', null)
        : query.eq('parent_id', parentId)
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addPartsCategory(params: PartsCategory) {
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editPartsCategory(params: PartsCategory) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deletePartsCategory(id: string) {
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deletePartsCategoryBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

export async function importPartsCategories(rows: PartsCategory[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_parts_category').upsert(keysToSnakeDeep(rows), {
        onConflict: 'category_code'
      }) as any,
    { showMessage: true, breakReturn: true }
  )
}

// 零部件
const getPartsSearchFilters = (params: PartsSearchParams): FilterSpec[] => [
  { col: 'partName', op: 'ilike', val: params.partName ? `%${params.partName}%` : undefined },
  { col: 'partCode', op: 'ilike', val: params.partCode ? `%${params.partCode}%` : undefined },
  { col: 'categoryId', op: 'eq', val: params.categoryId },
  { col: 'brand', op: 'ilike', val: params.brand ? `%${params.brand}%` : undefined },
  { col: 'model', op: 'ilike', val: params.model ? `%${params.model}%` : undefined },
  { col: 'supplierId', op: 'eq', val: params.supplierId },
  { col: 'status', op: 'eq', val: params.status }
]

const PARTS_SELECT = `
  *,
  category:vehicle_parts_category!vehicle_parts_category_id_fkey(
    id,
    category_name
  ),
  supplier:vehicle_supplier!vehicle_parts_supplier_id_fkey(
    id,
    supplier_name,
    contact_person,
    contact_phone
  )
`

export async function fetchPartsList(params: PartsSearchParams) {
  const { from = 0, to = 9 } = params
  const filters = getPartsSearchFilters(params)

  let query: any = supabase
    .from('vehicle_parts')
    .select(PARTS_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportPartsList(
  params: PartsSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const filters = getPartsSearchFilters(params)

  let query: any = supabase
    .from('vehicle_parts')
    .select(PARTS_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addParts(params: Parts) {
  return await responseHandle(
    () => supabase.from('vehicle_parts').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editParts(params: Parts) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_parts').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteParts(id: string) {
  return await responseHandle(() => supabase.from('vehicle_parts').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deletePartsBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('vehicle_parts').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importParts(rows: Parts[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_parts').upsert(keysToSnakeDeep(rows), {
        onConflict: 'tenant_id,part_code'
      }) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchSupplierOptions() {
  const query = supabase
    .from('vehicle_supplier')
    .select('id, supplier_name, contact_person, contact_phone')
    .order('supplier_name', { ascending: true })

  return await responseHandle(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 车辆档案
const VEHICLE_ARCHIVE_TABLE = 'vehicle_archive'

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

  const result = await responseHandle(() => query as any, {
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

  const result = await responseHandle<VehicleArchiveDeleteBase[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true,
    breakReturn: true
  })

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

  await responseHandle(() => query as any, {
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
            .eq('id', carrierId) as any,
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

export async function fetchVehicleArchiveList(params: VehicleArchiveSearchParams) {
  const { from = 0, to = 9, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleArchive[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleArchiveList(
  params: VehicleArchiveSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleArchive[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleArchiveDetail(id: string) {
  return await responseHandle<VehicleArchive>(
    () =>
      supabase
        .from(VEHICLE_ARCHIVE_TABLE)
        .select(VEHICLE_ARCHIVE_SELECT)
        .eq('id', id)
        .single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleArchive(params: VehicleArchiveWritePayload) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
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
        .eq('id', id) as any,
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
        .in('id', ids) as any,
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
  params: Partial<Pick<VehicleArchive, 'carrierId' | 'plateNo' | 'companyName'>> = {}
) {
  const { carrierId, plateNo, companyName } = params
  const filters: FilterSpec[] = [
    { col: 'carrierId', op: 'eq', val: carrierId },
    { col: 'plateNo', op: 'ilike', val: plateNo ? `%${plateNo}%` : undefined },
    { col: 'companyName', op: 'ilike', val: companyName ? `%${companyName}%` : undefined }
  ]

  let query: any = supabase
    .from(VEHICLE_ARCHIVE_TABLE)
    .select('id, plate_no, company_name, vin, self_no, carrier_id, vehicle_type')
    .order('plate_no', { ascending: true })
    .limit(200)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle<Api.VehicleMgtSys.VehicleManage.VehicleOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
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
            .order('company_name', { ascending: true }) as any,
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

export async function fetchVehicleReminderInsuranceExpiryList(params: VehicleReminderSearchParams) {
  return await fetchVehicleReminderViewList('vehicle_reminder_insurance_expiry', params, 'days')
}

export async function fetchVehicleReminderInspectionExpiryList(
  params: VehicleReminderSearchParams
) {
  return await fetchVehicleReminderViewList('vehicle_reminder_inspection_expiry', params, 'days')
}

export async function fetchVehicleReminderVehicleServiceLifeList(
  params: VehicleReminderSearchParams
) {
  return await fetchVehicleReminderViewList('vehicle_reminder_vehicle_service_life', params, 'days')
}

export async function fetchVehicleReminderMaintenanceExpiryList(
  params: VehicleReminderSearchParams
) {
  return await fetchVehicleReminderViewList(
    'vehicle_reminder_maintenance_expiry',
    params,
    'expired'
  )
}

export async function fetchVehicleReminderPartServiceLifeList(params: VehicleReminderSearchParams) {
  return await fetchVehicleReminderViewList('vehicle_reminder_part_service_life', params, 'expired')
}

export async function fetchInsuranceCompanyOptions() {
  const query = supabase
    .from('vehicle_insurance_company')
    .select('id, company_name, contact_person, contact_phone')
    .order('company_name', { ascending: true })
    .limit(200)

  return await responseHandle<Api.VehicleMgtSys.VehicleManage.InsuranceCompanyOption[]>(
    () => query as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

// 车辆保险
const VEHICLE_INSURANCE_TABLE = 'vehicle_insurance'

const applyDateRange = (query: any, column: string, range?: string[]): any => {
  const [startDate, endDate] = range ?? []
  if (startDate) query = query.gte(column, startDate)
  if (endDate) query = query.lte(column, endDate)
  return query
}

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

export async function fetchVehicleInsuranceList(params: VehicleInsuranceSearchParams) {
  const {
    from = 0,
    to = 9,
    commercialExpireDateRange,
    compulsoryExpireDateRange,
    createTimeRange
  } = params
  let query: any = supabase
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

  return await responseHandle<VehicleInsurance[]>(() => query as any, {
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
  let query: any = supabase
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

  return await responseHandle<VehicleInsurance[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleInsuranceDetail(id: string) {
  return await responseHandle<VehicleInsurance>(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleInsurance(params: VehicleInsurance) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSURANCE_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_INSURANCE_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_INSURANCE_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
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

export async function fetchVehicleInspectionList(params: VehicleInspectionSearchParams) {
  const { from = 0, to = 9, expireDateRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleInspection[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleInspectionList(
  params: VehicleInspectionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, expireDateRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleInspection[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleInspectionDetail(id: string) {
  return await responseHandle<VehicleInspection>(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}
export async function addVehicleInspection(params: VehicleInspection) {
  return await responseHandle(
    () => supabase.from(VEHICLE_INSPECTION_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_INSPECTION_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_INSPECTION_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
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
  params: VehicleRoutineInspectionSearchParams
) {
  const { from = 0, to = 9, inspectionTimeRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleRoutineInspectionRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleRoutineInspectionList(
  params: VehicleRoutineInspectionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, inspectionTimeRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleRoutineInspectionRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleRoutineInspectionDetail(id: string) {
  return await responseHandle<VehicleRoutineInspectionRecord>(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleRoutineInspection(params: VehicleRoutineInspectionRecord) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ROUTINE_INSPECTION_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () =>
      supabase
        .from(VEHICLE_ROUTINE_INSPECTION_TABLE)
        .delete({ count: 'exact' })
        .eq('id', id) as any,
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
    () =>
      supabase
        .from(VEHICLE_ROUTINE_INSPECTION_TABLE)
        .delete({ count: 'exact' })
        .in('id', ids) as any,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

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

export async function fetchVehicleMileageList(params: VehicleMileageSearchParams) {
  const { from = 0, to = 9, drivingTimeRange } = params
  let query: any = supabase
    .from(VEHICLE_MILEAGE_TABLE)
    .select('*', { count: 'exact' })
    .order('start_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'start_time', drivingTimeRange)
  query = applyFilters(query, getVehicleMileageSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleMileageRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleMileageList(
  params: VehicleMileageSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, drivingTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleMileageRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
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

export async function fetchVehicleViolationList(params: VehicleViolationSearchParams) {
  const { from = 0, to = 9, violationTimeRange } = params
  let query: any = supabase
    .from(VEHICLE_VIOLATION_TABLE)
    .select('*', { count: 'exact' })
    .order('violation_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'violation_time', violationTimeRange)
  query = applyFilters(query, getVehicleViolationSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleViolationRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleViolationList(
  params: VehicleViolationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, violationTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleViolationRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
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

export async function fetchVehicleAccidentList(params: VehicleAccidentSearchParams) {
  const { from = 0, to = 9, accidentTimeRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleAccidentRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleAccidentList(
  params: VehicleAccidentSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, accidentTimeRange, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleAccidentRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleAccidentDetail(id: string) {
  return await responseHandle<VehicleAccidentRecord>(
    () => supabase.from(VEHICLE_ACCIDENT_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleAccident(params: VehicleAccidentRecord) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ACCIDENT_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_ACCIDENT_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_ACCIDENT_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

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

export async function fetchVehicleMaintenanceList(params: VehicleMaintenanceSearchParams) {
  const { from = 0, to = 9, createTimeRange } = params
  let query: any = supabase
    .from(VEHICLE_MAINTENANCE_TABLE)
    .select('*', { count: 'exact' })
    .order('start_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehicleMaintenanceSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehicleMaintenanceRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVehicleMaintenanceList(
  params: VehicleMaintenanceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, createTimeRange } = params
  let query: any = supabase
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

  return await responseHandle<VehicleMaintenanceRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehicleMaintenanceDetail(id: string) {
  return await responseHandle<VehicleMaintenanceRecord>(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehicleMaintenance(params: VehicleMaintenanceRecord) {
  return await responseHandle(
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_MAINTENANCE_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
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

export async function fetchVehiclePartUsageList(params: VehiclePartUsageSearchParams) {
  const { from = 0, to = 9, createTimeRange } = params
  let query: any = supabase
    .from(VEHICLE_PART_USAGE_TABLE)
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDateRange(query, 'create_time', createTimeRange)
  query = applyFilters(query, getVehiclePartUsageSearchFilters(params), {
    skipEmpty: true,
    camelToSnake: true
  })

  return await responseHandle<VehiclePartUsage[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVehiclePartUsageDetail(id: string) {
  return await responseHandle<VehiclePartUsage>(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).select('*').eq('id', id).single() as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function addVehiclePartUsage(params: VehiclePartUsage) {
  return await responseHandle(
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).insert(keysToSnakeDeep(params)) as any,
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
        .eq('id', id) as any,
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
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
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
    () => supabase.from(VEHICLE_PART_USAGE_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}
