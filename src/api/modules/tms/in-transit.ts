import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { createDriverWaybillPayload } from '@/api/modules/tms/waybill-shared'
import { fetchSecureInTransitWaybills, fetchSecureOrders } from '@/api/modules/tms/transport-secure'

type InTransitMonitorRecord = Api.Tms.InTransit.MonitorRecord
type InTransitMonitorSearchParams = Api.Tms.InTransit.MonitorSearchParams

const { supabase } = useSupabase()

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

const fetchInTransitOrderMonitorRows = async (
  params: InTransitMonitorSearchParams,
  existingWaybillNos: Set<string>
): Promise<InTransitMonitorRecord[]> => {
  const { keyword, to = 199 } = params
  const result = await fetchSecureOrders<Api.Tms.Order.OrderRecord>(
    {
      from: 0,
      to,
      orderStatuses: MONITORED_ORDER_STATUSES,
      cargoKeyword: keyword,
      vehicleKeyword: keyword
    },
    'in_transit'
  )

  return result.data
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
  const result = await fetchSecureInTransitWaybills({ from, to, keyword, statuses })
  const rows = result.data
  const fallbackRows = await fetchInTransitOrderMonitorRows(
    params,
    new Set(rows.map((row) => String(row.waybillNo)))
  )
  const monitorRows = [...rows, ...fallbackRows]
  if (!monitorRows.length) return { ...result, data: [] }

  return {
    ...result,
    data: monitorRows.filter(isMonitoredTransportRow)
  }
}

export async function analyzeTransportAnomalyByAi(
  orderId: string
): Promise<QueryResult<Api.Tms.InTransit.TransportAnomalyAdvisorResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.InTransit.TransportAnomalyAdvisorResponse>(
      'ai-transport-anomaly-advisor',
      { body: { orderId } }
    )

  return {
    data: data ?? null,
    error: await normalizeTransportAnomalyAdvisorError(error)
  }
}

async function normalizeTransportAnomalyAdvisorError(error: unknown): Promise<unknown | null> {
  if (!error || typeof error !== 'object' || !('context' in error)) return error

  const context = (error as { context?: unknown }).context
  if (!(context instanceof Response)) return error

  try {
    const payload = (await context.clone().json()) as { code?: unknown; message?: unknown }
    if (typeof payload.message !== 'string' || !payload.message) return error
    return {
      code: typeof payload.code === 'string' ? payload.code : undefined,
      message: payload.message
    }
  } catch {
    return error
  }
}

export function subscribeInTransitMonitorChanges(onChange: () => void): () => void {
  const channel = supabase
    .channel(`tms-in-transit-monitor-${createRealtimeChannelId()}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'tms_transport_change_signal' },
      onChange
    )
    .subscribe()

  return () => {
    void supabase.removeChannel(channel)
  }
}
