import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

interface TaxPeriodListPayload {
  records: Api.Fms.TaxPeriodRecord[]
  total: number
  fieldAccess: Api.Fms.TaxFieldAccessMap
}

interface TaxLedgerLineListPayload {
  records: Api.Fms.TaxLedgerLineRecord[]
  fieldAccess: Api.Fms.TaxFieldAccessMap
  isRecordOwner: boolean
}

export async function fetchTaxPeriodList(params: Api.Fms.TaxPeriodSearchParams = {}) {
  const { accountSetId, from = 0, status, taxType, to = 19 } = params
  const result = await responseHandle<TaxPeriodListPayload>(
    () =>
      supabase.rpc('fms_list_tax_periods_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_tax_type: taxType || null,
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

export async function fetchTaxPeriodDetail(id: string) {
  return await responseHandle<Api.Fms.TaxPeriodRecord>(
    () => supabase.rpc('fms_get_tax_period_secure', { p_period_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchTaxLedgerLines(periodId: string) {
  const result = await responseHandle<TaxLedgerLineListPayload>(
    () => supabase.rpc('fms_list_tax_ledger_lines_secure', { p_period_id: periodId }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {},
    isRecordOwner: result.data?.isRecordOwner ?? false
  }
}

export async function fetchTaxSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.TaxSummary>(
    () =>
      supabase.rpc('fms_tax_summary_secure', {
        p_account_set_id: accountSetId || null,
        p_tenant_id: null
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveTaxPeriod(payload: Api.Fms.SaveTaxPeriodPayload) {
  return await responseHandle<Api.Fms.TaxPeriodRecord>(
    () => supabase.rpc('save_fms_tax_period_secure', { p_payload: payload }),
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
      supabase.rpc('save_fms_tax_ledger_line_secure', {
        p_period_id: periodId,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '税务台账明细已保存' }
  )
}

export async function deleteTaxLedgerLine(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_tax_ledger_line_secure', { p_line_id: id }),
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
      supabase.rpc('act_fms_tax_period_secure', {
        p_period_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '税务期间状态已更新' }
  )
}
