import { useSupabase } from '@/hooks'
import { applyCreateTimeRange, type SupabaseQueryLike } from '@/api/modules/tms/query'

type OrderRecord = Api.Tms.Order.OrderRecord
type OrderSearchParams = Api.Tms.Order.OrderSearchParams
type InTransitMonitorRecord = Api.Tms.InTransit.MonitorRecord

const { supabase, responseHandle } = useSupabase()

export const ORDER_SELECT = `
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

export const uniqueStringValues = (values: Array<string | null | undefined>): string[] =>
  Array.from(new Set(values.map((value) => String(value ?? '').trim()).filter(Boolean)))

export const applyOrderFilters = (
  query: SupabaseQueryLike,
  params: OrderSearchParams
): SupabaseQueryLike => {
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

  return applyCreateTimeRange(query, createTimeRange)
}

export const applyOrderListFilters = (
  query: SupabaseQueryLike,
  params: OrderSearchParams
): SupabaseQueryLike => applyOrderFilters(query.neq('order_status', 'created'), params)

const DRIVER_WAYBILL_SELECT =
  'id, tenant_id, waybill_no, status, loaded_at, departed_at, unloaded_at, cancelled_at, update_time'

const fetchDriverWaybillMap = async (
  orderNos: string[]
): Promise<Map<string, InTransitMonitorRecord>> => {
  if (!orderNos.length) return new Map()

  const { data } = await responseHandle<InTransitMonitorRecord[]>(
    () => supabase.from('tms_waybill').select(DRIVER_WAYBILL_SELECT).in('waybill_no', orderNos),
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

export const mergeOrdersWithDriverWaybills = async <T extends OrderRecord>(
  orders: T[] | null | undefined
): Promise<T[]> => {
  const rows = orders ?? []
  const waybillMap = await fetchDriverWaybillMap(uniqueStringValues(rows.map((row) => row.orderNo)))
  return rows.map((row) => mergeDriverWaybillStatus(row, waybillMap.get(String(row.orderNo))) as T)
}
