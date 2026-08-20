import { pick, pickBy } from 'lodash-es'
import { useSupabase } from '@/hooks'

type CarrierPrice = Api.Tms.BasicData.CarrierPrice
type CarrierPriceSearchParams = Api.Tms.BasicData.CarrierPriceSearchParams

interface SecureListPayload<TRecord, TAccess extends Record<string, string>> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const CARRIER_PRICE_PAYLOAD_KEYS = [
  'quoteNo',
  'carrierId',
  'driverId',
  'vehicleId',
  'originRegion',
  'destinationRegion',
  'transportMode',
  'contactName',
  'contactPhone',
  'driverName',
  'driverPhone',
  'plateNo',
  'vehicleType',
  'vehicleLength',
  'cargoItems',
  'cargoQuantityTotal',
  'cargoVolumeTotal',
  'cargoWeightTotal',
  'billingMethod',
  'transportCost',
  'splitTransportFee',
  'loadingFee',
  'packageFee',
  'otherFee',
  'totalFee',
  'cashAmount',
  'prepaidAmount',
  'collectAmount',
  'periodicAmount',
  'paymentTotal',
  'remark'
] as const satisfies readonly (keyof CarrierPrice)[]

const createPayload = (record: Partial<CarrierPrice>): Record<string, unknown> =>
  pickBy(pick(record, CARRIER_PRICE_PAYLOAD_KEYS), (value) => value !== undefined)

const toListRpcParams = (
  params: CarrierPriceSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_carrier_id: params.carrierId || null,
    p_record_id: params.recordId || null,
    p_origin_region: params.originRegion || null,
    p_destination_region: params.destinationRegion || null,
    p_transport_mode: params.transportMode || null,
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

export async function fetchCarrierPriceList(params: CarrierPriceSearchParams) {
  const result = await responseHandle<
    SecureListPayload<CarrierPrice, Api.Tms.BasicData.CarrierPriceFieldAccessMap>
  >(() => supabase.rpc('tms_list_carrier_prices_secure', toListRpcParams(params, 'list')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCarrierPriceList(
  params: CarrierPriceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<CarrierPrice, Api.Tms.BasicData.CarrierPriceFieldAccessMap>
  >(() => supabase.rpc('tms_list_carrier_prices_secure', toListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCarrierPriceDetail(id: string) {
  return await responseHandle<CarrierPrice | null>(
    () => supabase.rpc('tms_get_carrier_price_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function addCarrierPrice(params: CarrierPrice) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_carrier_price_secure', {
        p_payload: keysToSnakeDeep(createPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data ? { id: result.data } : null }
}

export async function editCarrierPrice(params: CarrierPrice) {
  const { id, ...data } = params
  if (!id) throw new Error('承运商价格 ID 不能为空')
  return await responseHandle<CarrierPrice>(
    () =>
      supabase.rpc('tms_update_carrier_price_secure', {
        p_id: id,
        p_payload: keysToSnakeDeep(createPayload(data))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrierPrice(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_carrier_price_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteCarrierPriceBatch(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('tms_delete_carrier_prices_secure', { p_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
