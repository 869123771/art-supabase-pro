import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/modules/tms/query'

type Customer = Api.Tms.BasicData.Customer
type CustomerSearchParams = Api.Tms.BasicData.CustomerSearchParams
type CustomerAddress = Api.Tms.BasicData.CustomerAddress
type CustomerAddressSearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
type CustomerSelectorItem = Api.Tms.Order.CustomerSelectorItem
type CustomerSelectorSearchParams = Api.Tms.Order.CustomerSelectorSearchParams

interface WriteOptions {
  showMessage?: boolean
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyDateRange = (query: SupabaseQueryLike, dateRange?: string[]): SupabaseQueryLike => {
  if (dateRange?.[0]) query = query.gte('create_time', `${dateRange[0]}T00:00:00`)
  if (dateRange?.[1]) query = query.lte('create_time', `${dateRange[1]}T23:59:59.999`)
  return query
}

const applyCustomerFilters = (
  query: SupabaseQueryLike,
  params: CustomerSearchParams
): SupabaseQueryLike => {
  const { customerLevel, industry, enabled, keyword, createTimeRange } = params
  if (customerLevel) query = query.eq('customer_level', customerLevel)
  if (industry) query = query.eq('industry', industry)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `customer_name.ilike.%${keyword}%,customer_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchCustomerList(params: CustomerSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => query, {
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
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerOptions() {
  return await responseHandle<Api.Tms.BasicData.CustomerOption[]>(
    () =>
      supabase
        .from('tms_customer')
        .select(
          'id, customer_code, customer_name, contact_name, contact_phone, region, region_adcode, address_detail, longitude, latitude, coordinate_system, coordinate_source, coordinate_status, geocode_provider, geocoded_at, postal_code'
        )
        .eq('enabled', true)
        .order('customer_name', { ascending: true })
        .limit(1000),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchCustomerSelectorList(params: CustomerSelectorSearchParams) {
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
  return await responseHandle<CustomerSelectorItem[]>(() => query, {
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

export async function deleteCustomer(id: string) {
  return await responseHandle(() => supabase.from('tms_customer').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCustomerBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_customer').delete().in('id', ids), {
    showMessage: true
  })
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

const applyCustomerAddressFilters = (
  query: SupabaseQueryLike,
  params: CustomerAddressSearchParams
): SupabaseQueryLike => {
  const { customerId, addressType, keyword, createTimeRange } = params
  if (customerId) query = query.eq('customer_id', customerId)
  if (addressType) query = query.eq('address_type', addressType)
  if (keyword) {
    query = query.or(
      `contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,address_detail.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchCustomerAddressList(params: CustomerAddressSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer_address')
    .select(
      '*, customer:tms_customer!tms_customer_address_customer_id_fkey(id, customer_code, customer_name, contact_name, contact_phone)',
      { count: 'exact' }
    )
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyCustomerAddressFilters(query, params)
  return await responseHandle<CustomerAddress[]>(() => query, {
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
  return await responseHandle(() => supabase.from('tms_customer_address').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCustomerAddressBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_customer_address').delete().in('id', ids), {
    showMessage: true
  })
}
