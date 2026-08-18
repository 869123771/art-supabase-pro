import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

type FundAccount = Api.Fms.FundAccountRecord
type FundLedger = Api.Fms.FundLedgerRecord
type FundTransfer = Api.Fms.FundTransferRecord
type ReconciliationBatch = Api.Fms.BankReconciliationBatchRecord

async function enrichFundAccounts(rows: FundAccount[]): Promise<FundAccount[]> {
  if (!rows.length) return rows
  const accountSetIds = [...new Set(rows.map((row) => row.accountSetId))]
  const currencyIds = [...new Set(rows.map((row) => row.currencyId))]
  const [accountSets, currencies] = await Promise.all([
    responseHandle<Api.Fms.AccountSetRecord[]>(
      () =>
        supabase
          .from('fms_account_set')
          .select('id, account_set_code, account_set_name')
          .in('id', accountSetIds),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<Api.Fms.CurrencyRecord[]>(
      () =>
        supabase
          .from('fms_currency')
          .select('id, currency_code, currency_name, symbol')
          .in('id', currencyIds),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  const accountSetMap = new Map((accountSets.data ?? []).map((item) => [item.id, item]))
  const currencyMap = new Map((currencies.data ?? []).map((item) => [item.id, item]))
  return rows.map((row) => ({
    ...row,
    accountSet: accountSetMap.get(row.accountSetId) ?? null,
    currency: currencyMap.get(row.currencyId) ?? null
  }))
}

export async function fetchFundAccountList(params: Api.Fms.FundAccountSearchParams = {}) {
  const { accountSetId, accountType, from = 0, keyword, status, tenantId, to = 19 } = params
  let query = supabase
    .from('fms_fund_account_summary')
    .select('*', { count: 'exact' })
    .order('is_default', { ascending: false })
    .order('account_code')
    .range(from, to)
  if (tenantId) query = query.eq('tenant_id', tenantId)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (accountType) query = query.eq('account_type', accountType)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `account_code.ilike.%${value}%,account_name.ilike.%${value}%,bank_name.ilike.%${value}%,account_no_masked.ilike.%${value}%`
    )
  }
  const result = await responseHandle<FundAccount[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await enrichFundAccounts(result.data ?? []) }
}

export async function fetchFundAccountOptions(
  params: Api.Fms.FundAccountSearchParams & { baseCurrencyOnly?: boolean } = {}
) {
  const result = await fetchFundAccountList({ ...params, from: 0, to: 999 })
  let rows = result.data ?? []
  if (params.baseCurrencyOnly) {
    const accountSetIds = [...new Set(rows.map((row) => row.accountSetId))]
    const sets = await responseHandle<Api.Fms.AccountSetRecord[]>(
      () =>
        supabase.from('fms_account_set').select('id, base_currency_code').in('id', accountSetIds),
      { ignoreCheck: true, showErrorMessage: true }
    )
    const baseCodeMap = new Map((sets.data ?? []).map((item) => [item.id, item.baseCurrencyCode]))
    rows = rows.filter((row) => row.currency?.currencyCode === baseCodeMap.get(row.accountSetId))
  }
  return {
    ...result,
    data: rows.map<Api.Fms.FundAccountOption>((row) => ({
      label: `${row.accountName}（${row.accountNoMasked}）`,
      value: row.id,
      tenantId: row.tenantId,
      accountSetId: row.accountSetId,
      currencyId: row.currencyId,
      currencyCode: row.currency?.currencyCode,
      accountType: row.accountType,
      status: row.status,
      reconciliationEnabled: row.reconciliationEnabled,
      availableBalance: row.availableBalance
    }))
  }
}

export async function fetchFundAccountOverview(accountSetId?: string) {
  return await responseHandle<Api.Fms.FundAccountOverview>(
    () =>
      supabase
        .rpc('fms_fund_account_overview', { p_account_set_id: accountSetId || null })
        .single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveFundAccount(payload: Api.Fms.SaveFundAccountPayload) {
  return await responseHandle<FundAccount>(
    () => supabase.rpc('save_fms_fund_account', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资金账户已更新' : '资金账户已创建'
    }
  )
}

export async function deleteFundAccount(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_fund_account', { p_account_id: id }),
    { breakReturn: true, showMessage: true, message: '资金账户已删除' }
  )
}

function applyFundLedgerFilters<TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: Api.Fms.FundLedgerSearchParams
): TQuery {
  const { accountSetId, direction, entryDateRange, fundAccountId, keyword, sourceType, status } =
    params
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (fundAccountId) query = query.eq('fund_account_id', fundAccountId)
  if (direction) query = query.eq('direction', direction)
  if (sourceType) query = query.eq('source_type', sourceType)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `entry_no.ilike.%${value}%,source_no.ilike.%${value}%,summary.ilike.%${value}%,counterparty_name.ilike.%${value}%,bank_reference.ilike.%${value}%`
    )
  }
  return applyDateRange(query, 'entry_date', entryDateRange)
}

