import { useSupabase } from '@/hooks'
import { startWorkflow } from '@/api/workflow'

type PaymentApplication = Api.Fms.CarrierPaymentApplicationRecord
type SearchParams = Api.Fms.CarrierPaymentApplicationSearchParams
type SavePayload = Api.Fms.SaveCarrierPaymentApplicationPayload
type ExecutePayload = Api.Fms.ExecuteCarrierPaymentApplicationPayload

interface SecureListPayload {
  records: PaymentApplication[]
  total: number
  fieldAccess?: Api.Fms.CarrierPaymentApplicationFieldAccessMap
}

const { supabase, responseHandle } = useSupabase()

const toListRpcParams = (
  params: SearchParams & { ids?: string[]; maxRows?: number },
  purpose: 'list' | 'export'
) => {
  const from = purpose === 'export' ? 0 : Math.max(params.from ?? 0, 0)
  const requestedTo = purpose === 'export' ? Math.max((params.maxRows ?? 10000) - 1, 0) : params.to
  return {
    p_from: from,
    p_to: Math.max(requestedTo ?? 9, from),
    p_carrier_id: params.carrierId || null,
    p_status: params.status || null,
    p_record_id: params.recordId || null,
    p_planned_payment_date_start: params.plannedPaymentDateRange?.[0] || null,
    p_planned_payment_date_end: params.plannedPaymentDateRange?.[1] || null,
    p_keyword: String(params.keyword ?? '').trim() || null,
    p_ids: params.ids?.length ? params.ids : null,
    p_purpose: purpose
  }
}

export async function fetchCarrierPaymentApplicationList(params: SearchParams) {
  const result = await responseHandle<SecureListPayload>(
    () =>
      supabase.rpc('tms_list_carrier_payment_applications_secure', toListRpcParams(params, 'list')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportCarrierPaymentApplicationList(
  params: SearchParams & { ids?: string[]; maxRows?: number }
) {
  const result = await responseHandle<SecureListPayload>(
    () =>
      supabase.rpc(
        'tms_list_carrier_payment_applications_secure',
        toListRpcParams(params, 'export')
      ),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchCarrierPaymentApplicationDetail(id: string) {
  return await responseHandle<PaymentApplication | null>(
    () => supabase.rpc('tms_get_carrier_payment_application_secure', { p_id: id }),
    { showErrorMessage: true }
  )
}

export async function saveCarrierPaymentApplication(params: SavePayload) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('save_tms_carrier_payment_application_secure', {
        p_application_id: params.id || null,
        p_carrier_id: params.carrierId,
        p_planned_payment_date: params.plannedPaymentDate,
        p_amount: params.amount,
        p_payment_method: params.paymentMethod,
        p_basis_urls: params.basisUrls ?? [],
        p_remark: params.remark || null,
        p_allocations: params.allocations,
        p_application_no: params.applicationNo || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function submitCarrierPaymentApplication(row: PaymentApplication) {
  await responseHandle<boolean>(
    () =>
      supabase.rpc('validate_tms_carrier_payment_application_submission_secure', {
        p_application_id: row.id
      }),
    { breakReturn: true, showErrorMessage: true }
  )
  const amount = Number(row.amount)
  if (!Number.isFinite(amount)) throw new Error('当前字段权限不足，无法提交付款金额审批')
  return await startWorkflow({
    businessType: 'tms_carrier_payment_application',
    businessId: row.id,
    businessTitle: `承运商付款申请 ${row.applicationNo} · ${row.carrierName}`,
    context: {
      amount,
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
      supabase.rpc('execute_fms_carrier_payment_application_secure', {
        p_application_id: params.applicationId,
        p_fund_account_id: params.fundAccountId,
        p_transaction_date: params.transactionDate,
        p_bank_reference: params.bankReference || null,
        p_voucher_urls: params.voucherUrls ?? [],
        p_transaction_no: params.transactionNo || null
      }),
    { showMessage: true, breakReturn: true, message: '付款已登记并完成自动核销' }
  )
}

export async function cancelCarrierPaymentApplication(id: string, reason: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('cancel_tms_carrier_payment_application_secure', {
        p_application_id: id,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true, message: '付款申请已取消' }
  )
}

export async function deleteCarrierPaymentApplication(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_tms_carrier_payment_application_secure', { p_application_id: id }),
    { showMessage: true, breakReturn: true }
  )
}
