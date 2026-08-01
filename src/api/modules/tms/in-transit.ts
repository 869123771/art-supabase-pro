import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'
import { ORDER_SELECT, uniqueStringValues } from '@/api/modules/tms/order-shared'
import {
  createDriverWaybillPayload,
  DISPATCH_VEHICLE_SELECT
} from '@/api/modules/tms/waybill-shared'

type OrderRecord = Api.Tms.Order.OrderRecord
type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
type InTransitMonitorRecord = Api.Tms.InTransit.MonitorRecord
type InTransitMonitorSearchParams = Api.Tms.InTransit.MonitorSearchParams

const { supabase, responseHandle } = useSupabase()

const createRealtimeChannelId = (): string => {
  if (typeof globalThis.crypto?.randomUUID === 'function') {
    return globalThis.crypto.randomUUID()
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

// 在途监控
const MONITORED_WAYBILL_STATUSES = [
  'pending',
  'accepted',
  'loading',
  'transporting',
  'unloading',
  'signed',
  'completed',
  // 兼容历史在途状态，司机端当前使用上面的标准状态。
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

const MONITORED_ORDER_STATUSES = [
  'pending_load',
  'pending_order',
  'pending_pickup',
  'transporting',
  'signed',
  'completed'
]

const EXCLUDED_MONITOR_STATUSES = new Set([
  'created',
  'cancelled',
  'canceled',
  'closed',
  '已取消',
  '已关闭'
])

const isMonitoredTransportRow = (row: InTransitMonitorRecord): boolean => {
  const waybillStatus = String(row.status ?? '')
    .trim()
    .toLowerCase()
  const orderStatus = String(row.order?.orderStatus ?? '')
    .trim()
    .toLowerCase()
  return (
    MONITORED_WAYBILL_STATUSES.includes(waybillStatus) &&
    !EXCLUDED_MONITOR_STATUSES.has(waybillStatus) &&
    !EXCLUDED_MONITOR_STATUSES.has(orderStatus)
  )
}

const fetchInTransitVehicleMap = async (
  ids: string[]
): Promise<Map<string, DispatchVehicleOption>> => {
  if (!ids.length) return new Map()

  const query = supabase
    .from('vehicle_archive')
    .select(DISPATCH_VEHICLE_SELECT)
    .in('id', ids) as unknown as SupabaseQueryLike

  const { data } = await responseHandle<DispatchVehicleOption[]>(() => query, {
    ignoreCheck: true
  })

  return new Map((data ?? []).map((item) => [String(item.id), item]))
}

const fetchInTransitDriverMap = async (
  ids: string[]
): Promise<Map<string, Api.Tms.BasicData.DriverOption>> => {
  if (!ids.length) return new Map()

  const query = supabase
    .from('tms_driver')
    .select('id, carrier_id, driver_name, phone')
    .in('id', ids) as unknown as SupabaseQueryLike

  const { data } = await responseHandle<Api.Tms.BasicData.DriverOption[]>(() => query, {
    ignoreCheck: true
  })

  return new Map((data ?? []).map((item) => [String(item.id), item]))
}

const fetchInTransitOrderMap = async (waybillNos: string[]): Promise<Map<string, OrderRecord>> => {
  if (!waybillNos.length) return new Map()

  const query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .in('order_no', waybillNos) as unknown as SupabaseQueryLike

  const { data } = await responseHandle<OrderRecord[]>(() => query, {
    ignoreCheck: true
  })

  return new Map((data ?? []).map((item) => [String(item.orderNo), item]))
}

const fetchInTransitOrderMonitorRows = async (
  params: InTransitMonitorSearchParams,
  existingWaybillNos: Set<string>
): Promise<InTransitMonitorRecord[]> => {
  const { keyword, to = 199 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .in('order_status', MONITORED_ORDER_STATUSES)
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .limit(to + 1) as unknown as SupabaseQueryLike

  if (keyword) {
    query = query.or(
      `order_no.ilike.%${keyword}%,cargo_no.ilike.%${keyword}%,dispatch_plate_no.ilike.%${keyword}%,dispatch_driver_name.ilike.%${keyword}%`
    )
  }

  const { data } = await responseHandle<OrderRecord[]>(() => query, {
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
  const { from = 0, to = 199, keyword, statuses = MONITORED_WAYBILL_STATUSES } = params
  let query = supabase
    .from('tms_waybill')
    .select('*', { count: 'exact' })
    .not('order_id', 'is', null)
    .order('update_time', { ascending: false, nullsFirst: false })
    .order('create_time', { ascending: false, nullsFirst: false })
    .range(from, to) as unknown as SupabaseQueryLike

  if (statuses.length) query = query.in('status', statuses)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%,cargo_name.ilike.%${keyword}%,shipper_name.ilike.%${keyword}%,receiver_name.ilike.%${keyword}%`
    )
  }

  const result = await responseHandle<InTransitMonitorRecord[]>(() => query, {
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
      .filter(isMonitoredTransportRow)
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
