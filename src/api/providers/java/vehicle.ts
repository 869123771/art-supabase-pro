import http from '@/utils/http'
import type { QueryResult } from '@/types/api/response'

type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
type InsuranceCompanySearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
type SupplierSearchParams = Api.VehicleMgtSys.BasicInfo.SupplierSearchParams
type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
type PartsCategorySearchParams = Api.VehicleMgtSys.BasicInfo.PartsCategorySearchParams
type Parts = Api.VehicleMgtSys.BasicInfo.Parts
type PartsSearchParams = Api.VehicleMgtSys.BasicInfo.PartsSearchParams
type JavaPageResult<T> = Api.Common.PaginatedResponse<T>

interface RangePaginationParams {
  from?: number
  to?: number
  current?: number
  size?: number
}

const API_PREFIX = '/api/vehicle-manage-system/basic-info'

const ENDPOINTS = {
  insuranceCompany: `${API_PREFIX}/insurance-companies`,
  supplier: `${API_PREFIX}/suppliers`,
  partsCategory: `${API_PREFIX}/parts-categories`,
  parts: `${API_PREFIX}/parts`
}

const withPageParams = <T extends RangePaginationParams>(params: T): T => {
  const nextParams = { ...params }
  const { from, to, current, size } = nextParams

  if (
    typeof from === 'number' &&
    typeof to === 'number' &&
    current === undefined &&
    size === undefined
  ) {
    const pageSize = Math.max(to - from + 1, 1)
    return {
      ...nextParams,
      current: Math.floor(from / pageSize) + 1,
      size: pageSize
    }
  }

  return nextParams
}

const getItemUrl = (baseUrl: string, id?: string) => `${baseUrl}/${id ?? ''}`

const toQueryResult = <T>(data: T, total?: number): QueryResult<T> => ({
  data,
  error: null,
  total
})

const normalizePageResult = <T>(result: JavaPageResult<T>): QueryResult<T[]> => {
  const records = result.records ?? (Array.isArray(result.data) ? result.data : [])
  return toQueryResult(records, result.total ?? result.count ?? records.length)
}

const normalizeListResult = <T>(result: T[] | JavaPageResult<T>): QueryResult<T[]> => {
  if (Array.isArray(result)) return toQueryResult(result, result.length)
  return normalizePageResult(result)
}

// 保险公司
export async function fetchInsuranceCompanyList(params: InsuranceCompanySearchParams) {
  const result = await http.get<JavaPageResult<InsuranceCompany>>({
    url: ENDPOINTS.insuranceCompany,
    params: withPageParams(params)
  })
  return normalizePageResult(result)
}

export async function exportInsuranceCompanyList(
  params: InsuranceCompanySearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await http.get<InsuranceCompany[] | JavaPageResult<InsuranceCompany>>({
    url: `${ENDPOINTS.insuranceCompany}/export`,
    params
  })
  return normalizeListResult(result)
}

export async function addInsuranceCompany(params: InsuranceCompany) {
  return await http.post<InsuranceCompany>({
    url: ENDPOINTS.insuranceCompany,
    data: params,
    showSuccessMessage: true
  })
}

export async function editInsuranceCompany(params: InsuranceCompany) {
  const { id, ...data } = params
  return await http.put<InsuranceCompany>({
    url: getItemUrl(ENDPOINTS.insuranceCompany, id),
    data,
    showSuccessMessage: true
  })
}

export async function deleteInsuranceCompany(id: string) {
  return await http.del<void>({
    url: getItemUrl(ENDPOINTS.insuranceCompany, id),
    showSuccessMessage: true
  })
}

export async function deleteInsuranceCompanyBatch(ids: string[]) {
  return await http.del<void>({
    url: `${ENDPOINTS.insuranceCompany}/batch`,
    data: { ids },
    showSuccessMessage: true
  })
}

export async function importInsuranceCompanies(rows: InsuranceCompany[]) {
  return await http.post<void>({
    url: `${ENDPOINTS.insuranceCompany}/import`,
    data: rows,
    showSuccessMessage: true
  })
}

export async function fetchSupplierList(params: SupplierSearchParams) {
  const result = await http.get<JavaPageResult<Supplier>>({
    url: ENDPOINTS.supplier,
    params: withPageParams(params)
  })
  return normalizePageResult(result)
}

export async function exportSupplierList(
  params: SupplierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await http.get<Supplier[] | JavaPageResult<Supplier>>({
    url: `${ENDPOINTS.supplier}/export`,
    params
  })
  return normalizeListResult(result)
}

// 供应厂商
export async function addSupplier(params: Supplier) {
  return await http.post<Supplier>({
    url: ENDPOINTS.supplier,
    data: params,
    showSuccessMessage: true
  })
}

