import { useSupabase } from '@/hooks'
import { fetchAccountSetIdentities } from '@/api/modules/fms/accounting/foundation'

const { supabase, responseHandle } = useSupabase()

type FundAccount = Api.Fms.FundAccountRecord
type FundLedger = Api.Fms.FundLedgerRecord
type FundTransfer = Api.Fms.FundTransferRecord
type ReconciliationBatch = Api.Fms.BankReconciliationBatchRecord

interface FundAccountListPayload {
  records?: FundAccount[]
  total?: number
  fieldAccess?: Api.Fms.FundAccountFieldAccessMap
}

interface BankReconciliationListPayload {
  records?: ReconciliationBatch[]
  total?: number
  fieldAccess?: Api.Fms.BankReconciliationFieldAccessMap
}

interface FundTransferListPayload {
  records?: FundTransfer[]
  total?: number
  fieldAccess?: Api.Fms.FundTransferFieldAccessMap
}

interface FundLedgerListPayload {
  records?: FundLedger[]
  total?: number
  fieldAccess?: Api.Fms.FundLedgerFieldAccessMap
}

interface BankStatementLineListPayload {
  records?: Api.Fms.BankStatementLineRecord[]
  fieldAccess?: Api.Fms.BankReconciliationFieldAccessMap
}

interface BankMatchCandidateListPayload {
  records?: Api.Fms.BankMatchCandidateRecord[]
  fieldAccess?: Api.Fms.BankReconciliationFieldAccessMap
}

type FundAccountOptionPayload = Omit<Api.Fms.FundAccountOption, 'label' | 'value'>

