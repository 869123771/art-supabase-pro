import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/hooks/core/useSupabase'

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
type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
type DeliverySearchParams = Api.Tms.Delivery.DeliverySearchParams
type DeliverySignPayload = Api.Tms.Delivery.DeliverySignPayload
type InTransitMonitorRecord = Api.Tms.InTransit.MonitorRecord
type InTransitMonitorSearchParams = Api.Tms.InTransit.MonitorSearchParams
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

const createRealtimeChannelId = (): string => {
  if (typeof globalThis.crypto?.randomUUID === 'function') {
    return globalThis.crypto.randomUUID()
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

const countByCarrierId = async (
  tableName: 'tms_driver' | 'vehicle_archive',
  carrierId: string
): Promise<number> => {
  const { total } = await responseHandle<null>(
    () =>
      supabase
        .from(tableName)
        .select('id', { count: 'exact', head: true })
        .eq('carrier_id', carrierId) as any,
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )

  return total ?? 0
}

const attachCarrierRelationCounts = async (
  result: QueryResult<Carrier[]>
): Promise<QueryResult<Carrier[]>> => {
  const rows = result.data ?? []
  const carrierIds = rows.map((row) => String(row.id || '')).filter(Boolean)

  if (!carrierIds.length) return result

  const [driverEntries, vehicleEntries] = await Promise.all([
    Promise.all(
      carrierIds.map(async (id) => [id, await countByCarrierId('tms_driver', id)] as const)
    ),
    Promise.all(
      carrierIds.map(async (id) => [id, await countByCarrierId('vehicle_archive', id)] as const)
    )
  ])

  const driverCountMap = new Map(driverEntries)
  const vehicleCountMap = new Map(vehicleEntries)

  return {
    ...result,
    data: rows.map((row) => ({
      ...row,
      driverCount: row.id ? (driverCountMap.get(row.id) ?? 0) : 0,
      vehicleCount: row.id ? (vehicleCountMap.get(row.id) ?? 0) : 0
    }))
  }
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
    .select(
      `
      id,
      customer_code,
      customer_name,
      contact_name,
      contact_phone,
      region,
      region_adcode,
      address_detail,
      longitude,
      latitude,
      coordinate_system,
      coordinate_source,
      coordinate_status,
      geocode_provider,
      geocoded_at,
      postal_code
    `
    )
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
      'id, customer_code, customer_name, contact_name, contact_phone, region, region_adcode, address_detail, longitude, latitude',
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
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .range(from, to)

  query = applyCustomerAddressFilters(query, params)
  return await responseHandle<CustomerAddress[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerDefaultAddress(
  customerId: string,
  addressType: CustomerAddress['addressType']
) {
  const query = supabase
    .from('tms_customer_address')
    .select('*')
    .eq('customer_id', customerId)
    .eq('address_type', addressType)
    .order('is_default', { ascending: false })
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle()

  return await responseHandle<CustomerAddress | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomerAddress(params: CustomerAddress) {
  return await responseHandle<CustomerAddress>(
    () =>
      supabase
        .from('tms_customer_address')
        .insert(keysToSnakeDeep(params))
        .select()
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function editCustomerAddress(params: CustomerAddress) {
  const { id, ...data } = params
  delete data.customer
  return await responseHandle<CustomerAddress>(
    () =>
      supabase
        .from('tms_customer_address')
        .update(keysToSnakeDeep(data), { count: 'exact' })
        .eq('id', id)
        .select()
        .single() as any,
    { showMessage: true, breakReturn: true, requireAffected: true }
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
  const result = await responseHandle<Carrier[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return await attachCarrierRelationCounts(result)
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
  const { carrierId, driverType, gender, enabled, keyword, createTimeRange } = params
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (driverType) query = query.eq('driver_type', driverType)
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
  params: Partial<
    Pick<Api.Tms.BasicData.DriverOption, 'carrierId' | 'driverName' | 'driverType'>
  > = {}
) {
  const { carrierId, driverName, driverType } = params
  let query: any = supabase
    .from('tms_driver')
    .select('id, carrier_id, driver_name, phone, driver_type, license_type, enabled')
    .eq('enabled', true)
    .order('driver_name', { ascending: true })
    .limit(200)

  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (driverType) query = query.eq('driver_type', driverType)
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

  if (orderStatus) {
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

const applyOrderListFilters = (query: any, params: OrderSearchParams) =>
  applyOrderFilters(query.neq('order_status', 'created'), params)

const DRIVER_WAYBILL_SELECT =
  'id, tenant_id, waybill_no, status, loaded_at, departed_at, unloaded_at, cancelled_at, update_time'

const fetchDriverWaybillMap = async (
  orderNos: string[]
): Promise<Map<string, InTransitMonitorRecord>> => {
  if (!orderNos.length) return new Map()

  const { data } = await responseHandle<InTransitMonitorRecord[]>(
    () =>
      supabase.from('tms_waybill').select(DRIVER_WAYBILL_SELECT).in('waybill_no', orderNos) as any,
    { ignoreCheck: true }
  )

  return new Map((data ?? []).map((item) => [String(item.waybillNo), item]))
}

const mergeDriverWaybillStatus = (
  order: OrderRecord,
  driverWaybill?: InTransitMonitorRecord
): OrderRecord => {
  if (!driverWaybill) return order

  return {
    ...order,
    driverWaybillLoadedAt: driverWaybill.loadedAt ?? order.driverWaybillLoadedAt,
    driverWaybillDepartedAt: driverWaybill.departedAt ?? order.driverWaybillDepartedAt,
    driverWaybillUnloadedAt: driverWaybill.unloadedAt ?? order.driverWaybillUnloadedAt,
    waybillStatus: driverWaybill.status ?? null,
    updateTime: driverWaybill.updateTime || order.updateTime
  }
}

const mergeOrdersWithDriverWaybills = async <T extends OrderRecord>(
  orders: T[] | null | undefined
): Promise<T[]> => {
  const rows = orders ?? []
  const waybillMap = await fetchDriverWaybillMap(uniqueStringValues(rows.map((row) => row.orderNo)))
  return rows.map((row) => mergeDriverWaybillStatus(row, waybillMap.get(String(row.orderNo))) as T)
}

export async function fetchOrderList(params: OrderSearchParams & Api.Common.CommonSearchParams) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyOrderListFilters(query, params)
  const result = await responseHandle<OrderRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

const ORDER_STATUS_COUNT_VALUES = [
  'pending_load',
  'pending_order',
  'pending_pickup',
  'transporting',
  'signed',
  'completed',
  'cancelled'
] as const

export async function fetchOrderStatusCounts(
  params: OrderSearchParams
): Promise<Record<string, number>> {
  const sharedFilters = { ...params, orderStatus: undefined }
  const countEntries = await Promise.all(
    ORDER_STATUS_COUNT_VALUES.map(async (orderStatus) => {
      let query: any = supabase.from('tms_order').select('id', { count: 'exact', head: true })

      query = applyOrderListFilters(query, { ...sharedFilters, orderStatus })
      const { total } = await responseHandle<null>(() => query as any, { ignoreCheck: true })
      return [orderStatus, total ?? 0] as const
    })
  )

  return Object.fromEntries(countEntries)
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

  query = ids?.length ? query.in('id', ids) : applyOrderListFilters(query, params)
  const result = await responseHandle<OrderRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function fetchOrderDetail(id: string) {
  const query = supabase.from('tms_order').select(ORDER_SELECT).eq('id', id).maybeSingle()

  const result = await responseHandle<OrderRecord | null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const rows = result.data ? await mergeOrdersWithDriverWaybills([result.data]) : []
  return { ...result, data: rows[0] ?? null }
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
  delete data.driverWaybillLoadedAt
  delete data.driverWaybillDepartedAt
  delete data.driverWaybillUnloadedAt

  return await responseHandle<OrderRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(data))
        .eq('id', id)
        .eq('order_status', 'pending_load')
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
  return await responseHandle(
    () => supabase.rpc('tms_delete_order_with_waybill', { p_order_id: id }) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteOrderBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.rpc('tms_delete_orders_with_waybills', { p_order_ids: ids }) as any,
    { showMessage: true, breakReturn: true }
  )
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
    query =
      dispatchStatus === 'loaded'
        ? query.in('dispatch_status', ['loaded', 'transporting', 'completed'])
        : query.eq('dispatch_status', dispatchStatus)
  if (dispatchVehicleId) query = query.eq('dispatch_vehicle_id', dispatchVehicleId)
  if (vehicleKeyword) {
    query = query.or(
      `dispatch_plate_no.ilike.%${vehicleKeyword}%,dispatch_vehicle_type.ilike.%${vehicleKeyword}%,dispatch_driver_name.ilike.%${vehicleKeyword}%,dispatch_driver_phone.ilike.%${vehicleKeyword}%`
    )
  }

  return applyPlannedTimeRange(query, plannedTimeRange)
}

interface DriverWaybillStatusReference {
  orderId?: string | null
}

interface WaybillStatusCountResult {
  total: number
  counts: Record<string, number>
}

const WAYBILL_STATUS_VALUES = [
  'pending',
  'loading',
  'transporting',
  'unloading',
  'completed',
  'cancelled'
] as const

const countWaybillOrders = async (
  params: WaybillSearchParams,
  orderIds?: string[] | null
): Promise<number> => {
  if (orderIds !== null && orderIds !== undefined && !orderIds.length) return 0

  let query: any = supabase.from('tms_order').select('id', { count: 'exact', head: true })
  query = applyWaybillFilters(query, params)
  if (orderIds?.length) query = query.in('id', orderIds)

  const { total } = await responseHandle<null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return total ?? 0
}

const fetchWaybillOrderIdsByStatus = async (status?: string): Promise<string[] | null> => {
  if (!status) return null

  const { data } = await responseHandle<DriverWaybillStatusReference[]>(
    () =>
      supabase
        .from('tms_waybill')
        .select('order_id')
        .eq('status', status)
        .not('order_id', 'is', null) as any,
    { ignoreCheck: true, showErrorMessage: true }
  )

  return uniqueStringValues((data ?? []).map((item) => item.orderId))
}

export async function fetchWaybillStatusCounts(
  params: WaybillSearchParams
): Promise<WaybillStatusCountResult> {
  const sharedFilters = { ...params, waybillStatus: undefined }
  const [total, countEntries] = await Promise.all([
    countWaybillOrders(sharedFilters),
    Promise.all(
      WAYBILL_STATUS_VALUES.map(async (waybillStatus) => {
        const orderIds = await fetchWaybillOrderIdsByStatus(waybillStatus)
        const count = await countWaybillOrders(sharedFilters, orderIds)
        return [waybillStatus, count] as const
      })
    )
  ])

  return { total, counts: Object.fromEntries(countEntries) }
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

const toNullableNumberValue = (value?: number | string | null): number | null => {
  if (value === null || value === undefined || value === '') return null
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : null
}

const createWaybillRoutePoints = (order: WaybillRecord) => {
  const shipperLongitude = toNullableNumberValue(order.shippingLongitude)
  const shipperLatitude = toNullableNumberValue(order.shippingLatitude)
  const receiverLongitude = toNullableNumberValue(order.receivingLongitude)
  const receiverLatitude = toNullableNumberValue(order.receivingLatitude)
  const points: Array<Record<string, unknown>> = []

  if (shipperLongitude !== null && shipperLatitude !== null) {
    points.push({
      type: 'shipper',
      name: order.shippingContactName,
      address: order.shippingAddressDetail,
      longitude: shipperLongitude,
      latitude: shipperLatitude,
      lng: shipperLongitude,
      lat: shipperLatitude
    })
  }

  if (receiverLongitude !== null && receiverLatitude !== null) {
    points.push({
      type: 'receiver',
      name: order.receivingContactName,
      address: order.receivingAddressDetail,
      longitude: receiverLongitude,
      latitude: receiverLatitude,
      lng: receiverLongitude,
      lat: receiverLatitude
    })
  }

  return points
}

const createDriverWaybillPayload = (order: WaybillRecord) => {
  const firstCargo = order.cargoItems?.find((item) => item.cargoName)
  const cargoWeightKg = toNullableNumberValue(order.cargoWeightTotal)
  const cargoQuantity = toNullableNumberValue(order.cargoQuantityTotal)

  return {
    orderId: order.id || null,
    tenantId: order.tenantId,
    waybillNo: order.orderNo,
    status: 'pending',
    driverId: order.dispatchDriverId || null,
    vehicleId: order.dispatchVehicleId || null,
    shipperAddressId: order.shippingAddressId || null,
    receiverAddressId: order.receivingAddressId || null,
    originCity: order.originStation,
    destinationCity: order.destinationStation,
    shipperName: order.shippingContactName || null,
    shipperPhone: order.shippingContactPhone || null,
    shipperAddress: order.shippingAddressDetail,
    shipperLongitude: toNullableNumberValue(order.shippingLongitude),
    shipperLatitude: toNullableNumberValue(order.shippingLatitude),
    receiverName: order.receivingContactName || null,
    receiverPhone: order.receivingContactPhone || null,
    receiverAddress: order.receivingAddressDetail,
    receiverLongitude: toNullableNumberValue(order.receivingLongitude),
    receiverLatitude: toNullableNumberValue(order.receivingLatitude),
    plannedLoadTime: order.plannedDepartureTime || null,
    plannedUnloadTime: order.plannedArrivalTime || null,
    cargoName: firstCargo?.cargoName || order.cargoNo || order.orderNo,
    cargoWeightTon:
      cargoWeightKg === null ? null : Math.round((cargoWeightKg / 1000) * 1000) / 1000,
    cargoVolumeM3: toNullableNumberValue(order.cargoVolumeTotal),
    cargoQuantity: cargoQuantity === null ? null : String(cargoQuantity),
    freightAmount: toNullableNumberValue(order.totalFee) ?? 0,
    routePoints: createWaybillRoutePoints(order),
    remark: order.dispatchRemark || order.orderRemark || null
  }
}

const upsertDriverWaybillFromOrder = async (order: WaybillRecord): Promise<void> => {
  await responseHandle(
    () =>
      supabase.from('tms_waybill').upsert(keysToSnakeDeep(createDriverWaybillPayload(order)), {
        onConflict: 'tenant_id,waybill_no'
      }) as any,
    { breakReturn: true }
  )
}

const cancelDriverWaybillFromOrder = async (order: WaybillRecord): Promise<void> => {
  await responseHandle(
    () =>
      supabase
        .from('tms_waybill')
        .update(keysToSnakeDeep({ status: 'cancelled', cancelledAt: new Date().toISOString() }))
        .eq('tenant_id', order.tenantId)
        .eq('waybill_no', order.orderNo) as any,
    { breakReturn: true }
  )
}

export async function fetchWaybillList(
  params: WaybillSearchParams & Api.Common.CommonSearchParams
) {
  const { from = 0, to = 9 } = params
  const orderIds = await fetchWaybillOrderIdsByStatus(params.waybillStatus)
  if (orderIds !== null && !orderIds.length) return { data: [], total: 0 }

  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyWaybillFilters(query, params)
  if (orderIds) query = query.in('id', orderIds)
  const result = await responseHandle<WaybillRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function exportWaybillList(
  params: WaybillSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const orderIds = ids?.length ? null : await fetchWaybillOrderIdsByStatus(params.waybillStatus)
  if (orderIds !== null && !orderIds.length) return { data: [], total: 0 }

  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyWaybillFilters(query, params)
  if (orderIds) query = query.in('id', orderIds)
  const result = await responseHandle<WaybillRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function dispatchWaybill(params: WaybillDispatchPayload) {
  const id = params.id
  if (!id) throw new Error('缺少运单ID')

  const result = await responseHandle<WaybillRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createDispatchUpdatePayload(params)))
        .eq('id', id)
        .select(ORDER_SELECT)
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
  if (result.data) await upsertDriverWaybillFromOrder(result.data)
  return result
}

export async function dispatchWaybillBatch(params: WaybillDispatchPayload) {
  const ids = params.ids?.filter(Boolean) ?? []
  if (!ids.length) throw new Error('请选择需要配载的运单')

  const result = await responseHandle<WaybillRecord[]>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createDispatchUpdatePayload(params)))
        .in('id', ids)
        .select(ORDER_SELECT) as any,
    { showMessage: true, breakReturn: true }
  )
  await Promise.all((result.data ?? []).map((order) => upsertDriverWaybillFromOrder(order)))
  return result
}

export async function cancelWaybillDispatch(id: string) {
  const result = await responseHandle<WaybillRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createCancelDispatchPayload()))
        .eq('id', id)
        .select(ORDER_SELECT)
        .single() as any,
    { showMessage: true, breakReturn: true }
  )
  if (result.data) await cancelDriverWaybillFromOrder(result.data)
  return result
}

export async function cancelWaybillDispatchBatch(ids: string[]) {
  const result = await responseHandle<WaybillRecord[]>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(createCancelDispatchPayload()))
        .in('id', ids)
        .select(ORDER_SELECT) as any,
    { showMessage: true, breakReturn: true }
  )
  await Promise.all((result.data ?? []).map((order) => cancelDriverWaybillFromOrder(order)))
  return result
}

export async function cancelWaybillOrder(id: string) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_order_with_waybill', { p_order_id: id }) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrderBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_orders_with_waybills', { p_order_ids: ids }) as any,
    { showMessage: true, breakReturn: true }
  )
}

export async function confirmWaybillDeparture(orderId: string) {
  return await responseHandle(
    () => supabase.rpc('tms_confirm_waybill_departure', { p_order_id: orderId }) as any,
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
    const { data: driverRows } = await responseHandle<Array<{ id?: string }>>(
      () =>
        supabase
          .from('tms_driver')
          .select('id')
          .or(`driver_name.ilike.%${keyword}%,phone.ilike.%${keyword}%`)
          .limit(200) as any,
      { ignoreCheck: true }
    )
    const driverIds = (driverRows ?? []).map((item) => item.id).filter((id): id is string => !!id)
    const conditions = [
      `plate_no.ilike.%${keyword}%`,
      `company_name.ilike.%${keyword}%`,
      `self_no.ilike.%${keyword}%`,
      `vehicle_type.ilike.%${keyword}%`
    ]
    if (driverIds.length) {
      const ids = driverIds.join(',')
      conditions.push(`primary_driver_id.in.(${ids})`)
    }
    query = query.or(conditions.join(','))
  }

  return await responseHandle<DispatchVehicleOption[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 在途监控
const IN_TRANSIT_WAYBILL_STATUSES = [
  'transporting',
  // 兼容历史数据，司机端当前约束使用上面的标准状态。
  'in_transit',
  'running',
  'processing',
  'in_progress',
  'ongoing',
  'assigned',
  'pickup',
  'started',
  'active',
  '待提货',
  '运输中',
  '进行中'
]

const IN_TRANSIT_ORDER_STATUSES = ['transporting']
const OUT_OF_TRANSIT_STATUSES = new Set(['cancelled', 'canceled', 'closed', '已取消', '已关闭'])

const uniqueStringValues = (values: Array<string | null | undefined>): string[] =>
  Array.from(new Set(values.map((value) => String(value ?? '').trim()).filter(Boolean)))

const isActiveTransitMonitorRow = (row: InTransitMonitorRecord): boolean => {
  const waybillStatus = String(row.status ?? '')
    .trim()
    .toLowerCase()
  const orderStatus = String(row.order?.orderStatus ?? '')
    .trim()
    .toLowerCase()
  return (
    IN_TRANSIT_WAYBILL_STATUSES.includes(waybillStatus) && !OUT_OF_TRANSIT_STATUSES.has(orderStatus)
  )
}

const fetchInTransitVehicleMap = async (
  ids: string[]
): Promise<Map<string, DispatchVehicleOption>> => {
  if (!ids.length) return new Map()

  const { data } = await responseHandle<DispatchVehicleOption[]>(
    () => supabase.from('vehicle_archive').select(DISPATCH_VEHICLE_SELECT).in('id', ids) as any,
    { ignoreCheck: true }
  )

  return new Map((data ?? []).map((item) => [String(item.id), item]))
}

const fetchInTransitDriverMap = async (
  ids: string[]
): Promise<Map<string, Api.Tms.BasicData.DriverOption>> => {
  if (!ids.length) return new Map()

  const { data } = await responseHandle<Api.Tms.BasicData.DriverOption[]>(
    () =>
      supabase.from('tms_driver').select('id, carrier_id, driver_name, phone').in('id', ids) as any,
    { ignoreCheck: true }
  )

  return new Map((data ?? []).map((item) => [String(item.id), item]))
}

const fetchInTransitOrderMap = async (waybillNos: string[]): Promise<Map<string, OrderRecord>> => {
  if (!waybillNos.length) return new Map()

  const { data } = await responseHandle<OrderRecord[]>(
    () => supabase.from('tms_order').select(ORDER_SELECT).in('order_no', waybillNos) as any,
    { ignoreCheck: true }
  )

  return new Map((data ?? []).map((item) => [String(item.orderNo), item]))
}

const fetchInTransitOrderMonitorRows = async (
  params: InTransitMonitorSearchParams,
  existingWaybillNos: Set<string>
): Promise<InTransitMonitorRecord[]> => {
  const { keyword, to = 199 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .in('order_status', IN_TRANSIT_ORDER_STATUSES)
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .limit(to + 1)

  if (keyword) {
    query = query.or(
      `order_no.ilike.%${keyword}%,cargo_no.ilike.%${keyword}%,dispatch_plate_no.ilike.%${keyword}%,dispatch_driver_name.ilike.%${keyword}%`
    )
  }

  const { data } = await responseHandle<OrderRecord[]>(() => query as any, {
    ignoreCheck: true
  })

  return (data ?? [])
    .filter((order) => !existingWaybillNos.has(String(order.orderNo)))
    .map((order) => ({
      ...createDriverWaybillPayload(order),
      id: `order-${order.id || order.orderNo}`,
      order,
      status: ['signed', 'completed'].includes(String(order.orderStatus))
        ? 'completed'
        : order.orderStatus === 'transporting'
          ? 'transporting'
          : 'pending',
      tenantId: order.tenantId
    }))
}

export async function fetchInTransitMonitorList(
  params: InTransitMonitorSearchParams = { from: 0, to: 199 }
) {
  const { from = 0, to = 199, keyword, statuses = IN_TRANSIT_WAYBILL_STATUSES } = params
  let query: any = supabase
    .from('tms_waybill')
    .select('*', { count: 'exact' })
    .not('order_id', 'is', null)
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .range(from, to)

  if (statuses.length) query = query.in('status', statuses)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%,cargo_name.ilike.%${keyword}%,shipper_name.ilike.%${keyword}%,receiver_name.ilike.%${keyword}%`
    )
  }

  const result = await responseHandle<InTransitMonitorRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const rows = result.data ?? []
  const fallbackRows = await fetchInTransitOrderMonitorRows(
    params,
    new Set(rows.map((row) => String(row.waybillNo)))
  )
  const monitorRows = [...rows, ...fallbackRows]
  if (!monitorRows.length) return { ...result, data: [] }

  const [vehicleMap, driverMap, orderMap] = await Promise.all([
    fetchInTransitVehicleMap(uniqueStringValues(monitorRows.map((row) => row.vehicleId))),
    fetchInTransitDriverMap(uniqueStringValues(monitorRows.map((row) => row.driverId))),
    fetchInTransitOrderMap(uniqueStringValues(monitorRows.map((row) => row.waybillNo)))
  ])

  return {
    ...result,
    data: monitorRows
      .map((row) => ({
        ...row,
        driver: row.driverId ? (driverMap.get(String(row.driverId)) ?? null) : null,
        order: row.order ?? orderMap.get(String(row.waybillNo)) ?? null,
        vehicle: row.vehicleId ? (vehicleMap.get(String(row.vehicleId)) ?? null) : null
      }))
      .filter(isActiveTransitMonitorRow)
  }
}

export function subscribeInTransitMonitorChanges(onChange: () => void): () => void {
  const channel = supabase
    .channel(`tms-in-transit-monitor-${createRealtimeChannelId()}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tms_waybill' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tms_order' }, onChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'vehicle_archive' }, onChange)
    .subscribe()

  return () => {
    void supabase.removeChannel(channel)
  }
}

// 配送管理 / 在途监控
const applySignedTimeRange = (query: any, signedTimeRange?: string[]) => {
  if (signedTimeRange?.[0]) query = query.gte('signed_at', `${signedTimeRange[0]}T00:00:00`)
  if (signedTimeRange?.[1]) query = query.lte('signed_at', `${signedTimeRange[1]}T23:59:59.999`)
  return query
}

const applyDeliveryFilters = (query: any, params: DeliverySearchParams) => {
  const { orderStatuses, signedTimeRange } = params

  query = applyOrderFilters(query, params)
  if (orderStatuses?.length) query = query.in('order_status', orderStatuses)

  return applySignedTimeRange(query, signedTimeRange)
}

interface DeliveryStatusCountResult {
  total: number
  counts: Record<string, number>
}

const DELIVERY_STATUS_COUNT_VALUES = ['signed', 'completed'] as const

const countDeliveryOrders = async (params: DeliverySearchParams): Promise<number> => {
  let query: any = supabase.from('tms_order').select('id', { count: 'exact', head: true })
  query = applyDeliveryFilters(query, params)

  const { total } = await responseHandle<null>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return total ?? 0
}

export async function fetchDeliveryStatusCounts(
  params: DeliverySearchParams
): Promise<DeliveryStatusCountResult> {
  const sharedFilters = {
    ...params,
    deliveryStatus: undefined,
    orderStatus: undefined,
    orderStatuses: undefined
  }
  const [total, countEntries] = await Promise.all([
    countDeliveryOrders({ ...sharedFilters, orderStatuses: [...DELIVERY_STATUS_COUNT_VALUES] }),
    Promise.all(
      DELIVERY_STATUS_COUNT_VALUES.map(async (orderStatus) => {
        const count = await countDeliveryOrders({ ...sharedFilters, orderStatuses: [orderStatus] })
        return [orderStatus, count] as const
      })
    )
  ])

  return { total, counts: Object.fromEntries(countEntries) }
}

export async function fetchDeliveryList(
  params: DeliverySearchParams & Api.Common.CommonSearchParams
) {
  const { from = 0, to = 9 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportDeliveryList(
  params: DeliverySearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query: any = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => query as any, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function signDeliveryOrder(params: DeliverySignPayload) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少运单ID')

  return await responseHandle(
    () =>
      supabase.rpc('tms_complete_order_with_waybill', {
        p_order_id: id,
        p_signed_cod_amount: data.signedCodAmount ?? 0,
        p_receipt_image_urls: data.receiptImageUrls ?? [],
        p_signed_at: data.signedAt ?? new Date().toISOString()
      }) as any,
    { showMessage: true, breakReturn: true }
  )
}
