import { useSupabase } from '@/hooks'

type AccountSet = Api.Fms.AccountSetRecord
type AccountSetSearchParams = Api.Fms.AccountSetSearchParams
type SaveAccountSetPayload = Api.Fms.SaveAccountSetPayload
type AccountingPeriod = Api.Fms.AccountingPeriodRecord
type AccountingPeriodStatus = Api.Fms.AccountingPeriodStatus
type AccountingFoundationSummary = Api.Fms.AccountingFoundationSummary

const { supabase, responseHandle } = useSupabase()

const ACCOUNT_SET_SELECT = `
  *,
  tenant:sys_tenant!fms_account_set_tenant_fkey(id, tenant_code, tenant_name)
`

export async function fetchAccountSetList(params: AccountSetSearchParams = {}) {
  const { from = 0, to = 19, keyword, status, tenantId } = params
  let query = supabase
    .from('fms_account_set')
    .select(ACCOUNT_SET_SELECT, { count: 'exact' })
    .order('is_default', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)

  if (tenantId) query = query.eq('tenant_id', tenantId)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `account_set_code.ilike.%${value}%,account_set_name.ilike.%${value}%,legal_entity_name.ilike.%${value}%,unified_social_credit_code.ilike.%${value}%`
    )
  }

  return await responseHandle<AccountSet[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchAccountSetOverview(tenantId?: string) {
  const fetchCount = async (status?: Api.Fms.AccountSetStatus): Promise<number> => {
    let query = supabase.from('fms_account_set').select('id', { count: 'exact', head: true })
    if (tenantId) query = query.eq('tenant_id', tenantId)
    if (status) query = query.eq('status', status)
    const result = await responseHandle<never[]>(() => query, {
      ignoreCheck: true,
      showErrorMessage: true
    })
    return result.total ?? 0
  }

  const [totalCount, activeCount, draftCount, suspendedCount] = await Promise.all([
    fetchCount(),
    fetchCount('active'),
    fetchCount('draft'),
    fetchCount('suspended')
  ])

  return {
    data: { totalCount, activeCount, draftCount, suspendedCount }
  }
}

export async function fetchAccountSetDetail(id: string) {
  return await responseHandle<AccountSet>(
    () => supabase.from('fms_account_set').select(ACCOUNT_SET_SELECT).eq('id', id).single(),
    { breakReturn: true, showErrorMessage: true }
  )
}

export async function fetchAccountSetOptions(params: AccountSetSearchParams = {}) {
  const result = await fetchAccountSetList({ ...params, from: 0, to: 999 })
  return {
    ...result,
    data: (result.data ?? []).map((item) => ({
      label: `${item.accountSetName}（${item.accountSetCode}）`,
      value: item.id,
      status: item.status,
      tenantId: item.tenantId
    }))
  }
}

export async function saveAccountSet(payload: SaveAccountSetPayload) {
  return await responseHandle<AccountSet>(
    () => supabase.rpc('save_fms_account_set', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '账套信息已更新' : '账套已创建'
    }
  )
}

export async function setAccountSetStatus(
  id: string,
  status: Api.Fms.AccountSetStatus,
  reason?: string | null
) {
  return await responseHandle<AccountSet>(
    () =>
      supabase.rpc('set_fms_account_set_status', {
        p_account_set_id: id,
        p_status: status,
        p_reason: reason || null
      }),
    { breakReturn: true, showMessage: true, message: '账套状态已更新' }
  )
}

export async function fetchAccountingPeriodList(accountSetId: string) {
  return await responseHandle<AccountingPeriod[]>(
    () =>
      supabase
        .from('fms_accounting_period')
        .select('*')
        .eq('account_set_id', accountSetId)
        .order('start_date', { ascending: true }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function setAccountingPeriodStatus(
  id: string,
  status: AccountingPeriodStatus,
  reason?: string | null
) {
  return await responseHandle<AccountingPeriod>(
    () =>
      supabase.rpc('set_fms_accounting_period_status', {
        p_period_id: id,
        p_status: status,
        p_reason: reason || null
      }),
    { breakReturn: true, showMessage: true, message: '会计期间状态已更新' }
  )
}

export async function fetchAccountingFoundationSummary(accountSetId: string) {
  return await responseHandle<AccountingFoundationSummary>(
    () =>
      supabase
        .rpc('fms_accounting_foundation_summary', { p_account_set_id: accountSetId })
        .single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}
