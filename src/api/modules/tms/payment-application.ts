import { useSupabase } from '@/hooks'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { startWorkflow } from '@/api/workflow'

type PaymentApplication = Api.Tms.Finance.CarrierPaymentApplicationRecord
type PaymentApplicationItem = Api.Tms.Finance.CarrierPaymentApplicationItem
type SearchParams = Api.Tms.Finance.CarrierPaymentApplicationSearchParams
type SavePayload = Api.Tms.Finance.SaveCarrierPaymentApplicationPayload
type ExecutePayload = Api.Tms.Finance.ExecuteCarrierPaymentApplicationPayload

const { supabase, responseHandle } = useSupabase()

function applyFilters(query: SupabaseQueryLike, params: SearchParams): SupabaseQueryLike {
  const { carrierId, keyword, plannedPaymentDateRange, status } = params
  if (carrierId) query = query.eq('carrier_id', carrierId)
  if (status) query = query.eq('status', status)
  if (keyword) {
    query = query.or(
      `application_no.ilike.%${keyword}%,carrier_name.ilike.%${keyword}%,statement_nos.ilike.%${keyword}%,paid_transaction_no.ilike.%${keyword}%,remark.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, 'planned_payment_date', plannedPaymentDateRange)
}

export async function fetchCarrierPaymentApplicationList(params: SearchParams) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_carrier_payment_application_summary')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  query = applyFilters(query, params)
  return await responseHandle<PaymentApplication[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportCarrierPaymentApplicationList(
  params: SearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_carrier_payment_application_summary')
    .select('*')
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyFilters(query, params)
  return await responseHandle<PaymentApplication[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCarrierPaymentApplicationDetail(id: string) {
  const [applicationResponse, itemResponse] = await Promise.all([
    responseHandle<PaymentApplication>(
      () =>
        supabase.from('tms_carrier_payment_application_summary').select('*').eq('id', id).single(),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<PaymentApplicationItem[]>(
      () =>
        supabase
          .from('tms_carrier_payment_application_item')
          .select('*')
          .eq('application_id', id)
          .order('statement_no_snapshot'),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: applicationResponse.data
      ? { ...applicationResponse.data, items: itemResponse.data ?? [] }
      : undefined
  }
}

export async function saveCarrierPaymentApplication(params: SavePayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('save_tms_carrier_payment_application', {
        p_application_id: params.id || null,
        p_carrier_id: params.carrierId,
        p_planned_payment_date: params.plannedPaymentDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_basis_urls: params.basisUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function submitCarrierPaymentApplication(row: PaymentApplication) {
  await responseHandle<boolean>(
    () =>
      supabase.rpc('validate_tms_carrier_payment_application_submission', {
        p_application_id: row.id
      }),
    { breakReturn: true, showErrorMessage: true }
  )
  return await startWorkflow({
    businessType: 'tms_carrier_payment_application',
    businessId: row.id,
    businessTitle: `承运商付款申请 ${row.applicationNo} · ${row.carrierName}`,
    context: {
      amount: Number(row.amount),
      applicationNo: row.applicationNo,
      carrierId: row.carrierId,
      carrierName: row.carrierName,
      plannedPaymentDate: row.plannedPaymentDate,
      statementCount: row.statementCount
    }
  })
}

export async function executeCarrierPaymentApplication(params: ExecutePayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('execute_tms_carrier_payment_application', {
        p_application_id: params.applicationId,
        p_transaction_date: params.transactionDate,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? []
      }),
    { showMessage: true, breakReturn: true, message: '付款已登记并完成自动核销' }
  )
}

export async function cancelCarrierPaymentApplication(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('cancel_tms_carrier_payment_application', {
        p_application_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true, message: '付款申请已取消' }
  )
}

export async function deleteCarrierPaymentApplication(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_tms_carrier_payment_application', { p_application_id: id }),
    { showMessage: true, breakReturn: true }
  )
}
