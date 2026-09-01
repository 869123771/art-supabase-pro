create or replace function app_private.activate_next_workflow_node(
  p_instance_id uuid,
  p_after_order integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance;
  v_config jsonb;
  v_node jsonb;
  v_assignee record;
  v_assignee_count integer;
begin
  select i.*
  into v_instance
  from public.wf_instance i
  where i.id = p_instance_id
  for update;

  if not found then
    raise exception '流程实例不存在';
  end if;

  select v.config
  into v_config
  from public.wf_version v
  where v.id = v_instance.version_id;

  for v_node in
    select value
    from jsonb_array_elements(v_config -> 'nodes')
    where (value ->> 'order')::integer > p_after_order
    order by (value ->> 'order')::integer
  loop
    if not app_private.workflow_condition_matches(v_instance.context_snapshot, v_node) then
      insert into public.wf_action(
        instance_id,
        node_key,
        node_name,
        action,
        actor_name_snapshot,
        comment,
        tenant_id
      )
      values (
        v_instance.id,
        v_node ->> 'key',
        v_node ->> 'name',
        'auto_skip',
        '系统',
        '条件不满足，自动跳过',
        v_instance.tenant_id
      );
      continue;
    end if;

    v_assignee_count := 0;

    for v_assignee in
      select *
      from app_private.resolve_workflow_assignees(
        v_instance.tenant_id,
        v_node,
        v_instance.initiator_user_id
      )
    loop
      insert into public.wf_task(
        instance_id,
        node_key,
        node_name,
        node_order,
        approval_mode,
        assignee_user_id,
        assignee_name_snapshot,
        due_at,
        tenant_id
      )
      values (
        v_instance.id,
        v_node ->> 'key',
        v_node ->> 'name',
        (v_node ->> 'order')::integer,
        v_node ->> 'approvalMode',
        v_assignee.user_id,
        v_assignee.user_name,
        case
          when coalesce((v_node ->> 'dueHours')::integer, 0) > 0
            then now() + make_interval(hours => (v_node ->> 'dueHours')::integer)
        end,
        v_instance.tenant_id
      );
      v_assignee_count := v_assignee_count + 1;
    end loop;

    if v_assignee_count = 0 then
      raise exception '节点“%”没有可用审批人，请检查角色、人员或自审配置', v_node ->> 'name';
    end if;

    update public.wf_instance
    set current_node_key = v_node ->> 'key',
        current_node_name = v_node ->> 'name',
        row_version = row_version + 1
    where id = v_instance.id;

    return;
  end loop;

  update public.wf_instance
  set status = 'approved',
      current_node_key = null,
      current_node_name = null,
      finished_at = now(),
      row_version = row_version + 1
  where id = v_instance.id;

  perform app_private.apply_workflow_business_status(
    v_instance.business_type,
    v_instance.business_id,
    'approved',
    '系统',
    '流程全部节点已通过'
  );
end;
$$;
revoke execute on function app_private.activate_next_workflow_node(uuid, integer)
  from public, anon, authenticated;
