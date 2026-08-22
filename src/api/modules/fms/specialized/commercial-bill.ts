import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

type Bill = Api.Fms.CommercialBillRecord

interface CommercialBillListPayload {
  records: Bill[]
  total: number
  fieldAccess: Api.Fms.CommercialBillFieldAccessMap
}

export async function fetchCommercialBillList(params: Api.Fms.CommercialBillSearchParams = {}) {
  const { accountSetId, billType, direction, from = 0, keyword, status, to = 19 } = params
  const result = await responseHandle<CommercialBillListPayload>(
    () =>
      supabase.rpc('fms_list_commercial_bills_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_direction: direction || null,
        p_bill_type: billType || null,
        p_status: status || null,
        p_keyword: keyword?.trim() || null,
        p_due_start_date: params.dueDateRange?.[0] || null,
        p_due_end_date: params.dueDateRange?.[1] || null,
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

export async function fetchCommercialBillDetail(id: string) {
  return await responseHandle<Bill>(
    () => supabase.rpc('fms_get_commercial_bill_secure', { p_bill_id: id }),
    { showErrorMessage: true }
  )
}

export async function fetchCommercialBillEvents(billId: string) {
  return await responseHandle<Api.Fms.CommercialBillEventRecord[]>(
    () => supabase.rpc('fms_list_commercial_bill_events_secure', { p_bill_id: billId }),
    { showErrorMessage: true }
  )
}

export async function fetchCommercialBillSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.CommercialBillSummary>(
    () =>
      supabase.rpc('fms_commercial_bill_summary_secure', {
        p_account_set_id: accountSetId || null,
        p_tenant_id: null
      }),
    { showErrorMessage: true }
  )
}

export async function saveCommercialBill(payload: Api.Fms.SaveCommercialBillPayload) {
  return await responseHandle<Bill>(
    () => supabase.rpc('save_fms_commercial_bill_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '票据草稿已更新' : '票据草稿已创建'
    }
  )
}

export async function deleteCommercialBill(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_commercial_bill_secure', { p_bill_id: id }),
    { breakReturn: true, showMessage: true, message: '票据草稿已删除' }
  )
}

export async function actCommercialBill(
  id: string,
  action: Api.Fms.CommercialBillAction,
  payload: {
    amount?: number | null
    counterpartyName?: string | null
    eventDate?: string | null
    fundAccountId?: string | null
    referenceNo?: string | null
    remark?: string | null
  } = {}
) {
  return await responseHandle<Bill>(
    () =>
      supabase.rpc('act_fms_commercial_bill_secure', {
        p_bill_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '票据状态已更新' }
  )
}
