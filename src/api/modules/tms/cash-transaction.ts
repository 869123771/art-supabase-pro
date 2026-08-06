import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'

type CashTransaction = Api.Tms.Finance.CashTransactionRecord
type CashTransactionSearchParams = Api.Tms.Finance.CashTransactionSearchParams
type AllocatableStatement = Api.Tms.Finance.CustomerStatementAllocatable
type AllocatableStatementSearchParams = Api.Tms.Finance.CustomerStatementAllocatableSearchParams
type CashAllocation = Api.Tms.Finance.CashAllocationRecord
type CreateReceiptPayload = Api.Tms.Finance.CreateCustomerReceiptPayload
type AllocateReceiptPayload = Api.Tms.Finance.AllocateCustomerReceiptPayload
type CarrierAllocatableStatement = Api.Tms.Finance.CarrierStatementAllocatable
type CarrierAllocatableSearchParams = Api.Tms.Finance.CarrierStatementAllocatableSearchParams
type CarrierCashAllocation = Api.Tms.Finance.CarrierCashAllocationRecord
type CreateCarrierPaymentPayload = Api.Tms.Finance.CreateCarrierPaymentPayload
type AllocateCarrierPaymentPayload = Api.Tms.Finance.AllocateCarrierPaymentPayload

const { supabase, responseHandle } = useSupabase()

const CASH_ALLOCATION_SELECT = `
  *,
  statement:tms_customer_statement!tms_cash_allocation_statement_id_fkey(
    id,
    statement_no,
    customer_id,
    customer_name_snapshot,
    period_start,
    period_end,
    status,
    settled_amount
  )
`

const CARRIER_CASH_ALLOCATION_SELECT = `
  *,
  statement:tms_carrier_statement!tms_carrier_cash_allocation_statement_id_fkey(
    id,
    statement_no,
    carrier_id,
    carrier_name_snapshot,
    period_start,
    period_end,
    status,
    settled_amount
  )
`

