import { omit } from 'lodash-es'
import { useSupabase } from '@/hooks'
import {
  applyDateRange,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type InspectionPlan = Api.Smis.InspectionControl.InspectionPlanRecord
type InspectionTask = Api.Smis.InspectionControl.InspectionTaskRecord
type InspectionTaskSearchParams = Api.Smis.InspectionControl.InspectionTaskSearchParams
type HiddenDanger = Api.Smis.InspectionControl.HiddenDangerRecord
type HiddenDangerSearchParams = Api.Smis.InspectionControl.HiddenDangerSearchParams
type HiddenDangerEvent = Api.Smis.InspectionControl.HiddenDangerEventRecord

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const riskPointRelation = `
  risk_point:smis_risk_point!smis_inspection_task_risk_point_tenant_fkey(
    id, risk_point_no, risk_point_name, current_risk_level, status,
    site:smis_site!smis_risk_point_site_tenant_fkey(id, site_name),
    area:smis_area!smis_risk_point_area_tenant_fkey(id, area_name)
  )
`

const taskSelect = `
  *,
  plan:smis_inspection_plan!smis_inspection_task_plan_tenant_fkey(id, plan_no, plan_name),
  ${riskPointRelation},
  inspector_user:sys_user!smis_inspection_task_inspector_tenant_fkey(
    id, user_name, nick_name, user_email
  ),
  result:smis_inspection_result!smis_inspection_result_task_tenant_fkey(*)
`

const dangerSelect = `
  *,
  task:smis_inspection_task!smis_hidden_danger_task_tenant_fkey(id, task_no, task_name),
  risk_point:smis_risk_point!smis_hidden_danger_risk_point_tenant_fkey(
    id, risk_point_no, risk_point_name, current_risk_level, status,
    site:smis_site!smis_risk_point_site_tenant_fkey(id, site_name),
    area:smis_area!smis_risk_point_area_tenant_fkey(id, area_name)
  ),
  hazard_source:smis_hazard_source!smis_hidden_danger_source_tenant_fkey(
    id, source_no, hazard_name
  ),
  responsible_user:sys_user!smis_hidden_danger_responsible_tenant_fkey(
    id, user_name, nick_name, user_email
  ),
  reviewer_user:sys_user!smis_hidden_danger_reviewer_tenant_fkey(
    id, user_name, nick_name, user_email
  )
`

const applyTaskFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: InspectionTaskSearchParams
): TQuery => {
  if (params.status) query = query.eq('status', params.status)
  if (params.riskPointId) query = query.eq('risk_point_id', params.riskPointId)
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim()
    query = query.or(`task_no.ilike.%${keyword}%,task_name.ilike.%${keyword}%`)
  }
  return applyDateRange(query, 'scheduled_start_at', params.scheduledTimeRange)
}

const applyDangerFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: HiddenDangerSearchParams
): TQuery => {
  if (params.status) query = query.eq('status', params.status)
  if (params.dangerLevel) query = query.eq('danger_level', params.dangerLevel)
  if (params.riskPointId) query = query.eq('risk_point_id', params.riskPointId)
  if (params.overdueOnly) {
    query = query
      .not('status', 'in', '(closed,cancelled)')
      .lt('rectification_deadline', new Date().toISOString())
  }
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim()
    query = query.or(
      `danger_no.ilike.%${keyword}%,danger_title.ilike.%${keyword}%,danger_description.ilike.%${keyword}%`
    )
  }
  return applyDateRange(query, 'reported_at', params.reportedTimeRange)
}

