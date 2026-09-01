-- Add explicit enterprise decision semantics to workflow nodes.
-- Existing any/all tasks retain their historical one-vote rejection behavior.

alter table public.wf_task
  add column if not exists approval_threshold_percent smallint not null default 100,
  add column if not exists reject_veto_enabled boolean not null default true;

alter table public.wf_task
  drop constraint if exists wf_task_approval_mode_check;

alter table public.wf_task
  add constraint wf_task_approval_mode_check
    check (approval_mode in ('any', 'all', 'percentage')),
  add constraint wf_task_approval_threshold_percent_check
    check (approval_threshold_percent between 1 and 100);

comment on column public.wf_task.approval_threshold_percent is
  'Immutable runtime snapshot of the approval percentage required by this node.';
comment on column public.wf_task.reject_veto_enabled is
  'Immutable runtime snapshot: one rejection immediately rejects the node when enabled.';

create or replace function app_private.validate_workflow_config(p_config jsonb)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_node jsonb;
  v_count integer;
  v_mode text;
  v_threshold integer;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or jsonb_typeof(p_config -> 'nodes') <> 'array' then
    raise exception '流程配置必须包含 nodes 数组';
  end if;

  v_count := jsonb_array_length(p_config -> 'nodes');
  if v_count < 1 or v_count > 30 then
    raise exception '审批节点数量必须在 1 到 30 之间';
  end if;

  if (select count(distinct node ->> 'key') from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点标识不能重复';
  end if;

  if (select count(distinct (node ->> 'order')::integer) from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点顺序不能重复';
  end if;

  for v_node in select value from jsonb_array_elements(p_config -> 'nodes') loop
    if btrim(coalesce(v_node ->> 'key', '')) = ''
       or (v_node ->> 'key') !~ '^[A-Za-z][A-Za-z0-9_-]{1,39}$'
       or btrim(coalesce(v_node ->> 'name', '')) = '' then
      raise exception '节点标识或名称不正确';
    end if;

    v_mode := coalesce(v_node ->> 'approvalMode', '');
    if v_mode not in ('any', 'all', 'percentage') then
      raise exception '节点 % 的审批方式不正确', v_node ->> 'name';
    end if;

    if v_mode = 'percentage' then
      if coalesce(v_node ->> 'approvalThresholdPercent', '') !~ '^[0-9]+$' then
        raise exception '节点 % 的通过比例必须是 1 到 100 的整数', v_node ->> 'name';
      end if;

      begin
        v_threshold := (v_node ->> 'approvalThresholdPercent')::integer;
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception '节点 % 的通过比例必须是 1 到 100 的整数', v_node ->> 'name';
      end;

      if v_threshold is null or v_threshold < 1 or v_threshold > 100 then
        raise exception '节点 % 的通过比例必须是 1 到 100 的整数', v_node ->> 'name';
      end if;
    end if;

    if v_node ? 'rejectVetoEnabled'
       and jsonb_typeof(v_node -> 'rejectVetoEnabled') <> 'boolean' then
      raise exception '节点 % 的一票否决配置必须是布尔值', v_node ->> 'name';
    end if;

    if coalesce(v_node #>> '{assignee,type}', '') not in ('users', 'roles', 'initiator') then
      raise exception '节点 % 的审批人类型不正确', v_node ->> 'name';
    end if;

    if (v_node #>> '{assignee,type}') = 'users'
       and coalesce(jsonb_array_length(v_node #> '{assignee,userIds}'), 0) = 0 then
      raise exception '节点 % 必须选择审批人', v_node ->> 'name';
    end if;

    if (v_node #>> '{assignee,type}') = 'roles'
       and coalesce(jsonb_array_length(v_node #> '{assignee,roleCodes}'), 0) = 0 then
      raise exception '节点 % 必须选择审批角色', v_node ->> 'name';
    end if;

    if coalesce(v_node #>> '{condition,operator}', 'always') not in
       ('always', 'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'contains', 'not_empty') then
      raise exception '节点 % 的条件运算符不受支持', v_node ->> 'name';
    end if;
  end loop;
end;
$$;

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
  v_mode text;
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
        instance_id, node_key, node_name, action, actor_name_snapshot, comment, tenant_id
      ) values (
        v_instance.id, v_node ->> 'key', v_node ->> 'name', 'auto_skip',
        '系统', '条件不满足，自动跳过', v_instance.tenant_id
      );
      continue;
    end if;

    v_mode := v_node ->> 'approvalMode';
    v_assignee_count := 0;

    for v_assignee in
      select *
      from app_private.resolve_workflow_assignees(
        v_instance.tenant_id, v_node, v_instance.initiator_user_id
      )
    loop
      insert into public.wf_task(
        instance_id, node_key, node_name, node_order, approval_mode,
        approval_threshold_percent, reject_veto_enabled, assignee_user_id,
        assignee_name_snapshot, due_at, tenant_id
      ) values (
        v_instance.id, v_node ->> 'key', v_node ->> 'name',
        (v_node ->> 'order')::integer, v_mode,
        case
          when v_mode = 'any' then 1
          when v_mode = 'all' then 100
          else (v_node ->> 'approvalThresholdPercent')::integer
        end,
        coalesce((v_node ->> 'rejectVetoEnabled')::boolean, true),
        v_assignee.user_id, v_assignee.user_name,
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
  v_actor_name text;
  v_task public.wf_task;
  v_instance public.wf_instance;
  v_existing_instance_id uuid;
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
  if p_action = 'reject' and btrim(coalesce(p_comment, '')) = '' then
    raise exception '驳回时必须填写原因';
  end if;

  if nullif(p_idempotency_key, '') is not null then
    select instance_id
    into v_existing_instance_id
    from public.wf_action
    where tenant_id = v_tenant_id
      and idempotency_key = p_idempotency_key;

    if found then
      return v_existing_instance_id;
    end if;
  end if;

  -- Read the task identity first, then serialize every decision on the instance.
  -- This lock order prevents parallel approvers from deadlocking each other.
  select *
  into v_task
  from public.wf_task
  where id = p_task_id
    and tenant_id = v_tenant_id;

  if not found or v_task.assignee_user_id <> v_user_id then
    raise exception '待办不存在或当前用户不是审批人';
  end if;

  select *
  into v_instance
  from public.wf_instance
  where id = v_task.instance_id
  for update;

  select *
  into v_task
  from public.wf_task
  where id = p_task_id
    and tenant_id = v_tenant_id
  for update;

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
      comment = nullif(btrim(coalesce(p_comment, '')), '')
  where id = v_task.id;

  insert into public.wf_action(
    instance_id, task_id, node_key, node_name, action, actor_user_id,
    actor_name_snapshot, comment, idempotency_key, tenant_id
  ) values (
    v_instance.id, v_task.id, v_task.node_key, v_task.node_name, p_action, v_user_id,
    v_actor_name, nullif(btrim(coalesce(p_comment, '')), ''),
    nullif(p_idempotency_key, ''), v_tenant_id
  );

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
        finish_comment = p_comment,
        current_node_key = null,
        current_node_name = null,
        row_version = row_version + 1
    where id = v_instance.id;

    perform app_private.apply_workflow_business_status(
      v_instance.business_type, v_instance.business_id, 'rejected', v_actor_name, p_comment
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

revoke execute on function app_private.act_workflow_task(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function app_private.act_workflow_task(uuid, text, text, text)
  to authenticated, service_role;

with approval_mode_type as (
  select id, tenant_id
  from public.sys_dict_type
  where code = 'workflowApprovalMode'
  order by create_time
  limit 1
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, sort, tag_type,
  tenant_id, create_by, update_by
)
select
  gen_random_uuid(), id, 'workflowApprovalMode_percentage', '1', 'percentage',
  '比例会签', 3, 'success', tenant_id, 'workflow-migration', 'workflow-migration'
from approval_mode_type
where not exists (
  select 1
  from public.sys_dictionary d
  where d.type_id = approval_mode_type.id
    and d.value = 'percentage'
);

;
