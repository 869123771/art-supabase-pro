import { pick, pickBy } from 'lodash-es'
import { useSupabase } from '@/hooks'

type CustomerPrice = Api.Tms.BasicData.CustomerPrice
type CustomerPriceSearchParams = Api.Tms.BasicData.CustomerPriceSearchParams

interface SecureListPayload<TRecord, TAccess extends Record<string, string>> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CUSTOMER_PRICE_PAYLOAD_KEYS = [
  'customerId',
  'originRegion',
  'destinationRegion',
  'transportType',
  'cargoType',
  'shippingAddressId',
  'receivingAddressId',
  'shippingContactName',
  'shippingContactPhone',
  'shippingAddressDetail',
  'shippingLongitude',
  'shippingLatitude',
  'receivingContactName',
  'receivingContactPhone',
  'receivingAddressDetail',
  'receivingLongitude',
  'receivingLatitude',
  'cargoItems',
  'cargoQuantityTotal',
  'cargoVolumeTotal',
  'cargoWeightTotal',
  'vehicleType',
  'vehicleLength',
  'vehicleCount',
  'billingMethod',
  'transportFee',
  'insuranceFee',
  'packageFee',
  'loadingFee',
  'transferFee',
  'fuelFee',
  'serviceFee',
  'otherFee',
  'totalFee',
  'cashAmount',
  'prepaidAmount',
  'collectAmount',
  'periodicAmount',
  'paymentTotal',
  'remark'
] as const satisfies readonly (keyof CustomerPrice)[]

const createPayload = (record: Partial<CustomerPrice>): Record<string, unknown> =>
  pickBy(pick(record, CUSTOMER_PRICE_PAYLOAD_KEYS), (value) => value !== undefined)

const toListRpcParams = (
  params: CustomerPriceSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_customer_id: params.customerId || null,
    p_record_id: params.recordId || null,
    p_origin_region: params.originRegion || null,
    p_destination_region: params.destinationRegion || null,
    p_transport_type: params.transportType || null,
    p_cargo_type: params.cargoType || null,
    p_billing_method: params.billingMethod || null,
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

export async function fetchCustomerPriceList(params: CustomerPriceSearchParams) {
  const result = await responseHandle<
    SecureListPayload<CustomerPrice, Api.Tms.BasicData.CustomerPriceFieldAccessMap>
  >(() => supabase.rpc('tms_list_customer_prices_secure', toListRpcParams(params, 'list')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCustomerPriceList(
  params: CustomerPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<CustomerPrice, Api.Tms.BasicData.CustomerPriceFieldAccessMap>
  >(() => supabase.rpc('tms_list_customer_prices_secure', toListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCustomerPriceDetail(id: string) {
  return await responseHandle<CustomerPrice | null>(
    () => supabase.rpc('tms_get_customer_price_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function addCustomerPrice(params: CustomerPrice) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_customer_price_secure', {
        p_payload: keysToSnakeDeep(createPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editCustomerPrice(params: CustomerPrice) {
  const { id, ...data } = params
  if (!id) throw new Error('客户价格 ID 不能为空')
  return await responseHandle<CustomerPrice>(
    () =>
      supabase.rpc('tms_update_customer_price_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(createPayload(data))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerPrice(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_customer_price_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCustomerPriceBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_customer_prices_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
