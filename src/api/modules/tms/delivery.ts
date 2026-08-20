import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import type { ApiRequestOptions } from '@/types/api/request'
import { fetchSecureOrders } from '@/api/modules/tms/transport-secure'

type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
type DeliverySearchParams = Api.Tms.Delivery.DeliverySearchParams
type DeliveryReceiptArchivePayload = Api.Tms.Delivery.DeliveryReceiptArchivePayload

const { supabase, responseHandle } = useSupabase()

interface DeliveryStatusCountResult {
  total: number
  counts: Record<string, number>
}

const DELIVERY_STATUS_COUNT_VALUES = ['signed', 'completed'] as const

const countDeliveryOrders = async (params: DeliverySearchParams): Promise<number> => {
  const result = await fetchSecureOrders<DeliveryRecord>(
    { ...params, countOnly: true },
    'delivery_list'
  )
  return result.total
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
  return await fetchSecureOrders<DeliveryRecord>(params, 'delivery_list', options)
}

export async function exportDeliveryList(
  params: DeliverySearchParams & { ids?: string[]; maxRows?: number }
) {
  return await fetchSecureOrders<DeliveryRecord>(params, 'delivery_export')
}

export async function archiveDeliveryReceipt(params: DeliveryReceiptArchivePayload) {
  const { id, ...data } = params
  if (!id) throw new Error('缺少运单 ID')

  const query = supabase.rpc('tms_archive_order_delivery_receipt', {
    p_order_id: id,
    p_signed_cod_amount: data.signedCodAmount ?? 0,
    p_receipt_image_urls: data.receiptImageUrls ?? [],
    p_signed_at: data.signedAt ?? new Date().toISOString()
  })

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
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}

export async function reviewWaybillReceiptOcrArtifact(
  params: Api.Tms.Delivery.ReceiptOcrReviewRequest
): Promise<QueryResult<Api.Tms.Delivery.ReceiptOcrReviewResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Delivery.ReceiptOcrReviewResponse>(
      'ai-waybill-receipt-ocr',
      { body: params }
    )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
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
