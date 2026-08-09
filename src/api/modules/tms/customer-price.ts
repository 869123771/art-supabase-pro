import { useSupabase } from '@/hooks'
import { applyCreateTimeRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'

type CustomerPrice = Api.Tms.BasicData.CustomerPrice
type CustomerPriceSearchParams = Api.Tms.BasicData.CustomerPriceSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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

const applyCustomerPriceFilters = (
  query: SupabaseQueryLike,
  params: CustomerPriceSearchParams
): SupabaseQueryLike => {
  const {
    customerId,
    originRegion,
    destinationRegion,
    transportType,
    cargoType,
    billingMethod,
    keyword,
    createTimeRange,
    recordId
  } = params

  if (recordId) query = query.eq('id', recordId)
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

  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchCustomerPriceList(params: CustomerPriceSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer_price')
    .select(CUSTOMER_PRICE_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyCustomerPriceFilters(query, params)
  return await responseHandle<CustomerPrice[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCustomerPriceList(
  params: CustomerPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_customer_price')
    .select(CUSTOMER_PRICE_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike

  query = ids?.length ? query.in('id', ids) : applyCustomerPriceFilters(query, params)
  return await responseHandle<CustomerPrice[]>(() => query, {
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

  return await responseHandle<CustomerPrice | null>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCustomerPrice(params: CustomerPrice) {
  return await responseHandle(
    () => supabase.from('tms_customer_price').insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editCustomerPrice(params: CustomerPrice) {
  const { id, ...data } = params
  delete data.customer
  return await responseHandle(
    () => supabase.from('tms_customer_price').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerPrice(id: string) {
  return await responseHandle(() => supabase.from('tms_customer_price').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCustomerPriceBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_customer_price').delete().in('id', ids), {
    showMessage: true
  })
}