export async function fetchInspectionPlanOptions() {
  const query = supabase
    .from('smis_inspection_plan')
    .select('*')
    .in('status', ['draft', 'active'])
    .order('plan_no', { ascending: true })
    .limit(1000)
  return await responseHandle<InspectionPlan[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addInspectionPlan(params: InspectionPlan) {
  return await responseHandle<InspectionPlan>(
    () => supabase.from('smis_inspection_plan').insert(keysToSnakeDeep(params)).select().single(),
    { showMessage: true, message: '检查计划已新增', breakReturn: true }
  )
}

export async function editInspectionPlan(params: InspectionPlan) {
  const { id } = params
  const payload = omit(params, ['id', 'createTime', 'updateTime'])
  return await responseHandle(
    () => supabase.from('smis_inspection_plan').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: '检查计划已更新', breakReturn: true }
  )
}

export async function fetchInspectionTaskList(
  params: InspectionTaskSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('smis_inspection_task')
    .select(taskSelect, { count: 'exact' })
    .order('scheduled_start_at', { ascending: false })
    .range(from, to)
  query = applyTaskFilters(query, params)
  return await responseHandle<InspectionTask[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addInspectionTask(params: InspectionTask) {
  return await responseHandle<InspectionTask>(
    () =>
      supabase
        .from('smis_inspection_task')
        .insert(keysToSnakeDeep(params))
        .select(taskSelect)
        .single(),
    { showMessage: true, message: '检查任务已新增', breakReturn: true }
  )
}

export async function editInspectionTask(params: InspectionTask) {
  const { id } = params
  const payload = omit(params, [
    'id',
    'status',
    'startedAt',
    'completedAt',
    'cancelledAt',
    'cancellationReason',
    'createTime',
    'updateTime',
    'plan',
    'riskPoint',
    'inspectorUser',
    'result',
    'hiddenDangerCount'
  ])
  return await responseHandle(
    () => supabase.from('smis_inspection_task').update(keysToSnakeDeep(payload)).eq('id', id),
    { showMessage: true, message: '检查任务已更新', breakReturn: true }
  )
}

export async function deleteInspectionTask(id: string) {
  return await responseHandle(
    () => supabase.from('smis_inspection_task').delete({ count: 'exact' }).eq('id', id),
    { showMessage: true, message: '待执行任务已删除', breakReturn: true, requireAffected: true }
  )
}

export async function transitionInspectionTask(params: {
  id: string
  action: 'start' | 'complete' | 'cancel'
  checkResult?: Api.Smis.InspectionControl.InspectionResult | null
  resultSummary?: string | null
  attachmentRefs?: Api.Smis.InspectionControl.AttachmentRef[]
  comment?: string | null
}) {
  return await responseHandle<InspectionTask>(
    () =>
      supabase.rpc('smis_transition_inspection_task', {
        p_task_id: params.id,
        p_action: params.action,
        p_check_result: params.checkResult || null,
        p_result_summary: params.resultSummary || null,
        p_attachment_refs: params.attachmentRefs ?? [],
        p_comment: params.comment || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchHiddenDangerList(
  params: HiddenDangerSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('smis_hidden_danger')
    .select(dangerSelect, { count: 'exact' })
    .order('reported_at', { ascending: false })
    .range(from, to)
  query = applyDangerFilters(query, params)
  return await responseHandle<HiddenDanger[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addHiddenDanger(params: HiddenDanger) {
  const payload = omit(params, [
    'id',
    'status',
    'reportedAt',
    'rectificationSubmittedAt',
    'closedAt',
    'cancelledAt',
    'createTime',
    'updateTime',
    'task',
    'riskPoint',
    'hazardSource',
    'responsibleUser',
    'reviewerUser'
  ])
  return await responseHandle<HiddenDanger>(
    () =>
      supabase
        .from('smis_hidden_danger')
        .insert(keysToSnakeDeep(payload))
        .select(dangerSelect)
        .single(),
    { showMessage: true, message: '隐患已上报', breakReturn: true }
  )
}

export async function transitionHiddenDanger(params: {
  id: string
  action: Api.Smis.InspectionControl.HiddenDangerAction
  responsibleUserId?: string | null
  rectificationDeadline?: string | null
  comment?: string | null
  attachmentRefs?: Api.Smis.InspectionControl.AttachmentRef[]
}) {
  return await responseHandle<HiddenDanger>(
    () =>
      supabase.rpc('smis_transition_hidden_danger', {
        p_hidden_danger_id: params.id,
        p_action: params.action,
        p_responsible_user_id: params.responsibleUserId || null,
        p_rectification_deadline: params.rectificationDeadline || null,
        p_comment: params.comment || null,
        p_attachment_refs: params.attachmentRefs ?? []
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function startHiddenDangerWorkflow(hiddenDangerId: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('smis_start_hidden_danger_workflow', {
        p_hidden_danger_id: hiddenDangerId
      }),
    { showMessage: true, message: '隐患复查审批已发起', breakReturn: true }
  )
}

export async function fetchHiddenDangerEventList(hiddenDangerId: string) {
  const query = supabase
    .from('smis_hidden_danger_event')
    .select(
      `
      *,
      actor_user:sys_user!smis_hidden_danger_event_actor_tenant_fkey(
        id, user_name, nick_name, user_email
      )
    `
    )
    .eq('hidden_danger_id', hiddenDangerId)
    .order('create_time', { ascending: false })
  return await responseHandle<HiddenDangerEvent[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchSmisRiskPointOptions() {
  const query = supabase
    .from('smis_risk_point')
    .select('id, risk_point_no, risk_point_name, current_risk_level')
    .eq('status', 'active')
    .order('risk_point_no', { ascending: true })
    .limit(2000)
  return await responseHandle<Api.Smis.RiskControl.RiskPointRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}
