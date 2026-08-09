import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { startWorkflow } from '@/api/workflow'

type Expense = Api.Tms.Finance.InTransitExpenseRecord
type ExpenseSearch = Api.Tms.Finance.InTransitExpenseSearchParams
type WaybillOption = Api.Tms.Finance.InTransitWaybillOption
type WaybillSearch = Api.Tms.Finance.InTransitWaybillOptionSearchParams
type Reimbursement = Api.Tms.Finance.ExpenseReimbursementRecord
type ReimbursementSearch = Api.Tms.Finance.ExpenseReimbursementSearchParams
type OcrRun = Api.Tms.Finance.InTransitExpenseOcrRunRecord
type OcrRunSearch = Api.Tms.Finance.InTransitExpenseOcrRunSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const WAYBILL_OPTION_SELECT = `
  id,
  waybill_no,
  status,
  order_id,
  driver_id,
  carrier_id,
  origin_city,
  destination_city,
  driver:tms_driver!tms_waybill_driver_id_fkey(id, driver_name, phone),
  order:tms_order!tms_waybill_order_id_fkey(
    id,
    order_no,
    dispatch_plate_no,
    dispatch_driver_name,
    dispatch_driver_phone,
    origin_station,
    destination_station
  )
`

function applyExpenseFilters(query: SupabaseQueryLike, params: ExpenseSearch): SupabaseQueryLike {
  const {
    recordId,
    orderId,
    expenseType,
    keyword,
    paymentStatus,
    reimbursementStatus,
    reportStatus,
    occurredAtRange
  } = params
  if (recordId) query = query.eq('id', recordId)
  if (orderId) query = query.eq('order_id', orderId)
  if (expenseType) query = query.eq('expense_type', expenseType)
  if (reportStatus) query = query.eq('report_status', reportStatus)
  if (reimbursementStatus) query = query.eq('reimbursement_status', reimbursementStatus)
  if (paymentStatus) query = query.eq('payment_status', paymentStatus)
  if (keyword) {
    const value = keyword.trim()
    query = query.or(
      `expense_no.ilike.%${value}%,waybill_no_snapshot.ilike.%${value}%,order_no_snapshot.ilike.%${value}%,plate_no_snapshot.ilike.%${value}%,driver_name_snapshot.ilike.%${value}%,provider_name.ilike.%${value}%,invoice_no.ilike.%${value}%`
    )
  }
  return applyDateRange(query, 'occurred_at', occurredAtRange, {
    startOfDay: true,
    endOfDay: true
  })
}

function applyReimbursementFilters(
  query: SupabaseQueryLike,
  params: ReimbursementSearch
): SupabaseQueryLike {
  const { keyword, paymentMethod, plannedPaymentDateRange, status } = params
  if (status) query = query.eq('status', status)
  if (paymentMethod) query = query.eq('payment_method', paymentMethod)
  if (keyword) {
    const value = keyword.trim()
    query = query.or(
      `reimbursement_no.ilike.%${value}%,applicant_name_snapshot.ilike.%${value}%,payee_name.ilike.%${value}%,waybill_nos.ilike.%${value}%,payment_no.ilike.%${value}%,payment_reference.ilike.%${value}%`
    )
  }
  return applyDateRange(query, 'planned_payment_date', plannedPaymentDateRange)
}

