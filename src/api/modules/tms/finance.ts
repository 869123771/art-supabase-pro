import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'
import TreeUtils from '@/utils/tree'

type WaybillCost = Api.Tms.Finance.WaybillCostRecord
type WaybillCostSearchParams = Api.Tms.Finance.WaybillCostSearchParams
type WaybillOption = Api.Tms.Finance.WaybillOption
type WaybillOptionSearchParams = Api.Tms.Finance.WaybillOptionSearchParams
type CostReviewPayload = Api.Tms.Finance.CostReviewPayload
type ExpenseItem = Api.Tms.Finance.ExpenseItem
type ExpenseItemSearchParams = Api.Tms.Finance.ExpenseItemSearchParams
type Reimbursement = Api.Tms.Finance.ExpenseReimbursementRecord
type ReimbursementSearch = Api.Tms.Finance.ExpenseReimbursementSearchParams
type OcrRun = Api.Tms.Finance.WaybillExpenseOcrRunRecord
type OcrRunSearch = Api.Tms.Finance.WaybillExpenseOcrRunSearchParams
type WaybillProfit = Api.Tms.Finance.WaybillProfitRecord
type WaybillProfitSearchParams = Api.Tms.Finance.WaybillProfitSearchParams
type FinanceWorkbenchStats = Api.Tms.Finance.FinanceWorkbenchStats

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()
const expenseItemTreeUtils = new TreeUtils({
  idKey: 'id',
  parentKey: 'parentId',
  childrenKey: 'children'
})

const WAYBILL_COST_SELECT = `
  *,
  expense_item:tms_expense_item!tms_waybill_cost_expense_item_id_fkey(*),
  reimbursement:tms_expense_reimbursement!tms_waybill_cost_reimbursement_id_fkey(
    id,
    reimbursement_no,
    status
  ),
  expense_payment:tms_expense_payment!tms_waybill_cost_expense_payment_id_fkey(
    id,
    payment_no,
    payment_date,
    bank_reference
  ),
  waybill:tms_waybill!tms_waybill_cost_waybill_id_fkey(
    id,
    waybill_no,
    status,
    order_id,
    carrier_id,
    driver_id,
    origin_city,
    destination_city,
    carrier:tms_carrier!tms_waybill_carrier_id_fkey(id, company_name),
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
  )
`

const WAYBILL_OPTION_SELECT = `
  id,
  waybill_no,
  status,
  order_id,
  carrier_id,
  driver_id,
  origin_city,
  destination_city,
  completed_at,
  carrier:tms_carrier!tms_waybill_carrier_id_fkey(id, company_name),
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

const fetchMatchingWaybillIds = async (params: {
  keyword?: string
  orderId?: string
}): Promise<string[]> => {
  const { keyword, orderId } = params
  if (!keyword && !orderId) return []
  let query = supabase.from('tms_waybill').select('id').limit(500)
  if (orderId) query = query.eq('order_id', orderId)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%`
    )
  }
  const { data } = await responseHandle<Array<{ id: string }>>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return (data ?? []).map((item) => item.id)
}

const applyCostFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: WaybillCostSearchParams,
  waybillIds: string[]
): TQuery => {
  const {
    auditStatus,
    costType,
    expenseItemId,
    keyword,
    occurredOnRange,
    recordId,
    settlementStatus
  } = params
  if (recordId) query = query.eq('id', recordId)
  if (auditStatus) query = query.eq('audit_status', auditStatus)
  if (costType) query = query.eq('cost_type', costType)
  if (expenseItemId) query = query.eq('expense_item_id', expenseItemId)
  if (settlementStatus) query = query.eq('settlement_status', settlementStatus)
  if (params.orderId) {
    query = waybillIds.length
      ? query.in('waybill_id', waybillIds)
      : query.eq('waybill_id', '00000000-0000-0000-0000-000000000000')
  }
  if (keyword) {
    const filters = [
      `cost_no.ilike.%${keyword}%`,
      `payee_name.ilike.%${keyword}%`,
      `provider_name.ilike.%${keyword}%`,
      `invoice_no.ilike.%${keyword}%`,
      `waybill_no_snapshot.ilike.%${keyword}%`,
      `order_no_snapshot.ilike.%${keyword}%`,
      `plate_no_snapshot.ilike.%${keyword}%`,
      `driver_name_snapshot.ilike.%${keyword}%`,
      `remark.ilike.%${keyword}%`,
      `reporter_name_snapshot.ilike.%${keyword}%`,
      `reporter_department_snapshot.ilike.%${keyword}%`
    ]
    if (waybillIds.length) filters.push(`waybill_id.in.(${waybillIds.join(',')})`)
    query = query.or(filters.join(','))
  }
  return applyDateRange(query, 'occurred_on', occurredOnRange)
}

