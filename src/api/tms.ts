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
type Cargo = Api.Tms.BasicData.Cargo
type CargoSearchParams = Api.Tms.BasicData.CargoSearchParams
type Contract = Api.Tms.BasicData.Contract
type ContractSearchParams = Api.Tms.BasicData.ContractSearchParams
type CustomerPrice = Api.Tms.BasicData.CustomerPrice
type CustomerPriceSearchParams = Api.Tms.BasicData.CustomerPriceSearchParams
type CarrierPrice = Api.Tms.BasicData.CarrierPrice
type CarrierPriceSearchParams = Api.Tms.BasicData.CarrierPriceSearchParams
type OrderRecord = Api.Tms.Order.OrderRecord
type OrderSearchParams = Api.Tms.Order.OrderSearchParams
type OrderFreightPayload = Api.Tms.Order.OrderFreightPayload
type WaybillRecord = Api.Tms.Waybill.WaybillRecord
type WaybillSearchParams = Api.Tms.Waybill.WaybillSearchParams
type WaybillDispatchPayload = Api.Tms.Waybill.WaybillDispatchPayload
type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
type DispatchVehicleSearchParams = Api.Tms.Waybill.DispatchVehicleSearchParams
type CustomerSelectorItem = Api.Tms.Order.CustomerSelectorItem
type CustomerSelectorSearchParams = Api.Tms.Order.CustomerSelectorSearchParams
type StationRecord = Api.Tms.Station.StationRecord
type StationSearchParams = Api.Tms.Station.StationSearchParams
type StationOptionSearchParams = Api.Tms.Station.StationOptionSearchParams

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

// 客户管理
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