function createExpensePayload(params: Expense) {
  return {
    expenseNo: params.expenseNo?.trim() || '',
    waybillId: params.waybillId,
    expenseType: params.expenseType,
    amount: Number(params.amount),
    occurredAt: params.occurredAt,
    quantity:
      params.quantity === null || params.quantity === undefined ? null : Number(params.quantity),
    unitPrice:
      params.unitPrice === null || params.unitPrice === undefined ? null : Number(params.unitPrice),
    providerName: params.providerName?.trim() || null,
    payeeName: params.payeeName?.trim() || null,
    paymentChannel: params.paymentChannel?.trim() || null,
    invoiceNo: params.invoiceNo?.trim() || null,
    meterNo: params.meterNo?.trim() || null,
    expenseLocation: params.expenseLocation?.trim() || null,
    expenseRegion: params.expenseRegion?.trim() || null,
    expenseRegionAdcode: params.expenseRegionAdcode?.trim() || null,
    expenseLongitude:
      params.expenseLongitude === null || params.expenseLongitude === undefined
        ? null
        : Number(params.expenseLongitude),
    expenseLatitude:
      params.expenseLatitude === null || params.expenseLatitude === undefined
        ? null
        : Number(params.expenseLatitude),
    expenseCoordinateSystem: params.expenseCoordinateSystem?.trim() || null,
    expenseCoordinateSource: params.expenseCoordinateSource?.trim() || null,
    expenseCoordinateStatus: params.expenseCoordinateStatus?.trim() || 'pending',
    expenseGeocodeProvider: params.expenseGeocodeProvider?.trim() || null,
    expenseGeocodedAt: params.expenseGeocodedAt || null,
    description: params.description?.trim() || null,
    attachments: [...(params.attachments ?? [])],
    latestOcrRunId: params.latestOcrRunId || null,
    ocrArtifactId: params.ocrArtifactId || null,
    ocrStatus: params.ocrStatus ?? 'not_started'
  }
}

export async function fetchInTransitExpenseList(params: ExpenseSearch) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_in_transit_expense_summary')
    .select('*', { count: 'exact' })
    .order('occurred_at', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyExpenseFilters(query, params)
  return await responseHandle<Expense[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchInTransitExpenseOverview() {
  const result = await responseHandle<Api.Tms.Finance.InTransitExpenseOverview>(
    () => supabase.from('tms_in_transit_expense_overview').select('*').maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return {
    data: result.data ?? {
      totalCount: 0,
      pendingReviewCount: 0,
      approvedUnconvertedCount: 0,
      pendingPaymentAmount: 0,
      paidAmount: 0
    }
  }
}

export async function fetchInTransitWaybillOptions(params: WaybillSearch = {}) {
  const { from = 0, to = 99, keyword, orderId } = params
  let query = supabase
    .from('tms_waybill')
    .select(WAYBILL_OPTION_SELECT, { count: 'exact' })
    .neq('status', 'cancelled')
    .order('create_time', { ascending: false })
    .range(from, to)
  if (orderId) query = query.eq('order_id', orderId)
  const result = await responseHandle<WaybillOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const source = result.data ?? []
  const normalizedKeyword = keyword?.trim().toLocaleLowerCase('zh-CN')
  const filtered = normalizedKeyword
    ? source.filter((item) =>
        [
          item.waybillNo,
          item.order?.orderNo,
          item.order?.dispatchPlateNo,
          item.driver?.driverName,
          item.order?.dispatchDriverName,
          item.originCity,
          item.destinationCity
        ].some((value) =>
          String(value ?? '')
            .toLocaleLowerCase('zh-CN')
            .includes(normalizedKeyword)
        )
      )
    : source
  return {
    data: filtered,
    total: normalizedKeyword ? filtered.length : (result.total ?? filtered.length)
  }
}

export async function addInTransitExpense(params: Expense) {
  return await responseHandle<Expense>(
    () =>
      supabase
        .from('tms_in_transit_expense')
        .insert(keysToSnakeDeep(createExpensePayload(params)))
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, message: '在途费用申报已保存' }
  )
}

export async function editInTransitExpense(params: Expense) {
  if (!params.id) throw new Error('缺少在途费用 ID')
  return await responseHandle<Expense>(
    () =>
      supabase
        .from('tms_in_transit_expense')
        .update(keysToSnakeDeep(createExpensePayload(params)), { count: 'exact' })
        .eq('id', params.id)
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true, message: '在途费用申报已更新' }
  )
}

export async function deleteInTransitExpense(id: string) {
  return await responseHandle(
    () => supabase.from('tms_in_transit_expense').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function submitInTransitExpense(row: Expense) {
  if (!row.id) throw new Error('缺少在途费用 ID')
  return await startWorkflow({
    businessType: 'tms_in_transit_expense',
    businessId: row.id,
    businessTitle: `在途费用 ${row.expenseNo || row.id.slice(0, 8)} · ${row.waybillNoSnapshot || ''}`
  })
}

export async function fetchExpenseReimbursementList(params: ReimbursementSearch) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_expense_reimbursement_summary')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyReimbursementFilters(query, params)
  return await responseHandle<Reimbursement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchExpenseReimbursementDetail(id: string) {
  const [reimbursement, items] = await Promise.all([
    responseHandle<Reimbursement>(
      () => supabase.from('tms_expense_reimbursement_summary').select('*').eq('id', id).single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<Api.Tms.Finance.ExpenseReimbursementItem[]>(
      () =>
        supabase
          .from('tms_expense_reimbursement_item')
          .select('*')
          .eq('reimbursement_id', id)
          .order('occurred_at_snapshot'),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: reimbursement.data ? { ...reimbursement.data, items: items.data ?? [] } : undefined
  }
}

export async function createExpenseReimbursement(
  params: Api.Tms.Finance.CreateExpenseReimbursementPayload
) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_tms_expense_reimbursement', {
        p_expense_ids: params.expenseIds,
        p_payee_name: params.payeeName,
        p_payee_bank: params.payeeBank || null,
        p_payee_account: params.payeeAccount || null,
        p_planned_payment_date: params.plannedPaymentDate,
        p_payment_method: params.paymentMethod,
        p_basis_urls: params.basisUrls ?? [],
        p_remark: params.remark || null,
        p_reimbursement_no: params.reimbursementNo || null
      }),
    { showMessage: true, breakReturn: true, message: '费用已转换为报销单' }
  )
}

export async function submitExpenseReimbursement(row: Reimbursement) {
  return await startWorkflow({
    businessType: 'tms_expense_reimbursement',
    businessId: row.id,
    businessTitle: `费用报销 ${row.reimbursementNo} · ${row.payeeName}`,
    context: {
      amount: Number(row.totalAmount),
      reimbursementNo: row.reimbursementNo,
      paymentMethod: row.paymentMethod,
      plannedPaymentDate: row.plannedPaymentDate,
      itemCount: row.itemCount,
      waybillCount: row.waybillCount
    }
  })
}

export async function deleteExpenseReimbursement(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_tms_expense_reimbursement', { p_reimbursement_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function executeExpenseReimbursement(
  params: Api.Tms.Finance.ExecuteExpenseReimbursementPayload
) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('execute_tms_expense_reimbursement', {
        p_reimbursement_id: params.reimbursementId,
        p_payment_date: params.paymentDate,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_remark: params.remark || null,
        p_payment_no: params.paymentNo || null
      }),
    { showMessage: true, breakReturn: true, message: '付款已登记，关联费用已逐笔核销' }
  )
}

