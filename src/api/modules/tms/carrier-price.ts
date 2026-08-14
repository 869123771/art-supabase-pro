import { useSupabase } from '@/hooks'
import { applyCreateTimeRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'

type CarrierPrice = Api.Tms.BasicData.CarrierPrice
type CarrierPriceSearchParams = Api.Tms.BasicData.CarrierPriceSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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

const applyCarrierPriceFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: CarrierPriceSearchParams
): TQuery => {
  const {
    carrierId,
    recordId,
    originRegion,
    destinationRegion,
    transportMode,
    billingMethod,
    keyword,
    createTimeRange
  } = params

  if (recordId) query = query.eq('id', recordId)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (originRegion) query = query.eq('origin_region', originRegion)
  if (destinationRegion) query = query.eq('destination_region', destinationRegion)
  if (transportMode) query = query.eq('transport_mode', transportMode)
  if (billingMethod) query = query.eq('billing_method', billingMethod)
  if (keyword) {
    query = query.or(
      `quote_no.ilike.%${keyword}%,contact_name.ilike.%${keyword}%,contact_phone.ilike.%${keyword}%,driver_name.ilike.%${keyword}%,driver_phone.ilike.%${keyword}%,plate_no.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }

  return applyCreateTimeRange(query, createTimeRange)
}

export async function fetchCarrierPriceList(params: CarrierPriceSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_carrier_price')
    .select(CARRIER_PRICE_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyCarrierPriceFilters(query, params)
  return await responseHandle<CarrierPrice[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCarrierPriceList(
  params: CarrierPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_carrier_price')
    .select(CARRIER_PRICE_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyCarrierPriceFilters(query, params)
  return await responseHandle<CarrierPrice[]>(() => query, {
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

  return await responseHandle<CarrierPrice | null>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addCarrierPrice(params: CarrierPrice) {
  return await responseHandle(
    () => supabase.from('tms_carrier_price').insert(keysToSnakeDeep(params)),
    { showMessage: true, breakReturn: true }
  )
}

export async function editCarrierPrice(params: CarrierPrice) {
  const { id, ...data } = params
  delete data.carrier
  delete data.driver
  delete data.vehicle
  return await responseHandle(
    () => supabase.from('tms_carrier_price').update(keysToSnakeDeep(data)).eq('id', id),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrierPrice(id: string) {
  return await responseHandle(() => supabase.from('tms_carrier_price').delete().eq('id', id), {
    showMessage: true
  })
}

export async function deleteCarrierPriceBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('tms_carrier_price').delete().in('id', ids), {
    showMessage: true
  })
}
