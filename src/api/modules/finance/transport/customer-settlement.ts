import { useSupabase } from '@/hooks'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type CustomerStatement = Api.Finance.CustomerStatementRecord
type CustomerStatementItem = Api.Finance.CustomerStatementItem
type CustomerStatementSearchParams = Api.Finance.CustomerStatementSearchParams
type EligibleWaybill = Api.Finance.CustomerStatementEligibleWaybill
type EligibleWaybillSearchParams = Api.Finance.CustomerStatementEligibleWaybillSearchParams
type CreateCustomerStatementPayload = Api.Finance.CreateCustomerStatementPayload
type CustomerStatementStatusPayload = Api.Finance.CustomerStatementStatusPayload

const { supabase, responseHandle } = useSupabase()

const applyStatementFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: CustomerStatementSearchParams
): TQuery => {
  const { customerId, keyword, periodRange, recordId, status } = params
  if (recordId) query = query.eq('id', recordId)
  if (customerId) query = query.eq('customer_id', customerId)
  if (status) query = query.eq('status', status)
  if (keyword) {
    query = query.or(
      `statement_no.ilike.%${keyword}%,customer_name.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  if (periodRange?.[0]) query = query.gte('period_start', periodRange[0])
  if (periodRange?.[1]) query = query.lte('period_end', periodRange[1])
  return query
}

export async function fetchCustomerStatementList(params: CustomerStatementSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_customer_statement_summary')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyStatementFilters(query, params)
  return await responseHandle<CustomerStatement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCustomerStatementList(
  params: CustomerStatementSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_customer_statement_summary')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyStatementFilters(query, params)
  return await responseHandle<CustomerStatement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerStatementEligibleWaybills(params: EligibleWaybillSearchParams) {
  const { customerId, from = 0, keyword, periodEnd, periodStart, to = 9 } = params
  let query = supabase
    .from('tms_customer_statement_eligible_waybill')
    .select('*', { count: 'exact' })
    .eq('customer_id', customerId)
    .order('completed_at', { ascending: false })
    .range(from, to)
  if (keyword) {
    query = query.or(
      `waybill_no.ilike.%${keyword}%,order_no.ilike.%${keyword}%,origin_station.ilike.%${keyword}%,destination_station.ilike.%${keyword}%`
    )
  }
  query = applyDateRange(query, 'completed_at', [periodStart, periodEnd], {
    startOfDay: true,
    endOfDay: true
  })
  return await responseHandle<EligibleWaybill[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerStatementDetail(id: string) {
  const [statementResponse, itemResponse] = await Promise.all([
    responseHandle<CustomerStatement>(
      () => supabase.from('tms_customer_statement_summary').select('*').eq('id', id).single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<CustomerStatementItem[]>(
      () =>
        supabase
          .from('tms_customer_statement_item')
          .select('*')
          .eq('statement_id', id)
          .order('completed_at_snapshot', { ascending: true }),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: statementResponse.data
      ? { ...statementResponse.data, items: itemResponse.data ?? [] }
      : undefined
  }
}

export async function createCustomerStatement(params: CreateCustomerStatementPayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_tms_customer_statement', {
        p_customer_id: params.customerId,
        p_period_start: params.periodStart,
        p_period_end: params.periodEnd,
        p_waybill_ids: params.waybillIds,
        p_remark: params.remark || null,
        p_statement_no: params.statementNo || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function updateCustomerStatementStatus(params: CustomerStatementStatusPayload) {
  if (params.status === 'pending_review') {
    const statement = await responseHandle<Pick<CustomerStatement, 'statementNo' | 'customerName'>>(
      () =>
        supabase
          .from('tms_customer_statement_summary')
          .select('statement_no, customer_name')
          .eq('id', params.id)
          .single(),
      { breakReturn: true, showErrorMessage: true }
    )
    if (!statement.data) throw new Error('客户对账单不存在')
    return await startWorkflow({
      businessType: 'tms_customer_statement',
      businessId: params.id,
      businessTitle: `客户对账单 ${statement.data.statementNo} · ${statement.data.customerName}`
    })
  }
  if (params.status === 'confirmed' || params.status === 'draft') {
    return await actWorkflowByBusiness({
      businessType: 'tms_customer_statement',
      businessId: params.id,
      action: params.status === 'confirmed' ? 'approve' : 'reject',
      comment: params.reviewRemark || null
    })
  }
  const payload: Record<string, string> = { status: params.status }
  if (params.reviewRemark) payload.review_remark = params.reviewRemark
  if (params.voidReason) payload.void_reason = params.voidReason
  return await responseHandle<CustomerStatement>(
    () =>
      supabase
        .from('tms_customer_statement')
        .update(payload, { count: 'exact' })
        .eq('id', params.id)
        .select('*')
        .single(),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}

export async function deleteCustomerStatement(id: string) {
  return await responseHandle(
    () => supabase.from('tms_customer_statement').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, breakReturn: true, requireAffected: true }
  )
}
