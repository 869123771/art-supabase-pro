import { normalizeSupabaseFunctionError } from '@/utils/supabase'
import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'

type CashTransaction = Api.Fms.CashTransactionRecord
type CashTransactionSearchParams = Api.Fms.CashTransactionSearchParams
type AllocatableStatement = Api.Fms.CustomerStatementAllocatable
type AllocatableStatementSearchParams = Api.Fms.CustomerStatementAllocatableSearchParams
type CreateReceiptPayload = Api.Fms.CreateCustomerReceiptPayload
type AllocateReceiptPayload = Api.Fms.AllocateCustomerReceiptPayload
type CarrierAllocatableStatement = Api.Fms.CarrierStatementAllocatable
type CarrierAllocatableSearchParams = Api.Fms.CarrierStatementAllocatableSearchParams
type CreateCarrierPaymentPayload = Api.Fms.CreateCarrierPaymentPayload
type AllocateCarrierPaymentPayload = Api.Fms.AllocateCarrierPaymentPayload

interface SecureAllocatablePayload<TRecord> {
  records: TRecord[]
  total: number
  fieldAccess?: Api.Fms.CashTransactionFieldAccessMap
}

const { supabase, responseHandle } = useSupabase()

const toCashListRpcParams = (
  params: CashTransactionSearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_direction: params.direction || null,
    p_status: params.status || null,
    p_customer_id: params.customerId || null,
    p_carrier_id: params.carrierId || null,
    p_record_id: params.recordId || null,
    p_transaction_date_start: params.dateRange?.[0] || null,
    p_transaction_date_end: params.dateRange?.[1] || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchCashTransactionList(params: CashTransactionSearchParams) {
  const result = await responseHandle<SecureAllocatablePayload<CashTransaction>>(
    () => supabase.rpc('tms_list_cash_transactions_secure', toCashListRpcParams(params, 'list')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCashTransactionList(
  params: CashTransactionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureAllocatablePayload<CashTransaction>>(
    () => supabase.rpc('tms_list_cash_transactions_secure', toCashListRpcParams(params, 'export')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCustomerStatementAllocatableList(
  params: AllocatableStatementSearchParams
) {
  const { customerId, from = 0, keyword, to = 9 } = params
  const result = await responseHandle<SecureAllocatablePayload<AllocatableStatement>>(
    () =>
      supabase.rpc('tms_list_customer_statement_allocatable_secure', {
        p_customer_id: customerId,
        p_keyword: String(keyword ?? '').trim() || null,
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from)
      }),
    {
      showErrorMessage: true
    }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

export async function fetchCarrierStatementAllocatableList(params: CarrierAllocatableSearchParams) {
  const { carrierId, from = 0, keyword, to = 9 } = params
  const result = await responseHandle<SecureAllocatablePayload<CarrierAllocatableStatement>>(
    () =>
      supabase.rpc('tms_list_carrier_statement_allocatable_secure', {
        p_carrier_id: carrierId,
        p_keyword: String(keyword ?? '').trim() || null,
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from)
      }),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

export async function fetchCashTransactionDetail(id: string) {
  return await responseHandle<CashTransaction | null>(
    () => supabase.rpc('tms_get_cash_transaction_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function createCarrierPayment(params: CreateCarrierPaymentPayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_fms_carrier_payment_secure', {
        p_carrier_id: params.carrierId,
        p_fund_account_id: params.fundAccountId,
        p_transaction_date: params.transactionDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations,
        p_transaction_no: params.transactionNo || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function allocateCarrierPayment(params: AllocateCarrierPaymentPayload) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('allocate_tms_carrier_payment_secure', {
        p_transaction_id: params.transactionId,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function reverseCarrierCashAllocation(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('reverse_tms_carrier_cash_allocation_secure', {
        p_allocation_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function createCustomerReceipt(params: CreateReceiptPayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_fms_customer_receipt_secure', {
        p_customer_id: params.customerId,
        p_fund_account_id: params.fundAccountId,
        p_transaction_date: params.transactionDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations,
        p_transaction_no: params.transactionNo || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function allocateCustomerReceipt(params: AllocateReceiptPayload) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('allocate_tms_customer_receipt_secure', {
        p_transaction_id: params.transactionId,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function reverseCashAllocation(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('reverse_tms_cash_allocation_secure', {
        p_allocation_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function voidCashTransaction(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('void_tms_cash_transaction_secure', {
        p_transaction_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function analyzeCashVoucherByAi(
  params: Api.Fms.CashVoucherOcrAnalyzeRequest
): Promise<QueryResult<Api.Fms.CashVoucherOcrAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.CashVoucherOcrAnalyzeResponse>(
    'ai-cash-voucher-ocr',
    { body: params }
  )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}

export async function reviewCashVoucherOcrArtifact(
  params: Api.Fms.CashVoucherOcrReviewRequest
): Promise<QueryResult<Api.Fms.CashVoucherOcrReviewResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.CashVoucherOcrReviewResponse>(
    'ai-cash-voucher-ocr',
    { body: params }
  )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}

export async function analyzeBankStatementBatchByAi(params: {
  rows: Array<Record<string, unknown>>
  fileName: string
}): Promise<QueryResult<Api.Fms.BankBatchAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.BankBatchAnalyzeResponse>(
    'ai-bank-statement-batch-match',
    { body: { action: 'analyze', ...params } }
  )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}

export async function commitBankStatementBatchByAi(params: {
  artifactId: string
  rows: Api.Fms.BankBatchMatchRow[]
}): Promise<QueryResult<Api.Fms.BankBatchCommitResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Fms.BankBatchCommitResponse>(
    'ai-bank-statement-batch-match',
    { body: { action: 'commit', ...params } }
  )
  return { data: data ?? null, error: await normalizeSupabaseFunctionError(error) }
}
