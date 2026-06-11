import { useSupabase } from '@/hooks'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
type InsuranceCompanySearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
type SupplierSearchParams = Api.VehicleMgtSys.BasicInfo.SupplierSearchParams
type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
type PartsCategorySearchParams = Api.VehicleMgtSys.BasicInfo.PartsCategorySearchParams

// 淇濋櫓鍏徃
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

// 渚涘簲鍘傚晢
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
