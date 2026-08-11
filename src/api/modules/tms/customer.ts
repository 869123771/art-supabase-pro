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
type CustomerSelectorItem = Api.Tms.Order.CustomerSelectorItem
type CustomerSelectorSearchParams = Api.Tms.Order.CustomerSelectorSearchParams

interface WriteOptions {
  showMessage?: boolean
}

export type CustomerDeleteDependencyCode =
  | 'cash_allocation'
  | 'cash_transaction'
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

export async function fetchCustomerOptions(_params?: unknown, options?: ApiRequestOptions) {
  return await responseHandle<Api.Tms.BasicData.CustomerOption[]>(
    () =>
      withRequestOptions(
        supabase
          .from('tms_customer')
          .select(
            'id, customer_code, customer_name, contact_name, contact_phone, region, region_adcode, address_detail, longitude, latitude, coordinate_system, coordinate_source, coordinate_status, geocode_provider, geocoded_at, postal_code'
          )
          .eq('enabled', true)
          .order('customer_name', { ascending: true })
          .limit(1000),
        options
      ),
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
