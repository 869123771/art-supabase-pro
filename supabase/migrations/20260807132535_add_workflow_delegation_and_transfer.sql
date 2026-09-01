-- Workflow delegation and explicit task transfer.
-- The original approval seat is preserved on every task while the effective
-- assignee may change. All assignment changes are recorded in immutable actions.

create table public.wf_delegation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.sys_tenant(id) on delete restrict,
  delegator_user_id uuid not null references public.sys_user(id) on delete restrict,
  delegate_user_id uuid not null references public.sys_user(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null,
  revoked_at timestamptz,
  revoked_by uuid references public.sys_user(id) on delete set null,
  revoke_reason text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint wf_delegation_users_different check (delegator_user_id <> delegate_user_id),
  constraint wf_delegation_period_valid check (ends_at > starts_at),
  constraint wf_delegation_reason_valid check (char_length(btrim(reason)) between 4 and 300),
  constraint wf_delegation_revoke_reason_valid check (
    revoke_reason is null or char_length(btrim(revoke_reason)) between 4 and 300
  )
);

create index wf_delegation_active_lookup_idx
  on public.wf_delegation(tenant_id, delegator_user_id, starts_at, ends_at)
  where revoked_at is null;

create index wf_delegation_delegate_idx
  on public.wf_delegation(tenant_id, delegate_user_id, starts_at, ends_at)
  where revoked_at is null;

alter table public.wf_delegation enable row level security;

create policy delegation_participant_select on public.wf_delegation
  for select to authenticated
  using (
    (select app_private.is_platform_super())
    or (
      tenant_id = (select app_private.current_user_tenant_id())
      and (
        delegator_user_id = (select app_private.current_app_user_id())
        or delegate_user_id = (select app_private.current_app_user_id())
      )
    )
  );

grant select on public.wf_delegation to authenticated, service_role;

create trigger wf_delegation_create_audit
before insert on public.wf_delegation
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger wf_delegation_update_audit
before update on public.wf_delegation
for each row execute function public.trg_set_update_time_and_by();

alter table public.wf_task
  add column original_assignee_user_id uuid,
  add column original_assignee_name_snapshot text,
  add column assignment_source text not null default 'direct',
  add column delegation_id uuid references public.wf_delegation(id) on delete set null,
  add column last_assigned_by uuid references public.sys_user(id) on delete set null,
  add column assignment_reason text;

update public.wf_task
set original_assignee_user_id = assignee_user_id,
    original_assignee_name_snapshot = assignee_name_snapshot
where original_assignee_user_id is null;

alter table public.wf_task
  alter column original_assignee_user_id set not null,
  alter column original_assignee_name_snapshot set not null,
  add constraint wf_task_original_assignee_user_id_fkey
    foreign key (original_assignee_user_id) references public.sys_user(id) on delete restrict not valid,
  add constraint wf_task_assignment_source_check
    check (assignment_source in ('direct', 'delegation', 'transfer'));

alter table public.wf_task validate constraint wf_task_original_assignee_user_id_fkey;

alter table public.wf_task
  drop constraint wf_task_instance_node_assignee_unique;

alter table public.wf_task
  add constraint wf_task_instance_node_original_assignee_unique
    unique (instance_id, node_key, original_assignee_user_id);

create index wf_task_original_assignee_idx
  on public.wf_task(original_assignee_user_id, status, create_time desc);

create index wf_task_delegation_id_idx
  on public.wf_task(delegation_id)
  where delegation_id is not null;

alter table public.wf_action
  drop constraint wf_action_type_check;

alter table public.wf_action
  add constraint wf_action_type_check check (
    action in (
      'submit', 'approve', 'reject', 'withdraw', 'cancel', 'auto_skip',
      'delegate', 'delegation_revoke', 'transfer'
    )
  );