export async function fetchFundLedgerList(params: Api.Fms.FundLedgerSearchParams = {}) {
  const { from = 0, to = 19 } = params
  let query = supabase
    .from('fms_fund_ledger_entry')
    .select('*', { count: 'exact' })
    .order('entry_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyFundLedgerFilters(query, params)
  const result = await responseHandle<FundLedger[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const accountIds = [...new Set((result.data ?? []).map((row) => row.fundAccountId))]
  const accounts = accountIds.length
    ? await fetchFundAccountList({ from: 0, to: 999 })
    : { data: [] as FundAccount[] }
  const accountMap = new Map(
    (accounts.data ?? []).filter((row) => accountIds.includes(row.id)).map((row) => [row.id, row])
  )
  return {
    ...result,
    data: (result.data ?? []).map((row) => ({
      ...row,
      fundAccount: accountMap.get(row.fundAccountId) ?? null
    }))
  }
}

export async function fetchFundTransferList(params: Api.Fms.FundTransferSearchParams = {}) {
  const {
    accountSetId,
    from = 0,
    keyword,
    sourceAccountId,
    status,
    targetAccountId,
    to = 19
  } = params
  let query = supabase
    .from('fms_fund_transfer_summary')
    .select('*', { count: 'exact' })
    .order('transfer_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (sourceAccountId) query = query.eq('source_account_id', sourceAccountId)
  if (targetAccountId) query = query.eq('target_account_id', targetAccountId)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `transfer_no.ilike.%${value}%,purpose.ilike.%${value}%,bank_reference.ilike.%${value}%,source_account_name.ilike.%${value}%,target_account_name.ilike.%${value}%`
    )
  }
  query = applyDateRange(query, 'transfer_date', params.transferDateRange)
  return await responseHandle<FundTransfer[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchFundTransferActions(id: string) {
  return await responseHandle<Api.Fms.FundTransferActionRecord[]>(
    () =>
      supabase
        .from('fms_fund_transfer_action')
        .select('*')
        .eq('transfer_id', id)
        .order('action_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveFundTransfer(payload: Api.Fms.SaveFundTransferPayload) {
  return await responseHandle<FundTransfer>(
    () => supabase.rpc('save_fms_fund_transfer', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资金调拨单已更新' : '资金调拨单已创建'
    }
  )
}

export async function transitionFundTransfer(
  id: string,
  action: Exclude<Api.Fms.FundTransferAction, 'create' | 'edit'>,
  options: { reason?: string | null; executionDate?: string | null; version?: number } = {}
) {
  return await responseHandle<FundTransfer>(
    () =>
      supabase.rpc('transition_fms_fund_transfer', {
        p_transfer_id: id,
        p_action: action,
        p_remark: options.reason || null,
        p_execution_date: options.executionDate || null,
        p_expected_version: options.version ?? null
      }),
    { breakReturn: true, showMessage: true, message: '资金调拨状态已更新' }
  )
}

export async function deleteFundTransfer(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_fund_transfer', { p_transfer_id: id }),
    { breakReturn: true, showMessage: true, message: '资金调拨单已删除' }
  )
}

export async function fetchBankReconciliationList(
  params: Api.Fms.BankReconciliationSearchParams = {}
) {
  const { accountSetId, from = 0, fundAccountId, keyword, status, to = 19 } = params
  let query = supabase
    .from('fms_bank_reconciliation_batch_summary')
    .select('*', { count: 'exact' })
    .order('statement_end_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (fundAccountId) query = query.eq('fund_account_id', fundAccountId)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `batch_no.ilike.%${value}%,account_name.ilike.%${value}%,account_no_masked.ilike.%${value}%,imported_file_name.ilike.%${value}%`
    )
  }
  if (params.statementDateRange?.length === 2) {
    query = query
      .gte('statement_end_date', params.statementDateRange[0])
      .lte('statement_start_date', params.statementDateRange[1])
  }
  return await responseHandle<ReconciliationBatch[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchBankReconciliationDetail(id: string) {
  return await responseHandle<ReconciliationBatch>(
    () => supabase.from('fms_bank_reconciliation_batch_summary').select('*').eq('id', id).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchBankStatementLines(batchId: string) {
  return await responseHandle<Api.Fms.BankStatementLineRecord[]>(
    () =>
      supabase
        .from('fms_bank_statement_line_summary')
        .select('*')
        .eq('batch_id', batchId)
        .order('transaction_date')
        .order('line_no'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchBankStatementMatches(lineId: string) {
  return await responseHandle<Api.Fms.BankStatementMatchRecord[]>(
    () =>
      supabase
        .from('fms_bank_statement_match')
        .select('*, ledgerEntry:fms_fund_ledger_entry(*)')
        .eq('statement_line_id', lineId)
        .order('matched_at'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function importBankReconciliation(payload: Api.Fms.ImportBankReconciliationPayload) {
  return await responseHandle<ReconciliationBatch>(
    () => supabase.rpc('import_fms_bank_reconciliation', { p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '银行流水已导入' }
  )
}

export async function autoMatchBankReconciliation(id: string, toleranceDays = 3) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('auto_match_fms_bank_reconciliation', {
        p_batch_id: id,
        p_date_tolerance_days: toleranceDays
      }),
    { breakReturn: true, showMessage: true, message: '自动匹配已完成' }
  )
}

export async function matchBankStatementLine(
  lineId: string,
  ledgerEntryId: string,
  amount?: number,
  remark?: string | null
) {
  return await responseHandle<Api.Fms.BankStatementMatchRecord>(
    () =>
      supabase.rpc('match_fms_bank_statement_line', {
        p_statement_line_id: lineId,
        p_ledger_entry_id: ledgerEntryId,
        p_matched_amount: amount ?? null,
        p_remark: remark || null
      }),
    { breakReturn: true, showMessage: true, message: '银行流水已匹配' }
  )
}

export async function unmatchBankStatementLine(matchId: string) {
  return await responseHandle<string>(
    () => supabase.rpc('unmatch_fms_bank_statement_line', { p_match_id: matchId }),
    { breakReturn: true, showMessage: true, message: '匹配已撤销' }
  )
}

export async function ignoreBankStatementLine(lineId: string, reason: string) {
  return await responseHandle<Api.Fms.BankStatementLineRecord>(
    () =>
      supabase.rpc('ignore_fms_bank_statement_line', {
        p_statement_line_id: lineId,
        p_reason: reason
      }),
    { breakReturn: true, showMessage: true, message: '银行流水已忽略' }
  )
}

export async function transitionBankReconciliation(
  id: string,
  action: 'complete' | 'void',
  options: { reason?: string | null; version?: number } = {}
) {
  return await responseHandle<ReconciliationBatch>(
    () =>
      supabase.rpc('transition_fms_bank_reconciliation', {
        p_batch_id: id,
        p_action: action,
        p_reason: options.reason || null,
        p_expected_version: options.version ?? null
      }),
    { breakReturn: true, showMessage: true, message: '银行对账状态已更新' }
  )
}
