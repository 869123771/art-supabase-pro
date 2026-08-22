import { useSupabase } from '@/hooks'
type Voucher = Api.Fms.SecureVoucherRecord
type VoucherSearchParams = Api.Fms.VoucherSearchParams
type VoucherTemplate = Api.Fms.VoucherTemplateRecord
type VoucherTemplateSearchParams = Api.Fms.VoucherTemplateSearchParams

interface VoucherListPayload {
  records: Voucher[]
  total: number
  fieldAccess?: Api.Fms.VoucherFieldAccessMap
}

interface VoucherTemplateListPayload {
  records?: VoucherTemplate[]
  total?: number
  fieldAccess?: Api.Fms.VoucherTemplateFieldAccessMap
}

const { supabase, responseHandle } = useSupabase()

function toVoucherListRpcParams(
  params: VoucherSearchParams & { ids?: string[] },
  purpose: 'list' | 'export'
) {
  const { accountSetId, from = 0, ids, keyword, sourceType, status, to = 19, voucherType } = params
  return {
    p_from: Math.max(from, 0),
    p_to: Math.max(to, from),
    p_account_set_id: accountSetId || null,
    p_status: status || null,
    p_voucher_type: voucherType || null,
    p_source_type: sourceType || null,
    p_keyword: keyword?.trim() || null,
    p_voucher_start_date: params.voucherDateRange?.[0] || null,
    p_voucher_end_date: params.voucherDateRange?.[1] || null,
    p_ids: ids?.length ? ids : null,
    p_purpose: purpose
  }
}

export async function fetchVoucherList(params: VoucherSearchParams) {
  const result = await responseHandle<VoucherListPayload>(
    () => supabase.rpc('fms_list_vouchers_secure', toVoucherListRpcParams(params, 'list')),
    { showErrorMessage: true }
  )
  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function exportVoucherList(
  params: VoucherSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const result = await responseHandle<VoucherListPayload>(
    () =>
      supabase.rpc(
        'fms_list_vouchers_secure',
        toVoucherListRpcParams(
          { ...params, ids, from: 0, to: Math.max(Math.min(maxRows, 10000) - 1, 0) },
          'export'
        )
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

export async function fetchVoucherDetail(id: string) {
  return await responseHandle<Voucher>(
    () => supabase.rpc('fms_get_voucher_secure', { p_voucher_id: id }),
    { breakReturn: true, showErrorMessage: true }
  )
}

export async function saveVoucher(payload: Api.Fms.SaveVoucherPayload) {
  return await responseHandle<Voucher>(
    () => supabase.rpc('save_fms_voucher_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '会计凭证已保存' : '会计凭证已创建'
    }
  )
}

export async function transitionVoucher(
  id: string,
  action: Exclude<Api.Fms.VoucherAction, 'create' | 'save' | 'reversal_create'>,
  reason?: string | null,
  actionDate?: string | null
) {
  const messageMap: Record<typeof action, string> = {
    submit: '凭证已提交审核',
    approve: '凭证已审核通过',
    reject: '凭证已驳回',
    post: '凭证已过账',
    void: '凭证已作废',
    reverse: '凭证已冲销并生成反向凭证'
  }
  return await responseHandle<Voucher>(
    () =>
      supabase.rpc('transition_fms_voucher_secure', {
        p_voucher_id: id,
        p_action: action,
        p_reason: reason || null,
        p_action_date: actionDate || null
      }),
    { breakReturn: true, showMessage: true, message: messageMap[action] }
  )
}

export async function fetchVoucherSummary(accountSetId: string) {
  return await responseHandle<Api.Fms.VoucherSummary>(
    () => supabase.rpc('fms_voucher_summary_secure', { p_account_set_id: accountSetId }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchVoucherTemplateList(params: VoucherTemplateSearchParams) {
  const { accountSetId, from = 0, isEnabled, keyword, to = 19, voucherType } = params
  const result = await responseHandle<VoucherTemplateListPayload>(
    () =>
      supabase.rpc('fms_list_voucher_templates_secure', {
        p_from: Math.max(from, 0),
        p_to: Math.max(to, from),
        p_account_set_id: accountSetId || null,
        p_voucher_type: voucherType || null,
        p_is_enabled: typeof isEnabled === 'boolean' ? isEnabled : null,
        p_keyword: keyword?.trim() || null
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

export async function fetchVoucherTemplateDetail(id: string) {
  return await responseHandle<VoucherTemplate>(
    () => supabase.rpc('fms_get_voucher_template_secure', { p_template_id: id }),
    { breakReturn: true, showErrorMessage: true }
  )
}

export async function saveVoucherTemplate(payload: Api.Fms.SaveVoucherTemplatePayload) {
  return await responseHandle<VoucherTemplate>(
    () => supabase.rpc('save_fms_voucher_template_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '凭证模板已更新' : '凭证模板已创建'
    }
  )
}

export async function deleteVoucherTemplate(id: string) {
  return await responseHandle<void>(
    () => supabase.rpc('delete_fms_voucher_template_secure', { p_template_id: id }),
    { breakReturn: true, showMessage: true, message: '凭证模板已删除' }
  )
}
