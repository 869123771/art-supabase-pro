-- Give platform super administrators an explicit, audited emergency approval path.
-- Ordinary approvers retain the existing tenant and assignee boundaries.

create or replace function app_private.search_platform_global_pending_workflow_tasks(
  p_keyword text default null,
  p_business_type text default null,
  p_tenant_id uuid default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    100
  );
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_result jsonb;
begin
  if (select auth.uid()) is null or not (select app_private.is_platform_super()) then
    raise exception '仅平台超级管理员可以查看全局待办' using errcode = '42501';
  end if;

  with filtered as (
    select
      to_jsonb(t) || jsonb_build_object(
        'instance',
          to_jsonb(i) || jsonb_build_object(
            'definition', jsonb_build_object(
              'id', d.id,
              'code', d.code,
              'name', d.name,
              'business_type', d.business_type
            ),
            'version', jsonb_build_object('id', v.id, 'version_no', v.version_no)
          ),
        'tenant', jsonb_build_object(
          'id', tenant.id,
          'tenant_code', tenant.tenant_code,
          'tenant_name', tenant.tenant_name
        )
      ) as record,
      case when t.due_at is not null and t.due_at < now() then 0 else 1 end as urgency_order,
      t.due_at,
      t.create_time
    from public.wf_task t
    join public.wf_instance i on i.id = t.instance_id
    join public.wf_definition d on d.id = i.definition_id
    join public.wf_version v on v.id = i.version_id
    join public.sys_tenant tenant on tenant.id = t.tenant_id
    where t.status = 'pending'
      and i.status = 'running'
      and i.current_node_key = t.node_key
      and (p_tenant_id is null or t.tenant_id = p_tenant_id)
      and (nullif(p_business_type, '') is null or i.business_type = p_business_type)
      and (
        v_keyword is null
        or i.business_title ilike '%' || v_keyword || '%'
        or i.business_id::text ilike '%' || v_keyword || '%'
        or i.initiator_name_snapshot ilike '%' || v_keyword || '%'
        or t.assignee_name_snapshot ilike '%' || v_keyword || '%'
        or tenant.tenant_name ilike '%' || v_keyword || '%'
        or d.name ilike '%' || v_keyword || '%'
      )
  ), page_rows as (
    select record, urgency_order, due_at, create_time
    from filtered
    order by urgency_order, due_at nulls last, create_time desc
    offset v_from limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(
      (
        select jsonb_agg(record order by urgency_order, due_at nulls last, create_time desc)
        from page_rows
      ),
      '[]'::jsonb
    ),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function app_private.search_platform_global_pending_workflow_tasks(
  text, text, uuid, integer, integer
) from public, anon, authenticated;
grant execute on function app_private.search_platform_global_pending_workflow_tasks(
  text, text, uuid, integer, integer
) to authenticated, service_role;

create or replace function public.search_platform_global_pending_workflow_tasks(
  p_keyword text default null,
  p_business_type text default null,
  p_tenant_id uuid default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.search_platform_global_pending_workflow_tasks(
    p_keyword, p_business_type, p_tenant_id, p_from, p_to
  )
$$;

revoke all on function public.search_platform_global_pending_workflow_tasks(
  text, text, uuid, integer, integer
) from public, anon;
grant execute on function public.search_platform_global_pending_workflow_tasks(
  text, text, uuid, integer, integer
) to authenticated, service_role;

create or replace function app_private.act_workflow_task(
  p_task_id uuid,
  p_action text,
  p_comment text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select app_private.current_app_user_id());
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_actor_name text;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_task public.wf_task;
  v_instance public.wf_instance;
  v_existing_instance_id uuid;
  v_existing_task_id uuid;
  v_action_id uuid;
  v_total_count integer;
  v_approved_count integer;
  v_rejected_count integer;
  v_pending_count integer;
  v_required_count integer;
  v_should_reject boolean := false;
begin
  if (select auth.uid()) is null or v_user_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;
  if p_action not in ('approve', 'reject') then
    raise exception '不支持的审批动作';
  end if;
  if p_action = 'reject' and v_comment is null then
    raise exception '驳回时必须填写原因';
  end if;
  if v_is_platform_super and coalesce(char_length(v_comment), 0) < 4 then
    raise exception '超管代审批原因至少填写4个字符';
  end if;
  if char_length(coalesce(v_comment, '')) > 500 then
    raise exception '审批意见不能超过500个字符';
  end if;

  -- Resolve the task first so a platform-super action uses the task tenant for
  -- idempotency, action audit rows, notifications, and business callbacks.
  select *
  into v_task
  from public.wf_task
  where id = p_task_id
    and (v_is_platform_super or tenant_id = v_tenant_id);

  if not found or (not v_is_platform_super and v_task.assignee_user_id <> v_user_id) then
    raise exception '待办不存在或当前用户不是审批人' using errcode = '42501';
  end if;

  if nullif(p_idempotency_key, '') is not null then
    select instance_id, task_id
    into v_existing_instance_id, v_existing_task_id
    from public.wf_action
    where tenant_id = v_task.tenant_id
      and idempotency_key = p_idempotency_key;

    if found then
      if v_existing_task_id is distinct from p_task_id then
        raise exception '幂等键已被其他审批任务使用';
      end if;
      return v_existing_instance_id;
    end if;
  end if;

  -- Keep the established instance-before-task lock order for concurrent decisions.
  select *
  into v_instance
  from public.wf_instance
  where id = v_task.instance_id
  for update;

  select *
  into v_task
  from public.wf_task
  where id = p_task_id
    and (v_is_platform_super or tenant_id = v_tenant_id)
  for update;

  if not found or (not v_is_platform_super and v_task.assignee_user_id <> v_user_id) then
    raise exception '待办不存在或当前用户不是审批人' using errcode = '42501';
  end if;
  if v_task.status <> 'pending' then
    raise exception '该待办已经处理';
  end if;
  if v_instance.status <> 'running' or v_instance.current_node_key <> v_task.node_key then
    raise exception '流程已结束或待办节点已失效';
  end if;

  select coalesce(nullif(nick_name, ''), nullif(user_name, ''), user_email, id::text)
  into v_actor_name
  from public.sys_user
  where id = v_user_id;

  update public.wf_task
  set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
      handled_at = now(),
      comment = v_comment
  where id = v_task.id;

  insert into public.wf_action(
    instance_id,
    task_id,
    node_key,
    node_name,
    action,
    actor_user_id,
    actor_name_snapshot,
    comment,
    metadata,
    idempotency_key,
    tenant_id
  ) values (
    v_instance.id,
    v_task.id,
    v_task.node_key,
    v_task.node_name,
    p_action,
    v_user_id,
    v_actor_name,
    v_comment,
    jsonb_build_object(
      'source', case when v_is_platform_super then 'platform_super_override' else 'workflow_workbench' end,
      'operatorType', case when v_is_platform_super then 'platform_super_override' else 'assignee' end,
      'originalAssigneeUserId', v_task.assignee_user_id,
      'originalAssigneeName', v_task.assignee_name_snapshot,
      'taskTenantId', v_task.tenant_id
    ),
    nullif(p_idempotency_key, ''),
    v_task.tenant_id
  ) returning id into v_action_id;

  if v_is_platform_super and v_task.assignee_user_id <> v_user_id then
    perform app_private.enqueue_user_notification(
      v_task.assignee_user_id,
      v_task.tenant_id,
      'message',
      '平台超级管理员已代为处理待办',
      v_actor_name || case when p_action = 'approve' then '代为通过了' else '代为驳回了' end
        || '“' || v_instance.business_title || '”'
        || coalesce('：' || v_comment, ''),
      case when p_action = 'approve' then 'success' else 'danger' end,
      'workflow_super_override',
      v_action_id,
      v_instance.business_type,
      v_instance.business_id,
      v_instance.id,
      '/workflow/workbench',
      jsonb_build_object('tab', 'handled', 'instanceId', v_instance.id)
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (where status = 'approved')::integer,
    count(*) filter (where status = 'rejected')::integer,
    count(*) filter (where status = 'pending')::integer
  into v_total_count, v_approved_count, v_rejected_count, v_pending_count
  from public.wf_task
  where instance_id = v_instance.id
    and node_key = v_task.node_key;

  v_required_count := case v_task.approval_mode
    when 'any' then 1
    when 'all' then v_total_count
    else ceil(v_total_count * v_task.approval_threshold_percent / 100.0)::integer
  end;

  if p_action = 'reject' then
    v_should_reject := v_task.reject_veto_enabled
      or (v_approved_count + v_pending_count < v_required_count);
  end if;

  if v_should_reject then
    update public.wf_task
    set status = 'cancelled', handled_at = now(), comment = '同节点审批结论已确定为驳回'
    where instance_id = v_instance.id
      and node_key = v_task.node_key
      and status = 'pending';

    update public.wf_instance
    set status = 'rejected',
        finished_at = now(),
        finish_comment = v_comment,
        current_node_key = null,
        current_node_name = null,
        row_version = row_version + 1
    where id = v_instance.id;

    perform app_private.apply_workflow_business_status(
      v_instance.business_type, v_instance.business_id, 'rejected', v_actor_name, v_comment
    );
    return v_instance.id;
  end if;

  if v_approved_count < v_required_count then
    return v_instance.id;
  end if;

  update public.wf_task
  set status = 'cancelled', handled_at = now(), comment = '同节点已达到通过条件'
  where instance_id = v_instance.id
    and node_key = v_task.node_key
    and status = 'pending';

  perform app_private.activate_next_workflow_node(v_instance.id, v_task.node_order);
  return v_instance.id;
end;
$$;

revoke all on function app_private.act_workflow_task(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function app_private.act_workflow_task(uuid, text, text, text)
  to authenticated, service_role;

comment on function public.search_platform_global_pending_workflow_tasks(
  text, text, uuid, integer, integer
) is 'Platform-super-only cross-tenant pending workflow task search.';

comment on function app_private.act_workflow_task(uuid, text, text, text) is
  'Acts on one workflow approval seat. Platform super administrators may proxy a pending seat with a mandatory reason; all decision semantics remain unchanged.';

notify pgrst, 'reload schema';

;
