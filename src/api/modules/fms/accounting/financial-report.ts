import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

interface FinancialStatementItemListPayload {
  records: Api.Fms.FinancialStatementItemRecord[]
  fieldAccess: Api.Fms.FinancialReportFieldAccessMap
}

interface FinancialStatementFormulaListPayload {
  records: Api.Fms.FinancialStatementFormulaRecord[]
  fieldAccess: Api.Fms.FinancialReportFieldAccessMap
  isRecordOwner: boolean
}

interface FinancialStatementReportPayload {
  records: Api.Fms.FinancialStatementReportRecord[]
  fieldAccess: Api.Fms.FinancialReportFieldAccessMap
}

export async function fetchFinancialStatementItems(
  accountSetId: string,
  statementType: Api.Fms.FinancialStatementType
) {
  const result = await responseHandle<FinancialStatementItemListPayload>(
    () =>
      supabase.rpc('fms_list_financial_statement_items_secure', {
        p_account_set_id: accountSetId,
        p_statement_type: statementType
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFinancialStatementFormulas(targetItemId: string) {
  const result = await responseHandle<FinancialStatementFormulaListPayload>(
    () =>
      supabase.rpc('fms_list_financial_statement_formulas_secure', {
        p_target_item_id: targetItemId
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {},
    isRecordOwner: result.data?.isRecordOwner ?? false
  }
}

export async function fetchFinancialStatementReport(
  params: Api.Fms.FinancialStatementReportParams
) {
  const result = await responseHandle<FinancialStatementReportPayload>(
    () =>
      supabase.rpc('fms_financial_statement_report_secure', {
        p_account_set_id: params.accountSetId,
        p_statement_type: params.statementType,
        p_fiscal_year: params.fiscalYear,
        p_period_from: params.periodFrom ?? 1,
        p_period_to: params.periodTo ?? 12
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function initializeFinancialStatementItems(accountSetId: string) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('initialize_fms_financial_statement_items_secure', {
        p_account_set_id: accountSetId
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: '标准财务报表项目已初始化'
    }
  )
}

export async function saveFinancialStatementItem(
  payload: Api.Fms.SaveFinancialStatementItemPayload
) {
  return await responseHandle<Api.Fms.FinancialStatementItemRecord>(
    () => supabase.rpc('save_fms_financial_statement_item_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '报表项目已更新' : '报表项目已创建'
    }
  )
}

export async function saveFinancialStatementMappings(
  statementItemId: string,
  mappings: Api.Fms.FinancialStatementMappingRecord[]
) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('save_fms_financial_statement_mappings_secure', {
        p_statement_item_id: statementItemId,
        p_mappings: mappings
      }),
    { breakReturn: true, showMessage: true, message: '科目取数映射已保存' }
  )
}

export async function saveFinancialStatementFormulas(
  targetItemId: string,
  formulas: Api.Fms.FinancialStatementFormulaRecord[]
) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('save_fms_financial_statement_formulas_secure', {
        p_target_item_id: targetItemId,
        p_formulas: formulas
      }),
    { breakReturn: true, showMessage: true, message: '报表计算公式已保存' }
  )
}

export async function fetchCashFlowAllocations(voucherId: string) {
  return await responseHandle<Api.Fms.CashFlowAllocationRecord[]>(
    () => supabase.rpc('fms_list_cash_flow_allocations_secure', { p_voucher_id: voucherId }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveCashFlowAllocations(
  voucherId: string,
  allocations: Api.Fms.SaveCashFlowAllocationPayload[]
) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('save_fms_cash_flow_allocations_secure', {
        p_voucher_id: voucherId,
        p_allocations: allocations
      }),
    { breakReturn: true, showMessage: true, message: '现金流量归集已保存' }
  )
}
