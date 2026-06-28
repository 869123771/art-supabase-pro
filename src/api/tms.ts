import { useSupabase } from '@/hooks'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

type Customer = Api.Tms.BasicData.Customer
type CustomerSearchParams = Api.Tms.BasicData.CustomerSearchParams
type CustomerAddress = Api.Tms.BasicData.CustomerAddress
type CustomerAddressSearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
type Carrier = Api.Tms.BasicData.Carrier
type CarrierSearchParams = Api.Tms.BasicData.CarrierSearchParams
type Driver = Api.Tms.BasicData.Driver
type DriverSearchParams = Api.Tms.BasicData.DriverSearchParams

const normalizeBooleanFilter = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return undefined
}

const applyDateRange = (query: any, dateRange?: string[]) => {
  if (dateRange?.[0]) query = query.gte('create_time', `${dateRange[0]}T00:00:00`)
  if (dateRange?.[1]) query = query.lte('create_time', `${dateRange[1]}T23:59:59.999`)
  return query
}

const applyCustomerFilters = (query: any, params: CustomerSearchParams) => {
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
  let query: any = supabase
    .from('tms_customer')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCustomerList(
  params: CustomerSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_customer')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCustomerFilters(query, params)
  return await responseHandle<Customer[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerOptions() {
  const query = supabase
    .from('tms_customer')
    .select('id, customer_code, customer_name, contact_name, contact_phone')
    .eq('enabled', true)
    .order('customer_name', { ascending: true })
    .limit(1000)

  return await responseHandle<Api.Tms.BasicData.CustomerOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomer(params: Customer) {
  return await responseHandle(
    () => supabase.from('tms_customer').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCustomer(params: Customer) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_customer').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomer(id: string) {
  return await responseHandle(() => supabase.from('tms_customer').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteCustomerBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_customer').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importCustomers(rows: Customer[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_customer')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,customer_code' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

const applyCustomerAddressFilters = (query: any, params: CustomerAddressSearchParams) => {
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
  let query: any = supabase
    .from('tms_customer_address')
    .select(
      '*, customer:tms_customer!tms_customer_address_customer_id_fkey(id, customer_code, customer_name, contact_name, contact_phone)',
      { count: 'exact' }
    )
    .order('is_default', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCustomerAddressFilters(query, params)
  return await responseHandle<CustomerAddress[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomerAddress(params: CustomerAddress) {
  return await responseHandle(
    () => supabase.from('tms_customer_address').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCustomerAddress(params: CustomerAddress) {
  const { id, ...data } = params
  delete data.customer
  return await responseHandle(
    () => supabase.from('tms_customer_address').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerAddress(id: string) {
  return await responseHandle(
    () => supabase.from('tms_customer_address').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deleteCustomerAddressBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_customer_address').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

const applyCarrierFilters = (query: any, params: CarrierSearchParams) => {
  const { carrierType, enabled, signedContract, keyword, createTimeRange } = params
  if (carrierType) query = query.eq('carrier_type', carrierType)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  const signedContractValue = normalizeBooleanFilter(signedContract)
  if (signedContractValue !== undefined) query = query.eq('signed_contract', signedContractValue)
  if (keyword) {
    query = query.or(
      `company_name.ilike.%${keyword}%,carrier_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchCarrierList(params: CarrierSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_carrier')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCarrierFilters(query, params)
  return await responseHandle<Carrier[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCarrierList(
  params: CarrierSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_carrier')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCarrierFilters(query, params)
  return await responseHandle<Carrier[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierDetail(id: string) {
  const query = supabase.from('tms_carrier').select('*').eq('id', id).maybeSingle()

  return await responseHandle<Carrier | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierOptions(
  params: Partial<Pick<Api.Tms.BasicData.CarrierOption, 'carrierCode' | 'companyName'>> = {}
) {
  const { carrierCode, companyName } = params
  let query: any = supabase
    .from('tms_carrier')
    .select('id, carrier_code, company_name, contact_name, contact_phone')
    .eq('enabled', true)
    .order('company_name', { ascending: true })
    .limit(200)

  if (carrierCode || companyName) {
    const terms = [companyName, carrierCode].filter(Boolean)
    const keyword = terms[0]
    if (keyword) {
      query = query.or(
        `company_name.ilike.%${keyword}%,carrier_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%`
      )
    }
  }

  return await responseHandle<Api.Tms.BasicData.CarrierOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCarrier(params: Carrier) {
  return await responseHandle(
    () => supabase.from('tms_carrier').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCarrier(params: Carrier) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_carrier').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrier(id: string) {
  return await responseHandle(() => supabase.from('tms_carrier').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteCarrierBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_carrier').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importCarriers(rows: Carrier[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_carrier')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,carrier_code' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

const DRIVER_SELECT = `
  *,
  carrier:tms_carrier!tms_driver_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  )
`

const applyDriverFilters = (query: any, params: DriverSearchParams) => {
  const { carrierId, gender, enabled, keyword, createTimeRange } = params
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (gender) query = query.eq('gender', gender)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `driver_name.ilike.%${keyword}%,phone.ilike.%${keyword}%,id_card_no.ilike.%${keyword}%,home_address.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchDriverList(params: DriverSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDriverFilters(query, params)
  return await responseHandle<Driver[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportDriverList(
  params: DriverSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyDriverFilters(query, params)
  return await responseHandle<Driver[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchDriverOptions(
  params: Partial<Pick<Api.Tms.BasicData.DriverOption, 'carrierId' | 'driverName'>> = {}
) {
  const { carrierId, driverName } = params
  let query: any = supabase
    .from('tms_driver')
    .select('id, carrier_id, driver_name, phone')
    .eq('enabled', true)
    .order('driver_name', { ascending: true })
    .limit(200)

  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (driverName) {
    query = query.or(`driver_name.ilike.%${driverName}%,phone.ilike.%${driverName}%`)
  }

  return await responseHandle<Api.Tms.BasicData.DriverOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchDriverListByCarrierId(carrierId: string) {
  const query = supabase
    .from('tms_driver')
    .select(DRIVER_SELECT)
    .eq('carrier_id', carrierId)
    .order('create_time', { ascending: false })
    .limit(1000)

  return await responseHandle<Driver[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addDriver(params: Driver) {
  return await responseHandle(
    () => supabase.from('tms_driver').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editDriver(params: Driver) {
  const { id, ...data } = params
  delete data.carrier
  return await responseHandle(
    () => supabase.from('tms_driver').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteDriver(id: string) {
  return await responseHandle(() => supabase.from('tms_driver').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteDriverBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_driver').delete().in('id', ids) as any, {
    showMessage: true
  })
}
