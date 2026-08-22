import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase'
import {
  type InsuranceCompany,
  type InsuranceCompanySearchParams,
  type Supplier,
  type SupplierSearchParams,
  type PartsCategory,
  type PartsCategorySearchParams,
  type Parts,
  type PartsSearchParams
} from './types'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 保险公司
export async function fetchInsuranceCompanyList(
  params: InsuranceCompanySearchParams,
  options?: ApiRequestOptions
) {
  const { companyName, contactPerson, contactPhone, from = 0, to = 9 } = params
  const filters: FilterSpec[] = [
    { col: 'companyName', op: 'ilike', val: companyName ? `%${companyName}%` : undefined },
    { col: 'contactPerson', op: 'ilike', val: contactPerson ? `%${contactPerson}%` : undefined },
    { col: 'contactPhone', op: 'ilike', val: contactPhone ? `%${contactPhone}%` : undefined }
  ]

  let query = supabase
    .from('vehicle_insurance_company')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => withRequestOptions(query, options), {
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

  let query = supabase
    .from('vehicle_insurance_company')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  return await responseHandle(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addInsuranceCompany(params: InsuranceCompany) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editInsuranceCompany(params: InsuranceCompany) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteInsuranceCompany(id: string) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').delete().eq('id', id),
    { showMessage: true }
  )
}

export async function deleteInsuranceCompanyBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('vehicle_insurance_company').delete().in('id', ids),
    { showMessage: true }
  )
}

export async function importInsuranceCompanies(rows: InsuranceCompany[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_insurance_company').upsert(keysToSnakeDeep(rows), {
        onConflict: 'company_name'
      }),
    { showMessage: true, breakReturn: true }
  )
}

// 供应厂商
interface SecureSupplierPayload {
  records: Supplier[]
  total: number
  fieldAccess?: Api.Vms.BasicInfo.SupplierFieldAccessMap
}

const createSupplierRpcParams = (
  params: SupplierSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export' | 'options'
) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_supplier_name: String(params.supplierName ?? '').trim() || null,
    p_contact_person: String(params.contactPerson ?? '').trim() || null,
    p_contact_phone: String(params.contactPhone ?? '').trim() || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchSupplierList(params: SupplierSearchParams, options?: ApiRequestOptions) {
  const result = await responseHandle<SecureSupplierPayload>(
    () =>
      withRequestOptions(
        supabase.rpc('vms_list_vehicle_suppliers_secure', createSupplierRpcParams(params, 'list')),
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

export async function exportSupplierList(
  params: SupplierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureSupplierPayload>(
    () =>
      supabase.rpc(
        'vms_list_vehicle_suppliers_secure',
        createSupplierRpcParams({ ...params, maxRows: params.maxRows ?? 10000 }, 'export')
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

export async function addSupplier(params: Supplier) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('vms_create_vehicle_supplier_secure', { p_payload: keysToSnakeDeep(params) }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editSupplier(params: Supplier) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少车辆供应商 ID')
  return await responseHandle<Supplier>(
    () =>
      supabase.rpc('vms_update_vehicle_supplier_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(data)
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteSupplier(id: string) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_suppliers_secure', { p_ids: [id] }),
    { showMessage: true, message: '删除成功' }
  )
}

export async function deleteSupplierBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_delete_vehicle_suppliers_secure', { p_ids: ids }),
    { showMessage: true }
  )
}

export async function importSuppliers(rows: Supplier[]) {
  return await responseHandle<number>(
    () => supabase.rpc('vms_import_vehicle_suppliers_secure', { p_rows: keysToSnakeDeep(rows) }),
    { showMessage: true, breakReturn: true }
  )
}

// 零部件类别
export async function fetchPartsCategoryList(
  params: PartsCategorySearchParams,
  options?: ApiRequestOptions
) {
  const { parentId, categoryName, categoryCode, status, from = 0, to = 9 } = params
  const filters: FilterSpec[] = [
    { col: 'categoryName', op: 'ilike', val: categoryName ? `%${categoryName}%` : undefined },
    { col: 'categoryCode', op: 'ilike', val: categoryCode ? `%${categoryCode}%` : undefined },
    { col: 'status', op: 'eq', val: status }
  ]

  let query = supabase
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

  return await responseHandle(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchPartsCategoryTree(
  params: Partial<Pick<PartsCategory, 'categoryName'>> = {},
  options?: ApiRequestOptions
) {
  const { categoryName } = params
  let query = supabase
    .from('vehicle_parts_category')
    .select('*')
    .order('sort', { ascending: true })
    .order('create_time', { ascending: false })

  if (categoryName) {
    query = query.ilike('category_name', `%${categoryName}%`)
  }

  return await responseHandle<PartsCategory[]>(() => withRequestOptions(query, options), {
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

  let query = supabase
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

  return await responseHandle(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addPartsCategory(params: PartsCategory) {
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editPartsCategory(params: PartsCategory) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deletePartsCategory(id: string) {
  return await responseHandle(() => supabase.from('vehicle_parts_category').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deletePartsCategoryBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('vehicle_parts_category').delete().in('id', ids),
    { showMessage: true }
  )
}

export async function importPartsCategories(rows: PartsCategory[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_parts_category').upsert(keysToSnakeDeep(rows), {
        onConflict: 'category_code'
      }),
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
  )
`

const enrichPartsWithSupplierNames = async (
  records: Parts[],
  options?: ApiRequestOptions
): Promise<Parts[]> => {
  const supplierIds = [...new Set(records.map((row) => row.supplierId).filter(Boolean))] as string[]
  if (!supplierIds.length) return records
  const { data } = await fetchSupplierOptions({ ids: supplierIds }, options)
  const suppliers = new Map<string, Supplier>(
    (data ?? []).flatMap((row) => (row.id ? ([[row.id, row]] as const) : []))
  )
  return records.map((row) => ({
    ...row,
    supplier: row.supplierId ? (suppliers.get(row.supplierId) ?? null) : null
  }))
}

export async function fetchPartsList(params: PartsSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  const filters = getPartsSearchFilters(params)

  let query = supabase
    .from('vehicle_parts')
    .select(PARTS_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  const result = await responseHandle<Parts[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await enrichPartsWithSupplierNames(result.data ?? [], options) }
}

export async function exportPartsList(
  params: PartsSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const filters = getPartsSearchFilters(params)

  let query = supabase
    .from('vehicle_parts')
    .select(PARTS_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  if (ids?.length) {
    query = query.in('id', ids)
  } else {
    query = applyFilters(query, filters, { skipEmpty: true, camelToSnake: true })
  }

  const result = await responseHandle<Parts[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await enrichPartsWithSupplierNames(result.data ?? []) }
}

export async function addParts(params: Parts) {
  return await responseHandle(
    () => supabase.from('vehicle_parts').insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editParts(params: Parts) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('vehicle_parts').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteParts(id: string) {
  return await responseHandle(() => supabase.from('vehicle_parts').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deletePartsBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('vehicle_parts').delete().in('id', ids), {
    showMessage: true
  })
}

export async function importParts(rows: Parts[]) {
  return await responseHandle(
    () =>
      supabase.from('vehicle_parts').upsert(keysToSnakeDeep(rows), {
        onConflict: 'tenant_id,part_code'
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchSupplierOptions(
  params?: { ids?: string[]; supplierName?: string },
  options?: ApiRequestOptions
) {
  const result = await responseHandle<SecureSupplierPayload>(
    () =>
      withRequestOptions(
        supabase.rpc(
          'vms_list_vehicle_suppliers_secure',
          createSupplierRpcParams({ ...params, from: 0, to: 9999 }, 'options')
        ),
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
