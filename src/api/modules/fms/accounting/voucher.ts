import { useSupabase } from '@/hooks'
import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'

type Voucher = Api.Fms.VoucherRecord
type VoucherSearchParams = Api.Fms.VoucherSearchParams
type VoucherTemplate = Api.Fms.VoucherTemplateRecord
type VoucherTemplateSearchParams = Api.Fms.VoucherTemplateSearchParams

const { supabase, responseHandle } = useSupabase()

const VOUCHER_SELECT = `
  *,
  accountSet:fms_account_set(id, account_set_code, account_set_name, base_currency_code)
`

const VOUCHER_LINE_SELECT = `
  *,
  subject:fms_subject(
    id, subject_code, subject_name, balance_direction,
    allow_quantity, unit_name, allow_foreign_currency
  ),
  currency:fms_currency(id, currency_code, currency_name)
`

function applyVoucherFilters<TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: VoucherSearchParams
): TQuery {
  const { accountSetId, keyword, sourceType, status, voucherDateRange, voucherType } = params
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (status) query = query.eq('status', status)
  if (voucherType) query = query.eq('voucher_type', voucherType)
  if (sourceType) query = query.eq('source_type', sourceType)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `voucher_no.ilike.%${value}%,summary.ilike.%${value}%,source_no.ilike.%${value}%`
    )
  }
  return applyDateRange(query, 'voucher_date', voucherDateRange)
}

export async function fetchVoucherList(params: VoucherSearchParams) {
  const { from = 0, to = 19 } = params
  let query = supabase
    .from('fms_voucher')
    .select(VOUCHER_SELECT, { count: 'exact' })
    .order('voucher_date', { ascending: false })
    .order('voucher_no', { ascending: false })
    .range(from, to)
  query = applyVoucherFilters(query, params)
  return await responseHandle<Voucher[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportVoucherList(
  params: VoucherSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('fms_voucher')
    .select(VOUCHER_SELECT)
    .order('voucher_date', { ascending: false })
    .order('voucher_no', { ascending: false })
    .limit(maxRows)
  query = ids?.length ? query.in('id', ids) : applyVoucherFilters(query, params)
  return await responseHandle<Voucher[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVoucherDetail(id: string) {
  const [voucherResult, lineResult, actionResult] = await Promise.all([
    responseHandle<Voucher>(
      () => supabase.from('fms_voucher').select(VOUCHER_SELECT).eq('id', id).single(),
      { breakReturn: true, showErrorMessage: true }
    ),
    responseHandle<Api.Fms.VoucherLineRecord[]>(
      () =>
        supabase
          .from('fms_voucher_line')
          .select(VOUCHER_LINE_SELECT)
          .eq('voucher_id', id)
          .order('line_no'),
      { ignoreCheck: true, showErrorMessage: true }
    ),
    responseHandle<Api.Fms.VoucherActionRecord[]>(
      () =>
        supabase.from('fms_voucher_action').select('*').eq('voucher_id', id).order('action_time'),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: voucherResult.data
      ? {
          ...voucherResult.data,
          lines: lineResult.data ?? [],
          actions: actionResult.data ?? []
        }
      : undefined
  }
}

export async function saveVoucher(payload: Api.Fms.SaveVoucherPayload) {
  return await responseHandle<Voucher>(
    () => supabase.rpc('save_fms_voucher', { p_payload: payload }),
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
      supabase.rpc('transition_fms_voucher', {
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
    () => supabase.rpc('fms_voucher_summary', { p_account_set_id: accountSetId }).single(),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function fetchVoucherTemplateList(params: VoucherTemplateSearchParams) {
  const { accountSetId, from = 0, isEnabled, keyword, to = 19, voucherType } = params
  let query = supabase
    .from('fms_voucher_template')
    .select('*', { count: 'exact' })
    .order('sort')
    .order('template_code')
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (voucherType) query = query.eq('voucher_type', voucherType)
  if (typeof isEnabled === 'boolean') query = query.eq('is_enabled', isEnabled)
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `template_code.ilike.%${value}%,template_name.ilike.%${value}%,summary.ilike.%${value}%`
    )
  }
  return await responseHandle<VoucherTemplate[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchVoucherTemplateDetail(id: string) {
  const [templateResult, lineResult] = await Promise.all([
    responseHandle<VoucherTemplate>(
      () => supabase.from('fms_voucher_template').select('*').eq('id', id).single(),
      { breakReturn: true, showErrorMessage: true }
    ),
    responseHandle<Api.Fms.VoucherTemplateLineRecord[]>(
      () =>
        supabase
          .from('fms_voucher_template_line')
          .select(
            '*, subject:fms_subject(id, subject_code, subject_name), currency:fms_currency(id, currency_code, currency_name)'
          )
          .eq('template_id', id)
          .order('line_no'),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: templateResult.data ? { ...templateResult.data, lines: lineResult.data ?? [] } : undefined
  }
}

export async function saveVoucherTemplate(payload: Api.Fms.SaveVoucherTemplatePayload) {
  return await responseHandle<VoucherTemplate>(
    () => supabase.rpc('save_fms_voucher_template', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '凭证模板已更新' : '凭证模板已创建'
    }
  )
}

export async function deleteVoucherTemplate(id: string) {
  return await responseHandle<void>(
    () => supabase.rpc('delete_fms_voucher_template', { p_template_id: id }),
    { breakReturn: true, showMessage: true, message: '凭证模板已删除' }
  )
}
