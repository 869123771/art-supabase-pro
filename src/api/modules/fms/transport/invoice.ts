import { createFriendlySupabaseError, normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type Invoice = Api.Fms.InvoiceRecord
type InvoiceSearchParams = Api.Fms.InvoiceSearchParams
type InvoiceableStatement = Api.Fms.InvoiceableStatement
type InvoiceableSearchParams = Api.Fms.InvoiceableStatementSearchParams
type SaveInvoicePayload = Api.Fms.SaveInvoicePayload
type InvoiceStatusPayload = Api.Fms.InvoiceStatusPayload & { businessTitle?: string }
type InvoiceStatementLink = Api.Fms.InvoiceStatementLinkRecord
type InvoiceDuplicateRecord = Api.Fms.InvoiceDuplicateRecord

interface SecureListPayload<TRecord> {
  records: TRecord[]
  total: number
  fieldAccess?: Api.Fms.InvoiceFieldAccessMap
}

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

const toInvoiceListRpcParams = (
  params: InvoiceSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_direction: params.direction || null,
    p_status: params.status || null,
    p_invoice_type: params.invoiceType || null,
    p_customer_id: params.customerId || null,
    p_carrier_id: params.carrierId || null,
    p_record_id: params.recordId || null,
    p_issue_date_start: params.issueDateRange?.[0] || null,
    p_issue_date_end: params.issueDateRange?.[1] || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchInvoiceList(params: InvoiceSearchParams) {
  const result = await responseHandle<SecureListPayload<Invoice>>(
    () => supabase.rpc('tms_list_invoices_secure', toInvoiceListRpcParams(params, 'list')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportInvoiceList(
  params: InvoiceSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureListPayload<Invoice>>(
    () => supabase.rpc('tms_list_invoices_secure', toInvoiceListRpcParams(params, 'export')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchInvoiceableStatementList(params: InvoiceableSearchParams) {
  const { counterpartyId, direction, from = 0, includeFullyInvoiced, keyword, to = 9 } = params
  const result = await responseHandle<SecureListPayload<InvoiceableStatement>>(
    () =>
      supabase.rpc('tms_list_invoiceable_statements_secure', {
        p_direction: direction,
        p_counterparty_id: counterpartyId,
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_keyword: String(keyword ?? '').trim() || null,
        p_include_fully_invoiced: Boolean(includeFullyInvoiced)
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

export async function fetchInvoiceDetail(id: string) {
  const [invoiceResponse, linkResponse] = await Promise.all([
    responseHandle<Invoice | null>(() => supabase.rpc('tms_get_invoice_secure', { p_id: id }), {
      showErrorMessage: true
    }),
    responseHandle<InvoiceStatementLink[]>(
      () => supabase.rpc('tms_list_invoice_statement_links_secure', { p_invoice_id: id }),
      { showErrorMessage: true }
    )
  ])
  return {
    data: invoiceResponse.data
      ? { ...invoiceResponse.data, statementLinks: linkResponse.data ?? [] }
      : undefined
  }
}

export async function fetchActiveInvoiceByLegalNo(params: {
  direction: Api.Fms.InvoiceDirection
  invoiceNo: string
  excludeId?: string
}) {
  return await responseHandle<InvoiceDuplicateRecord | null>(
    () =>
      supabase.rpc('tms_find_active_invoice_by_legal_no_secure', {
        p_direction: params.direction,
        p_invoice_no: params.invoiceNo.trim(),
        p_exclude_id: params.excludeId || null
      }),
    {
      showErrorMessage: false
    }
  )
}

export async function saveInvoice(params: SaveInvoicePayload) {
  const result = await responseHandle<string>(
    () =>
      supabase.rpc('save_tms_invoice_secure', {
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
      supabase.rpc('update_tms_invoice_status_secure', {
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
): Promise<QueryResult<Api.Fms.InvoiceComplianceAuditResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.InvoiceComplianceAuditResponse>(
    'ai-invoice-compliance-auditor',
    { body: { invoiceId } }
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function analyzeInvoiceAttachmentByAi(
  params: Api.Fms.InvoiceOcrAnalyzeRequest
): Promise<QueryResult<Api.Fms.InvoiceOcrAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.InvoiceOcrAnalyzeResponse>(
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
  return await responseHandle<Api.Fms.InvoiceCounterpartyResolution>(
    () =>
      supabase.rpc('resolve_tms_invoice_counterparty', {
        p_artifact_id: artifactId
      }),
    { ignoreCheck: true, showErrorMessage: false }
  )
}

export async function createInvoiceCounterpartyFromOcr(
  params: Api.Fms.CreateInvoiceCounterpartyFromOcrPayload
) {
  return await responseHandle<Api.Fms.CreateInvoiceCounterpartyFromOcrResponse>(
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
  params: Api.Fms.InvoiceOcrReviewRequest
): Promise<QueryResult<Api.Fms.InvoiceOcrReviewResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.InvoiceOcrReviewResponse>(
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
