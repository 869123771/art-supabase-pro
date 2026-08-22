import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'
import TreeUtils from '@/utils/tree'

type WaybillCost = Api.Fms.WaybillCostRecord
type WaybillCostSearchParams = Api.Fms.WaybillCostSearchParams
type WaybillOption = Api.Fms.WaybillOption
type WaybillOptionSearchParams = Api.Fms.WaybillOptionSearchParams
type CostReviewPayload = Api.Fms.CostReviewPayload
type ExpenseItem = Api.Fms.ExpenseItem
type ExpenseItemSearchParams = Api.Fms.ExpenseItemSearchParams
type Reimbursement = Api.Fms.ExpenseReimbursementRecord
type ReimbursementSearch = Api.Fms.ExpenseReimbursementSearchParams
type OcrRun = Api.Fms.WaybillExpenseOcrRunRecord
type OcrRunSearch = Api.Fms.WaybillExpenseOcrRunSearchParams
type WaybillProfit = Api.Fms.WaybillProfitRecord
type WaybillProfitSearchParams = Api.Fms.WaybillProfitSearchParams
type FinanceWorkbenchStats = Api.Fms.FinanceWorkbenchStats

interface SecureListPayload<TRecord, TAccess extends Record<string, string> = never> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()
const expenseItemTreeUtils = new TreeUtils({
  idKey: 'id',
  parentKey: 'parentId',
  childrenKey: 'children'
})