const createCostWritePayload = (params: WaybillCost) => ({
  costNo: params.costNo?.trim() || '',
  waybillId: params.waybillId,
  expenseItemId: params.expenseItemId,
  amount: Number(params.amount),
  occurredOn: params.occurredOn,
  quantity:
    params.quantity === null || params.quantity === undefined ? null : Number(params.quantity),
  unitPrice:
    params.unitPrice === null || params.unitPrice === undefined ? null : Number(params.unitPrice),
  providerName: params.providerName?.trim() || null,
  payeeName: params.payeeName || null,
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
  carrierId: params.carrierId || null,
  driverId: params.driverId || null,
  remark: params.remark || null,
  attachments: params.attachments ?? [],
  reporterUserId: params.reporterUserId || null,
  latestOcrRunId: params.latestOcrRunId || null,
  ocrArtifactId: params.ocrArtifactId || null,
  ocrStatus: params.ocrStatus ?? 'not_started'
})

const createExpenseItemWritePayload = (params: ExpenseItem) => ({
  parentId: params.parentId || null,
  itemCode: params.itemCode.trim(),
  itemName: params.itemName.trim(),
  businessCategory: params.isSelectable ? params.businessCategory || null : null,
  isSelectable: Boolean(params.isSelectable),
  reimbursementAllowed: params.isSelectable && Boolean(params.reimbursementAllowed),
  isEnabled: Boolean(params.isEnabled),
  sort: Number(params.sort || 0),
  remark: params.remark?.trim() || null
})

export async function fetchExpenseItemList(params: ExpenseItemSearchParams = {}) {
  const { from = 0, to = 999, keyword, isEnabled, parentId } = params
  let query = supabase
    .from('tms_expense_item')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('item_code', { ascending: true })
    .range(from, to)
  if (keyword) {
    const value = keyword.trim()
    query = query.or(
      `item_code.ilike.%${value}%,item_name.ilike.%${value}%,remark.ilike.%${value}%`
    )
  }
  if (typeof isEnabled === 'boolean') query = query.eq('is_enabled', isEnabled)
  if (parentId === null) query = query.is('parent_id', null)
  else if (parentId) query = query.eq('parent_id', parentId)
  return await responseHandle<ExpenseItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchExpenseItemTree(params: ExpenseItemSearchParams = {}) {
  const result = await fetchExpenseItemList({ ...params, from: 0, to: 9999 })
  return {
    ...result,
    data: expenseItemTreeUtils.listToTree(result.data ?? [], (a, b) => {
      const left = a as ExpenseItem
      const right = b as ExpenseItem
      return left.sort - right.sort || left.itemCode.localeCompare(right.itemCode, 'zh-CN')
    }) as ExpenseItem[]
  }
}

export async function addExpenseItem(params: ExpenseItem) {
  return await responseHandle<ExpenseItem>(
    () =>
      supabase
        .from('tms_expense_item')
        .insert(keysToSnakeDeep(createExpenseItemWritePayload(params)))
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, message: '费用项目已创建' }
  )
}

