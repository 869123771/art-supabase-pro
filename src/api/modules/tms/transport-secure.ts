import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

export type TransportOrderScope =
  | 'order_list'
  | 'order_export'
  | 'order_detail'
  | 'order_open'
  | 'waybill_list'
  | 'waybill_export'
  | 'delivery_list'
  | 'delivery_export'
  | 'in_transit'
  | 'dashboard'

type TransportOrderParams = Api.Tms.Waybill.WaybillSearchParams &
  Api.Common.CommonSearchParams & {
    ids?: string[]
    maxRows?: number
    orderStatuses?: string[]
    signedTimeRange?: string[]
    countOnly?: boolean
  }

interface SecureTransportPayload<TRecord, TAccess> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

const { supabase, responseHandle } = useSupabase()

const startOfDay = (value?: string): string | null => (value ? `${value}T00:00:00` : null)
const endOfDay = (value?: string): string | null => (value ? `${value}T23:59:59.999` : null)

const normalizeStatus = (value?: string): string | null =>
  value && value !== '__all__' ? value : null

const createOrderRpcParams = (params: TransportOrderParams, scope: TransportOrderScope) => {
  const from = Math.max(params.from ?? 0, 0)
  const requestedTo = params.maxRows ? from + Math.max(params.maxRows, 1) - 1 : params.to
  const to = Math.max(requestedTo ?? 9, from)
  return {
    p_scope: scope,
    p_from: from,
    p_to: to,
    p_record_id: params.recordId || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_order_status: normalizeStatus(params.orderStatus),
    p_order_statuses: params.orderStatuses?.length ? params.orderStatuses : null,
    p_payment_method: params.paymentMethod || null,
    p_origin_station_id: params.originStationId || null,
    p_destination_station_id: params.destinationStationId || null,
    p_transfer_station_id: params.transferStationId || null,
    p_dispatch_status: normalizeStatus(params.dispatchStatus),
    p_dispatch_statuses: params.dispatchStatuses?.length ? params.dispatchStatuses : null,
    p_dispatch_vehicle_id: params.dispatchVehicleId || null,
    p_waybill_status: normalizeStatus(params.waybillStatus),
    p_cargo_keyword: String(params.cargoKeyword ?? '').trim() || null,
    p_shipping_keyword: String(params.shippingKeyword ?? '').trim() || null,
    p_receiving_keyword: String(params.receivingKeyword ?? '').trim() || null,
    p_vehicle_keyword: String(params.vehicleKeyword ?? '').trim() || null,
    p_create_time_from: startOfDay(params.createTimeRange?.[0]),
    p_create_time_to: endOfDay(params.createTimeRange?.[1]),
    p_planned_time_from: startOfDay(params.plannedTimeRange?.[0]),
    p_planned_time_to: endOfDay(params.plannedTimeRange?.[1]),
    p_signed_time_from: startOfDay(params.signedTimeRange?.[0]),
    p_signed_time_to: endOfDay(params.signedTimeRange?.[1]),
    p_count_only: params.countOnly === true
  }
}

export async function fetchSecureOrders<TRecord extends Api.Tms.Order.OrderRecord>(
  params: TransportOrderParams,
  scope: TransportOrderScope,
  options?: ApiRequestOptions
) {
  const result = await responseHandle<
    SecureTransportPayload<TRecord, Api.Tms.Order.OrderFieldAccessMap>
  >(
    () =>
      withRequestOptions(
        supabase.rpc('tms_list_orders_secure', createOrderRpcParams(params, scope)),
        options
      ),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchSecureInTransitWaybills(params: {
  from?: number
  to?: number
  statuses?: string[]
  keyword?: string
}) {
  const result = await responseHandle<
    SecureTransportPayload<Api.Tms.InTransit.MonitorRecord, Api.Tms.Waybill.WaybillFieldAccessMap>
  >(() =>
    supabase.rpc('tms_list_waybills_secure', {
      p_scope: 'in_transit',
      p_from: Math.max(params.from ?? 0, 0),
      p_to: Math.max(params.to ?? 199, params.from ?? 0),
      p_statuses: params.statuses?.length ? params.statuses : null,
      p_keyword: String(params.keyword ?? '').trim() || null
    })
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}
