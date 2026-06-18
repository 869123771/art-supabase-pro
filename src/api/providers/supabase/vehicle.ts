import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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

const normalizePartsPayload = async (params: Parts): Promise<Parts> => {
  const payload = { ...params }

  if (payload.categoryId) {
    const { data } = await responseHandle<Pick<PartsCategory, 'categoryName'>[]>(
      () =>
        supabase
          .from('vehicle_parts_category')
          .select('category_name')
          .eq('id', payload.categoryId)
          .limit(1) as any,
      { ignoreCheck: true, showErrorMessage: true }
    )
    payload.categoryName = data?.[0]?.categoryName ?? payload.categoryName ?? ''
  } else {
    payload.categoryName = ''
  }

  if (payload.supplierId) {
    const { data } = await responseHandle<
      Pick<Supplier, 'supplierName' | 'contactPerson' | 'contactPhone'>[]
    >(
      () =>
        supabase
          .from('vehicle_supplier')
          .select('supplier_name, contact_person, contact_phone')
          .eq('id', payload.supplierId)
          .limit(1) as any,
      { ignoreCheck: true, showErrorMessage: true }
    )
    const supplier = data?.[0]
    payload.supplierName = supplier?.supplierName ?? payload.supplierName ?? ''
    payload.supplierContact =
      payload.supplierContact ||
      [supplier?.contactPerson, supplier?.contactPhone].filter(Boolean).join(' / ')
  } else {
    payload.supplierName = ''
  }

  return payload
}

export async function fetchPartsList(params: PartsSearchParams) {
  const { from = 0, to = 9 } = params
  const filters = getPartsSearchFilters(params)

  let query: any = supabase
    .from('vehicle_parts')
    .select('*', { count: 'exact' })
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

export async function addParts(params: Parts) {
  const payload = await normalizePartsPayload(params)
  return await responseHandle(
    () => supabase.from('vehicle_parts').insert(keysToSnakeDeep(payload)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editParts(params: Parts) {
  const { id, ...data } = await normalizePartsPayload(params)
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
  const payload = await Promise.all(rows.map((row) => normalizePartsPayload(row)))
  return await responseHandle(
    () =>
      supabase.from('vehicle_parts').upsert(keysToSnakeDeep(payload), {
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

const getVehicleArchiveSearchFilters = (params: VehicleArchiveSearchParams): FilterSpec[] => [
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
  { col: 'chassisNo', op: 'ilike', val: params.chassisNo ? `%${params.chassisNo}%` : undefined },
  { col: 'operationStatus', op: 'eq', val: params.operationStatus },
  { col: 'auditStatus', op: 'eq', val: params.auditStatus },
  { col: 'auditStatus', op: 'in', val: params.auditStatuses }
]

export async function fetchVehicleArchiveList(params: VehicleArchiveSearchParams) {
  const { from = 0, to = 9, createTimeRange } = params
  let query: any = supabase
    .from(VEHICLE_ARCHIVE_TABLE)
    .select('*', { count: 'exact' })
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
    .select('*')
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
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).select('*').eq('id', id).single() as any,
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

export async function deleteVehicleArchive(id: string) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).delete({ count: 'exact' }).eq('id', id) as any,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteVehicleArchiveBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from(VEHICLE_ARCHIVE_TABLE).delete({ count: 'exact' }).in('id', ids) as any,
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
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
