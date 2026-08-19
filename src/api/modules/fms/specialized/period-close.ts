import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export async function fetchPeriodCloseRuns(params: Api.Fms.PeriodCloseSearchParams = {}) {
  const { accountSetId, from = 0, status, to = 19 } = params
  let query = supabase
    .from('fms_period_close_run')
    .select('*, period:fms_accounting_period!fms_period_close_run_period_fkey(*)', {
      count: 'exact'
    })
    .order('create_time', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (status) query = query.eq('status', status)
  return await responseHandle<Api.Fms.PeriodCloseRunRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchPeriodCloseChecks(runId: string) {
  return await responseHandle<Api.Fms.PeriodCloseCheckRecord[]>(
    () =>
      supabase
        .from('fms_period_close_check')
        .select('*')
        .eq('close_run_id', runId)
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchPeriodCloseSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.PeriodCloseSummary>(
    () =>
      supabase.rpc('fms_period_close_summary', { p_account_set_id: accountSetId || null }).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function runPeriodCloseChecks(periodId: string) {
  return await responseHandle<Api.Fms.PeriodCloseRunRecord>(
    () => supabase.rpc('run_fms_period_close_checks', { p_accounting_period_id: periodId }),
    { breakReturn: true, showMessage: true, message: '关账检查已完成' }
  )
}

export async function generateProfitLossCarryforward(periodId: string) {
  return await responseHandle<Api.Fms.VoucherRecord>(
    () =>
      supabase.rpc('generate_fms_profit_loss_carryforward', {
        p_accounting_period_id: periodId
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: '损益结转凭证已生成，请完成审核与记账'
    }
  )
}

export async function actPeriodCloseRun(
  id: string,
  action: Api.Fms.PeriodCloseAction,
  reason?: string
) {
  return await responseHandle<Api.Fms.PeriodCloseRunRecord>(
    () =>
      supabase.rpc('act_fms_period_close_run', {
        p_run_id: id,
        p_action: action,
        p_reason: reason || null
      }),
    { breakReturn: true, showMessage: true, message: '会计期间状态已更新' }
  )
}