const toCostListRpcParams = (
  params: WaybillCostSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_record_id: params.recordId || null,
    p_order_id: params.orderId || null,
    p_waybill_id: params.waybillId || null,
    p_carrier_id: params.carrierId || null,
    p_expense_item_id: params.expenseItemId || null,
    p_cost_type: params.costType || null,
    p_audit_status: params.auditStatus || null,
    p_settlement_status: params.settlementStatus || null,
    p_occurred_on_start: params.occurredOnRange?.[0] || null,
    p_occurred_on_end: params.occurredOnRange?.[1] || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
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
  const { from = 0, to = 999, keyword, tenantId, isEnabled, parentId } = params
  let query = supabase
    .from('tms_expense_item')
    .select('*, tenant:sys_tenant!tms_expense_item_tenant_id_fkey(id, tenant_code, tenant_name)', {
      count: 'exact'
    })
    .order('sort', { ascending: true })
    .order('item_code', { ascending: true })
    .range(from, to)
  if (keyword) {
    const value = keyword.trim()
    query = query.or(
      `item_code.ilike.%${value}%,item_name.ilike.%${value}%,remark.ilike.%${value}%`
    )
  }
  if (tenantId) query = query.eq('tenant_id', tenantId)
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
  const result = await responseHandle<Api.Fms.WaybillCostOverview>(
    () => supabase.rpc('tms_get_waybill_cost_overview_secure'),
    { showErrorMessage: true }
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
  const result = await responseHandle<
    SecureListPayload<WaybillCost, Api.Fms.WaybillCostFieldAccessMap>
  >(() => supabase.rpc('tms_list_waybill_costs_secure', toCostListRpcParams(params, 'list')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchWaybillCostDetail(id: string) {
  return await responseHandle<WaybillCost | null>(
    () => supabase.rpc('tms_get_waybill_cost_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function exportWaybillCostList(
  params: WaybillCostSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<WaybillCost, Api.Fms.WaybillCostFieldAccessMap>
  >(() => supabase.rpc('tms_list_waybill_costs_secure', toCostListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFinanceWaybillOptions(params: WaybillOptionSearchParams = {}) {
  const result = await responseHandle<SecureListPayload<WaybillOption>>(
    () =>
      supabase.rpc('tms_list_waybill_cost_options_secure', {
        p_from: Math.max(params.from ?? 0, 0),
        p_to: Math.max(params.to ?? 999, params.from ?? 0),
        p_keyword: String(params.keyword ?? '').trim() || null,
        p_order_id: params.orderId || null
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

export async function addWaybillCost(params: WaybillCost) {
  return await responseHandle<WaybillCost>(
    () =>
      supabase.rpc('tms_save_waybill_cost_secure', {
        p_id: null,
        p_payload: keysToSnakeDeep(createCostWritePayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function editWaybillCost(params: WaybillCost) {
  if (!params.id) throw new Error('缺少费用ID')
  return await responseHandle<WaybillCost>(
    () =>
      supabase.rpc('tms_save_waybill_cost_secure', {
        p_id: params.id,
        p_payload: keysToSnakeDeep(createCostWritePayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteWaybillCost(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('tms_delete_waybill_cost_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
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
  return await responseHandle<string>(
    () =>
      supabase.rpc('tms_void_waybill_cost_secure', {
        p_id: id,
        p_reason: reviewRemark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function analyzeWaybillCostByAi(
  costId: string
): Promise<QueryResult<Api.Fms.WaybillCostAuditResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.WaybillCostAuditResponse>(
    'ai-waybill-cost-auditor',
    { body: { costId } }
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function fetchExpenseReimbursementList(params: ReimbursementSearch) {
  const { from = 0, to = 9 } = params
  const result = await responseHandle<
    SecureListPayload<Reimbursement, Api.Fms.ExpenseReimbursementFieldAccessMap>
  >(
    () =>
      supabase.rpc('tms_list_expense_reimbursements_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_keyword: params.keyword?.trim() || null,
        p_status: params.status || null,
        p_payment_method: params.paymentMethod || null,
        p_planned_payment_date_start: params.plannedPaymentDateRange?.[0] || null,
        p_planned_payment_date_end: params.plannedPaymentDateRange?.[1] || null,
        p_ids: null
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchExpenseReimbursementDetail(id: string) {
  return await responseHandle<Reimbursement | null>(
    () => supabase.rpc('tms_get_expense_reimbursement_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function createExpenseReimbursement(
  params: Api.Fms.CreateExpenseReimbursementPayload
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
    businessTitle: `费用报销 ${row.reimbursementNo}`,
    context: {
      reimbursementNo: row.reimbursementNo,
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
  params: Api.Fms.ExecuteExpenseReimbursementPayload
) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('execute_fms_expense_reimbursement_secure', {
        p_reimbursement_id: params.reimbursementId,
        p_fund_account_id: params.fundAccountId,
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
): Promise<QueryResult<Api.Fms.WaybillExpenseOcrAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.WaybillExpenseOcrAnalyzeResponse>(
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

const toProfitListRpcParams = (
  params: WaybillProfitSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_waybill_status: params.waybillStatus || null,
    p_completed_at_start: params.completedAtRange?.[0]
      ? `${params.completedAtRange[0]}T00:00:00`
      : null,
    p_completed_at_end: params.completedAtRange?.[1]
      ? `${params.completedAtRange[1]}T23:59:59.999`
      : null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchWaybillProfitList(params: WaybillProfitSearchParams) {
  const result = await responseHandle<
    SecureListPayload<WaybillProfit, Api.Fms.WaybillProfitFieldAccessMap>
  >(() => supabase.rpc('tms_list_waybill_profits_secure', toProfitListRpcParams(params, 'list')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function analyzeWaybillProfitByAi(): Promise<
  QueryResult<Api.Fms.WaybillProfitAnalysisResponse>
> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.WaybillProfitAnalysisResponse>(
    'ai-waybill-profit-analyst'
  )

  return {
    data: data ?? null,
    error: await normalizeSupabaseFunctionError(error)
  }
}

export async function analyzeReceivablesCollectionByAi(): Promise<
  QueryResult<Api.Fms.ReceivablesCollectionResponse>
> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.ReceivablesCollectionResponse>(
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
  const result = await responseHandle<
    SecureListPayload<WaybillProfit, Api.Fms.WaybillProfitFieldAccessMap>
  >(
    () => supabase.rpc('tms_list_waybill_profits_secure', toProfitListRpcParams(params, 'export')),
    {
      showErrorMessage: true
    }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFinanceWorkbench() {
  return await responseHandle<FinanceWorkbenchStats>(
    () => supabase.rpc('tms_get_finance_workbench_secure'),
    { showErrorMessage: true }
  )
}
