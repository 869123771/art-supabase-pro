import { useSupabase } from '@/hooks'
import { actWorkflowByBusiness, startWorkflow } from '@/api/workflow'

type Statement = Api.Fms.CarrierStatementRecord
type SearchParams = Api.Fms.CarrierStatementSearchParams
type EligibleCost = Api.Fms.CarrierStatementEligibleCost
type EligibleSearchParams = Api.Fms.CarrierStatementEligibleCostSearchParams
type CreatePayload = Api.Fms.CreateCarrierStatementPayload
type StatusPayload = Api.Fms.CarrierStatementStatusPayload

interface SecureListPayload<TRecord, TAccess extends Record<string, string> = never> {
  records: TRecord[]
  total: number
  fieldAccess?: TAccess
}

const { supabase, responseHandle } = useSupabase()

const toListRpcParams = (
  params: SearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_carrier_id: params.carrierId || null,
    p_record_id: params.recordId || null,
    p_status: params.status || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_period_start: params.periodRange?.[0] || null,
    p_period_end: params.periodRange?.[1] || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchCarrierStatementList(params: SearchParams) {
  const result = await responseHandle<
    SecureListPayload<Statement, Api.Fms.CarrierStatementFieldAccessMap>
  >(() => supabase.rpc('tms_list_carrier_statements_secure', toListRpcParams(params, 'list')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCarrierStatementList(
  params: SearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<
    SecureListPayload<Statement, Api.Fms.CarrierStatementFieldAccessMap>
  >(() => supabase.rpc('tms_list_carrier_statements_secure', toListRpcParams(params, 'export')), {
    showErrorMessage: true
  })
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCarrierStatementEligibleCosts(params: EligibleSearchParams) {
  const result = await responseHandle<
    SecureListPayload<EligibleCost, Api.Fms.CarrierStatementFieldAccessMap>
  >(
    () =>
      supabase.rpc('tms_list_carrier_statement_eligible_costs_secure', {
        p_carrier_id: params.carrierId,
        p_period_start: params.periodStart,
        p_period_end: params.periodEnd,
        p_keyword: String(params.keyword ?? '').trim() || null,
        p_from: Math.max(params.from ?? 0, 0),
        p_to: Math.max(params.to ?? 9, params.from ?? 0)
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

export async function fetchCarrierStatementDetail(id: string) {
  return await responseHandle<Statement | null>(
    () => supabase.rpc('tms_get_carrier_statement_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function createCarrierStatement(params: CreatePayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('tms_create_carrier_statement_secure', {
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
      comment: params.reviewRemark || null
    })
  }
  if (params.status === 'voided') {
    return await responseHandle<boolean>(
      () =>
        supabase.rpc('tms_void_carrier_statement_secure', {
          p_id: params.id,
          p_reason: params.voidReason || null
        }),
      { showMessage: true, breakReturn: true }
    )
  }
  throw new Error(`不支持直接变更承运商对账单状态：${params.status}`)
}

export async function deleteCarrierStatement(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('tms_delete_carrier_statement_secure', { p_id: id }),
    { showMessage: true, breakReturn: true }
  )
}
