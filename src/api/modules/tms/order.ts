import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import {
  applyOrderListFilters,
  mergeOrdersWithDriverWaybills,
  ORDER_SELECT
} from '@/api/modules/tms/order-shared'

type OrderRecord = Api.Tms.Order.OrderRecord
type OrderSearchParams = Api.Tms.Order.OrderSearchParams
type OrderFreightPayload = Api.Tms.Order.OrderFreightPayload
type RelatedWaybillSummary = Api.Tms.Waybill.RelatedWaybillSummary

interface RelatedWaybillRow extends RelatedWaybillSummary {
  driver?: { driverName?: string | null; phone?: string | null } | null
  vehicle?: { plateNo?: string | null } | null
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

export async function fetchOrderList(
  params: OrderSearchParams & Api.Common.CommonSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyOrderListFilters(query, params)
  const result = await responseHandle<OrderRecord[]>(() => withRequestOptions(query, options), {
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
      let query = supabase.from('tms_order').select('id', { count: 'exact', head: true })

      query = applyOrderListFilters(query, { ...sharedFilters, orderStatus })
      const { total } = await responseHandle<null>(() => query, { ignoreCheck: true })
      return [orderStatus, total ?? 0] as const
    })
  )

  return Object.fromEntries(countEntries)
}

export async function exportOrderList(
  params: OrderSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows)

  query = ids?.length ? query.in('id', ids) : applyOrderListFilters(query, params)
  const result = await responseHandle<OrderRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function fetchOrderDetail(id: string) {
  const query = supabase.from('tms_order').select(ORDER_SELECT).eq('id', id).maybeSingle()

  const result = await responseHandle<OrderRecord | null>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const rows = result.data ? await mergeOrdersWithDriverWaybills([result.data]) : []
  const order = rows[0] ?? null
  if (!order?.id) return { ...result, data: order }

  const [audit, relatedWaybills] = await Promise.all([
    fetchDriverDeliveryAudit(order.id),
    fetchRelatedWaybills(order.id)
  ])
  return { ...result, data: { ...order, ...audit, relatedWaybills } }
}

async function fetchRelatedWaybills(orderId: string): Promise<RelatedWaybillSummary[]> {
  const { data } = await responseHandle<RelatedWaybillRow[]>(
    () =>
      supabase
        .from('tms_waybill')
        .select(
          `
            id,
            waybill_no,
            status,
            accepted_at,
            departed_at,
            completed_at,
            driver:tms_driver!tms_waybill_driver_id_fkey(driver_name, phone),
            vehicle:vehicle_archive!tms_waybill_vehicle_id_fkey(plate_no)
          `
        )
        .eq('order_id', orderId)
        .order('create_time', { ascending: false }),
    {
      breakReturn: true,
      errorMessage: '关联运单加载失败，请稍后重试'
    }
  )

  return (data ?? []).map((item) => {
    return {
      id: item.id,
      waybillNo: item.waybillNo,
      status: item.status,
      acceptedAt: item.acceptedAt,
      departedAt: item.departedAt,
      completedAt: item.completedAt,
      driverName: item.driver?.driverName ?? null,
      driverPhone: item.driver?.phone ?? null,
      plateNo: item.vehicle?.plateNo ?? null
    }
  })
}