async function enrichFundAccounts(rows: FundAccount[]): Promise<FundAccount[]> {
  if (!rows.length) return rows
  const accountSetIds = [...new Set(rows.map((row) => row.accountSetId))]
  const currencyIds = [...new Set(rows.map((row) => row.currencyId))]
  const [accountSets, currencies] = await Promise.all([
    fetchAccountSetIdentities(accountSetIds),
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
  const result = await responseHandle<FundAccountListPayload>(
    () =>
      supabase.rpc('fms_list_fund_accounts_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_account_type: accountType || null,
        p_status: status || null,
        p_keyword: keyword?.trim() || null,
        p_tenant_id: tenantId || null
      }),
    { showErrorMessage: true }
  )
  return {
    data: await enrichFundAccounts(result.data?.records ?? []),
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchFundAccountOptions(
  params: Api.Fms.FundAccountSearchParams & { baseCurrencyOnly?: boolean } = {}
) {
  const result = await responseHandle<FundAccountOptionPayload[]>(
    () =>
      supabase.rpc('fms_list_fund_account_options_secure', {
        p_account_set_id: params.accountSetId || null,
        p_status: params.status || null,
        p_base_currency_only: params.baseCurrencyOnly ?? false
      }),
    { showErrorMessage: true }
  )
  return {
    ...result,
    data: (result.data ?? []).map<Api.Fms.FundAccountOption>((row) => ({
      ...row,
      label: row.accountNoMasked ? `${row.accountName}（${row.accountNoMasked}）` : row.accountName,
      value: row.id
    }))
  }
}

export async function fetchFundAccountOverview(accountSetId?: string) {
  return await responseHandle<Api.Fms.FundAccountOverview>(
    () =>
      supabase.rpc('fms_get_fund_account_overview_secure', {
        p_account_set_id: accountSetId || null
      }),
    { showErrorMessage: true }
  )
}

export async function saveFundAccount(payload: Api.Fms.SaveFundAccountPayload) {
  return await responseHandle<FundAccount>(
    () => supabase.rpc('save_fms_fund_account_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '资金账户已更新' : '资金账户已创建'
    }
  )
}

export async function deleteFundAccount(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_fund_account_secure', { p_account_id: id }),
    { breakReturn: true, showMessage: true, message: '资金账户已删除' }
  )
}

export async function fetchFundLedgerList(params: Api.Fms.FundLedgerSearchParams = {}) {
  const { from = 0, to = 19 } = params
  const result = await responseHandle<FundLedgerListPayload>(
    () =>
      supabase.rpc('fms_list_fund_ledger_entries_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: params.accountSetId || null,
        p_fund_account_id: params.fundAccountId || null,
        p_direction: params.direction || null,
        p_source_type: params.sourceType || null,
        p_status: params.status || null,
        p_keyword: params.keyword?.trim() || null,
        p_entry_start_date: params.entryDateRange?.[0] || null,
        p_entry_end_date: params.entryDateRange?.[1] || null,
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
  const result = await responseHandle<FundTransferListPayload>(
    () =>
      supabase.rpc('fms_list_fund_transfers_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_source_account_id: sourceAccountId || null,
        p_target_account_id: targetAccountId || null,
        p_status: status || null,
        p_keyword: keyword?.trim() || null,
        p_transfer_start_date: params.transferDateRange?.[0] || null,
        p_transfer_end_date: params.transferDateRange?.[1] || null,
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

export async function fetchFundTransferDetail(id: string) {
  return await responseHandle<FundTransfer>(
    () => supabase.rpc('fms_get_fund_transfer_secure', { p_transfer_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchFundTransferActions(id: string) {
  return await responseHandle<Api.Fms.FundTransferActionRecord[]>(
    () => supabase.rpc('fms_list_fund_transfer_actions_secure', { p_transfer_id: id }),
    { showErrorMessage: true }
  )
}

export async function saveFundTransfer(payload: Api.Fms.SaveFundTransferPayload) {
  return await responseHandle<FundTransfer>(
    () => supabase.rpc('save_fms_fund_transfer_secure', { p_payload: payload }),
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
      supabase.rpc('transition_fms_fund_transfer_secure', {
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
    () => supabase.rpc('delete_fms_fund_transfer_secure', { p_transfer_id: id }),
    { breakReturn: true, showMessage: true, message: '资金调拨单已删除' }
  )
}

export async function fetchBankReconciliationList(
  params: Api.Fms.BankReconciliationSearchParams = {}
) {
  const { accountSetId, from = 0, fundAccountId, keyword, status, to = 19 } = params
  const result = await responseHandle<BankReconciliationListPayload>(
    () =>
      supabase.rpc('fms_list_bank_reconciliations_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_fund_account_id: fundAccountId || null,
        p_status: status || null,
        p_keyword: keyword?.trim() || null,
        p_statement_start_date: params.statementDateRange?.[0] || null,
        p_statement_end_date: params.statementDateRange?.[1] || null,
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

export async function fetchBankReconciliationDetail(id: string) {
  return await responseHandle<ReconciliationBatch>(
    () => supabase.rpc('fms_get_bank_reconciliation_secure', { p_batch_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchBankStatementLines(batchId: string) {
  const result = await responseHandle<BankStatementLineListPayload>(
    () => supabase.rpc('fms_list_bank_statement_lines_secure', { p_batch_id: batchId }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchBankStatementMatches(lineId: string) {
  return await responseHandle<Api.Fms.BankStatementMatchRecord[]>(
    () =>
      supabase.rpc('fms_list_bank_statement_matches_secure', {
        p_statement_line_id: lineId
      }),
    { showErrorMessage: true }
  )
}

export async function fetchBankMatchCandidates(lineId: string, toleranceDays = 30) {
  const result = await responseHandle<BankMatchCandidateListPayload>(
    () =>
      supabase.rpc('fms_list_bank_match_candidates_secure', {
        p_statement_line_id: lineId,
        p_date_tolerance_days: toleranceDays
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function importBankReconciliation(payload: Api.Fms.ImportBankReconciliationPayload) {
  return await responseHandle<ReconciliationBatch>(
    () => supabase.rpc('import_fms_bank_reconciliation_secure', { p_payload: payload }),
    { breakReturn: true, showMessage: true, message: '银行流水已导入' }
  )
}

export async function autoMatchBankReconciliation(id: string, toleranceDays = 3) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('auto_match_fms_bank_reconciliation_secure', {
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
      supabase.rpc('match_fms_bank_statement_line_secure', {
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
    () => supabase.rpc('unmatch_fms_bank_statement_line_secure', { p_match_id: matchId }),
    { breakReturn: true, showMessage: true, message: '匹配已撤销' }
  )
}

export async function ignoreBankStatementLine(lineId: string, reason: string) {
  return await responseHandle<Api.Fms.BankStatementLineRecord>(
    () =>
      supabase.rpc('ignore_fms_bank_statement_line_secure', {
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
      supabase.rpc('transition_fms_bank_reconciliation_secure', {
        p_batch_id: id,
        p_action: action,
        p_reason: options.reason || null,
        p_expected_version: options.version ?? null
      }),
    { breakReturn: true, showMessage: true, message: '银行对账状态已更新' }
  )
}
