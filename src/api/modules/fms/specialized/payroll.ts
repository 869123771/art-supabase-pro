import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

type PayrollRun = Api.Fms.PayrollRunRecord

interface PayrollRunListPayload {
  records: PayrollRun[]
  total: number
  fieldAccess: Api.Fms.PayrollFieldAccessMap
}

interface PayrollLineListPayload {
  records: Api.Fms.PayrollLineRecord[]
  fieldAccess: Api.Fms.PayrollFieldAccessMap
  isRecordOwner: boolean
}

export async function fetchPayrollRunList(params: Api.Fms.PayrollRunSearchParams = {}) {
  const { accountSetId, from = 0, status, to = 19 } = params
  const result = await responseHandle<PayrollRunListPayload>(
    () =>
      supabase.rpc('fms_list_payroll_runs_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_status: status || null,
        p_tenant_id: null
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

export async function fetchPayrollRunDetail(id: string) {
  return await responseHandle<PayrollRun>(
    () => supabase.rpc('fms_get_payroll_run_secure', { p_run_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchPayrollLines(runId: string) {
  const result = await responseHandle<PayrollLineListPayload>(
    () => supabase.rpc('fms_list_payroll_lines_secure', { p_run_id: runId }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {},
    isRecordOwner: result.data?.isRecordOwner ?? false
  }
}

export async function fetchPayrollEmployeeOptions(runId: string) {
  return await responseHandle<Api.Fms.PayrollEmployeeOption[]>(
    () =>
      supabase.rpc('fms_list_payroll_employee_options_secure', {
        p_run_id: runId,
        p_tenant_id: null
      }),
    { showErrorMessage: true }
  )
}

export async function fetchPayrollSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.PayrollSummary>(
    () =>
      supabase.rpc('fms_payroll_summary_secure', {
        p_account_set_id: accountSetId || null,
        p_tenant_id: null
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function savePayrollRun(payload: Api.Fms.SavePayrollRunPayload) {
  return await responseHandle<Api.Fms.PayrollRunRecord>(
    () => supabase.rpc('save_fms_payroll_run_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '薪资批次已更新' : '薪资批次已创建'
    }
  )
}

export async function savePayrollLine(runId: string, payload: Api.Fms.SavePayrollLinePayload) {
  return await responseHandle<Api.Fms.PayrollLineRecord>(
    () => supabase.rpc('save_fms_payroll_line_secure', { p_run_id: runId, p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '薪资明细已保存' }
  )
}

export async function deletePayrollLine(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_payroll_line_secure', { p_line_id: id }),
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
      supabase.rpc('act_fms_payroll_run_secure', {
        p_run_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '薪资批次状态已更新' }
  )
}