export async function fetchCustomerSelectorList(params: CustomerSelectorSearchParams) {
  const { from = 0, to = 9, keyword } = params
  let query: any = supabase
    .from('tms_customer')
    .select(
      'id, customer_code, customer_name, contact_name, contact_phone, region, address_detail',
      {
        count: 'exact'
      }
    )
    .eq('enabled', true)
    .order('create_time', { ascending: false })
    .range(from, to)

  if (keyword) {
    query = query.or(
      `customer_name.ilike.%${keyword}%,customer_code.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,address_detail.ilike.%${keyword}%`
    )
  }

  return await responseHandle<CustomerSelectorItem[]>(() => query as any, {
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

// 地址管理
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

// 承运商管理
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

// 司机管理
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

// 货物管理
const applyCargoFilters = (query: any, params: CargoSearchParams) => {
  const { unit, enabled, keyword, createTimeRange } = params
  if (unit) query = query.eq('unit', unit)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `cargo_name.ilike.%${keyword}%,cargo_code.ilike.%${keyword}%,unit.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchCargoList(params: CargoSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_cargo')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCargoFilters(query, params)
  return await responseHandle<Cargo[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCargoList(
  params: CargoSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_cargo')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCargoFilters(query, params)
  return await responseHandle<Cargo[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCargo(params: Cargo) {
  return await responseHandle(
    () => supabase.from('tms_cargo').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCargo(params: Cargo) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_cargo').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCargo(id: string) {
  return await responseHandle(() => supabase.from('tms_cargo').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteCargoBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_cargo').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importCargoes(rows: Cargo[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_cargo')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,cargo_name' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

// 合同管理
const CONTRACT_SELECT = `
  *,
  carrier:tms_carrier!tms_contract_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  )
`

const applyContractFilters = (query: any, params: ContractSearchParams) => {
  const { contractStatus, carrierId, billingMethod, keyword, createTimeRange } = params
  if (contractStatus) query = query.eq('contract_status', contractStatus)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `contract_name.ilike.%${keyword}%,contract_no.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,waybill_no.ilike.%${keyword}%,handler.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchContractList(params: ContractSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_contract')
    .select(CONTRACT_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyContractFilters(query, params)
  return await responseHandle<Contract[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportContractList(
  params: ContractSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_contract')
    .select(CONTRACT_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyContractFilters(query, params)
  return await responseHandle<Contract[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchContractDetail(id: string) {
  const query = supabase.from('tms_contract').select(CONTRACT_SELECT).eq('id', id).maybeSingle()

  return await responseHandle<Contract | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addContract(params: Contract) {
  return await responseHandle(
    () => supabase.from('tms_contract').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editContract(params: Contract) {
  const { id, ...data } = params
  delete data.carrier
  return await responseHandle(
    () => supabase.from('tms_contract').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteContract(id: string) {
  return await responseHandle(() => supabase.from('tms_contract').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteContractBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_contract').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importContracts(rows: Contract[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_contract')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,contract_no' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

// 客户价格维护
const CUSTOMER_PRICE_SELECT = `
  *,
  customer:tms_customer!tms_customer_price_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone
  )
`

const applyCustomerPriceFilters = (query: any, params: CustomerPriceSearchParams) => {
  const {
    customerId,
    originRegion,
    destinationRegion,
    transportType,
    cargoType,
    billingMethod,
    keyword,
    createTimeRange
  } = params

  if (customerId) query = query.eq('customer_id', customerId)
  if (originRegion) query = query.eq('origin_region', originRegion)
  if (destinationRegion) query = query.eq('destination_region', destinationRegion)
  if (transportType) query = query.eq('transport_type', transportType)
  if (cargoType) query = query.eq('cargo_type', cargoType)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `shipping_contact_name.ilike.%${keyword}%,shipping_contact_phone.ilike.%${keyword}%,shipping_address_detail.ilike.%${keyword}%,receiving_contact_name.ilike.%${keyword}%,receiving_contact_phone.ilike.%${keyword}%,receiving_address_detail.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }

  return applyDateRange(query, createTimeRange)
}

export async function fetchCustomerPriceList(params: CustomerPriceSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_customer_price')
    .select(CUSTOMER_PRICE_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCustomerPriceFilters(query, params)
  return await responseHandle<CustomerPrice[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCustomerPriceList(
  params: CustomerPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_customer_price')
    .select(CUSTOMER_PRICE_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCustomerPriceFilters(query, params)
  return await responseHandle<CustomerPrice[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerPriceDetail(id: string) {
  const query = supabase
    .from('tms_customer_price')
    .select(CUSTOMER_PRICE_SELECT)
    .eq('id', id)
    .maybeSingle()

  return await responseHandle<CustomerPrice | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomerPrice(params: CustomerPrice) {
  return await responseHandle(
    () => supabase.from('tms_customer_price').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCustomerPrice(params: CustomerPrice) {
  const { id, ...data } = params
  delete data.customer
  return await responseHandle(
    () => supabase.from('tms_customer_price').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerPrice(id: string) {
  return await responseHandle(
    () => supabase.from('tms_customer_price').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deleteCustomerPriceBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_customer_price').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

//承运商价格维护
const CARRIER_PRICE_SELECT = `
  *,
  carrier:tms_carrier!tms_carrier_price_carrier_id_fkey(
    id,
    carrier_code,
    company_name,
    contact_name,
    contact_phone
  ),
  driver:tms_driver!tms_carrier_price_driver_id_fkey(
    id,
    carrier_id,
    driver_name,
    phone
  ),
  vehicle:vehicle_archive!tms_carrier_price_vehicle_id_fkey(
    id,
    carrier_id,
    plate_no,
    company_name,
    vehicle_type,
    vin,
    self_no
  )
`

const applyCarrierPriceFilters = (query: any, params: CarrierPriceSearchParams) => {
  const {
    carrierId,
    originRegion,
    destinationRegion,
    transportMode,
    billingMethod,
    keyword,
    createTimeRange
  } = params

  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (originRegion) query = query.eq('origin_region', originRegion)
  if (destinationRegion) query = query.eq('destination_region', destinationRegion)
  if (transportMode) query = query.eq('transport_mode', transportMode)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,driver_name.ilike.%${keyword}%,driver_phone.ilike.%${keyword}%,plate_no.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }

  return applyDateRange(query, createTimeRange)
}

export async function fetchCarrierPriceList(params: CarrierPriceSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_carrier_price')
    .select(CARRIER_PRICE_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCarrierPriceFilters(query, params)
  return await responseHandle<CarrierPrice[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCarrierPriceList(
  params: CarrierPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_carrier_price')
    .select(CARRIER_PRICE_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCarrierPriceFilters(query, params)
  return await responseHandle<CarrierPrice[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierPriceDetail(id: string) {
  const query = supabase
    .from('tms_carrier_price')
    .select(CARRIER_PRICE_SELECT)
    .eq('id', id)
    .maybeSingle()

  return await responseHandle<CarrierPrice | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCarrierPrice(params: CarrierPrice) {
  return await responseHandle(
    () => supabase.from('tms_carrier_price').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCarrierPrice(params: CarrierPrice) {
  const { id, ...data } = params
  delete data.carrier
  delete data.driver
  delete data.vehicle
  return await responseHandle(
    () => supabase.from('tms_carrier_price').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrierPrice(id: string) {
  return await responseHandle(
    () => supabase.from('tms_carrier_price').delete().eq('id', id) as any,
    { showMessage: true }
  )
}

export async function deleteCarrierPriceBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('tms_carrier_price').delete().in('id', ids) as any,
    { showMessage: true }
  )
}

// 站点管理
const applyStationFilters = (query: any, params: StationSearchParams) => {
  const { stationType, enabled, keyword, createTimeRange } = params
  if (stationType) query = query.eq('station_type', stationType)
  const enabledValue = normalizeBooleanFilter(enabled)
  if (enabledValue !== undefined) query = query.eq('enabled', enabledValue)
  if (keyword) {
    query = query.or(
      `station_code.ilike.%${keyword}%,station_name.ilike.%${keyword}%,region_code.ilike.%${keyword}%,manager_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, createTimeRange)
}

export async function fetchStationList(params: StationSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_station')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .range(from, to)

  query = applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportStationList(
  params: StationSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_station')
    .select('*')
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyStationFilters(query, params)
  return await responseHandle<StationRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchStationOptions(params: StationOptionSearchParams = {}) {
  let query: any = supabase
    .from('tms_station')
    .select('id, station_code, station_name, station_type, region_code')
    .eq('enabled', true)
    .order('sort', { ascending: true })
    .order('station_code', { ascending: true })
    .limit(1000)

  if (params.stationType) query = query.eq('station_type', params.stationType)
  if (params.keyword) {
    query = query.or(
      `station_code.ilike.%${params.keyword}%,station_name.ilike.%${params.keyword}%,region_code.ilike.%${params.keyword}%`
    )
  }

  return await responseHandle<Api.Tms.Order.StationOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addStation(params: StationRecord) {
  return await responseHandle(
    () => supabase.from('tms_station').insert(keysToSnakeDeep(params)) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editStation(params: StationRecord) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('tms_station').update(keysToSnakeDeep(data)).eq('id', id) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteStation(id: string) {
  return await responseHandle(() => supabase.from('tms_station').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteStationBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_station').delete().in('id', ids) as any, {
    showMessage: true
  })
}

export async function importStations(rows: StationRecord[]) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_station')
        .upsert(keysToSnakeDeep(rows), { onConflict: 'tenant_id,station_code' }) as any,
    { showMessage: true, breakReturn: true }
  )
}

const ORDER_SELECT = `
  *,
  originStationRef:tms_station!tms_order_origin_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  destinationStationRef:tms_station!tms_order_destination_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  transferStationRef:tms_station!tms_order_transfer_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  shippingCustomer:tms_customer!tms_order_shipping_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone,
    region,
    address_detail
  ),
  receivingCustomer:tms_customer!tms_order_receiving_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone,
    region,
    address_detail
  )
`

const applyOrderFilters = (query: any, params: OrderSearchParams) => {
  const {
    cargoKeyword,
    shippingKeyword,
    receivingKeyword,
    orderStatus,
    paymentMethod,
    originStationId,
    destinationStationId,
    transferStationId,
    createTimeRange
  } = params

  if (orderStatus === 'pending_load') {
    query = query.in('order_status', ['pending_load', 'created'])
  } else if (orderStatus === 'pending_order') {
    query = query.in('order_status', ['pending_order', 'loaded'])
  } else if (orderStatus) {
    query = query.eq('order_status', orderStatus)
  }
  if (paymentMethod) query = query.eq('payment_method', paymentMethod)
  if (originStationId) query = query.eq('origin_station_id', originStationId)
  if (destinationStationId) query = query.eq('destination_station_id', destinationStationId)
  if (transferStationId) query = query.eq('transfer_station_id', transferStationId)
  if (cargoKeyword) {
    query = query.or(`order_no.ilike.%${cargoKeyword}%,cargo_no.ilike.%${cargoKeyword}%`)
  }
  if (shippingKeyword) {
    query = query.or(
      `shipping_contact_name.ilike.%${shippingKeyword}%,shipping_contact_phone.ilike.%${shippingKeyword}%,shipping_address_detail.ilike.%${shippingKeyword}%`
    )
  }
  if (receivingKeyword) {
    query = query.or(
      `receiving_contact_name.ilike.%${receivingKeyword}%,receiving_contact_phone.ilike.%${receivingKeyword}%,receiving_address_detail.ilike.%${receivingKeyword}%`
    )
  }

  return applyDateRange(query, createTimeRange)
}

export async function fetchOrderList(params: OrderSearchParams & Api.Common.CommonSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyOrderFilters(query, params)
  return await responseHandle<OrderRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportOrderList(
  params: OrderSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyOrderFilters(query, params)
  return await responseHandle<OrderRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchOrderDetail(id: string) {
  const query = supabase.from('tms_order').select(ORDER_SELECT).eq('id', id).maybeSingle()

  return await responseHandle<OrderRecord | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addOrder(params: OrderRecord) {
  return await responseHandle<OrderRecord>(
    () => supabase.from('tms_order').insert(keysToSnakeDeep(params)).select().single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editOrder(params: OrderRecord) {
  const { id, ...data } = params
  delete data.shippingCustomer
  delete data.receivingCustomer
  delete data.originStationRef
  delete data.destinationStationRef
  delete data.transferStationRef
  delete data.dispatchVehicle
  delete data.dispatchDriver

  return await responseHandle<OrderRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(data))
        .eq('id', id)
        .select()
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editOrderFreight(params: OrderFreightPayload) {
  const { id, ...data } = params

  return await responseHandle<OrderRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(data))
        .eq('id', id)
        .select()
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteOrder(id: string) {
  return await responseHandle(() => supabase.from('tms_order').delete().eq('id', id) as any, {
    showMessage: true
  })
}

export async function deleteOrderBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_order').delete().in('id', ids) as any, {
    showMessage: true
  })
}

// 运单配载管理
const DISPATCH_VEHICLE_SELECT = `
  id,
  carrier_id,
  plate_no,
  company_name,
  vin,
  self_no,
  vehicle_type,
  primary_driver_id,
  driver_one_name,
  driver_one_phone,
  tonnage_or_seat,
  overall_length,
  primaryDriver:tms_driver!vehicle_archive_primary_driver_id_fkey(
    id,
    carrier_id,
    driver_name,
    phone
  )
`

const applyPlannedTimeRange = (query: any, plannedTimeRange?: string[]) => {
  if (plannedTimeRange?.[0]) {
    query = query.gte('planned_departure_time', `${plannedTimeRange[0]}T00:00:00`)
  }
  if (plannedTimeRange?.[1]) {
    query = query.lte('planned_departure_time', `${plannedTimeRange[1]}T23:59:59.999`)
  }
  return query
}

const applyWaybillFilters = (query: any, params: WaybillSearchParams) => {
  const { dispatchStatus, dispatchStatuses, dispatchVehicleId, vehicleKeyword, plannedTimeRange } =
    params

  query = applyOrderFilters(query, params)
  if (dispatchStatuses?.length) query = query.in('dispatch_status', dispatchStatuses)
  if (!dispatchStatuses?.length && dispatchStatus)
    query = query.eq('dispatch_status', dispatchStatus)
  if (dispatchVehicleId) query = query.eq('dispatch_vehicle_id', dispatchVehicleId)
  if (vehicleKeyword) {
    query = query.or(
      `dispatch_plate_no.ilike.%${vehicleKeyword}%,dispatch_vehicle_type.ilike.%${vehicleKeyword}%,dispatch_driver_name.ilike.%${vehicleKeyword}%,dispatch_driver_phone.ilike.%${vehicleKeyword}%`
    )
  }

  return applyPlannedTimeRange(query, plannedTimeRange)
}

const createDispatchUpdatePayload = (params: WaybillDispatchPayload) => ({
  orderStatus: 'pending_order',
  dispatchStatus: 'loaded',
  dispatchVehicleId: params.dispatchVehicleId,
  dispatchDriverId: params.dispatchDriverId || null,
  dispatchPlateNo: params.dispatchPlateNo,
  dispatchVehicleType: params.dispatchVehicleType || null,
  dispatchVehicleLength: params.dispatchVehicleLength || null,
  dispatchDriverName: params.dispatchDriverName || null,
  dispatchDriverPhone: params.dispatchDriverPhone || null,
  plannedDepartureTime: params.plannedDepartureTime,
  plannedArrivalTime: params.plannedArrivalTime,
  dispatchRemark: params.dispatchRemark || null,
  dispatchedAt: new Date().toISOString()
})

const createCancelDispatchPayload = () => ({
  orderStatus: 'pending_load',
  dispatchStatus: 'pending',
  dispatchVehicleId: null,
  dispatchDriverId: null,
  dispatchPlateNo: null,
  dispatchVehicleType: null,
  dispatchVehicleLength: null,
  dispatchDriverName: null,
  dispatchDriverPhone: null,
  plannedDepartureTime: null,
  plannedArrivalTime: null,
  dispatchRemark: null,
  dispatchedAt: null,
  dispatchBy: null
})

export async function fetchWaybillList(
  params: WaybillSearchParams & Api.Common.CommonSearchParams
) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyWaybillFilters(query, params)
  return await responseHandle<WaybillRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportWaybillList(
  params: WaybillSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyWaybillFilters(query, params)
  return await responseHandle<WaybillRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function dispatchWaybill(params: WaybillDispatchPayload) {
  const id = params.id
  if (!id) throw new Error('缺少运单ID')

  return await responseHandle<WaybillRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createDispatchUpdatePayload(params)))
        .eq('id', id)
        .select(ORDER_SELECT)
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function dispatchWaybillBatch(params: WaybillDispatchPayload) {
  const ids = params.ids?.filter(Boolean) ?? []
  if (!ids.length) throw new Error('请选择需要配载的运单')

  return await responseHandle<WaybillRecord[]>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createDispatchUpdatePayload(params)))
        .in('id', ids)
        .select(ORDER_SELECT) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillDispatch(id: string) {
  return await responseHandle<WaybillRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createCancelDispatchPayload()))
        .eq('id', id)
        .select(ORDER_SELECT)
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillDispatchBatch(ids: string[]) {
  return await responseHandle<WaybillRecord[]>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createCancelDispatchPayload()))
        .in('id', ids)
        .select(ORDER_SELECT) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrder(id: string) {
  return await responseHandle<WaybillRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep({ orderStatus: 'cancelled', dispatchStatus: 'cancelled' }))
        .eq('id', id)
        .select(ORDER_SELECT)
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchDispatchVehicleOptions(params: DispatchVehicleSearchParams = {}) {
  const { from = 0, to = 9, keyword } = params
  let query: any = supabase
    .from('vehicle_archive')
    .select(DISPATCH_VEHICLE_SELECT, { count: 'exact' })
    .order('plate_no', { ascending: true })
    .range(from, to)

  if (keyword) {
    query = query.or(
      `plate_no.ilike.%${keyword}%,company_name.ilike.%${keyword}%,self_no.ilike.%${keyword}%,vehicle_type.ilike.%${keyword}%,driver_one_name.ilike.%${keyword}%,driver_one_phone.ilike.%${keyword}%`
    )
  }

  return await responseHandle<DispatchVehicleOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}
