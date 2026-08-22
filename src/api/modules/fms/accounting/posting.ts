import { useSupabase } from '@/hooks'

type PostingRule = Api.Fms.SecurePostingRuleRecord
type PostingEvent = Api.Fms.SecurePostingEventRecord

interface PostingListPayload<TRecord> {
  records?: TRecord[]
  total?: number
  fieldAccess?: Api.Fms.AutoPostingFieldAccessMap
}

const { supabase, responseHandle } = useSupabase()

export async function fetchAccountingWorkloadSummary(accountSetId?: string) {
  return await responseHandle<Api.Fms.AccountingWorkloadSummary>(
    () =>
      supabase.rpc('fms_accounting_workload_summary_secure', {
        p_account_set_id: accountSetId || null
      }),
    { breakReturn: true, showErrorMessage: true }
  )
}

function withSourceEvent<T extends { sourceType: string; eventCode: string }>(
  row: T
): T & {
  sourceEvent: string
} {
  return { ...row, sourceEvent: `${row.sourceType}:${row.eventCode}` }
}

export async function fetchPostingRuleList(params: Api.Fms.PostingRuleSearchParams) {
  const { accountSetId, from = 0, isEnabled, keyword, sourceEvent, to = 19 } = params
  const [sourceType, eventCode] = sourceEvent ? sourceEvent.split(':') : []
  const result = await responseHandle<PostingListPayload<PostingRule>>(
    () =>
      supabase.rpc('fms_list_posting_rules_secure', {
        p_from: from,
        p_to: to,
        p_account_set_id: accountSetId || null,
        p_source_type: sourceType || null,
        p_event_code: eventCode || null,
        p_is_enabled: typeof isEnabled === 'boolean' ? isEnabled : null,
        p_keyword: keyword?.trim() || null
      }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
  return {
    ...result,
    data: (result.data?.records ?? []).map(withSourceEvent),
    total: result.data?.total ?? 0,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchPostingRuleDetail(id: string) {
  const result = await responseHandle<PostingRule>(
    () => supabase.rpc('fms_get_posting_rule_secure', { p_rule_id: id }),
    { breakReturn: true, showErrorMessage: true }
  )
  return { ...result, data: result.data ? withSourceEvent(result.data) : undefined }
}

export async function savePostingRule(payload: Api.Fms.SavePostingRulePayload) {
  return await responseHandle<PostingRule>(
    () => supabase.rpc('save_fms_posting_rule_secure', { p_payload: payload }),
    {
      breakReturn: true,
      showMessage: true,
      message: payload.id ? '自动入账规则已更新' : '自动入账规则已创建'
    }
  )
}

export async function deletePostingRule(id: string) {
  return await responseHandle<string>(
    () => supabase.rpc('delete_fms_posting_rule_secure', { p_rule_id: id }),
    { breakReturn: true, showMessage: true, message: '自动入账规则已删除' }
  )
}

export async function fetchPostingEventList(params: Api.Fms.PostingEventSearchParams) {
  const { from = 0, to = 19 } = params
  const [sourceType, eventCode] = params.sourceEvent ? params.sourceEvent.split(':') : []
  const [dateFrom, dateTo] = params.eventDateRange ?? []
  const result = await responseHandle<PostingListPayload<PostingEvent>>(
    () =>
      supabase.rpc('fms_list_posting_events_secure', {
        p_from: from,
        p_to: to,
        p_account_set_id: params.accountSetId || null,
        p_status: params.status || null,
        p_source_type: sourceType || null,
        p_event_code: eventCode || null,
        p_date_from: dateFrom || null,
        p_date_to: dateTo || null,
        p_keyword: params.keyword?.trim() || null
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return {
    ...result,
    data: (result.data?.records ?? []).map(withSourceEvent),
    total: result.data?.total ?? 0,
    fieldAccess: result.data?.fieldAccess ?? {}
  }
}

export async function fetchPostingEventDetail(id: string) {
  const result = await responseHandle<PostingEvent>(
    () => supabase.rpc('fms_get_posting_event_secure', { p_event_id: id }),
    { breakReturn: true, showErrorMessage: true }
  )
  return { ...result, data: result.data ? withSourceEvent(result.data) : undefined }
}

export async function retryPostingEvent(id: string) {
  return await responseHandle<PostingEvent>(
    () => supabase.rpc('retry_fms_posting_event_secure', { p_event_id: id }),
    { breakReturn: true, showMessage: true, message: '自动入账事件已重新处理' }
  )
}

export async function processPendingPostingEvents(limit = 50) {
  return await responseHandle<Api.Fms.PostingEventProcessResult[]>(
    () => supabase.rpc('process_pending_fms_posting_events_secure', { p_limit: limit }),
    { ignoreCheck: true, showMessage: true, message: '待处理事件批量处理完成' }
  )
}
