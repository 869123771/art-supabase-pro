import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'

const { supabase, responseHandle } = useSupabase()

const DEFINITION_SELECT = `
  *,
  tenant:sys_tenant!wf_definition_tenant_id_fkey(id, tenant_code, tenant_name),
  versions:wf_version!wf_version_definition_id_fkey(*)
`

const TASK_SELECT = `
  *,
  instance:wf_instance!wf_task_instance_id_fkey!inner(
    *,
    definition:wf_definition!wf_instance_definition_id_fkey(id, code, name, business_type),
    version:wf_version!wf_instance_version_id_fkey(id, version_no)
  )
`

const INSTANCE_SELECT = `
  *,
  definition:wf_definition!wf_instance_definition_id_fkey(id, code, name, business_type),
  version:wf_version!wf_instance_version_id_fkey(id, version_no),
  tasks:wf_task(*),
  actions:wf_action(
    *,
    actor:sys_user!wf_action_actor_user_id_fkey(id, user_name, nick_name, user_email, avatar)
  )
`

export async function fetchWorkflowDefinitionList(
  params: Api.Workflow.WorkflowDefinitionSearchParams
) {
  const { from = 0, to = 9, keyword, businessType, status, tenantId } = params
  let query = supabase
    .from('wf_definition')
    .select(DEFINITION_SELECT, { count: 'exact' })
    .order('update_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  if (keyword) query = query.or(`code.ilike.%${keyword}%,name.ilike.%${keyword}%`)
  if (businessType) query = query.eq('business_type', businessType)
  if (status) query = query.eq('status', status)
  if (tenantId) query = query.eq('tenant_id', tenantId)

  return await responseHandle<Api.Workflow.WorkflowDefinitionRecord[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchWorkflowDefinitionDetail(id: string) {
  return await responseHandle<Api.Workflow.WorkflowDefinitionRecord>(
    () => supabase.from('wf_definition').select(DEFINITION_SELECT).eq('id', id).single(),
    { showErrorMessage: true, breakReturn: true }
  )
}

export async function saveWorkflowDefinition(payload: Api.Workflow.WorkflowDefinitionSavePayload) {
  return await responseHandle<{ definitionId: string; versionId: string; versionNo: number }>(
    // Workflow config is an explicit JSON contract and intentionally keeps camelCase keys.
    () => supabase.rpc('save_workflow_definition', { p_definition: payload }),
    { showMessage: true, breakReturn: true }
  )
}

export async function publishWorkflowDefinition(id: string) {
  return await responseHandle<{ definitionId: string; versionId: string; versionNo: number }>(
    () => supabase.rpc('publish_workflow_definition', { p_definition_id: id }),
    { showMessage: true, breakReturn: true, message: '流程发布成功' }
  )
}

export async function setWorkflowDefinitionEnabled(id: string, enabled: boolean) {
  return await responseHandle(
    () =>
      supabase.rpc('set_workflow_definition_enabled', {
        p_definition_id: id,
        p_enabled: enabled
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function deleteWorkflowDefinition(id: string) {
  return await responseHandle(
    () => supabase.rpc('delete_workflow_definition', { p_definition_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchWorkflowUserOptions(
  params: Api.Workflow.WorkflowOptionSearchParams = {}
) {
  const { tenantId } = params
  let query = supabase
    .from('sys_user')
    .select('id, user_name, nick_name, user_email, avatar')
    .eq('status', '1')
    .order('user_name')
    .limit(1000) as unknown as SupabaseQueryLike
  if (tenantId) query = query.eq('tenant_id', tenantId)

  return await responseHandle<Api.Workflow.WorkflowUserOption[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchWorkflowRoleOptions(
  params: Api.Workflow.WorkflowOptionSearchParams = {}
) {
  const { tenantId } = params
  let query = supabase
    .from('sys_role')
    .select('id, role_code, role_name')
    .eq('enabled', true)
    .order('role_name')
    .limit(500) as unknown as SupabaseQueryLike
  if (tenantId) query = query.eq('tenant_id', tenantId)

  return await responseHandle<Api.Workflow.WorkflowRoleOption[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchPendingWorkflowTasks(params: Api.Workflow.WorkflowTaskSearchParams) {
  const { from = 0, to = 9, keyword, businessType, assigneeUserId } = params
  let query = supabase
    .from('wf_task')
    .select(TASK_SELECT, { count: 'exact' })
    .eq('assignee_user_id', assigneeUserId)
    .eq('status', 'pending')
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) query = query.ilike('instance.business_title', `%${keyword}%`)
  if (businessType) query = query.eq('instance.business_type', businessType)
  return await responseHandle<Api.Workflow.WorkflowTaskRecord[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchPlatformGlobalPendingWorkflowTasks(
  params: Api.Workflow.PlatformGlobalWorkflowTaskSearchParams
) {
  const { from = 0, to = 19, keyword, businessType, tenantId } = params
  return await responseHandle<Api.Workflow.WorkflowTaskPage>(
    () =>
      supabase.rpc('search_platform_global_pending_workflow_tasks', {
        p_keyword: keyword?.trim() || null,
        p_business_type: businessType || null,
        p_tenant_id: tenantId || null,
        p_from: from,
        p_to: to
      }),
    { showErrorMessage: true, breakReturn: true }
  )
}

export async function fetchHandledWorkflowTasks(params: Api.Workflow.WorkflowTaskSearchParams) {
  const { from = 0, to = 9, keyword, businessType, status, assigneeUserId } = params
  let query = supabase
    .from('wf_task')
    .select(TASK_SELECT, { count: 'exact' })
    .eq('assignee_user_id', assigneeUserId)
    .neq('status', 'pending')
    .order('handled_at', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) query = query.ilike('instance.business_title', `%${keyword}%`)
  if (businessType) query = query.eq('instance.business_type', businessType)
  if (status) query = query.eq('status', status)
  return await responseHandle<Api.Workflow.WorkflowTaskRecord[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchInitiatedWorkflowInstances(
  params: Api.Workflow.WorkflowInstanceSearchParams
) {
  const { from = 0, to = 9, keyword, businessType, status, initiatorUserId } = params
  let query = supabase
    .from('wf_instance')
    .select(
      `*, definition:wf_definition!wf_instance_definition_id_fkey(id, code, name, business_type), version:wf_version!wf_instance_version_id_fkey(id, version_no)`,
      { count: 'exact' }
    )
    .eq('initiator_user_id', initiatorUserId)
    .order('started_at', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike
  if (keyword) query = query.ilike('business_title', `%${keyword}%`)
  if (businessType) query = query.eq('business_type', businessType)
  if (status) query = query.eq('status', status)
  return await responseHandle<Api.Workflow.WorkflowInstanceRecord[]>(() => query, {
    showErrorMessage: true
  })
}

export async function fetchWorkflowInstanceDetail(id: string) {
  return await responseHandle<Api.Workflow.WorkflowInstanceRecord>(
    () => supabase.from('wf_instance').select(INSTANCE_SELECT).eq('id', id).single(),
    { showErrorMessage: true, breakReturn: true }
  )
}

export async function fetchWorkflowWorkbenchSummary(
  userId: string
): Promise<Api.Workflow.WorkflowWorkbenchSummary> {
  const [pending, handled, initiatedRunning, initiatedCompleted] = await Promise.all([
    supabase
      .from('wf_task')
      .select('id', { count: 'exact', head: true })
      .eq('assignee_user_id', userId)
      .eq('status', 'pending'),
    supabase
      .from('wf_task')
      .select('id', { count: 'exact', head: true })
      .eq('assignee_user_id', userId)
      .neq('status', 'pending'),
    supabase
      .from('wf_instance')
      .select('id', { count: 'exact', head: true })
      .eq('initiator_user_id', userId)
      .eq('status', 'running'),
    supabase
      .from('wf_instance')
      .select('id', { count: 'exact', head: true })
      .eq('initiator_user_id', userId)
      .neq('status', 'running')
  ])
  const error = pending.error || handled.error || initiatedRunning.error || initiatedCompleted.error
  if (error) throw new Error(error.message)
  return {
    pendingCount: pending.count ?? 0,
    handledCount: handled.count ?? 0,
    initiatedRunningCount: initiatedRunning.count ?? 0,
    initiatedCompletedCount: initiatedCompleted.count ?? 0
  }
}

export async function fetchWorkflowMonitorList(params: Api.Workflow.WorkflowMonitorSearchParams) {
  const { from = 0, to = 19, keyword, businessType, status, slaStatus } = params
  return await responseHandle<Api.Workflow.WorkflowMonitorPage>(
    () =>
      supabase.rpc('search_workflow_instances_for_monitor', {
        p_keyword: keyword?.trim() || null,
        p_business_type: businessType || null,
        p_status: status || null,
        p_sla_status: slaStatus || null,
        p_from: from,
        p_to: to
      }),
    { breakReturn: true }
  )
}

export async function fetchWorkflowMonitorSummary(): Promise<Api.Workflow.WorkflowMonitorSummary> {
  const result = await responseHandle<Api.Workflow.WorkflowMonitorSummary>(
    () => supabase.rpc('get_workflow_monitor_summary'),
    { breakReturn: true }
  )
  if (!result.data) throw new Error('审批运营概览加载失败')
  return result.data
}

export async function fetchWorkflowCallbackOutbox(
  status: Api.Workflow.WorkflowCallbackStatus | null = null,
  limit = 50
): Promise<Api.Workflow.WorkflowCallbackOutbox> {
  const result = await responseHandle<Api.Workflow.WorkflowCallbackOutbox>(
    () =>
      supabase.rpc('get_workflow_callback_outbox', {
        p_status: status,
        p_limit: limit
      }),
    { breakReturn: true }
  )
  if (!result.data) throw new Error('业务回调队列加载失败')
  return result.data
}

export async function retryWorkflowBusinessCallback(outboxId: string) {
  return await responseHandle<{ id: string; status: Api.Workflow.WorkflowCallbackStatus }>(
    () => supabase.rpc('retry_workflow_business_callback', { p_outbox_id: outboxId }),
    { showMessage: true, breakReturn: true, message: '已发起人工补偿' }
  )
}

export async function startWorkflow(params: {
  businessType: string
  businessId: string
  businessTitle: string
  context?: Record<string, unknown>
}) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('start_workflow', {
        p_business_type: params.businessType,
        p_business_id: params.businessId,
        p_business_title: params.businessTitle,
        p_context: params.context ?? {},
        p_idempotency_key: crypto.randomUUID()
      }),
    { showMessage: true, breakReturn: true, message: '已提交审批' }
  )
}

export async function actWorkflowTask(params: {
  taskId: string
  action: 'approve' | 'reject'
  comment?: string | null
}) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('act_workflow_task', {
        p_task_id: params.taskId,
        p_action: params.action,
        p_comment: params.comment || null,
        p_idempotency_key: crypto.randomUUID()
      }),
    {
      showMessage: true,
      breakReturn: true,
      message: params.action === 'approve' ? '审批已通过' : '已驳回申请'
    }
  )
}

export async function actWorkflowByBusiness(params: {
  businessType: string
  businessId: string
  action: 'approve' | 'reject'
  comment?: string | null
}) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('act_workflow_by_business', {
        p_business_type: params.businessType,
        p_business_id: params.businessId,
        p_action: params.action,
        p_comment: params.comment || null,
        p_idempotency_key: crypto.randomUUID()
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function withdrawWorkflow(instanceId: string, comment?: string | null) {
  return await responseHandle(
    () =>
      supabase.rpc('withdraw_workflow', {
        p_instance_id: instanceId,
        p_comment: comment || null
      }),
    { showMessage: true, breakReturn: true, message: '申请已撤回' }
  )
}

export async function cancelWorkflowInstance(instanceId: string, comment: string) {
  return await responseHandle<string>(
    () =>
      supabase.rpc('cancel_workflow_instance', {
        p_instance_id: instanceId,
        p_comment: comment,
        p_idempotency_key: crypto.randomUUID()
      }),
    { showMessage: true, breakReturn: true, message: '流程已终止' }
  )
}