export async function editExpenseItem(params: ExpenseItem) {
  if (!params.id) throw new Error('缺少费用项目 ID')
  return await responseHandle<ExpenseItem>(
    () =>
      supabase
        .from('tms_expense_item')
        .update(keysToSnakeDeep(createExpenseItemWritePayload(params)), { count: 'exact' })
        .eq('id', params.id)
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true, message: '费用项目已更新' }
  )
}

export async function deleteExpenseItem(id: string) {
  return await responseHandle(
    () => supabase.from('tms_expense_item').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true, message: '费用项目已删除' }
  )
}

export async function fetchWaybillCostOverview() {
  const result = await responseHandle<Api.Tms.Finance.WaybillCostOverview>(
    () => supabase.from('tms_waybill_cost_overview').select('*').maybeSingle(),
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

export async function fetchWaybillCostList(params: WaybillCostSearchParams) {
  const { from = 0, to = 9, keyword } = params
  const waybillIds = await fetchMatchingWaybillIds({ keyword, orderId: params.orderId })
  let query = supabase
    .from('tms_waybill_cost')
    .select(WAYBILL_COST_SELECT, { count: 'exact' })
    .order('occurred_on', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyCostFilters(query, params, waybillIds)
  return await responseHandle<WaybillCost[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportWaybillCostList(
  params: WaybillCostSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000, keyword } = params
  const waybillIds = await fetchMatchingWaybillIds({ keyword, orderId: params.orderId })
  let query = supabase
    .from('tms_waybill_cost')
    .select(WAYBILL_COST_SELECT)
    .order('occurred_on', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyCostFilters(query, params, waybillIds)
  return await responseHandle<WaybillCost[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFinanceWaybillOptions(params: WaybillOptionSearchParams = {}) {
  const { from = 0, to = 999, keyword, orderId } = params
  let query = supabase
    .from('tms_waybill')
    .select(WAYBILL_OPTION_SELECT, { count: 'exact' })
    .neq('status', 'cancelled')
    .order('create_time', { ascending: false })
    .range(from, to)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%`
    )
  }
  if (orderId) query = query.eq('order_id', orderId)
  return await responseHandle<WaybillOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addWaybillCost(params: WaybillCost) {
  return await responseHandle<WaybillCost>(
    () =>
      supabase
        .from('tms_waybill_cost')
        .insert(keysToSnakeDeep(createCostWritePayload(params)))
        .select(WAYBILL_COST_SELECT)
        .single(),
    { showMessage: true, breakReturn: true }
  )
}

export async function editWaybillCost(params: WaybillCost) {
  if (!params.id) throw new Error('缺少费用ID')
  return await responseHandle<WaybillCost>(
    () =>
      supabase
        .from('tms_waybill_cost')
        .update(keysToSnakeDeep(createCostWritePayload(params)), { count: 'exact' })
        .eq('id', params.id)
        .select(WAYBILL_COST_SELECT)
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteWaybillCost(id: string) {
  return await responseHandle(
    () => supabase.from('tms_waybill_cost').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function submitWaybillCost(id: string) {
  return await startWorkflow({
    businessType: 'tms_waybill_cost',
    businessId: id,
    businessTitle: `运单费用审批 · ${id.slice(0, 8)}`
  })
}

export async function reviewWaybillCost(params: CostReviewPayload) {
  return await actWorkflowByBusiness({
    businessType: 'tms_waybill_cost',
    businessId: params.id,
    action: params.auditStatus === 'approved' ? 'approve' : 'reject',
    comment: params.reviewRemark || null
  })
}

export async function voidWaybillCost(id: string, reviewRemark?: string | null) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_waybill_cost')
        .update(keysToSnakeDeep({ auditStatus: 'voided', reviewRemark: reviewRemark || null }), {
          count: 'exact'
        })
        .eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function analyzeWaybillCostByAi(
  costId: string
): Promise<QueryResult<Api.Tms.Finance.WaybillCostAuditResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Finance.WaybillCostAuditResponse>(
    'ai-waybill-cost-auditor',
    { body: { costId } }
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

const applyReimbursementFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: ReimbursementSearch
): TQuery => {
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

export async function fetchExpenseReimbursementList(params: ReimbursementSearch) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_expense_reimbursement_summary')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
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
          .order('occurred_on_snapshot'),
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
        p_cost_ids: params.costIds,
        p_payee_name: params.payeeName,
        p_payee_bank: params.payeeBank || null,
        p_payee_account: params.payeeAccount || null,
        p_planned_payment_date: params.plannedPaymentDate,
        p_payment_method: params.paymentMethod,
        p_basis_urls: params.basisUrls ?? [],
        p_remark: params.remark || null,
        p_reimbursement_no: params.reimbursementNo || null
      }),
    { showMessage: true, breakReturn: true, message: '运单费用已转换为报销单' }
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

export async function fetchWaybillExpenseOcrEnabled(): Promise<boolean> {
  const { data, error } = await supabase
    .rpc('get_effective_ai_feature_configs')
    .eq('feature', 'waybill_expense_ocr')
  if (error) return true
  const row = Array.isArray(data) ? data[0] : undefined
  return row ? Boolean(row.enabled) : true
}

export async function analyzeWaybillExpenseByAi(
  imageUrls: string[]
): Promise<QueryResult<Api.Tms.Finance.WaybillExpenseOcrAnalyzeResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.WaybillExpenseOcrAnalyzeResponse>(
      'ai-waybill-expense-ocr',
      { body: { action: 'analyze', imageUrls } }
    )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}

export async function reviewWaybillExpenseOcrArtifact(params: {
  artifactId: string
  entityId: string
  finalPayload: Record<string, unknown>
}) {
  return await supabase.functions.invoke('ai-waybill-expense-ocr', {
    body: {
      action: 'review',
      artifactId: params.artifactId,
      entityId: params.entityId,
      outcome: 'applied',
      finalPayload: params.finalPayload
    }
  })
}

export async function fetchWaybillExpenseOcrRunList(params: OcrRunSearch) {
  const { from = 0, to = 9, keyword, status } = params
  let query = supabase
    .from('ai_run')
    .select('*', { count: 'exact' })
    .eq('feature', 'waybill_expense_ocr')
    .order('started_at', { ascending: false })
    .range(from, to)
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

const applyProfitFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: WaybillProfitSearchParams
): TQuery => {
  const { keyword, waybillStatus, completedAtRange } = params
  if (waybillStatus) query = query.eq('waybill_status', waybillStatus)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,customer_name.ilike.%${keyword}%,carrier_name.ilike.%${keyword}%,plate_no.ilike.%${keyword}%,driver_name.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, 'completed_at', completedAtRange, {
    startOfDay: true,
    endOfDay: true
  })
}

export async function fetchWaybillProfitList(params: WaybillProfitSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_waybill_profit')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyProfitFilters(query, params)
  return await responseHandle<WaybillProfit[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function analyzeWaybillProfitByAi(): Promise<
  QueryResult<Api.Tms.Finance.WaybillProfitAnalysisResponse>
> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.WaybillProfitAnalysisResponse>(
      'ai-waybill-profit-analyst'
    )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function analyzeReceivablesCollectionByAi(): Promise<
  QueryResult<Api.Tms.Finance.ReceivablesCollectionResponse>
> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.ReceivablesCollectionResponse>(
      'ai-receivables-collection-advisor'
    )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function exportWaybillProfitList(
  params: WaybillProfitSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_waybill_profit')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyProfitFilters(query, params)
  return await responseHandle<WaybillProfit[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFinanceWorkbench() {
  const [workbenchResponse, exceptionResponse] = await Promise.all([
    responseHandle<FinanceWorkbenchStats>(
      () => supabase.from('tms_finance_workbench').select('*').single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<Partial<FinanceWorkbenchStats>>(
      () => supabase.from('tms_finance_exception_summary').select('*').single(),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: workbenchResponse.data
      ? { ...workbenchResponse.data, ...(exceptionResponse.data ?? {}) }
      : undefined
  }
}