create or replace function app_private.resolve_workflow_assignment(
  p_tenant_id uuid,
  p_original_user_id uuid,
  p_at timestamptz default now()
)
returns table(
  assignee_user_id uuid,
  assignee_name text,
  delegation_id uuid,
  assignment_source text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    coalesce(delegate_user.id, original_user.id),
    coalesce(
      nullif(delegate_user.nick_name, ''), nullif(delegate_user.user_name, ''),
      delegate_user.user_email,
      nullif(original_user.nick_name, ''), nullif(original_user.user_name, ''),
      original_user.user_email, original_user.id::text
    ),
    active_delegation.id,
    case when active_delegation.id is null then 'direct' else 'delegation' end
  from public.sys_user original_user
  left join lateral (
    select delegation.id, delegation.delegate_user_id
    from public.wf_delegation delegation
    join public.sys_user candidate
      on candidate.id = delegation.delegate_user_id
     and candidate.tenant_id = p_tenant_id
     and candidate.status = '1'
    where delegation.tenant_id = p_tenant_id
      and delegation.delegator_user_id = p_original_user_id
      and delegation.revoked_at is null
      and delegation.starts_at <= p_at
      and delegation.ends_at > p_at
    order by delegation.create_time desc, delegation.id
    limit 1
  ) active_delegation on true
  left join public.sys_user delegate_user on delegate_user.id = active_delegation.delegate_user_id
  where original_user.id = p_original_user_id
    and original_user.tenant_id = p_tenant_id
    and original_user.status = '1';
$function$;

revoke all on function app_private.resolve_workflow_assignment(uuid, uuid, timestamptz)
  from public, anon, authenticated;

create or replace function app_private.activate_next_workflow_node(
  p_instance_id uuid,
  p_after_order integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_instance public.wf_instance;
  v_config jsonb;
  v_node jsonb;
  v_original_assignee record;
  v_assignment record;
  v_assignee_count integer;
  v_mode text;
  v_candidate_count integer := 0;
begin
  select i.* into v_instance
  from public.wf_instance i
  where i.id = p_instance_id
  for update;

  if not found then raise exception '流程实例不存在'; end if;

  select v.config into v_config
  from public.wf_version v
  where v.id = v_instance.version_id;

  for v_node in
    select value
    from jsonb_array_elements(v_config -> 'nodes')
    where (value ->> 'order')::integer > p_after_order
    order by (value ->> 'order')::integer
  loop
    v_candidate_count := v_candidate_count + 1;

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

    for v_original_assignee in
      select * from app_private.resolve_workflow_assignees(
        v_instance.tenant_id, v_node, v_instance.initiator_user_id
      )
    loop
      select * into v_assignment
      from app_private.resolve_workflow_assignment(
        v_instance.tenant_id, v_original_assignee.user_id, now()
      );

      if not found then continue; end if;

      insert into public.wf_task(
        instance_id, node_key, node_name, node_order, approval_mode,
        approval_threshold_percent, reject_veto_enabled,
        assignee_user_id, assignee_name_snapshot,
        original_assignee_user_id, original_assignee_name_snapshot,
        assignment_source, delegation_id, assignment_reason,
        due_at, tenant_id
      ) values (
        v_instance.id, v_node ->> 'key', v_node ->> 'name',
        (v_node ->> 'order')::integer, v_mode,
        case when v_mode = 'any' then 1 when v_mode = 'all' then 100
          else (v_node ->> 'approvalThresholdPercent')::integer end,
        coalesce((v_node ->> 'rejectVetoEnabled')::boolean, true),
        v_assignment.assignee_user_id, v_assignment.assignee_name,
        v_original_assignee.user_id, v_original_assignee.user_name,
        v_assignment.assignment_source, v_assignment.delegation_id,
        case when v_assignment.delegation_id is null then null else '按有效委托自动分配' end,
        case when coalesce((v_node ->> 'dueHours')::integer, 0) > 0
          then now() + make_interval(hours => (v_node ->> 'dueHours')::integer) end,
        v_instance.tenant_id
      );
      v_assignee_count := v_assignee_count + 1;
    end loop;

    if v_assignee_count = 0 then
      raise exception '节点“%”没有可用审批人，请检查角色、人员、自审或委托配置', v_node ->> 'name';
    end if;

    update public.wf_instance
    set current_node_key = v_node ->> 'key',
        current_node_name = v_node ->> 'name',
        row_version = row_version + 1
    where id = v_instance.id;
    return;
  end loop;

  if v_candidate_count > 0
     and not coalesce((v_config ->> 'allowAutoApprove')::boolean, false) then
    raise exception '后续审批条件全部未命中，流程已安全阻断；请检查业务上下文或显式开启自动通过策略';
  end if;

  update public.wf_instance
  set status = 'approved', current_node_key = null, current_node_name = null,
      finished_at = now(), row_version = row_version + 1
  where id = v_instance.id;

  perform app_private.apply_workflow_business_status(
    v_instance.business_type, v_instance.business_id, 'approved', '系统', '流程全部节点已通过'
  );
end;
$function$;

revoke all on function app_private.activate_next_workflow_node(uuid, integer)
  from public, anon, authenticated;

create or replace function app_private.create_workflow_delegation(
  p_delegate_user_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_delegator_user_id uuid := (select app_private.current_app_user_id());
  v_actor_name text;
  v_delegate_name text;
  v_delegation_id uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_task record;
begin
  if (select auth.uid()) is null or v_delegator_user_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;
  if p_delegate_user_id = v_delegator_user_id then raise exception '不能委托给自己'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception '委托结束时间必须晚于开始时间';
  end if;
  if p_ends_at > p_starts_at + interval '180 days' then
    raise exception '单次委托不能超过 180 天';
  end if;
  if char_length(v_reason) not between 4 and 300 then
    raise exception '委托原因需填写 4 至 300 个字符';
  end if;

  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_actor_name
  from public.sys_user
  where id = v_delegator_user_id and tenant_id = v_tenant_id and status = '1';

  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_delegate_name
  from public.sys_user
  where id = p_delegate_user_id and tenant_id = v_tenant_id and status = '1';

  if v_actor_name is null or v_delegate_name is null then
    raise exception '委托人或受托人不存在、已停用或不属于当前租户';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('workflow-delegation:' || v_tenant_id::text || ':' || v_delegator_user_id::text, 91312)
  );

  if exists (
    select 1 from public.wf_delegation delegation
    where delegation.tenant_id = v_tenant_id
      and delegation.delegator_user_id = v_delegator_user_id
      and delegation.revoked_at is null
      and tstzrange(delegation.starts_at, delegation.ends_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception '该时间段已存在有效委托，请先调整或撤销原委托';
  end if;

  insert into public.wf_delegation(
    tenant_id, delegator_user_id, delegate_user_id, starts_at, ends_at, reason
  ) values (
    v_tenant_id, v_delegator_user_id, p_delegate_user_id, p_starts_at, p_ends_at, v_reason
  ) returning id into v_delegation_id;

  if p_starts_at <= now() and p_ends_at > now() then
    perform 1
    from public.wf_instance instance
    where instance.id in (
      select task.instance_id
      from public.wf_task task
      where task.tenant_id = v_tenant_id
        and task.assignee_user_id = v_delegator_user_id
        and task.status = 'pending'
    )
    order by instance.id
    for update;

    for v_task in
      select task.*, instance.business_type, instance.business_id, instance.business_title
      from public.wf_task task
      join public.wf_instance instance on instance.id = task.instance_id
      where task.tenant_id = v_tenant_id
        and task.assignee_user_id = v_delegator_user_id
        and task.status = 'pending'
      order by task.id
      for update of task
    loop
      update public.wf_task
      set assignee_user_id = p_delegate_user_id,
          assignee_name_snapshot = v_delegate_name,
          assignment_source = 'delegation',
          delegation_id = v_delegation_id,
          last_assigned_by = v_delegator_user_id,
          assignment_reason = v_reason
      where id = v_task.id;

      insert into public.wf_action(
        instance_id, task_id, node_key, node_name, action,
        actor_user_id, actor_name_snapshot, comment, metadata, tenant_id
      ) values (
        v_task.instance_id, v_task.id, v_task.node_key, v_task.node_name, 'delegate',
        v_delegator_user_id, v_actor_name, v_reason,
        jsonb_build_object(
          'delegationId', v_delegation_id,
          'fromUserId', v_delegator_user_id,
          'fromUserName', v_actor_name,
          'toUserId', p_delegate_user_id,
          'toUserName', v_delegate_name
        ), v_tenant_id
      );

      perform app_private.enqueue_user_notification(
        p_delegate_user_id, v_tenant_id, 'todo', '收到委托审批',
        v_actor_name || '将“' || v_task.business_title || '”委托给你审批：' || v_reason,
        'warning', 'workflow_delegation', v_task.id,
        v_task.business_type, v_task.business_id, v_task.instance_id,
        '/workflow/workbench', jsonb_build_object('tab','pending','instanceId',v_task.instance_id)
      );
    end loop;
  end if;

  return v_delegation_id;
end;
$function$;

create or replace function app_private.revoke_workflow_delegation(
  p_delegation_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_user_id uuid := (select app_private.current_app_user_id());
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_reason text := btrim(coalesce(p_reason, ''));
  v_delegation public.wf_delegation;
  v_actor_name text;
  v_delegator_name text;
  v_task record;
begin
  if (select auth.uid()) is null or v_user_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;
  if char_length(v_reason) not between 4 and 300 then
    raise exception '撤销原因需填写 4 至 300 个字符';
  end if;

  select * into v_delegation
  from public.wf_delegation
  where id = p_delegation_id
    and (v_is_platform_super or tenant_id = v_tenant_id)
  for update;

  if not found or (not v_is_platform_super and v_delegation.delegator_user_id <> v_user_id) then
    raise exception '委托不存在或无权撤销' using errcode = '42501';
  end if;
  if v_delegation.revoked_at is not null then return v_delegation.id; end if;

  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_actor_name from public.sys_user where id = v_user_id;
  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_delegator_name from public.sys_user where id = v_delegation.delegator_user_id;

  update public.wf_delegation
  set revoked_at = now(), revoked_by = v_user_id, revoke_reason = v_reason
  where id = v_delegation.id;

  perform 1
  from public.wf_instance instance
  where instance.id in (
    select task.instance_id from public.wf_task task
    where task.delegation_id = v_delegation.id
      and task.status = 'pending'
  )
  order by instance.id
  for update;

  for v_task in
    select task.*, instance.business_type, instance.business_id, instance.business_title
    from public.wf_task task
    join public.wf_instance instance on instance.id = task.instance_id
    join public.sys_user original_user on original_user.id = task.original_assignee_user_id
    where task.delegation_id = v_delegation.id
      and task.status = 'pending'
      and original_user.status = '1'
    order by task.id
    for update of task
  loop
    update public.wf_task
    set assignee_user_id = v_task.original_assignee_user_id,
        assignee_name_snapshot = v_task.original_assignee_name_snapshot,
        assignment_source = 'direct', delegation_id = null,
        last_assigned_by = v_user_id, assignment_reason = v_reason
    where id = v_task.id;

    insert into public.wf_action(
      instance_id, task_id, node_key, node_name, action,
      actor_user_id, actor_name_snapshot, comment, metadata, tenant_id
    ) values (
      v_task.instance_id, v_task.id, v_task.node_key, v_task.node_name, 'delegation_revoke',
      v_user_id, v_actor_name, v_reason,
      jsonb_build_object(
        'delegationId', v_delegation.id,
        'fromUserId', v_delegation.delegate_user_id,
        'toUserId', v_task.original_assignee_user_id,
        'toUserName', v_task.original_assignee_name_snapshot
      ), v_delegation.tenant_id
    );

    perform app_private.enqueue_user_notification(
      v_task.original_assignee_user_id, v_delegation.tenant_id, 'todo', '委托已撤销，待办已收回',
      '“' || v_task.business_title || '”已恢复由你审批：' || v_reason,
      'info', 'workflow_delegation_revoke', v_task.id,
      v_task.business_type, v_task.business_id, v_task.instance_id,
      '/workflow/workbench', jsonb_build_object('tab','pending','instanceId',v_task.instance_id)
    );
  end loop;

  return v_delegation.id;
end;
$function$;

create or replace function app_private.transfer_workflow_task(
  p_task_id uuid,
  p_assignee_user_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_user_id uuid := (select app_private.current_app_user_id());
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_reason text := btrim(coalesce(p_reason, ''));
  v_instance_id uuid;
  v_instance public.wf_instance;
  v_task public.wf_task;
  v_actor_name text;
  v_target_name text;
begin
  if (select auth.uid()) is null or v_user_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;
  if char_length(v_reason) not between 4 and 300 then
    raise exception '转交原因需填写 4 至 300 个字符';
  end if;

  select instance_id into v_instance_id
  from public.wf_task
  where id = p_task_id and (v_is_platform_super or tenant_id = v_tenant_id);
  if v_instance_id is null then raise exception '待办不存在或无权操作' using errcode = '42501'; end if;

  select * into v_instance from public.wf_instance
  where id = v_instance_id for update;
  select * into v_task from public.wf_task
  where id = p_task_id and (v_is_platform_super or tenant_id = v_tenant_id) for update;

  if not found or (not v_is_platform_super and v_task.assignee_user_id <> v_user_id) then
    raise exception '只有当前审批人可以转交待办' using errcode = '42501';
  end if;
  if v_task.status <> 'pending' or v_instance.status <> 'running' then
    raise exception '仅运行中的待办可以转交';
  end if;
  if p_assignee_user_id = v_task.assignee_user_id then raise exception '不能转交给当前审批人'; end if;

  if nullif(p_idempotency_key, '') is not null and exists (
    select 1 from public.wf_action
    where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key
  ) then
    return v_task.instance_id;
  end if;

  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_actor_name from public.sys_user where id = v_user_id;
  select coalesce(nullif(nick_name,''), nullif(user_name,''), user_email, id::text)
  into v_target_name
  from public.sys_user
  where id = p_assignee_user_id and tenant_id = v_task.tenant_id and status = '1';
  if v_target_name is null then raise exception '新审批人不存在、已停用或不属于当前租户'; end if;

  update public.wf_task
  set assignee_user_id = p_assignee_user_id,
      assignee_name_snapshot = v_target_name,
      assignment_source = 'transfer', delegation_id = null,
      last_assigned_by = v_user_id, assignment_reason = v_reason
  where id = v_task.id;

  insert into public.wf_action(
    instance_id, task_id, node_key, node_name, action,
    actor_user_id, actor_name_snapshot, comment, metadata,
    idempotency_key, tenant_id
  ) values (
    v_task.instance_id, v_task.id, v_task.node_key, v_task.node_name, 'transfer',
    v_user_id, v_actor_name, v_reason,
    jsonb_build_object(
      'fromUserId', v_task.assignee_user_id,
      'fromUserName', v_task.assignee_name_snapshot,
      'toUserId', p_assignee_user_id,
      'toUserName', v_target_name,
      'originalAssigneeUserId', v_task.original_assignee_user_id,
      'originalAssigneeName', v_task.original_assignee_name_snapshot,
      'operatorType', case when v_is_platform_super then 'platform_super_transfer' else 'assignee_transfer' end
    ), nullif(p_idempotency_key, ''), v_task.tenant_id
  );

  perform app_private.enqueue_user_notification(
    p_assignee_user_id, v_task.tenant_id, 'todo', '收到转交审批',
    v_actor_name || '将“' || v_instance.business_title || '”转交给你审批：' || v_reason,
    'warning', 'workflow_transfer', v_task.id,
    v_instance.business_type, v_instance.business_id, v_instance.id,
    '/workflow/workbench', jsonb_build_object('tab','pending','instanceId',v_instance.id)
  );

  return v_task.instance_id;
end;
$function$;

create or replace function public.create_workflow_delegation(
  p_delegate_user_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text
)
returns uuid
language sql
set search_path = ''
as $function$
  select app_private.create_workflow_delegation(
    p_delegate_user_id, p_starts_at, p_ends_at, p_reason
  )
$function$;

create or replace function public.revoke_workflow_delegation(
  p_delegation_id uuid,
  p_reason text
)
returns uuid
language sql
set search_path = ''
as $function$
  select app_private.revoke_workflow_delegation(p_delegation_id, p_reason)
$function$;

create or replace function public.transfer_workflow_task(
  p_task_id uuid,
  p_assignee_user_id uuid,
  p_reason text,
  p_idempotency_key text default null
)
returns uuid
language sql
set search_path = ''
as $function$
  select app_private.transfer_workflow_task(
    p_task_id, p_assignee_user_id, p_reason, p_idempotency_key
  )
$function$;

revoke all on function app_private.create_workflow_delegation(uuid, timestamptz, timestamptz, text)
  from public, anon, authenticated;
revoke all on function app_private.revoke_workflow_delegation(uuid, text)
  from public, anon, authenticated;
revoke all on function app_private.transfer_workflow_task(uuid, uuid, text, text)
  from public, anon, authenticated;

grant execute on function app_private.create_workflow_delegation(uuid, timestamptz, timestamptz, text)
  to authenticated, service_role;
grant execute on function app_private.revoke_workflow_delegation(uuid, text)
  to authenticated, service_role;
grant execute on function app_private.transfer_workflow_task(uuid, uuid, text, text)
  to authenticated, service_role;

revoke all on function public.create_workflow_delegation(uuid, timestamptz, timestamptz, text)
  from public, anon;
revoke all on function public.revoke_workflow_delegation(uuid, text)
  from public, anon;
revoke all on function public.transfer_workflow_task(uuid, uuid, text, text)
  from public, anon;

grant execute on function public.create_workflow_delegation(uuid, timestamptz, timestamptz, text)
  to authenticated, service_role;
grant execute on function public.revoke_workflow_delegation(uuid, text)
  to authenticated, service_role;
grant execute on function public.transfer_workflow_task(uuid, uuid, text, text)
  to authenticated, service_role;

with action_type as (
  select id, tenant_id from public.sys_dict_type where code = 'workflowActionType'
), rows(value, label, sort, tag_type) as (
  values
    ('delegate', '委托', 7::bigint, 'warning'),
    ('delegation_revoke', '撤销委托', 8::bigint, 'info'),
    ('transfer', '转交', 9::bigint, 'warning')
)
insert into public.sys_dictionary(
  type_id, code, status, value, label, i18n_scope, sort,
  tenant_id, tag_type, create_by, update_by
)
select action_type.id, 'workflowActionType_' || rows.value, '1', rows.value,
       rows.label, '1', rows.sort, action_type.tenant_id, rows.tag_type,
       'workflow-migration', 'workflow-migration'
from action_type cross join rows
where not exists (
  select 1 from public.sys_dictionary dictionary
  where dictionary.type_id = action_type.id and dictionary.value = rows.value
);

;