const applyTransactionFilters = (
  query: SupabaseQueryLike,
  params: CashTransactionSearchParams
): SupabaseQueryLike => {
  const { carrierId, customerId, dateRange, direction, keyword, status } = params
  if (customerId) query = query.eq('customer_id', customerId)
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (direction) query = query.eq('direction', direction)
  if (status) query = query.eq('status', status)
  if (keyword) {
    query = query.or(
      `transaction_no.ilike.%${keyword}%,counterparty_name.ilike.%${keyword}%,bank_reference.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, 'transaction_date', dateRange)
}

export async function fetchCashTransactionList(params: CashTransactionSearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_cash_transaction_summary')
    .select('*', { count: 'exact' })
    .order('transaction_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyTransactionFilters(query, params)
  return await responseHandle<CashTransaction[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCashTransactionList(
  params: CashTransactionSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_cash_transaction_summary')
    .select('*')
    .order('transaction_date', { ascending: false })
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyTransactionFilters(query, params)
  return await responseHandle<CashTransaction[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCustomerStatementAllocatableList(
  params: AllocatableStatementSearchParams
) {
  const { customerId, from = 0, keyword, to = 9 } = params
  let query = supabase
    .from('tms_customer_statement_allocatable')
    .select('*', { count: 'exact' })
    .eq('customer_id', customerId)
    .order('period_end', { ascending: true })
    .order('create_time', { ascending: true })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) {
    query = query.or(`statement_no.ilike.%${keyword}%,customer_name.ilike.%${keyword}%`)
  }
  return await responseHandle<AllocatableStatement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierStatementAllocatableList(params: CarrierAllocatableSearchParams) {
  const { carrierId, from = 0, keyword, to = 9 } = params
  let query = supabase
    .from('tms_carrier_statement_allocatable')
    .select('*', { count: 'exact' })
    .eq('carrier_id', carrierId)
    .order('period_end', { ascending: true })
    .order('create_time', { ascending: true })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) query = query.or(`statement_no.ilike.%${keyword}%,carrier_name.ilike.%${keyword}%`)
  return await responseHandle<CarrierAllocatableStatement[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCashTransactionDetail(id: string) {
  const transactionResponse = await responseHandle<CashTransaction>(
    () => supabase.from('tms_cash_transaction_summary').select('*').eq('id', id).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
  const allocationResponse =
    transactionResponse.data?.direction === 'payment'
      ? await responseHandle<CarrierCashAllocation[]>(
          () =>
            supabase
              .from('tms_carrier_cash_allocation')
              .select(CARRIER_CASH_ALLOCATION_SELECT)
              .eq('transaction_id', id)
              .order('create_time', { ascending: false }),
          { ignoreCheck: true, showErrorMessage: true }
        )
      : await responseHandle<CashAllocation[]>(
          () =>
            supabase
              .from('tms_cash_allocation')
              .select(CASH_ALLOCATION_SELECT)
              .eq('transaction_id', id)
              .order('create_time', { ascending: false }),
          { ignoreCheck: true, showErrorMessage: true }
        )
  return {
    data: transactionResponse.data
      ? { ...transactionResponse.data, allocations: allocationResponse.data ?? [] }
      : undefined
  }
}

export async function createCarrierPayment(params: CreateCarrierPaymentPayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_tms_carrier_payment', {
        p_carrier_id: params.carrierId,
        p_transaction_date: params.transactionDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function allocateCarrierPayment(params: AllocateCarrierPaymentPayload) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('allocate_tms_carrier_payment', {
        p_transaction_id: params.transactionId,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function reverseCarrierCashAllocation(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('reverse_tms_carrier_cash_allocation', {
        p_allocation_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function createCustomerReceipt(params: CreateReceiptPayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('create_tms_customer_receipt', {
        p_customer_id: params.customerId,
        p_transaction_date: params.transactionDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function allocateCustomerReceipt(params: AllocateReceiptPayload) {
  return await responseHandle<number>(
    () =>
      supabase.rpc('allocate_tms_customer_receipt', {
        p_transaction_id: params.transactionId,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function reverseCashAllocation(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('reverse_tms_cash_allocation', {
        p_allocation_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function voidCashTransaction(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('void_tms_cash_transaction', {
        p_transaction_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function analyzeCashVoucherByAi(
  params: Api.Tms.Finance.CashVoucherOcrAnalyzeRequest
): Promise<QueryResult<Api.Tms.Finance.CashVoucherOcrAnalyzeResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.CashVoucherOcrAnalyzeResponse>(
      'ai-cash-voucher-ocr',
      { body: params }
    )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

export async function reviewCashVoucherOcrArtifact(
  params: Api.Tms.Finance.CashVoucherOcrReviewRequest
): Promise<QueryResult<Api.Tms.Finance.CashVoucherOcrReviewResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Finance.CashVoucherOcrReviewResponse>(
      'ai-cash-voucher-ocr',
      { body: params }
    )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

export async function analyzeBankStatementBatchByAi(params: {
  rows: Array<Record<string, unknown>>
  fileName: string
}): Promise<QueryResult<Api.Tms.Finance.BankBatchAnalyzeResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Finance.BankBatchAnalyzeResponse>(
    'ai-bank-statement-batch-match',
    { body: { action: 'analyze', ...params } }
  )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

export async function commitBankStatementBatchByAi(params: {
  artifactId: string
  rows: Api.Tms.Finance.BankBatchMatchRow[]
}): Promise<QueryResult<Api.Tms.Finance.BankBatchCommitResponse>> {
  const { data, error } = await supabase.functions.invoke<Api.Tms.Finance.BankBatchCommitResponse>(
    'ai-bank-statement-batch-match',
    { body: { action: 'commit', ...params } }
  )
  return { data: data ?? null, error: await normalizeFunctionInvokeError(error) }
}

async function normalizeFunctionInvokeError(error: unknown): Promise<unknown | null> {
  if (!error || typeof error !== 'object' || !('context' in error)) return error
  const context = (error as { context?: unknown }).context
  if (!(context instanceof Response)) return error
  try {
    const payload = (await context.clone().json()) as { code?: unknown; message?: unknown }
    if (typeof payload.message !== 'string' || !payload.message) return error
    return {
      code: typeof payload.code === 'string' ? payload.code : undefined,
      message: payload.message
    }
  } catch {
    return error
  }
}
