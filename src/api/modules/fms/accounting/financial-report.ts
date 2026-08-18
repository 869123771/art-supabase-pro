import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

const STATEMENT_ITEM_SELECT = `
  *,
  mappings:fms_financial_statement_mapping(
    id,
    subject_id,
    mapping_direction,
    factor,
    remark,
    subject:fms_subject(id, subject_code, subject_name, category)
  )
`

export async function fetchFinancialStatementItems(
  accountSetId: string,
  statementType: Api.Fms.FinancialStatementType
) {
  return await responseHandle<Api.Fms.FinancialStatementItemRecord[]>(
    () =>
      supabase
        .from('fms_financial_statement_item')
        .select(STATEMENT_ITEM_SELECT)
        .eq('account_set_id', accountSetId)
        .eq('statement_type', statementType)
        .order('line_no'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchFinancialStatementFormulas(targetItemId: string) {
  return await responseHandle<Api.Fms.FinancialStatementFormulaRecord[]>(
    () =>
      supabase
        .from('fms_financial_statement_formula')
        .select(
          `
          *,
          sourceItem:fms_financial_statement_item!fms_financial_statement_formula_source_fkey(
            id, item_code, item_name, line_no
          )
        `
        )
        .eq('target_item_id', targetItemId)
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchFinancialStatementReport(
  params: Api.Fms.FinancialStatementReportParams
) {
  return await responseHandle<Api.Fms.FinancialStatementReportRecord[]>(
    () =>
      supabase.rpc('fms_financial_statement_report', {
        p_account_set_id: params.accountSetId,
        p_statement_type: params.statementType,
        p_fiscal_year: params.fiscalYear,
        p_period_from: params.periodFrom ?? 1,
        p_period_to: params.periodTo ?? 12
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function initializeFinancialStatementItems(accountSetId: string) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('initialize_fms_financial_statement_items', {
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
    () => supabase.rpc('save_fms_financial_statement_item', { p_payload: payload }),
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
      supabase.rpc('save_fms_financial_statement_mappings', {
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
      supabase.rpc('save_fms_financial_statement_formulas', {
        p_target_item_id: targetItemId,
        p_formulas: formulas
      }),
    { breakReturn: true, showMessage: true, message: '报表计算公式已保存' }
  )
}

export async function fetchCashFlowAllocations(voucherId: string) {
  return await responseHandle<Api.Fms.CashFlowAllocationRecord[]>(
    () =>
      supabase
        .from('fms_cash_flow_allocation')
        .select(
          `
          *,
          statementItem:fms_financial_statement_item(
            id, item_code, item_name, cash_flow_direction
          ),
          voucherLine:fms_voucher_line!inner(voucher_id)
        `
        )
        .eq('voucherLine.voucher_id', voucherId)
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveCashFlowAllocations(
  voucherId: string,
  allocations: Api.Fms.SaveCashFlowAllocationPayload[]
) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('save_fms_cash_flow_allocations', {
        p_voucher_id: voucherId,
        p_allocations: allocations
      }),
    { breakReturn: true, showMessage: true, message: '现金流量归集已保存' }
  )
}
