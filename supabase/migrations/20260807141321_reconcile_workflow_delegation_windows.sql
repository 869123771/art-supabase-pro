-- Reconcile scheduled workflow delegation windows.
-- Pending tasks are moved when a delegation starts and returned (or moved to
-- the next effective delegation) when it ends. Explicit transfers are never
-- overwritten by this scheduler.

create or replace function app_private.reconcile_workflow_delegations(
  p_at timestamptz default now(),
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 2000);
  v_candidate record;
  v_task record;
  v_assignment record;
  v_changed integer := 0;
  v_activated integer := 0;
  v_returned integer := 0;
  v_comment text;
  v_action text;
begin
  for v_candidate in
    select task.id, task.instance_id
    from public.wf_task task
    join public.wf_instance instance on instance.id = task.instance_id
    where task.status = 'pending'
      and instance.status = 'running'
      and task.assignment_source in ('direct', 'delegation')
      and (
        (
          task.assignment_source = 'direct'
          and exists (
            select 1
            from public.wf_delegation delegation
            join public.sys_user delegate_user
              on delegate_user.id = delegation.delegate_user_id
             and delegate_user.tenant_id = task.tenant_id
             and delegate_user.status = '1'
            where delegation.tenant_id = task.tenant_id
              and delegation.delegator_user_id = task.original_assignee_user_id
              and delegation.revoked_at is null
              and delegation.starts_at <= p_at
              and delegation.ends_at > p_at
          )
        )
        or (
          task.assignment_source = 'delegation'
          and not exists (
            select 1
            from public.wf_delegation delegation
            where delegation.id = task.delegation_id
              and delegation.revoked_at is null
              and delegation.starts_at <= p_at
              and delegation.ends_at > p_at
          )
        )
      )
    order by task.create_time, task.id
    limit v_limit
  loop
    perform 1
    from public.wf_instance instance
    where instance.id = v_candidate.instance_id
    for update;

    select
      task.*,
      instance.business_type,
      instance.business_id,
      instance.business_title
    into v_task
    from public.wf_task task
    join public.wf_instance instance on instance.id = task.instance_id
    where task.id = v_candidate.id
      and task.status = 'pending'
      and instance.status = 'running'
      and task.assignment_source in ('direct', 'delegation')
    for update of task;

    if not found then
      continue;
    end if;

    select * into v_assignment
    from app_private.resolve_workflow_assignment(
      v_task.tenant_id,
      v_task.original_assignee_user_id,
      p_at
    );

    if not found
       or (
         v_task.assignee_user_id = v_assignment.assignee_user_id
         and v_task.assignment_source = v_assignment.assignment_source
         and v_task.delegation_id is not distinct from v_assignment.delegation_id
       ) then
      continue;
    end if;

    if v_assignment.assignment_source = 'delegation' then
      select '委托时段已生效，系统自动分配：' || delegation.reason
      into v_comment
      from public.wf_delegation delegation
      where delegation.id = v_assignment.delegation_id;
      v_action := 'delegate';
      v_activated := v_activated + 1;
    else
      v_comment := '委托时段已结束，系统自动退回原审批人';
      v_action := 'delegation_revoke';
      v_returned := v_returned + 1;
    end if;

    update public.sys_notification notification
    set is_read = true,
        read_at = coalesce(notification.read_at, p_at)
    where notification.recipient_user_id = v_task.assignee_user_id
      and notification.category = 'todo'
      and notification.is_read = false
      and notification.source_id = v_task.id
      and notification.source_type in ('workflow_task', 'workflow_delegation', 'workflow_delegation_revoke');

    update public.wf_task
    set assignee_user_id = v_assignment.assignee_user_id,
        assignee_name_snapshot = v_assignment.assignee_name,
        assignment_source = v_assignment.assignment_source,
        delegation_id = v_assignment.delegation_id,
        last_assigned_by = null,
        assignment_reason = v_comment
    where id = v_task.id;

    insert into public.wf_action(
      instance_id, task_id, node_key, node_name, action,
      actor_name_snapshot, comment, metadata, tenant_id
    ) values (
      v_task.instance_id, v_task.id, v_task.node_key, v_task.node_name, v_action,
      '系统调度', v_comment,
      jsonb_build_object(
        'reason', 'delegation_window_reconciliation',
        'effectiveAt', p_at,
        'fromUserId', v_task.assignee_user_id,
        'fromUserName', v_task.assignee_name_snapshot,
        'toUserId', v_assignment.assignee_user_id,
        'toUserName', v_assignment.assignee_name,
        'delegationId', v_assignment.delegation_id
      ),
      v_task.tenant_id
    );

    perform app_private.enqueue_user_notification(
      v_assignment.assignee_user_id,
      v_task.tenant_id,
      'todo',
      case when v_assignment.assignment_source = 'delegation'
        then '委托已生效，收到审批待办'
        else '委托已结束，审批待办已退回'
      end,
      '“' || v_task.business_title || '”' || v_comment,
      case when v_assignment.assignment_source = 'delegation' then 'warning' else 'info' end,
      case when v_assignment.assignment_source = 'delegation'
        then 'workflow_delegation'
        else 'workflow_delegation_revoke'
      end,
      v_task.id,
      v_task.business_type,
      v_task.business_id,
      v_task.instance_id,
      '/workflow/workbench',
      jsonb_build_object('tab', 'pending', 'instanceId', v_task.instance_id)
    );

    v_changed := v_changed + 1;
  end loop;

  return jsonb_build_object(
    'changedCount', v_changed,
    'activatedCount', v_activated,
    'returnedCount', v_returned
  );
end;
$function$;

revoke all on function app_private.reconcile_workflow_delegations(timestamptz, integer)
  from public, anon, authenticated;
grant execute on function app_private.reconcile_workflow_delegations(timestamptz, integer)
  to service_role;

do $block$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'workflow-delegation-reconciliation';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'workflow-delegation-reconciliation',
    '*/5 * * * *',
    $job$select app_private.reconcile_workflow_delegations(now(), 500);$job$
  );
end;
$block$;

comment on function app_private.reconcile_workflow_delegations(timestamptz, integer) is
  'Moves pending workflow tasks as delegation windows start and end without overwriting explicit transfers.';;
