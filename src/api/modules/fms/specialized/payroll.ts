import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

export async function fetchPayrollRunList(params: Api.Fms.PayrollRunSearchParams = {}) {
  const { accountSetId, from = 0, status, to = 19 } = params
  let query = supabase
    .from('fms_payroll_run')
    .select('*, period:fms_accounting_period!fms_payroll_run_period_fkey(*)', { count: 'exact' })
    .order('payroll_month', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (status) query = query.eq('status', status)
  return await responseHandle<Api.Fms.PayrollRunRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchPayrollLines(runId: string) {
  return await responseHandle<Api.Fms.PayrollLineRecord[]>(
    () =>
      supabase
        .from('fms_payroll_line')
        .select('*')
        .eq('run_id', runId)
        .order('employee_no_snapshot'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchPayrollEmployeeOptions(tenantId?: string) {
  let query = supabase
    .from('hr_employee')
    .select('id,tenant_id,employee_no,employee_name')
    .in('employment_status', ['probation', 'active'])
    .order('employee_no')
  if (tenantId) query = query.eq('tenant_id', tenantId)
  return await responseHandle<Api.Fms.PayrollEmployeeOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchPayrollSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.PayrollSummary>(
    () => supabase.rpc('fms_payroll_summary', { p_account_set_id: accountSetId || null }).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function savePayrollRun(payload: Api.Fms.SavePayrollRunPayload) {
  return await responseHandle<Api.Fms.PayrollRunRecord>(
    () => supabase.rpc('save_fms_payroll_run', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '薪资批次已更新' : '薪资批次已创建'
    }
  )
}

export async function savePayrollLine(runId: string, payload: Api.Fms.SavePayrollLinePayload) {
  return await responseHandle<Api.Fms.PayrollLineRecord>(
    () => supabase.rpc('save_fms_payroll_line', { p_run_id: runId, p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '薪资明细已保存' }
  )
}

export async function deletePayrollLine(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_payroll_line', { p_line_id: id }),
    {
      breakReturn: true,
      showMessage: true,
      message: '薪资明细已删除'
    }
  )
}

export async function actPayrollRun(
  id: string,
  action: Api.Fms.PayrollRunAction,
  payload: {
    actionDate?: string
    fundAccountId?: string
    reason?: string
    referenceNo?: string
  } = {}
) {
  return await responseHandle<Api.Fms.PayrollRunRecord>(
    () =>
      supabase.rpc('act_fms_payroll_run', { p_run_id: id, p_action: action, p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '薪资批次状态已更新' }
  )
}
