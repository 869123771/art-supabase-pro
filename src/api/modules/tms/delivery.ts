import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { applyOrderFilters, ORDER_SELECT } from '@/api/modules/tms/order-shared'
import type { ApiRequestOptions } from '@/types/api/request'

type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
type DeliverySearchParams = Api.Tms.Delivery.DeliverySearchParams
type DeliverySignPayload = Api.Tms.Delivery.DeliverySignPayload

const { supabase, responseHandle } = useSupabase()

// 配送签收 / 在途监控
const applySignedTimeRange = (
  query: SupabaseQueryLike,
  signedTimeRange?: string[]
): SupabaseQueryLike => {
  if (signedTimeRange?.[0]) query = query.gte('signed_at', `${signedTimeRange[0]}T00:00:00`)
  if (signedTimeRange?.[1]) query = query.lte('signed_at', `${signedTimeRange[1]}T23:59:59.999`)
  return query
}

const applyDeliveryFilters = (
  query: SupabaseQueryLike,
  params: DeliverySearchParams
): SupabaseQueryLike => {
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
  let query = supabase
    .from('tms_order')
    .select('id', { count: 'exact', head: true }) as unknown as SupabaseQueryLike

  query = applyDeliveryFilters(query, params)

  const { total } = await responseHandle<null>(() => query, {
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
  params: DeliverySearchParams & Api.Common.CommonSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportDeliveryList(
  params: DeliverySearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike

  query = ids?.length ? query.in('id', ids) : applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function signDeliveryOrder(params: DeliverySignPayload) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少运单 ID')

  const query = supabase.rpc('tms_complete_order_with_waybill', {
    p_order_id: id,
    p_signed_cod_amount: data.signedCodAmount ?? 0,
    p_receipt_image_urls: data.receiptImageUrls ?? [],
    p_signed_at: data.signedAt ?? new Date().toISOString()
  }) as unknown as PromiseLike<QueryResult<unknown>>

  return await responseHandle(() => query, {
    showMessage: true,
    breakReturn: true
  })
}

export async function analyzeWaybillReceiptByAi(
  params: Api.Tms.Delivery.ReceiptOcrAnalyzeRequest
): Promise<QueryResult<Api.Tms.Delivery.ReceiptOcrAnalyzeResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Delivery.ReceiptOcrAnalyzeResponse>(
      'ai-waybill-receipt-ocr',
      { body: params }
    )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

export async function reviewWaybillReceiptOcrArtifact(
  params: Api.Tms.Delivery.ReceiptOcrReviewRequest
): Promise<QueryResult<Api.Tms.Delivery.ReceiptOcrReviewResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Delivery.ReceiptOcrReviewResponse>(
      'ai-waybill-receipt-ocr',
      { body: params }
    )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

const RECEIPT_EXCEPTION_SELECT = `
  id,tenant_id,work_order_no,order_id,ai_artifact_review_id,order_no_snapshot,severity,status,
  exception_types,summary,evidence_urls,assignee_id,started_at,due_at,resolution_note,
  create_by,create_time,update_time
`

interface ReceiptExceptionRow {
  id: string
  tenant_id: string
  work_order_no: string
  order_id: string
  ai_artifact_review_id: string
  order_no_snapshot: string
  severity: Api.Tms.Delivery.ReceiptExceptionSeverity
  status: Api.Tms.Delivery.ReceiptExceptionStatus
  exception_types?: string[] | null
  summary: string
  evidence_urls?: string[] | null
  assignee_id?: string | null
  started_at?: string | null
  due_at: string
  resolution_note?: string | null
  create_by?: string | null
  create_time: string
  update_time: string
}

function mapReceiptException(row: ReceiptExceptionRow): Api.Tms.Delivery.ReceiptExceptionWorkOrder {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    workOrderNo: row.work_order_no,
    orderId: row.order_id,
    aiArtifactReviewId: row.ai_artifact_review_id,
    orderNoSnapshot: row.order_no_snapshot,
    severity: row.severity,
    status: row.status,
    exceptionTypes: row.exception_types ?? [],
    summary: row.summary,
    evidenceUrls: row.evidence_urls ?? [],
    assigneeId: row.assignee_id,
    startedAt: row.started_at,
    dueAt: row.due_at,
    resolutionNote: row.resolution_note,
    createBy: row.create_by,
    createTime: row.create_time,
    updateTime: row.update_time
  }
}

export async function fetchReceiptExceptionWorkOrders(params: {
  recordId?: string
  status?: Api.Tms.Delivery.ReceiptExceptionStatus | ''
  keyword?: string
}) {
  let query = supabase
    .from('tms_receipt_exception_work_order')
    .select(RECEIPT_EXCEPTION_SELECT)
    .order('create_time', { ascending: false })
  if (params.recordId) query = query.eq('id', params.recordId)
  if (params.status) query = query.eq('status', params.status)
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim().replace(/[%_,()]/g, '')
    query = query.or(
      `work_order_no.ilike.%${keyword}%,order_no_snapshot.ilike.%${keyword}%,summary.ilike.%${keyword}%`
    )
  }
  const result = await responseHandle<ReceiptExceptionRow[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: (result.data ?? []).map(mapReceiptException) }
}

export async function createReceiptExceptionWorkOrder(params: {
  artifactId: string
  orderId: string
  evidenceUrls: string[]
  workOrderNo?: string | null
}) {
  const result = await responseHandle<ReceiptExceptionRow>(
    () =>
      supabase.rpc('create_ai_receipt_exception_work_order', {
        p_artifact_id: params.artifactId,
        p_order_id: params.orderId,
        p_evidence_urls: params.evidenceUrls,
        p_work_order_no: params.workOrderNo || null
      }),
    { breakReturn: true, showErrorMessage: true }
  )
  return result.data ? mapReceiptException(result.data) : null
}

export async function transitionReceiptExceptionWorkOrder(
  id: string,
  status: Api.Tms.Delivery.ReceiptExceptionStatus,
  note?: string
) {
  const result = await responseHandle<ReceiptExceptionRow>(
    () =>
      supabase.rpc('transition_ai_receipt_exception_work_order', {
        p_work_order_id: id,
        p_next_status: status,
        p_note: note?.trim() || null
      }),
    { breakReturn: true, showErrorMessage: true }
  )
  return result.data ? mapReceiptException(result.data) : null
}

async function normalizeFunctionInvokeError(error: unknown): Promise<unknown | null> {
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
