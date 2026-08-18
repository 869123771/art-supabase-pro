import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export async function fetchTaxPeriodList(params: Api.Fms.TaxPeriodSearchParams = {}) {
  const { accountSetId, from = 0, status, taxType, to = 19 } = params
  let query = supabase
    .from('fms_tax_period')
    .select('*, period:fms_accounting_period!fms_tax_period_period_fkey(*)', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (taxType) query = query.eq('tax_type', taxType)
  if (status) query = query.eq('status', status)
  return await responseHandle<Api.Fms.TaxPeriodRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchTaxLedgerLines(periodId: string) {
  return await responseHandle<Api.Fms.TaxLedgerLineRecord[]>(
    () =>
      supabase
        .from('fms_tax_ledger_line')
        .select('*')
        .eq('tax_period_id', periodId)
        .order('occurred_on')
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchTaxSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.TaxSummary>(
    () => supabase.rpc('fms_tax_summary', { p_account_set_id: accountSetId || null }).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveTaxPeriod(payload: Api.Fms.SaveTaxPeriodPayload) {
  return await responseHandle<Api.Fms.TaxPeriodRecord>(
    () => supabase.rpc('save_fms_tax_period', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '税务期间已更新' : '税务期间已创建'
    }
  )
}

export async function saveTaxLedgerLine(
  periodId: string,
  payload: Api.Fms.SaveTaxLedgerLinePayload
) {
  return await responseHandle<Api.Fms.TaxLedgerLineRecord>(
    () =>
      supabase.rpc('save_fms_tax_ledger_line', { p_tax_period_id: periodId, p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '税务台账明细已保存' }
  )
}

export async function deleteTaxLedgerLine(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_tax_ledger_line', { p_line_id: id }),
    { breakReturn: true, showMessage: true, message: '税务台账明细已删除' }
  )
}

export async function actTaxPeriod(
  id: string,
  action: Api.Fms.TaxPeriodAction,
  payload: {
    actionDate?: string
    filingReference?: string
    fundAccountId?: string
    reason?: string
    referenceNo?: string
  } = {}
) {
  return await responseHandle<Api.Fms.TaxPeriodRecord>(
    () =>
      supabase.rpc('act_fms_tax_period', {
        p_tax_period_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '税务期间状态已更新' }
  )
}
