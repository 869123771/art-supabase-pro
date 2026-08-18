import { applyDateRange } from '@/api/providers/supabase/query'
import { useSupabase } from '@/hooks'

const { supabase, responseHandle } = useSupabase()

type Bill = Api.Fms.CommercialBillRecord

export async function fetchCommercialBillList(params: Api.Fms.CommercialBillSearchParams = {}) {
  const { accountSetId, billType, direction, from = 0, keyword, status, to = 19 } = params
  let query = supabase
    .from('fms_commercial_bill')
    .select('*', { count: 'exact' })
    .order('due_date')
    .order('create_time', { ascending: false })
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (direction) query = query.eq('direction', direction)
  if (billType) query = query.eq('bill_type', billType)
  if (status) query = query.eq('status', status)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `bill_no.ilike.%${value}%,external_bill_no.ilike.%${value}%,drawer_name.ilike.%${value}%,payee_name.ilike.%${value}%,acceptor_name.ilike.%${value}%,counterparty_name.ilike.%${value}%`
    )
  }
  query = applyDateRange(query, 'due_date', params.dueDateRange)
  return await responseHandle<Bill[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchCommercialBillEvents(billId: string) {
  return await responseHandle<Api.Fms.CommercialBillEventRecord[]>(
    () =>
      supabase
        .from('fms_commercial_bill_event')
        .select('*')
        .eq('bill_id', billId)
        .order('event_date')
        .order('create_time'),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchCommercialBillSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.CommercialBillSummary>(
    () =>
      supabase
        .rpc('fms_commercial_bill_summary', { p_account_set_id: accountSetId || null })
        .single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function saveCommercialBill(payload: Api.Fms.SaveCommercialBillPayload) {
  return await responseHandle<Bill>(
    () => supabase.rpc('save_fms_commercial_bill', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '票据草稿已更新' : '票据草稿已创建'
    }
  )
}

export async function deleteCommercialBill(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_commercial_bill', { p_bill_id: id }),
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
      supabase.rpc('act_fms_commercial_bill', {
        p_bill_id: id,
        p_action: action,
        p_payload: payload
      }),
    { breakReturn: true, showMessage: true, message: '票据状态已更新' }
  )
}
