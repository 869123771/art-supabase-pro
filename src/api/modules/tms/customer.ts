import { useSupabase } from '@/hooks'
import {
  applyCreateTimeRange,
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Customer = Api.Tms.BasicData.Customer
type CustomerSearchParams = Api.Tms.BasicData.CustomerSearchParams
type CustomerAddress = Api.Tms.BasicData.CustomerAddress
type CustomerAddressSearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
type FavoriteRouteSearchParams = Api.Tms.BasicData.FavoriteRouteSearchParams
type CustomerSelectorItem = Api.Tms.Order.CustomerSelectorItem
type CustomerSelectorSearchParams = Api.Tms.Order.CustomerSelectorSearchParams

interface WriteOptions {
  showMessage?: boolean
}

interface CustomerOptionParams {
  excludeId?: string
  includeDisabled?: boolean
}

export type CustomerDeleteDependencyCode =
  | 'cash_allocation'
  | 'cash_transaction'
  | 'contract'
  | 'customer_price'
  | 'customer_statement'
  | 'customer_statement_item'
  | 'invoice'

export interface CustomerDeleteDependency {
  customerId: string
  dependencyCode: CustomerDeleteDependencyCode
  dependencyCount: number
}

export interface CustomerDeleteDependencyDetail {
  customerId: string
  dependencyCode: CustomerDeleteDependencyCode
  recordId: string
  targetId: string
  recordNo: string
  recordSummary?: string | null
  recordStatus?: string | null
  recordAmount?: number | null
  createdAt: string
}

export type CustomerDeleteSafeCleanupCode = Extract<
  CustomerDeleteDependencyCode,
  'customer_price' | 'customer_statement' | 'invoice'
>

export interface CustomerDeleteSafeCleanupCandidate {
  customerId: string
  dependencyCode: CustomerDeleteSafeCleanupCode
  recordId: string
}

export interface CustomerDeleteSafeCleanupResult {
  dependencyCode: CustomerDeleteSafeCleanupCode
  deletedCount: number
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const applyCustomerFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: CustomerSearchParams
): TQuery => {
  const { customerId, customerLevel, industry, enabled, keyword, createTimeRange } = params
  if (customerId) query = query.eq('id', customerId)
  if (customerLevel) query = query.eq('customer_level', customerLevel)
  if (industry) query = query.eq('industry', industry)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `customer_name.ilike.%${keyword}%,customer_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchCustomerList(params: CustomerSearchParams, options?: ApiRequestOptions) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCustomerList(
  params: CustomerSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_customer')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerOptions(
  params: CustomerOptionParams = {},
  options?: ApiRequestOptions
) {
  const { excludeId, includeDisabled = false } = params
  let query = supabase
    .from('tms_customer')
    .select(
      'id, customer_code, customer_name, enabled, contact_name, contact_phone, region, region_adcode, address_detail, longitude, latitude, coordinate_system, coordinate_source, coordinate_status, geocode_provider, geocoded_at, postal_code'
    )
    .order('customer_name', { ascending: true })
    .limit(1000)

  if (!includeDisabled) query = query.eq('enabled', true)
  if (excludeId) query = query.neq('id', excludeId)

  return await responseHandle<Api.Tms.BasicData.CustomerOption[]>(
    () => withRequestOptions(query, options),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchCustomerSelectorList(
  params: CustomerSelectorSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, keyword } = params
  let query = supabase
    .from('tms_customer')
    .select(
      'id, customer_code, customer_name, contact_name, contact_phone, region, region_adcode, address_detail, longitude, latitude',
      { count: 'exact' }
    )
    .eq('enabled', true)
    .order('create_time', { ascending: false })
    .range(from, to)
  if (keyword) {
    query = query.or(
      `customer_name.ilike.%${keyword}%,customer_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,address_detail.ilike.%${keyword}%`
    )
  }
  return await responseHandle<CustomerSelectorItem[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomer(params: Customer, options: WriteOptions = {}) {
  return await responseHandle<Customer>(
    () => supabase.from('tms_customer').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function editCustomer(params: Customer) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_customer').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchCustomerDeleteDependencies(
  customerIds: string[]
): Promise<CustomerDeleteDependency[]> {
  if (!customerIds.length) return []
  const { data } = await responseHandle<CustomerDeleteDependency[]>(
    () => supabase.rpc('get_tms_customer_delete_dependencies', { p_customer_ids: customerIds }),
    { breakReturn: true }
  )
  return (data ?? []).map((item) => ({
    ...item,
    dependencyCount: Number(item.dependencyCount) || 0
  }))
}

export async function fetchCustomerDeleteDependencyDetails(
  customerIds: string[]
): Promise<CustomerDeleteDependencyDetail[]> {
  if (!customerIds.length) return []
  const { data } = await responseHandle<CustomerDeleteDependencyDetail[]>(
    () =>
      supabase.rpc('get_tms_customer_delete_dependency_details', { p_customer_ids: customerIds }),
    { breakReturn: true }
  )
  return (data ?? []).map((item) => ({
    ...item,
    recordAmount:
      item.recordAmount === null || item.recordAmount === undefined
        ? null
        : Number(item.recordAmount)
  }))
}

export async function fetchCustomerDeleteSafeCleanupCandidates(
  customerIds: string[]
): Promise<CustomerDeleteSafeCleanupCandidate[]> {
  if (!customerIds.length) return []
  const { data } = await responseHandle<CustomerDeleteSafeCleanupCandidate[]>(
    () =>
      supabase.rpc('get_tms_customer_delete_safe_cleanup_candidates', {
        p_customer_ids: customerIds
      }),
    { breakReturn: true }
  )
  return data ?? []
}

export async function cleanupCustomerDeleteSafeDependencies(
  customerIds: string[]
): Promise<CustomerDeleteSafeCleanupResult[]> {
  if (!customerIds.length) return []
  const { data } = await responseHandle<CustomerDeleteSafeCleanupResult[]>(
    () =>
      supabase.rpc('cleanup_tms_customer_safe_delete_dependencies', {
        p_customer_ids: customerIds
      }),
    { breakReturn: true }
  )
  return (data ?? []).map((item) => ({
    ...item,
    deletedCount: Number(item.deletedCount) || 0
  }))
}

export async function deleteCustomer(id: string) {
  return await responseHandle(
    () => supabase.from('tms_customer').delete({ count: 'exact' }).eq('id', id),
    { breakReturn: true, requireAffected: true }
  )
}

export async function deleteCustomerBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_customer').delete({ count: 'exact' }).in('id', ids),
    { breakReturn: true, requireAffected: true }
  )
}

export async function importCustomers(rows: Customer[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_customer')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,customer_code' }),
    { showMessage: true, breakReturn: true }
  )
}

const applyCustomerAddressFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: CustomerAddressSearchParams
): TQuery => {
  const { customerId, addressType, keyword, createTimeRange, recordId } = params
  if (recordId) query = query.eq('id', recordId)
  if (customerId) query = query.eq('customer_id', customerId)
  if (addressType) query = query.eq('address_type', addressType)
  if (keyword) {
    query = query.or(
      `contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,address_detail.ilike.%${keyword}%`
    )
  }
  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchCustomerAddressList(
  params: CustomerAddressSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer_address')
    .select(
      '*, customer:tms_customer!tms_customer_address_customer_id_fkey(id, customer_code, customer_name, contact_name, contact_phone)',
      { count: 'exact' }
    )
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .range(from, to)
  query = applyCustomerAddressFilters(query, params)
  return await responseHandle<CustomerAddress[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerDefaultAddress(
  customerId: string,
  addressType: CustomerAddress['addressType']
) {
  return await responseHandle<CustomerAddress | null>(
    () =>
      supabase
        .from('tms_customer_address')
        .select('*')
        .eq('customer_id', customerId)
        .eq('address_type', addressType)
        .order('is_default', { ascending: false })
        .order('update_time', { ascending: false, nullsFirst: false })
        .order('create_time', { ascending: false, nullsFirst: false })
        .limit(1)
        .maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function addCustomerAddress(params: CustomerAddress, options: WriteOptions = {}) {
  return await responseHandle<CustomerAddress>(
    () => supabase.from('tms_customer_address').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
}

export async function editCustomerAddress(params: CustomerAddress) {
  const { id } = params
  const data = { ...params }
  delete data.id
  delete data.customer
  return await responseHandle<CustomerAddress>(
    () =>
      supabase
        .from('tms_customer_address')
        .update(keysToSnakeDeep(data), { count: 'exact' })
        .eq('id', id)
        .select()
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCustomerAddress(id: string) {
  return await responseHandle(
    () => supabase.from('tms_customer_address').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCustomerAddressBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_customer_address').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function updateCustomerAddressGeofence(
  id: string,
  payload: Pick<CustomerAddress, 'geofenceEnabled' | 'geofenceRadiusM' | 'geofenceUpdatedAt'>
) {
  return await responseHandle<CustomerAddress>(
    () =>
      supabase
        .from('tms_customer_address')
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id)
        .select()
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function fetchCustomerAddressOptions(
  params: {
    customerId?: string
    addressType?: CustomerAddress['addressType']
  } = {}
) {
  let query = supabase
    .from('tms_customer_address')
    .select('*')
    .order('is_default', { ascending: false })
    .order('update_time', { ascending: false, nullsFirst: false })
  if (params.customerId) query = query.eq('customer_id', params.customerId)
  if (params.addressType) query = query.eq('address_type', params.addressType)
  return await responseHandle<CustomerAddress[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFavoriteRouteList(
  params: FavoriteRouteSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, customerId, enabled, keyword } = params
  let query = supabase
    .from('tms_favorite_route')
    .select(
      `
        *,
        customer:tms_customer!tms_favorite_route_customer_id_fkey(
          id, customer_code, customer_name
        ),
        origin_address:tms_customer_address!tms_favorite_route_origin_address_id_fkey(*),
        destination_address:tms_customer_address!tms_favorite_route_destination_address_id_fkey(*)
      `,
      { count: 'exact' }
    )
    .order('enabled', { ascending: false })
    .order('update_time', { ascending: false, nullsFirst: false })
    .range(from, to)
  if (customerId) query = query.eq('customer_id', customerId)
  if (enabled !== undefined) query = query.eq('enabled', enabled)
  if (keyword?.trim()) {
    const trimmedKeyword = keyword.trim()
    query = query.or(`route_name.ilike.%${trimmedKeyword}%,remark.ilike.%${trimmedKeyword}%`)
  }
  return await responseHandle<FavoriteRoute[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addFavoriteRoute(params: FavoriteRoute) {
  return await responseHandle<FavoriteRoute>(
    () => supabase.from('tms_favorite_route').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editFavoriteRoute(params: FavoriteRoute) {
  const { id, ...payload } = params
  return await responseHandle<FavoriteRoute>(
    () =>
      supabase
        .from('tms_favorite_route')
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id)
        .select()
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteFavoriteRoute(id: string) {
  return await responseHandle(
    () => supabase.from('tms_favorite_route').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteFavoriteRouteBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_favorite_route').delete({ count: 'exact' }).in('id', ids),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}