export async function editSupplier(params: Supplier) {
  const { id, ...data } = params
  return await http.put<Supplier>({
    url: getItemUrl(ENDPOINTS.supplier, id),
    data,
    showSuccessMessage: true
  })
}

export async function deleteSupplier(id: string) {
  return await http.del<void>({
    url: getItemUrl(ENDPOINTS.supplier, id),
    showSuccessMessage: true
  })
}

export async function deleteSupplierBatch(ids: string[]) {
  return await http.del<void>({
    url: `${ENDPOINTS.supplier}/batch`,
    data: { ids },
    showSuccessMessage: true
  })
}

export async function importSuppliers(rows: Supplier[]) {
  return await http.post<void>({
    url: `${ENDPOINTS.supplier}/import`,
    data: rows,
    showSuccessMessage: true
  })
}

// 零部件类别
export async function fetchPartsCategoryList(params: PartsCategorySearchParams) {
  const result = await http.get<JavaPageResult<PartsCategory>>({
    url: ENDPOINTS.partsCategory,
    params: withPageParams(params)
  })
  return normalizePageResult(result)
}

export async function fetchPartsCategoryTree(
  params: Partial<Pick<PartsCategory, 'categoryName'>> = {}
) {
  const result = await http.get<PartsCategory[] | JavaPageResult<PartsCategory>>({
    url: `${ENDPOINTS.partsCategory}/tree`,
    params
  })
  return normalizeListResult(result)
}

export async function exportPartsCategoryList(
  params: PartsCategorySearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await http.get<PartsCategory[] | JavaPageResult<PartsCategory>>({
    url: `${ENDPOINTS.partsCategory}/export`,
    params
  })
  return normalizeListResult(result)
}

export async function addPartsCategory(params: PartsCategory) {
  return await http.post<PartsCategory>({
    url: ENDPOINTS.partsCategory,
    data: params,
    showSuccessMessage: true
  })
}

export async function editPartsCategory(params: PartsCategory) {
  const { id, ...data } = params
  return await http.put<PartsCategory>({
    url: getItemUrl(ENDPOINTS.partsCategory, id),
    data,
    showSuccessMessage: true
  })
}

export async function deletePartsCategory(id: string) {
  return await http.del<void>({
    url: getItemUrl(ENDPOINTS.partsCategory, id),
    showSuccessMessage: true
  })
}

export async function deletePartsCategoryBatch(ids: string[]) {
  return await http.del<void>({
    url: `${ENDPOINTS.partsCategory}/batch`,
    data: { ids },
    showSuccessMessage: true
  })
}

export async function importPartsCategories(rows: PartsCategory[]) {
  return await http.post<void>({
    url: `${ENDPOINTS.partsCategory}/import`,
    data: rows,
    showSuccessMessage: true
  })
}

// 零部件

export async function fetchPartsList(params: PartsSearchParams) {
  const result = await http.get<JavaPageResult<Parts>>({
    url: ENDPOINTS.parts,
    params: withPageParams(params)
  })
  return normalizePageResult(result)
}

export async function exportPartsList(
  params: PartsSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await http.get<Parts[] | JavaPageResult<Parts>>({
    url: `${ENDPOINTS.parts}/export`,
    params
  })
  return normalizeListResult(result)
}

export async function addParts(params: Parts) {
  return await http.post<Parts>({
    url: ENDPOINTS.parts,
    data: params,
    showSuccessMessage: true
  })
}

export async function editParts(params: Parts) {
  const { id, ...data } = params
  return await http.put<Parts>({
    url: getItemUrl(ENDPOINTS.parts, id),
    data,
    showSuccessMessage: true
  })
}

export async function deleteParts(id: string) {
  return await http.del<void>({
    url: getItemUrl(ENDPOINTS.parts, id),
    showSuccessMessage: true
  })
}

export async function deletePartsBatch(ids: string[]) {
  return await http.del<void>({
    url: `${ENDPOINTS.parts}/batch`,
    data: { ids },
    showSuccessMessage: true
  })
}

export async function importParts(rows: Parts[]) {
  return await http.post<void>({
    url: `${ENDPOINTS.parts}/import`,
    data: rows,
    showSuccessMessage: true
  })
}

export async function fetchSupplierOptions() {
  const result = await http.get<
    | Pick<Supplier, 'id' | 'supplierName' | 'contactPerson' | 'contactPhone'>[]
    | JavaPageResult<Pick<Supplier, 'id' | 'supplierName' | 'contactPerson' | 'contactPhone'>>
  >({
    url: `${ENDPOINTS.supplier}/options`
  })
  return normalizeListResult(result)
}
