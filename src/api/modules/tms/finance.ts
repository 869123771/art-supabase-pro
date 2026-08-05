import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'

type WaybillCost = Api.Tms.Finance.WaybillCostRecord
type WaybillCostSearchParams = Api.Tms.Finance.WaybillCostSearchParams
type WaybillOption = Api.Tms.Finance.WaybillOption
type WaybillOptionSearchParams = Api.Tms.Finance.WaybillOptionSearchParams
type CostReviewPayload = Api.Tms.Finance.CostReviewPayload
type WaybillProfit = Api.Tms.Finance.WaybillProfitRecord
type WaybillProfitSearchParams = Api.Tms.Finance.WaybillProfitSearchParams
type FinanceWorkbenchStats = Api.Tms.Finance.FinanceWorkbenchStats

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const WAYBILL_COST_SELECT = `
  *,
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
    origin_station,
    destination_station
  )
`

const fetchMatchingWaybillIds = async (keyword: string): Promise<string[]> => {
  const { data } = await responseHandle<Array<{ id: string }>>(
    () =>
      supabase
        .from('tms_waybill')
        .select('id')
        .or(
          `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%`
        )
        .limit(500),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return (data ?? []).map((item) => item.id)
}

const applyCostFilters = (
  query: SupabaseQueryLike,
  params: WaybillCostSearchParams,
  waybillIds: string[]
): SupabaseQueryLike => {
  const { auditStatus, costType, keyword, occurredOnRange } = params
  if (auditStatus) query = query.eq('audit_status', auditStatus)
  if (costType) query = query.eq('cost_type', costType)
  if (keyword) {
    const filters = [`payee_name.ilike.%${keyword}%`, `remark.ilike.%${keyword}%`]
    if (waybillIds.length) filters.push(`waybill_id.in.(${waybillIds.join(',')})`)
    query = query.or(filters.join(','))
  }
  return applyDateRange(query, 'occurred_on', occurredOnRange)
}

const createCostWritePayload = (params: WaybillCost) => ({
  waybillId: params.waybillId,
  costType: params.costType,
  amount: Number(params.amount),
  occurredOn: params.occurredOn,
  payeeName: params.payeeName || null,
  carrierId: params.carrierId || null,
  driverId: params.driverId || null,
  remark: params.remark || null,
  attachments: params.attachments ?? []
})

export async function fetchWaybillCostList(params: WaybillCostSearchParams) {
  const { from = 0, to = 9, keyword } = params
  const waybillIds = keyword ? await fetchMatchingWaybillIds(keyword) : []
  let query = supabase
    .from('tms_waybill_cost')
    .select(WAYBILL_COST_SELECT, { count: 'exact' })
    .order('occurred_on', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
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
  const waybillIds = keyword ? await fetchMatchingWaybillIds(keyword) : []
  let query = supabase
    .from('tms_waybill_cost')
    .select(WAYBILL_COST_SELECT)
    .order('occurred_on', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyCostFilters(query, params, waybillIds)
  return await responseHandle<WaybillCost[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFinanceWaybillOptions(params: WaybillOptionSearchParams = {}) {
  const { from = 0, to = 999, keyword } = params
  let query = supabase
    .from('tms_waybill')
    .select(WAYBILL_OPTION_SELECT, { count: 'exact' })
    .neq('status', 'cancelled')
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%`
    )
  }
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
  return await responseHandle(
    () =>
      supabase
        .from('tms_waybill_cost')
        .update({ audit_status: 'pending_review' }, { count: 'exact' })
        .eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function reviewWaybillCost(params: CostReviewPayload) {
  return await responseHandle(
    () =>
      supabase
        .from('tms_waybill_cost')
        .update(
          keysToSnakeDeep({
            auditStatus: params.auditStatus,
            reviewRemark: params.reviewRemark || null
          }),
          { count: 'exact' }
        )
        .eq('id', params.id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
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

const applyProfitFilters = (
  query: SupabaseQueryLike,
  params: WaybillProfitSearchParams
): SupabaseQueryLike => {
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
    .range(from, to) as unknown as SupabaseQueryLike
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
    error: await normalizeFunctionInvokeError(error)
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
    error: await normalizeFunctionInvokeError(error)
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
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyProfitFilters(query, params)
  return await responseHandle<WaybillProfit[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFinanceWorkbench() {
  return await responseHandle<FinanceWorkbenchStats>(
    () => supabase.from('tms_finance_workbench').select('*').single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}
