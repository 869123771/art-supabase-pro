import { useSupabase } from '@/hooks'
import { normalizeBooleanFilter, withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Customer = Api.Tms.BasicData.Customer
type CustomerSearchParams = Api.Tms.BasicData.CustomerSearchParams
type CustomerAddress = Api.Tms.BasicData.CustomerAddress
type CustomerAddressSearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
type FavoriteRouteSearchParams = Api.Tms.BasicData.FavoriteRouteSearchParams
type CustomerSelectorItem = Api.Tms.Order.CustomerSelectorItem
type CustomerSelectorSearchParams = Api.Tms.Order.CustomerSelectorSearchParams

type CustomerSelectorRecord = CustomerSelectorItem

interface WriteOptions {
  showMessage?: boolean
}

interface CustomerOptionParams {
  excludeId?: string
  includeDisabled?: boolean
  tenantId?: string
}

interface SecureListPayload<TRecord, TAccess extends Record<string, string>> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

interface SecureImportResult {
  count: number
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

const CUSTOMER_PAYLOAD_KEYS = [
  'parentUnitId',
  'customerCode',
  'customerName',
  'industry',
  'customerLevel',
  'tags',
  'region',
  'regionAdcode',
  'addressDetail',
  'longitude',
  'latitude',
  'coordinateSystem',
  'coordinateSource',
  'coordinateStatus',
  'geocodeProvider',
  'geocodedAt',
  'postalCode',
  'enabled',
  'contactName',
  'contactPhone',
  'contactDepartment',
  'contactPosition',
  'contactEmail',
  'contactQq',
  'invoiceTitle',
  'taxNo',
  'bankName',
  'bankAccount',
  'remark'
] as const satisfies readonly (keyof Customer)[]

const CUSTOMER_ADDRESS_PAYLOAD_KEYS = [
  'customerId',
  'addressType',
  'contactName',
  'contactPhone',
  'region',
  'regionAdcode',
  'addressDetail',
  'longitude',
  'latitude',
  'coordinateSystem',
  'coordinateSource',
  'coordinateStatus',
  'geocodeProvider',
  'geocodedAt',
  'postalCode',
  'isDefault',
  'remark',
  'geofenceEnabled',
  'geofenceRadiusM',
  'geofenceUpdatedAt'
] as const satisfies readonly (keyof CustomerAddress)[]

const pickPayload = <TRecord extends object, TKey extends Extract<keyof TRecord, string>>(
  record: TRecord,
  keys: readonly TKey[]
): Record<string, unknown> =>
  Object.fromEntries(
    keys.filter((key) => record[key] !== undefined).map((key) => [key, record[key]])
  )

const toCustomerListRpcParams = (
  params: CustomerSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_customer_id: params.customerId || null,
    p_customer_level: params.customerLevel || null,
    p_industry: params.industry || null,
    p_enabled: normalizeBooleanFilter(params.enabled) ?? null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_create_time_from: params.createTimeRange?.[0]
      ? `${params.createTimeRange[0]}T00:00:00`
      : null,
    p_create_time_to: params.createTimeRange?.[1]
      ? `${params.createTimeRange[1]}T23:59:59.999`
      : null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchCustomerList(params: CustomerSearchParams, options?: ApiRequestOptions) {
  const query = supabase.rpc('tms_list_customers_secure', toCustomerListRpcParams(params, 'list'))
  const result = await responseHandle<
    SecureListPayload<Customer, Api.Tms.BasicData.CustomerFieldAccessMap>
  >(() => withRequestOptions(query, options), { showErrorMessage: true })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCustomerList(
  params: CustomerSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<Customer, Api.Tms.BasicData.CustomerFieldAccessMap>
  >(() => supabase.rpc('tms_list_customers_secure', toCustomerListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCustomerOptions(
  params: CustomerOptionParams = {},
  options?: ApiRequestOptions
) {
  return await responseHandle<Api.Tms.BasicData.CustomerOption[]>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_customer_options_secure', {
          p_exclude_id: params.excludeId || null,
          p_include_disabled: params.includeDisabled ?? false,
          p_tenant_id: params.tenantId || null
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

export async function fetchCustomerSelectorList(
  params: CustomerSelectorSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, keyword, addressType } = params
  const result = await responseHandle<SecureListPayload<CustomerSelectorRecord, never>>(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_customer_selector_secure', {
          p_from: from,
          p_to: to,
          p_keyword: String(keyword ?? '').trim() || null,
          p_address_type: addressType || null
        }),
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

export async function addCustomer(params: Customer, options: WriteOptions = {}) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_customer_secure', {
        p_payload: keysToSnakeDeep(pickPayload(params, CUSTOMER_PAYLOAD_KEYS))
      }),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editCustomer(params: Customer) {
  const { id, ...data } = params
  if (!id) throw new Error('客户 ID 不能为空')
  return await responseHandle<Customer>(
    () =>
      supabase.rpc('tms_update_customer_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(pickPayload(data, CUSTOMER_PAYLOAD_KEYS))
      }),
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
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_customer_secure', { p_id: id }),
    { breakReturn: true }
  )
}

export async function deleteCustomerBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_customers_secure', { p_ids: ids }),
    { breakReturn: true }
  )
}

export async function importCustomers(rows: Customer[]) {
  return await responseHandle<SecureImportResult>(
    () =>
      supabase.rpc('tms_import_customers_secure', {
        p_rows: rows.map((row) => keysToSnakeDeep(pickPayload(row, CUSTOMER_PAYLOAD_KEYS)))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchCustomerAddressList(
  params: CustomerAddressSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  const query = supabase.rpc('tms_list_customer_addresses_secure', {
    p_from: from,
    p_to: to,
    p_customer_id: params.customerId || null,
    p_address_type: params.addressType || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_create_time_from: params.createTimeRange?.[0]
      ? `${params.createTimeRange[0]}T00:00:00`
      : null,
    p_create_time_to: params.createTimeRange?.[1]
      ? `${params.createTimeRange[1]}T23:59:59.999`
      : null,
    p_record_id: params.recordId || null
  })
  const result = await responseHandle<
    SecureListPayload<CustomerAddress, Api.Tms.BasicData.CustomerAddressFieldAccessMap>
  >(() => withRequestOptions(query, options), { showErrorMessage: true })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCustomerDefaultAddress(
  customerId: string,
  addressType: CustomerAddress['addressType']
) {
  return await responseHandle<CustomerAddress | null>(
    () =>
      supabase.rpc('tms_get_customer_default_address_secure', {
        p_customer_id: customerId,
        p_address_type: addressType
      }),
    { showErrorMessage: true }
  )
}

export async function addCustomerAddress(params: CustomerAddress, options: WriteOptions = {}) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_customer_address_secure', {
        p_payload: keysToSnakeDeep(pickPayload(params, CUSTOMER_ADDRESS_PAYLOAD_KEYS))
      }),
    { showMessage: options.showMessage ?? true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editCustomerAddress(params: CustomerAddress) {
  const { id } = params
  if (!id) throw new Error('客户地址 ID 不能为空')
  return await responseHandle<CustomerAddress>(
    () =>
      supabase.rpc('tms_update_customer_address_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(pickPayload(params, CUSTOMER_ADDRESS_PAYLOAD_KEYS))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerAddress(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_customer_address_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerAddressBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_customer_addresses_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function updateCustomerAddressGeofence(
  id: string,
  payload: Pick<CustomerAddress, 'geofenceEnabled' | 'geofenceRadiusM' | 'geofenceUpdatedAt'>
) {
  return await responseHandle<CustomerAddress>(
    () =>
      supabase.rpc('tms_update_customer_address_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(payload)
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchCustomerAddressOptions(
  params: {
    customerId?: string
    tenantId?: string
    addressType?: CustomerAddress['addressType']
  } = {}
) {
  return await responseHandle<CustomerAddress[]>(
    () =>
      supabase.rpc('tms_list_customer_address_options_secure', {
        p_customer_id: params.customerId || null,
        p_tenant_id: params.tenantId || null,
        p_address_type: params.addressType || null
      }),
    { showErrorMessage: true }
  )
}

export async function fetchFavoriteRouteList(
  params: FavoriteRouteSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9, tenantId, customerId, enabled, keyword } = params
  const query = supabase.rpc('tms_list_favorite_routes_secure', {
    p_from: from,
    p_to: to,
    p_tenant_id: tenantId || null,
    p_customer_id: customerId || null,
    p_enabled: enabled ?? null,
    p_keyword: String(keyword ?? '').trim() || null
  })
  const result = await responseHandle<SecureListPayload<FavoriteRoute, never>>(
    () => withRequestOptions(query, options),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
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
