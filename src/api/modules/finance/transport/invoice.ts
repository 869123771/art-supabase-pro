import { createFriendlySupabaseError, normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type Invoice = Api.Finance.InvoiceRecord
type InvoiceSearchParams = Api.Finance.InvoiceSearchParams
type InvoiceableStatement = Api.Finance.InvoiceableStatement
type InvoiceableSearchParams = Api.Finance.InvoiceableStatementSearchParams
type SaveInvoicePayload = Api.Finance.SaveInvoicePayload
type InvoiceStatusPayload = Api.Finance.InvoiceStatusPayload & { businessTitle?: string }
type InvoiceStatementLink = Api.Finance.InvoiceStatementLinkRecord
type InvoiceDuplicateRecord = Api.Finance.InvoiceDuplicateRecord

const { supabase, responseHandle } = useSupabase()
const ACTIVE_LEGAL_NO_CONSTRAINT = 'tms_invoice_active_legal_no_key'

export class InvoiceLegalNumberConflictError extends Error {
  constructor() {
    super('同方向下该发票号码已登记，请核对已有发票后再处理')
    this.name = 'InvoiceLegalNumberConflictError'
  }
}

export function isInvoiceLegalNumberConflict(error: unknown): boolean {
  if (error instanceof InvoiceLegalNumberConflictError) return true
  if (!error || typeof error !== 'object') return false
  const candidate = error as { code?: unknown; constraint?: unknown; message?: unknown }
  return (
    candidate.code === '23505' &&
    (candidate.constraint === ACTIVE_LEGAL_NO_CONSTRAINT ||
      String(candidate.message ?? '').includes(ACTIVE_LEGAL_NO_CONSTRAINT))
  )
}

function toError(error: unknown): Error {
  return createFriendlySupabaseError(error, '发票保存失败，请稍后重试')
}

function applyInvoiceFilters<TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: InvoiceSearchParams
): TQuery {
  const {
    carrierId,
    customerId,
    direction,
    invoiceType,
    issueDateRange,
    keyword,
    recordId,
    status
  } = params
  if (recordId) query = query.eq('id', recordId)
  if (direction) query = query.eq('direction', direction)
  if (invoiceType) query = query.eq('invoice_type', invoiceType)
  if (status) query = query.eq('status', status)
  if (customerId) query = query.eq('customer_id', customerId)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (keyword) {
    query = query.or(
      `invoice_record_no.ilike.%${keyword}%,invoice_no.ilike.%${keyword}%,invoice_code.ilike.%${keyword}%,counterparty_name_snapshot.ilike.%${keyword}%,invoice_title.ilike.%${keyword}%,tax_number.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, 'issue_date', issueDateRange)
}

export async function fetchInvoiceList(params: InvoiceSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_invoice_summary')
    .select('*', { count: 'exact' })
    .order('issue_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyInvoiceFilters(query, params)
  return await responseHandle<Invoice[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportInvoiceList(
  params: InvoiceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_invoice_summary')
    .select('*')
    .order('issue_date', { ascending: false })
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyInvoiceFilters(query, params)
  return await responseHandle<Invoice[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchInvoiceableStatementList(params: InvoiceableSearchParams) {
  const { counterpartyId, direction, from = 0, includeFullyInvoiced, keyword, to = 9 } = params
  let query = supabase
    .from('tms_invoiceable_statement')
    .select('*', { count: 'exact' })
    .eq('direction', direction)
    .eq('counterparty_id', counterpartyId)
    .order('period_end', { ascending: true })
    .range(from, to)
  if (!includeFullyInvoiced) query = query.gt('uninvoiced_amount', 0)
  if (keyword) {
    query = query.or(`statement_no.ilike.%${keyword}%,counterparty_name.ilike.%${keyword}%`)
  }
  return await responseHandle<InvoiceableStatement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchInvoiceDetail(id: string) {
  const [invoiceResponse, linkResponse] = await Promise.all([
    responseHandle<Invoice>(
      () => supabase.from('tms_invoice_summary').select('*').eq('id', id).single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<InvoiceStatementLink[]>(
      () =>
        supabase
          .from('tms_invoice_detail_link')
          .select('*')
          .eq('invoice_id', id)
          .order('period_end', { ascending: true }),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: invoiceResponse.data
      ? { ...invoiceResponse.data, statementLinks: linkResponse.data ?? [] }
      : undefined
  }
}

export async function fetchActiveInvoiceByLegalNo(params: {
  direction: Api.Finance.InvoiceDirection
  invoiceNo: string
  excludeId?: string
}) {
  let query = supabase
    .from('tms_invoice_summary')
    .select(
      'id,invoice_record_no,direction,invoice_no,status,counterparty_name_snapshot,issue_date,total_amount'
    )
    .eq('direction', params.direction)
    .eq('invoice_no', params.invoiceNo.trim())
    .neq('status', 'voided')
    .limit(1)

  if (params.excludeId) query = query.neq('id', params.excludeId)

  return await responseHandle<InvoiceDuplicateRecord | null>(() => query.maybeSingle(), {
    ignoreCheck: true,
    showErrorMessage: false
  })
}

export async function saveInvoice(params: SaveInvoicePayload) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('save_tms_invoice', {
        p_invoice_id: params.id || null,
        p_direction: params.direction,
        p_invoice_type: params.invoiceType,
        p_customer_id: params.customerId || null,
        p_carrier_id: params.carrierId || null,
        p_invoice_title: params.invoiceTitle || null,
        p_tax_number: params.taxNumber || null,
        p_invoice_code: params.invoiceCode || null,
        p_invoice_no: params.invoiceNo || null,
        p_issue_date: params.issueDate,
        p_tax_rate: params.taxRate,
        p_amount_excluding_tax: params.amountExcludingTax,
        p_tax_amount: params.taxAmount,
        p_total_amount: params.totalAmount,
        p_attachments: params.attachments ?? [],
        p_remark: params.remark || null,
        p_statement_links: params.statementLinks,
        p_invoice_record_no: params.invoiceRecordNo || null
      }),
    { returnRawError: true }
  )

  if (result.error) {
    if (isInvoiceLegalNumberConflict(result.error)) throw new InvoiceLegalNumberConflictError()
    throw toError(result.error)
  }
  return result
}

export async function updateInvoiceStatus(params: InvoiceStatusPayload) {
  if (params.action === 'submit') {
    return await startWorkflow({
      businessType: 'tms_invoice',
      businessId: params.id,
      businessTitle: params.businessTitle || `发票 ${params.id}`
    })
  }
  if (params.action === 'approve' || params.action === 'reject') {
    return await actWorkflowByBusiness({
      businessType: 'tms_invoice',
      businessId: params.id,
      action: params.action,
      comment: params.remark
    })
  }
  return await responseHandle<string>(
    () =>
      supabase.rpc('update_tms_invoice_status', {
        p_invoice_id: params.id,
        p_action: params.action,
        p_remark: params.remark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteInvoice(id: string) {
  return await responseHandle(
    () => supabase.from('tms_invoice').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function analyzeInvoiceComplianceByAi(
  invoiceId: string
): Promise<QueryResult<Api.Finance.InvoiceComplianceAuditResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Finance.InvoiceComplianceAuditResponse>(
      'ai-invoice-compliance-auditor',
      { body: { invoiceId } }
    )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function analyzeInvoiceAttachmentByAi(
  params: Api.Finance.InvoiceOcrAnalyzeRequest
): Promise<QueryResult<Api.Finance.InvoiceOcrAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Finance.InvoiceOcrAnalyzeResponse>(
    'ai-invoice-ocr',
    {
      body: params
    }
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function resolveInvoiceCounterparty(artifactId: string) {
  return await responseHandle<Api.Finance.InvoiceCounterpartyResolution>(
    () =>
      supabase.rpc('resolve_tms_invoice_counterparty', {
        p_artifact_id: artifactId
      }),
    { ignoreCheck: true, showErrorMessage: false }
  )
}

export async function createInvoiceCounterpartyFromOcr(
  params: Api.Finance.CreateInvoiceCounterpartyFromOcrPayload
) {
  return await responseHandle<Api.Finance.CreateInvoiceCounterpartyFromOcrResponse>(
    () =>
      supabase.rpc('create_tms_invoice_counterparty_from_ocr', {
        p_artifact_id: params.artifactId,
        p_name: params.name,
        p_tax_no: params.taxNo || null,
        p_carrier_type: params.carrierType || null
      }),
    { showMessage: false, breakReturn: true }
  )
}

export async function reviewInvoiceOcrArtifact(
  params: Api.Finance.InvoiceOcrReviewRequest
): Promise<QueryResult<Api.Finance.InvoiceOcrReviewResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Finance.InvoiceOcrReviewResponse>(
    'ai-invoice-ocr',
    {
      body: params
    }
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}
