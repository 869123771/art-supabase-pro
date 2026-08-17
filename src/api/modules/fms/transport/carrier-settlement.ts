import { useSupabase } from '@/hooks'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type Statement = Api.Fms.CarrierStatementRecord
type StatementItem = Api.Fms.CarrierStatementItem
type SearchParams = Api.Fms.CarrierStatementSearchParams
type EligibleCost = Api.Fms.CarrierStatementEligibleCost
type EligibleSearchParams = Api.Fms.CarrierStatementEligibleCostSearchParams
type CreatePayload = Api.Fms.CreateCarrierStatementPayload
type StatusPayload = Api.Fms.CarrierStatementStatusPayload & { businessTitle?: string }

const { supabase, responseHandle } = useSupabase()

function applyFilters<TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: SearchParams
): TQuery {
  const { carrierId, keyword, periodRange, recordId, status } = params
  if (recordId) query = query.eq('id', recordId)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (status) query = query.eq('status', status)
  if (keyword) {
    query = query.or(
      `statement_no.ilike.%${keyword}%,carrier_name.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  if (periodRange?.[0]) query = query.gte('period_start', periodRange[0])
  if (periodRange?.[1]) query = query.lte('period_end', periodRange[1])
  return query
}

export async function fetchCarrierStatementList(params: SearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_carrier_statement_summary')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyFilters(query, params)
  return await responseHandle<Statement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCarrierStatementList(
  params: SearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_carrier_statement_summary')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyFilters(query, params)
  return await responseHandle<Statement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierStatementEligibleCosts(params: EligibleSearchParams) {
  const { carrierId, from = 0, keyword, periodEnd, periodStart, to = 9 } = params
  let query = supabase
    .from('tms_carrier_statement_eligible_cost')
    .select('*', { count: 'exact' })
    .eq('carrier_id', carrierId)
    .order('occurred_on', { ascending: false })
    .range(from, to)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,payee_name.ilike.%${keyword}%,origin_city.ilike.%${keyword}%,destination_city.ilike.%${keyword}%`
    )
  }
  query = applyDateRange(query, 'occurred_on', [periodStart, periodEnd])
  return await responseHandle<EligibleCost[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierStatementDetail(id: string) {
  const [statementResponse, itemResponse] = await Promise.all([
    responseHandle<Statement>(
      () => supabase.from('tms_carrier_statement_summary').select('*').eq('id', id).single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<StatementItem[]>(
      () =>
        supabase
          .from('tms_carrier_statement_item')
          .select('*')
          .eq('statement_id', id)
          .order('occurred_on_snapshot', { ascending: true }),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: statementResponse.data
      ? { ...statementResponse.data, items: itemResponse.data ?? [] }
      : undefined
  }
}

export async function createCarrierStatement(params: CreatePayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_tms_carrier_statement', {
        p_carrier_id: params.carrierId,
        p_period_start: params.periodStart,
        p_period_end: params.periodEnd,
        p_cost_ids: params.costIds,
        p_remark: params.remark || null,
        p_statement_no: params.statementNo || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function updateCarrierStatementStatus(params: StatusPayload) {
  if (params.status === 'pending_review') {
    return await startWorkflow({
      businessType: 'tms_carrier_statement',
      businessId: params.id,
      businessTitle: params.businessTitle || `承运商对账单 ${params.id}`
    })
  }
  if (params.status === 'confirmed' || params.status === 'draft') {
    return await actWorkflowByBusiness({
      businessType: 'tms_carrier_statement',
      businessId: params.id,
      action: params.status === 'confirmed' ? 'approve' : 'reject',
      comment: params.reviewRemark
    })
  }
  const payload: Record<string, string> = { status: params.status }
  if (params.reviewRemark) payload.review_remark = params.reviewRemark
  if (params.voidReason) payload.void_reason = params.voidReason
  return await responseHandle<Statement>(
    () =>
      supabase
        .from('tms_carrier_statement')
        .update(payload, { count: 'exact' })
        .eq('id', params.id)
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCarrierStatement(id: string) {
  return await responseHandle(
    () => supabase.from('tms_carrier_statement').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}