async function fetchDriverDeliveryAudit(orderId: string): Promise<Partial<OrderRecord>> {
  const { data: waybill, error: waybillError } = await supabase
    .from('tms_waybill')
    .select('id, completed_at')
    .eq('order_id', orderId)
    .order('create_time', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (waybillError || !waybill) return {}

  const [eventResult, proofResult] = await Promise.all([
    supabase
      .from('tms_waybill_event')
      .select('event_type, event_time, operator_name, payload')
      .eq('waybill_id', waybill.id)
      .in('event_type', ['signed', 'completed'])
      .order('event_time', { ascending: true }),
    supabase
      .from('tms_waybill_proof')
      .select('id, proof_type')
      .eq('waybill_id', waybill.id)
      .in('proof_type', ['delivery_photo', 'receipt'])
  ])

  const signedEvent = (eventResult.data ?? []).find(
    (event) =>
      event.event_type === 'signed' ||
      String((event.payload as Record<string, unknown> | null)?.action ?? '') === 'submit_signature'
  )

  return {
    driverWaybillCompletedAt: waybill.completed_at,
    driverWaybillSignedAt: signedEvent?.event_time ?? null,
    driverWaybillSignedBy: signedEvent?.operator_name ?? null,
    driverWaybillSignatureProofCount: proofResult.data?.length ?? 0
  }
}

export async function addOrder(params: OrderRecord) {
  return await responseHandle<OrderRecord>(
    () => supabase.from('tms_order').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function analyzeOrderByAi(
  params: Api.Tms.Order.AiOrderAnalyzeRequest
): Promise<QueryResult<Api.Tms.Order.AiOrderAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Order.AiOrderAnalyzeResponse>(
    'ai-order-assistant',
    { body: params }
  )

  return {
    data: data ?? null,
    error: await normalizeEdgeFunctionError(error)
  }
}

export async function generateAiOrderExample(
  params: Api.Tms.Order.AiOrderExampleRequest = {}
): Promise<QueryResult<Api.Tms.Order.AiOrderExampleResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Order.AiOrderExampleResponse>(
    'ai-order-assistant',
    { body: { ...params, action: 'generate_example' } }
  )

  return {
    data: data ?? null,
    error: await normalizeEdgeFunctionError(error)
  }
}

export async function createAiOrderMasterData(tasks: Api.Tms.Order.AiOrderMasterDataCreateTask[]) {
  return await responseHandle<Api.Tms.Order.AiOrderMasterDataCreateResult[]>(
    () =>
      supabase.rpc('create_ai_order_master_data', {
        p_tasks: keysToSnakeDeep(tasks)
      }),
    { breakReturn: true }
  )
}

export async function reviewAiOrderArtifact(
  params: Api.Tms.Order.AiOrderReviewRequest
): Promise<QueryResult<Api.Tms.Order.AiOrderReviewResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Order.AiOrderReviewResponse>(
    'ai-order-assistant',
    { body: params }
  )

  return {
    data: data ?? null,
    error: await normalizeEdgeFunctionError(error)
  }
}

async function normalizeEdgeFunctionError(error: unknown): Promise<unknown | null> {
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

export async function editOrder(params: OrderRecord) {
  const { id, ...data } = params
  delete data.shippingCustomer
  delete data.receivingCustomer
  delete data.originStationRef
  delete data.destinationStationRef
  delete data.transferStationRef
  delete data.dispatchVehicle
  delete data.dispatchDriver
  delete data.driverWaybillAcceptedAt
  delete data.driverWaybillLoadedAt
  delete data.driverWaybillDepartedAt
  delete data.driverWaybillUnloadedAt
  delete data.driverWaybillCompletedAt
  delete data.driverWaybillSignedAt
  delete data.driverWaybillSignedBy
  delete data.driverWaybillSignatureProofCount
  delete data.waybillStatus

  return await responseHandle<OrderRecord>(
    () =>
      supabase
        .from('tms_order')
        .update(keysToSnakeDeep(data))
        .eq('id', id)
        .eq('order_status', 'pending_load')
        .select()
        .single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editOrderFreight(params: OrderFreightPayload) {
  const { id, ...data } = params

  return await responseHandle<OrderRecord>(
    () => supabase.from('tms_order').update(keysToSnakeDeep(data)).eq('id', id).select().single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteOrder(id: string) {
  return await responseHandle(
    () => supabase.rpc('tms_delete_order_with_waybill', { p_order_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteOrderBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.rpc('tms_delete_orders_with_waybills', { p_order_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}
