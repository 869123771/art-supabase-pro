import { applyDateRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { useSupabase } from '@/hooks'

type PostingRule = Api.Fms.PostingRuleRecord
type PostingEvent = Api.Fms.PostingEventRecord

const { supabase, responseHandle } = useSupabase()

const POSTING_RULE_SELECT = `
  *,
  accountSet:fms_account_set(id, account_set_code, account_set_name)
`

const POSTING_EVENT_SELECT = `
  *,
  accountSet:fms_account_set(id, account_set_code, account_set_name),
  rule:fms_posting_rule(id, rule_code, rule_name),
  voucher:fms_voucher!fms_posting_event_voucher_id_fkey(id, voucher_no, status, total_debit)
`

function withSourceEvent<T extends { sourceType: string; eventCode: string }>(
  row: T
): T & {
  sourceEvent: string
} {
  return { ...row, sourceEvent: `${row.sourceType}:${row.eventCode}` }
}

export async function fetchPostingRuleList(params: Api.Fms.PostingRuleSearchParams) {
  const { accountSetId, from = 0, isEnabled, keyword, sourceEvent, to = 19 } = params
  let query = supabase
    .from('fms_posting_rule')
    .select(POSTING_RULE_SELECT, { count: 'exact' })
    .order('priority')
    .order('rule_code')
    .range(from, to)
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (typeof isEnabled === 'boolean') query = query.eq('is_enabled', isEnabled)
  if (sourceEvent) {
    const [sourceType, eventCode] = sourceEvent.split(':')
    query = query.eq('source_type', sourceType).eq('event_code', eventCode)
  }
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `rule_code.ilike.%${value}%,rule_name.ilike.%${value}%,remark.ilike.%${value}%`
    )
  }
  const result = await responseHandle<PostingRule[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: (result.data ?? []).map(withSourceEvent) }
}

export async function fetchPostingRuleDetail(id: string) {
  const [ruleResult, lineResult] = await Promise.all([
    responseHandle<PostingRule>(
      () => supabase.from('fms_posting_rule').select(POSTING_RULE_SELECT).eq('id', id).single(),
      { breakReturn: true, showErrorMessage: true }
    ),
    responseHandle<Api.Fms.PostingRuleLineRecord[]>(
      () =>
        supabase
          .from('fms_posting_rule_line')
          .select('*, subject:fms_subject(id, subject_code, subject_name)')
          .eq('rule_id', id)
          .order('line_no'),
      { ignoreCheck: true, showErrorMessage: true }
    )
  ])
  return {
    data: ruleResult.data
      ? { ...withSourceEvent(ruleResult.data), lines: lineResult.data ?? [] }
      : undefined
  }
}

export async function savePostingRule(payload: Api.Fms.SavePostingRulePayload) {
  return await responseHandle<PostingRule>(
    () => supabase.rpc('save_fms_posting_rule', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '自动入账规则已更新' : '自动入账规则已创建'
    }
  )
}

export async function deletePostingRule(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_posting_rule', { p_rule_id: id }),
    { breakReturn: true, showMessage: true, message: '自动入账规则已删除' }
  )
}

function applyPostingEventFilters<TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: Api.Fms.PostingEventSearchParams
): TQuery {
  const { accountSetId, eventDateRange, keyword, sourceEvent, status } = params
  if (accountSetId) query = query.eq('account_set_id', accountSetId)
  if (status) query = query.eq('status', status)
  if (sourceEvent) {
    const [sourceType, eventCode] = sourceEvent.split(':')
    query = query.eq('source_type', sourceType).eq('event_code', eventCode)
  }
  if (keyword?.trim()) {
    const value = keyword.trim()
    query = query.or(
      `source_no.ilike.%${value}%,summary.ilike.%${value}%,last_error.ilike.%${value}%`
    )
  }
  return applyDateRange(query, 'event_date', eventDateRange)
}

export async function fetchPostingEventList(params: Api.Fms.PostingEventSearchParams) {
  const { from = 0, to = 19 } = params
  let query = supabase
    .from('fms_posting_event')
    .select(POSTING_EVENT_SELECT, { count: 'exact' })
    .order('event_date', { ascending: false })
    .order('create_time', { ascending: false })
    .range(from, to)
  query = applyPostingEventFilters(query, params)
  const result = await responseHandle<PostingEvent[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: (result.data ?? []).map(withSourceEvent) }
}

export async function fetchPostingEventDetail(id: string) {
  const result = await responseHandle<PostingEvent>(
    () => supabase.from('fms_posting_event').select(POSTING_EVENT_SELECT).eq('id', id).single(),
    { breakReturn: true, showErrorMessage: true }
  )
  return { ...result, data: result.data ? withSourceEvent(result.data) : undefined }
}

export async function retryPostingEvent(id: string) {
  return await responseHandle<PostingEvent>(
    () => supabase.rpc('retry_fms_posting_event', { p_event_id: id }),
    { breakReturn: true, showMessage: true, message: '自动入账事件已重新处理' }
  )
}

export async function processPendingPostingEvents(limit = 50) {
  return await responseHandle<Api.Fms.PostingEventProcessResult[]>(
    () => supabase.rpc('process_pending_fms_posting_events', { p_limit: limit }),
    { ignoreCheck: true, showMessage: true, message: '待处理事件批量处理完成' }
  )
}