export async function fetchInTransitExpenseOcrEnabled(): Promise<boolean> {
  const { data, error } = await supabase
    .rpc('get_effective_ai_feature_configs')
    .eq('feature', 'in_transit_expense_ocr')
  if (error) return true
  const row = Array.isArray(data) ? data[0] : undefined
  return row ? Boolean(row.enabled) : true
}

export async function analyzeInTransitExpenseByAi(
  imageUrls: string[]
): Promise<QueryResult<Api.Tms.Finance.InTransitExpenseOcrAnalyzeResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.InTransitExpenseOcrAnalyzeResponse>(
      'ai-in-transit-expense-ocr',
      { body: { action: 'analyze', imageUrls } }
    )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

export async function reviewInTransitExpenseOcrArtifact(params: {
  artifactId: string
  entityId: string
  finalPayload: Record<string, unknown>
}) {
  return await supabase.functions.invoke('ai-in-transit-expense-ocr', {
    body: {
      action: 'review',
      artifactId: params.artifactId,
      entityId: params.entityId,
      outcome: 'applied',
      finalPayload: params.finalPayload
    }
  })
}

export async function fetchInTransitExpenseOcrRunList(params: OcrRunSearch) {
  const { from = 0, to = 9, keyword, status } = params
  let query = supabase
    .from('ai_run')
    .select('*', { count: 'exact' })
    .eq('feature', 'in_transit_expense_ocr')
    .order('started_at', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  if (status) query = query.eq('status', status)
  if (keyword) {
    const value = keyword.trim()
    query = query.or(
      `model.ilike.%${value}%,error_code.ilike.%${value}%,error_message.ilike.%${value}%,create_by.ilike.%${value}%`
    )
  }
  query = applyDateRange(query, 'started_at', params.createTimeRange, {
    startOfDay: true,
    endOfDay: true
  })
  return await responseHandle<OcrRun[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
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
