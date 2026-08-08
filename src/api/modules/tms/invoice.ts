import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type Invoice = Api.Tms.Finance.InvoiceRecord
type InvoiceSearchParams = Api.Tms.Finance.InvoiceSearchParams
type InvoiceableStatement = Api.Tms.Finance.InvoiceableStatement
type InvoiceableSearchParams = Api.Tms.Finance.InvoiceableStatementSearchParams
type SaveInvoicePayload = Api.Tms.Finance.SaveInvoicePayload
type InvoiceStatusPayload = Api.Tms.Finance.InvoiceStatusPayload & { businessTitle?: string }
type InvoiceStatementLink = Api.Tms.Finance.InvoiceStatementLinkRecord

const { supabase, responseHandle } = useSupabase()

function applyInvoiceFilters(
  query: SupabaseQueryLike,
  params: InvoiceSearchParams
): SupabaseQueryLike {
  const { carrierId, customerId, direction, invoiceType, issueDateRange, keyword, status } = params
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
    .range(from, to) as unknown as SupabaseQueryLike
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
    .limit(maxRows) as unknown as SupabaseQueryLike
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
    .range(from, to) as unknown as SupabaseQueryLike
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

export async function saveInvoice(params: SaveInvoicePayload) {
  return await responseHandle<string>(
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
        p_statement_links: params.statementLinks
      }),
    { showMessage: true, breakReturn: true }
  )
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
): Promise<QueryResult<Api.Tms.Finance.InvoiceComplianceAuditResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.InvoiceComplianceAuditResponse>(
      'ai-invoice-compliance-auditor',
      { body: { invoiceId } }
    )

  return {
    data: data ?? null,
    error: await normalizeFunctionInvokeError(error)
  }
}

export async function analyzeInvoiceAttachmentByAi(
  params: Api.Tms.Finance.InvoiceOcrAnalyzeRequest
): Promise<QueryResult<Api.Tms.Finance.InvoiceOcrAnalyzeResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.InvoiceOcrAnalyzeResponse>('ai-invoice-ocr', {
      body: params
    })

  return {
    data: data ?? null,
    error: await normalizeFunctionInvokeError(error)
  }
}

export async function resolveInvoiceCounterparty(artifactId: string) {
  return await responseHandle<Api.Tms.Finance.InvoiceCounterpartyResolution>(
    () =>
      supabase.rpc('resolve_tms_invoice_counterparty', {
        p_artifact_id: artifactId
      }),
    { ignoreCheck: true, showErrorMessage: false }
  )
}

export async function createInvoiceCounterpartyFromOcr(
  params: Api.Tms.Finance.CreateInvoiceCounterpartyFromOcrPayload
) {
  return await responseHandle<Api.Tms.Finance.CreateInvoiceCounterpartyFromOcrResponse>(
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
  params: Api.Tms.Finance.InvoiceOcrReviewRequest
): Promise<QueryResult<Api.Tms.Finance.InvoiceOcrReviewResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Finance.InvoiceOcrReviewResponse>(
    'ai-invoice-ocr',
    {
      body: params
    }
  )

  return {
    data: data ?? null,
    error: await normalizeFunctionInvokeError(error)
  }
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
