-- Enterprise approval workflow engine.
-- Definition publishing is versioned and immutable. Runtime mutations are only exposed through RPCs.

create or replace function app_private.can_manage_workflow()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sys_user u
    where u.auth_user_id = (select auth.uid())
      and u.status = '1'
      and coalesce(u.user_roles, '{}'::text[])
        && array['R_SUPER', 'R_ADMIN', 'YQ_ADMIN']::text[]
  );
$$;
revoke execute on function app_private.can_manage_workflow() from public, anon;
grant execute on function app_private.can_manage_workflow() to authenticated, service_role;
create table public.wf_definition (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  business_type text not null,
  description text,
  status text not null default 'draft',
  current_version_id uuid,
  published_at timestamptz,
  published_by text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint wf_definition_code_not_blank check (btrim(code) <> ''),
  constraint wf_definition_code_format check (code ~ '^[A-Za-z][A-Za-z0-9_.-]{1,63}$'),
  constraint wf_definition_name_not_blank check (btrim(name) <> ''),
  constraint wf_definition_business_type_not_blank check (btrim(business_type) <> ''),
  constraint wf_definition_status_check check (status in ('draft', 'published', 'disabled')),
  constraint wf_definition_tenant_code_unique unique (tenant_id, code)
);
create table public.wf_version (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.wf_definition(id) on delete cascade,
  version_no integer not null,
  status text not null default 'draft',
  config jsonb not null default '{"nodes":[]}'::jsonb,
  change_note text,
  published_at timestamptz,
  published_by text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint wf_version_no_positive check (version_no > 0),
  constraint wf_version_status_check check (status in ('draft', 'published', 'retired')),
  constraint wf_version_config_object check (jsonb_typeof(config) = 'object'),
  constraint wf_version_definition_no_unique unique (definition_id, version_no)
);
alter table public.wf_definition
  add constraint wf_definition_current_version_fkey
  foreign key (current_version_id) references public.wf_version(id) on delete set null;
create table public.wf_instance (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.wf_definition(id) on delete restrict,
  version_id uuid not null references public.wf_version(id) on delete restrict,
  business_type text not null,
  business_id uuid not null,
  business_title text not null,
  initiator_user_id uuid not null references public.sys_user(id) on delete restrict,
  initiator_name_snapshot text not null,
  status text not null default 'running',
  current_node_key text,
  current_node_name text,
  context_snapshot jsonb not null default '{}'::jsonb,
  row_version integer not null default 1,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  finish_comment text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint wf_instance_title_not_blank check (btrim(business_title) <> ''),
  constraint wf_instance_status_check check (
    status in ('running', 'approved', 'rejected', 'withdrawn', 'cancelled')
  ),
  constraint wf_instance_context_object check (jsonb_typeof(context_snapshot) = 'object'),
  constraint wf_instance_row_version_positive check (row_version > 0)
);
create table public.wf_task (
  id uuid primary key default gen_random_uuid(),
  instance_id uuid not null references public.wf_instance(id) on delete cascade,
  node_key text not null,
  node_name text not null,
  node_order integer not null,
  approval_mode text not null,
  assignee_user_id uuid not null references public.sys_user(id) on delete restrict,
  assignee_name_snapshot text not null,
  status text not null default 'pending',
  handled_at timestamptz,
  comment text,
  due_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint wf_task_node_key_not_blank check (btrim(node_key) <> ''),
  constraint wf_task_approval_mode_check check (approval_mode in ('any', 'all')),
  constraint wf_task_status_check check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  constraint wf_task_instance_node_assignee_unique unique (instance_id, node_key, assignee_user_id)
);
create table public.wf_action (
  id uuid primary key default gen_random_uuid(),
  instance_id uuid not null references public.wf_instance(id) on delete cascade,
  task_id uuid references public.wf_task(id) on delete set null,
  node_key text,
  node_name text,
  action text not null,
  actor_user_id uuid references public.sys_user(id) on delete set null,
  actor_name_snapshot text not null,
  comment text,
  metadata jsonb not null default '{}'::jsonb,
  idempotency_key text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint wf_action_type_check check (
    action in ('submit', 'approve', 'reject', 'withdraw', 'cancel', 'auto_skip')
  ),
  constraint wf_action_metadata_object check (jsonb_typeof(metadata) = 'object')
);
create unique index wf_definition_one_active_business_idx
  on public.wf_definition(tenant_id, business_type)
  where status = 'published';
create unique index wf_version_one_draft_idx
  on public.wf_version(definition_id)
  where status = 'draft';
create unique index wf_version_one_published_idx
  on public.wf_version(definition_id)
  where status = 'published';
create unique index wf_instance_one_running_business_idx
  on public.wf_instance(tenant_id, business_type, business_id)
  where status = 'running';
create unique index wf_action_idempotency_idx
  on public.wf_action(tenant_id, idempotency_key)
  where idempotency_key is not null;
create index wf_definition_tenant_status_idx
  on public.wf_definition(tenant_id, status, update_time desc);
create index wf_version_definition_status_idx
  on public.wf_version(definition_id, status, version_no desc);
create index wf_instance_tenant_status_time_idx
  on public.wf_instance(tenant_id, status, started_at desc);
create index wf_instance_initiator_time_idx
  on public.wf_instance(initiator_user_id, started_at desc);
create index wf_task_assignee_status_time_idx
  on public.wf_task(assignee_user_id, status, create_time desc);
create index wf_task_instance_node_idx
  on public.wf_task(instance_id, node_order, node_key);
create index wf_action_instance_time_idx
  on public.wf_action(instance_id, create_time, id);
comment on table public.wf_definition is 'Tenant-scoped reusable approval workflow identity.';
comment on table public.wf_version is 'Immutable after publishing; stores the complete workflow configuration snapshot.';
comment on table public.wf_instance is 'Runtime approval instance bound to one business record and one published version.';
comment on table public.wf_task is 'Concrete approval work item resolved to one application user.';
comment on table public.wf_action is 'Append-only business audit trail for approval actions.';
create or replace function app_private.trg_protect_workflow_records()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'wf_version' and old.status <> 'draft' then
    if tg_op = 'DELETE'
       or new.definition_id is distinct from old.definition_id
       or new.version_no is distinct from old.version_no
       or new.config is distinct from old.config
       or new.tenant_id is distinct from old.tenant_id
       or not (old.status = 'published' and new.status = 'retired') then
      raise exception '已发布或已归档的流程版本不可修改';
    end if;
  end if;
  if tg_table_name = 'wf_action' then
    raise exception '审批动作记录不可修改或删除';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke execute on function app_private.trg_protect_workflow_records() from public, anon, authenticated;
create trigger wf_version_protect
before update or delete on public.wf_version
for each row execute function app_private.trg_protect_workflow_records();
create trigger wf_action_protect
before update or delete on public.wf_action
for each row execute function app_private.trg_protect_workflow_records();
create trigger wf_definition_create_audit before insert on public.wf_definition
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_definition_update_audit before update on public.wf_definition
for each row execute function public.trg_set_update_time_and_by();
create trigger wf_version_create_audit before insert on public.wf_version
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_version_update_audit before update on public.wf_version
for each row execute function public.trg_set_update_time_and_by();
create trigger wf_instance_create_audit before insert on public.wf_instance
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_instance_update_audit before update on public.wf_instance
for each row execute function public.trg_set_update_time_and_by();
create trigger wf_task_create_audit before insert on public.wf_task
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_task_update_audit before update on public.wf_task
for each row execute function public.trg_set_update_time_and_by();
create trigger wf_action_create_audit before insert on public.wf_action
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create or replace function app_private.can_view_workflow_instance(p_instance_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.wf_instance i
    where i.id = p_instance_id
      and (
        (select app_private.is_platform_super())
        or (
          i.tenant_id = (select app_private.current_user_tenant_id())
          and (
            i.initiator_user_id = (select app_private.current_app_user_id())
            or (select app_private.can_manage_workflow())
            or exists (
              select 1 from public.wf_task t
              where t.instance_id = i.id
                and t.assignee_user_id = (select app_private.current_app_user_id())
            )
          )
        )
      )
  );
$$;
revoke execute on function app_private.can_view_workflow_instance(uuid) from public, anon;
grant execute on function app_private.can_view_workflow_instance(uuid) to authenticated, service_role;
alter table public.wf_definition enable row level security;
alter table public.wf_version enable row level security;
alter table public.wf_instance enable row level security;
alter table public.wf_task enable row level security;
alter table public.wf_action enable row level security;
create policy tenant_select on public.wf_definition for select to authenticated
using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy tenant_select on public.wf_version for select to authenticated
using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy participant_select on public.wf_instance for select to authenticated
using ((select app_private.can_view_workflow_instance(id)));
create policy participant_select on public.wf_task for select to authenticated
using ((select app_private.can_view_workflow_instance(instance_id)));
create policy participant_select on public.wf_action for select to authenticated
using ((select app_private.can_view_workflow_instance(instance_id)));
revoke all on table public.wf_definition, public.wf_version, public.wf_instance,
  public.wf_task, public.wf_action from public, anon, authenticated;
grant select on table public.wf_definition, public.wf_version, public.wf_instance,
  public.wf_task, public.wf_action to authenticated;
grant all on table public.wf_definition, public.wf_version, public.wf_instance,
  public.wf_task, public.wf_action to service_role;
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
    if coalesce(v_node ->> 'approvalMode', '') not in ('any', 'all') then
      raise exception '节点 % 的审批方式不正确', v_node ->> 'name';
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
create or replace function app_private.workflow_condition_matches(p_context jsonb, p_node jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_operator text := coalesce(p_node #>> '{condition,operator}', 'always');
  v_field text := p_node #>> '{condition,field}';
  v_expected jsonb := p_node #> '{condition,value}';
  v_actual jsonb;
begin
  if v_operator = 'always' then return true; end if;
  if v_field is null or v_field !~ '^[A-Za-z][A-Za-z0-9_.-]{0,79}$' then return false; end if;
  v_actual := p_context #> string_to_array(v_field, '.');
  if v_operator = 'not_empty' then return v_actual is not null and v_actual <> 'null'::jsonb and v_actual <> '""'::jsonb; end if;
  if v_operator = 'eq' then return v_actual = v_expected; end if;
  if v_operator = 'ne' then return v_actual is distinct from v_expected; end if;
  if v_operator in ('gt', 'gte', 'lt', 'lte') then
    begin
      return case v_operator
        when 'gt' then (v_actual #>> '{}')::numeric > (v_expected #>> '{}')::numeric
        when 'gte' then (v_actual #>> '{}')::numeric >= (v_expected #>> '{}')::numeric
        when 'lt' then (v_actual #>> '{}')::numeric < (v_expected #>> '{}')::numeric
        else (v_actual #>> '{}')::numeric <= (v_expected #>> '{}')::numeric end;
    exception when invalid_text_representation then return false; end;
  end if;
  if v_operator = 'in' then return jsonb_typeof(v_expected) = 'array' and v_expected @> jsonb_build_array(v_actual); end if;
  if v_operator = 'contains' then
    return case jsonb_typeof(v_actual)
      when 'array' then v_actual @> jsonb_build_array(v_expected)
      when 'string' then position(lower(v_expected #>> '{}') in lower(v_actual #>> '{}')) > 0
      else false end;
  end if;
  return false;
end;
$$;
create or replace function app_private.resolve_workflow_assignees(
  p_tenant_id uuid,
  p_node jsonb,
  p_initiator_user_id uuid
)
returns table(user_id uuid, user_name text)
language sql
stable
security definer
set search_path = ''
as $$
  with requested_users as (
    select nullif(value, '')::uuid user_id
    from jsonb_array_elements_text(coalesce(p_node #> '{assignee,userIds}', '[]'::jsonb))
    where p_node #>> '{assignee,type}' = 'users'
    union all
    select p_initiator_user_id where p_node #>> '{assignee,type}' = 'initiator'
  ), requested_roles as (
    select value role_code
    from jsonb_array_elements_text(coalesce(p_node #> '{assignee,roleCodes}', '[]'::jsonb))
    where p_node #>> '{assignee,type}' = 'roles'
  ), candidates as (
    select u.id
    from public.sys_user u
    where u.id in (select requested_users.user_id from requested_users)
    union
    select u.id
    from public.sys_user u
    where exists (
      select 1 from requested_roles rr
      where rr.role_code = any(coalesce(u.user_roles, '{}'::text[]))
    )
  )
  select u.id,
         coalesce(nullif(u.nick_name, ''), nullif(u.user_name, ''), u.user_email, u.id::text)
  from public.sys_user u
  join candidates c on c.id = u.id
  where u.tenant_id = p_tenant_id
    and u.status = '1'
    and (
      coalesce((p_node ->> 'allowSelfApproval')::boolean, false)
      or u.id <> p_initiator_user_id
    )
  order by u.user_name nulls last, u.user_email;
$$;
revoke execute on function app_private.resolve_workflow_assignees(uuid, jsonb, uuid)
  from public, anon, authenticated;
create or replace function app_private.apply_workflow_business_status(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);
  if p_business_type = 'tms_waybill_cost' then
    update public.tms_waybill_cost
    set audit_status = case p_status
          when 'running' then 'pending_review'
          when 'approved' then 'approved'
          when 'rejected' then 'rejected'
          when 'withdrawn' then 'draft'
          else audit_status end,
        submitted_at = case when p_status = 'running' then now() else submitted_at end,
        submitted_by = case when p_status = 'running' then p_actor else submitted_by end,
        reviewed_at = case when p_status in ('approved', 'rejected') then now() else reviewed_at end,
        reviewed_by = case when p_status in ('approved', 'rejected') then p_actor else reviewed_by end,
        review_remark = case when p_status in ('approved', 'rejected') then nullif(btrim(p_comment), '') else review_remark end
    where id = p_business_id;
    if not found then raise exception '运单费用不存在或已被删除'; end if;
  end if;
end;
$$;
revoke execute on function app_private.apply_workflow_business_status(text, uuid, text, text, text)
  from public, anon, authenticated;
create or replace function app_private.trg_require_workflow_for_cost_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.audit_status is distinct from old.audit_status
     and (
       new.audit_status in ('pending_review', 'approved', 'rejected')
       or (old.audit_status = 'rejected' and new.audit_status = 'draft')
     )
     and coalesce(pg_catalog.current_setting('app.workflow_engine', true), '') <> 'on' then
    raise exception '费用审批状态必须通过审批中心流转';
  end if;
  return new;
end;
$$;
revoke execute on function app_private.trg_require_workflow_for_cost_review()
  from public, anon, authenticated;
create trigger tms_waybill_cost_workflow_guard
before update on public.tms_waybill_cost
for each row execute function app_private.trg_require_workflow_for_cost_review();
create or replace function app_private.activate_next_workflow_node(p_instance_id uuid, p_after_order integer)
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
  select i into v_instance
  from public.wf_instance i
  where i.id = p_instance_id for update;
  if not found then raise exception '流程实例不存在'; end if;
  select v.config into v_config from public.wf_version v where v.id = v_instance.version_id;

  for v_node in
    select value from jsonb_array_elements(v_config -> 'nodes')
    where (value ->> 'order')::integer > p_after_order
    order by (value ->> 'order')::integer
  loop
    if not app_private.workflow_condition_matches(v_instance.context_snapshot, v_node) then
      insert into public.wf_action(instance_id,node_key,node_name,action,actor_name_snapshot,comment,tenant_id)
      values (v_instance.id,v_node->>'key',v_node->>'name','auto_skip','系统','条件不满足，自动跳过',v_instance.tenant_id);
      continue;
    end if;
    v_assignee_count := 0;
    for v_assignee in
      select * from app_private.resolve_workflow_assignees(v_instance.tenant_id,v_node,v_instance.initiator_user_id)
    loop
      insert into public.wf_task(
        instance_id,node_key,node_name,node_order,approval_mode,assignee_user_id,
        assignee_name_snapshot,due_at,tenant_id
      ) values (
        v_instance.id,v_node->>'key',v_node->>'name',(v_node->>'order')::integer,
        v_node->>'approvalMode',v_assignee.user_id,v_assignee.user_name,
        case when coalesce((v_node->>'dueHours')::integer,0) > 0
          then now() + make_interval(hours => (v_node->>'dueHours')::integer) end,
        v_instance.tenant_id
      );
      v_assignee_count := v_assignee_count + 1;
    end loop;
    if v_assignee_count = 0 then
      raise exception '节点“%”没有可用审批人，请检查角色、人员或自审配置', v_node->>'name';
    end if;
    update public.wf_instance
    set current_node_key=v_node->>'key',current_node_name=v_node->>'name',row_version=row_version+1
    where id=v_instance.id;
    return;
  end loop;

  update public.wf_instance
  set status='approved',current_node_key=null,current_node_name=null,
      finished_at=now(),row_version=row_version+1
  where id=v_instance.id;
  perform app_private.apply_workflow_business_status(
    v_instance.business_type,v_instance.business_id,'approved','系统','流程全部节点已通过'
  );
end;
$$;
revoke execute on function app_private.activate_next_workflow_node(uuid, integer)
  from public, anon, authenticated;
create or replace function app_private.save_workflow_definition(p_definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_definition public.wf_definition;
  v_version public.wf_version;
  v_definition_id uuid;
  v_config jsonb := coalesce(p_definition -> 'config', '{"nodes":[]}'::jsonb);
  v_actor text;
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有流程配置权限' using errcode='42501';
  end if;
  perform app_private.validate_workflow_config(v_config);
  v_actor := coalesce(nullif(auth.jwt()->>'email',''),auth.uid()::text);
  begin v_definition_id := nullif(p_definition->>'id','')::uuid;
  exception when invalid_text_representation then raise exception '流程 ID 格式不正确'; end;

  if v_definition_id is null then
    insert into public.wf_definition(code,name,business_type,description,tenant_id,create_by,update_by)
    values (
      btrim(p_definition->>'code'),btrim(p_definition->>'name'),btrim(p_definition->>'businessType'),
      nullif(btrim(coalesce(p_definition->>'description','')),''),v_tenant_id,v_actor,v_actor
    ) returning * into v_definition;
    insert into public.wf_version(definition_id,version_no,config,change_note,tenant_id,create_by,update_by)
    values (
      v_definition.id,1,v_config,nullif(btrim(coalesce(p_definition->>'changeNote','')),''),
      v_tenant_id,v_actor,v_actor
    ) returning * into v_version;
  else
    select * into v_definition from public.wf_definition
    where id=v_definition_id and tenant_id=v_tenant_id for update;
    if not found then raise exception '流程不存在或无权编辑'; end if;
    if v_definition.current_version_id is not null and (
      v_definition.code <> btrim(p_definition->>'code')
      or v_definition.business_type <> btrim(p_definition->>'businessType')
    ) then
      raise exception '流程发布后不可修改流程编码和业务类型';
    end if;
    update public.wf_definition set
      code=btrim(p_definition->>'code'),name=btrim(p_definition->>'name'),
      business_type=btrim(p_definition->>'businessType'),
      description=nullif(btrim(coalesce(p_definition->>'description','')),''),update_by=v_actor
    where id=v_definition.id returning * into v_definition;
    select * into v_version from public.wf_version
    where definition_id=v_definition.id and status='draft' for update;
    if found then
      update public.wf_version set config=v_config,
        change_note=nullif(btrim(coalesce(p_definition->>'changeNote','')),''),update_by=v_actor
      where id=v_version.id returning * into v_version;
    else
      insert into public.wf_version(definition_id,version_no,config,change_note,tenant_id,create_by,update_by)
      select v_definition.id,coalesce(max(version_no),0)+1,v_config,
        nullif(btrim(coalesce(p_definition->>'changeNote','')),''),v_tenant_id,v_actor,v_actor
      from public.wf_version where definition_id=v_definition.id
      returning * into v_version;
    end if;
  end if;
  return jsonb_build_object('definitionId',v_definition.id,'versionId',v_version.id,'versionNo',v_version.version_no);
end;
$$;
create or replace function app_private.publish_workflow_definition(p_definition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_definition public.wf_definition;
  v_version public.wf_version;
  v_actor text := coalesce(nullif(auth.jwt()->>'email',''),auth.uid()::text);
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有流程发布权限' using errcode='42501';
  end if;
  select * into v_definition from public.wf_definition
  where id=p_definition_id and tenant_id=v_tenant_id for update;
  if not found then raise exception '流程不存在或无权发布'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_tenant_id::text||':'||v_definition.business_type,81173));
  if exists (
    select 1 from public.wf_definition d where d.tenant_id=v_tenant_id
      and d.business_type=v_definition.business_type and d.status='published' and d.id<>v_definition.id
  ) then raise exception '该业务类型已有启用流程，请先停用后再发布'; end if;
  select * into v_version from public.wf_version
  where definition_id=v_definition.id and status='draft' for update;
  if not found then raise exception '没有可发布的草稿版本'; end if;
  perform app_private.validate_workflow_config(v_version.config);
  update public.wf_version set status='retired',update_by=v_actor
  where definition_id=v_definition.id and status='published';
  update public.wf_version set status='published',published_at=now(),published_by=v_actor,update_by=v_actor
  where id=v_version.id returning * into v_version;
  update public.wf_definition set status='published',current_version_id=v_version.id,
    published_at=now(),published_by=v_actor,update_by=v_actor
  where id=v_definition.id;
  return jsonb_build_object('definitionId',v_definition.id,'versionId',v_version.id,'versionNo',v_version.version_no);
end;
$$;
create or replace function app_private.set_workflow_definition_enabled(p_definition_id uuid,p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_definition public.wf_definition;
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有流程启停权限' using errcode='42501';
  end if;
  select * into v_definition from public.wf_definition
  where id=p_definition_id and tenant_id=v_tenant_id for update;
  if not found then raise exception '流程不存在或无权操作'; end if;
  if p_enabled and v_definition.current_version_id is null then raise exception '流程尚未发布，不能启用'; end if;
  if p_enabled and exists (
    select 1 from public.wf_definition d where d.tenant_id=v_tenant_id
      and d.business_type=v_definition.business_type and d.status='published' and d.id<>v_definition.id
  ) then raise exception '该业务类型已有启用流程'; end if;
  update public.wf_definition set status=case when p_enabled then 'published' else 'disabled' end
  where id=p_definition_id;
end;
$$;
create or replace function app_private.delete_workflow_definition(p_definition_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有流程删除权限' using errcode='42501';
  end if;
  if exists (select 1 from public.wf_instance where definition_id=p_definition_id) then
    raise exception '流程已有运行记录，不能删除，可改为停用';
  end if;
  delete from public.wf_definition
  where id=p_definition_id and tenant_id=v_tenant_id and current_version_id is null;
  if not found then raise exception '仅未发布且无实例的流程可以删除'; end if;
end;
$$;
create or replace function app_private.start_workflow(
  p_business_type text,p_business_id uuid,p_business_title text,p_context jsonb,p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_user_id uuid := (select app_private.current_app_user_id());
  v_actor text := coalesce(nullif(auth.jwt()->>'email',''),auth.uid()::text);
  v_actor_name text;
  v_definition public.wf_definition;
  v_instance_id uuid;
  v_context jsonb := coalesce(p_context,'{}'::jsonb);
  v_cost record;
begin
  if (select auth.uid()) is null or v_user_id is null then raise exception '当前登录用户未绑定业务账号'; end if;
  if jsonb_typeof(v_context) <> 'object' then raise exception '流程上下文必须是对象'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_tenant_id::text||':'||p_business_type||':'||p_business_id::text,91311));
  select id into v_instance_id from public.wf_instance
  where tenant_id=v_tenant_id and business_type=p_business_type and business_id=p_business_id and status='running';
  if found then return v_instance_id; end if;
  select coalesce(nullif(nick_name,''),nullif(user_name,''),user_email,id::text)
  into v_actor_name from public.sys_user where id=v_user_id and tenant_id=v_tenant_id and status='1';
  select * into v_definition from public.wf_definition
  where tenant_id=v_tenant_id and business_type=p_business_type and status='published';
  if not found then raise exception '当前业务类型没有已启用的审批流程'; end if;
  if p_business_type='tms_waybill_cost' then
    select id,tenant_id,audit_status,amount,cost_type,waybill_id into v_cost
    from public.tms_waybill_cost where id=p_business_id and tenant_id=v_tenant_id for update;
    if not found then raise exception '运单费用不存在或无权提交'; end if;
    if v_cost.audit_status not in ('draft','rejected') then raise exception '当前费用状态不允许提交审批'; end if;
    v_context := v_context || jsonb_build_object(
      'amount',v_cost.amount,'costType',v_cost.cost_type,'waybillId',v_cost.waybill_id
    );
  end if;
  insert into public.wf_instance(
    definition_id,version_id,business_type,business_id,business_title,initiator_user_id,
    initiator_name_snapshot,context_snapshot,tenant_id,create_by,update_by
  ) values (
    v_definition.id,v_definition.current_version_id,p_business_type,p_business_id,
    btrim(p_business_title),v_user_id,v_actor_name,v_context,v_tenant_id,v_actor,v_actor
  ) returning id into v_instance_id;
  insert into public.wf_action(
    instance_id,action,actor_user_id,actor_name_snapshot,comment,idempotency_key,tenant_id,create_by
  ) values (
    v_instance_id,'submit',v_user_id,v_actor_name,'提交审批',nullif(p_idempotency_key,''),v_tenant_id,v_actor
  );
  perform app_private.apply_workflow_business_status(p_business_type,p_business_id,'running',v_actor_name,null);
  perform app_private.activate_next_workflow_node(v_instance_id,0);
  return v_instance_id;
end;
$$;
create or replace function app_private.act_workflow_task(
  p_task_id uuid,p_action text,p_comment text,p_idempotency_key text
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
begin
  if (select auth.uid()) is null or v_user_id is null then raise exception '当前登录用户未绑定业务账号'; end if;
  if p_action not in ('approve','reject') then raise exception '不支持的审批动作'; end if;
  if p_action='reject' and btrim(coalesce(p_comment,''))='' then raise exception '驳回时必须填写原因'; end if;
  if nullif(p_idempotency_key,'') is not null then
    select instance_id into v_existing_instance_id from public.wf_action
    where tenant_id=v_tenant_id and idempotency_key=p_idempotency_key;
    if found then return v_existing_instance_id; end if;
  end if;
  select * into v_task from public.wf_task
  where id=p_task_id and tenant_id=v_tenant_id for update;
  if not found or v_task.assignee_user_id<>v_user_id then raise exception '待办不存在或当前用户不是审批人'; end if;
  if v_task.status<>'pending' then raise exception '该待办已经处理'; end if;
  select * into v_instance from public.wf_instance where id=v_task.instance_id for update;
  if v_instance.status<>'running' or v_instance.current_node_key<>v_task.node_key then
    raise exception '流程已结束或待办节点已失效';
  end if;
  select coalesce(nullif(nick_name,''),nullif(user_name,''),user_email,id::text)
  into v_actor_name from public.sys_user where id=v_user_id;
  update public.wf_task set status=case when p_action='approve' then 'approved' else 'rejected' end,
    handled_at=now(),comment=nullif(btrim(coalesce(p_comment,'')),'') where id=v_task.id;
  insert into public.wf_action(
    instance_id,task_id,node_key,node_name,action,actor_user_id,actor_name_snapshot,
    comment,idempotency_key,tenant_id
  ) values (
    v_instance.id,v_task.id,v_task.node_key,v_task.node_name,p_action,v_user_id,v_actor_name,
    nullif(btrim(coalesce(p_comment,'')),''),nullif(p_idempotency_key,''),v_tenant_id
  );
  if p_action='reject' then
    update public.wf_task set status='cancelled',handled_at=now(),comment='同节点已驳回'
    where instance_id=v_instance.id and node_key=v_task.node_key and status='pending';
    update public.wf_instance set status='rejected',finished_at=now(),finish_comment=p_comment,
      current_node_key=null,current_node_name=null,row_version=row_version+1 where id=v_instance.id;
    perform app_private.apply_workflow_business_status(
      v_instance.business_type,v_instance.business_id,'rejected',v_actor_name,p_comment
    );
    return v_instance.id;
  end if;
  if v_task.approval_mode='all' and exists (
    select 1 from public.wf_task where instance_id=v_instance.id
      and node_key=v_task.node_key and status='pending'
  ) then return v_instance.id; end if;
  if v_task.approval_mode='any' then
    update public.wf_task set status='cancelled',handled_at=now(),comment='同节点已由其他审批人通过'
    where instance_id=v_instance.id and node_key=v_task.node_key and status='pending';
  end if;
  perform app_private.activate_next_workflow_node(v_instance.id,v_task.node_order);
  return v_instance.id;
end;
$$;
create or replace function app_private.withdraw_workflow(p_instance_id uuid,p_comment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select app_private.current_app_user_id());
  v_instance public.wf_instance;
  v_actor_name text;
begin
  select * into v_instance from public.wf_instance where id=p_instance_id for update;
  if not found or v_instance.initiator_user_id<>v_user_id then raise exception '流程不存在或仅发起人可以撤回'; end if;
  if v_instance.status<>'running' then raise exception '流程已结束，不能撤回'; end if;
  if exists (select 1 from public.wf_task where instance_id=p_instance_id and status in ('approved','rejected')) then
    raise exception '已有审批人处理，不能直接撤回';
  end if;
  select coalesce(nullif(nick_name,''),nullif(user_name,''),user_email,id::text)
  into v_actor_name from public.sys_user where id=v_user_id;
  update public.wf_task set status='cancelled',handled_at=now(),comment='发起人撤回'
  where instance_id=p_instance_id and status='pending';
  update public.wf_instance set status='withdrawn',finished_at=now(),finish_comment=p_comment,
    current_node_key=null,current_node_name=null,row_version=row_version+1 where id=p_instance_id;
  insert into public.wf_action(instance_id,action,actor_user_id,actor_name_snapshot,comment,tenant_id)
  values (p_instance_id,'withdraw',v_user_id,v_actor_name,nullif(btrim(coalesce(p_comment,'')),''),v_instance.tenant_id);
  perform app_private.apply_workflow_business_status(
    v_instance.business_type,v_instance.business_id,'withdrawn',v_actor_name,p_comment
  );
end;
$$;
create or replace function public.save_workflow_definition(p_definition jsonb)
returns jsonb language sql security invoker set search_path='' as
$$ select app_private.save_workflow_definition(p_definition) $$;
create or replace function public.publish_workflow_definition(p_definition_id uuid)
returns jsonb language sql security invoker set search_path='' as
$$ select app_private.publish_workflow_definition(p_definition_id) $$;
create or replace function public.set_workflow_definition_enabled(p_definition_id uuid,p_enabled boolean)
returns void language sql security invoker set search_path='' as
$$ select app_private.set_workflow_definition_enabled(p_definition_id,p_enabled) $$;
create or replace function public.delete_workflow_definition(p_definition_id uuid)
returns void language sql security invoker set search_path='' as
$$ select app_private.delete_workflow_definition(p_definition_id) $$;
create or replace function public.start_workflow(
  p_business_type text,p_business_id uuid,p_business_title text,p_context jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns uuid language sql security invoker set search_path='' as
$$ select app_private.start_workflow(p_business_type,p_business_id,p_business_title,p_context,p_idempotency_key) $$;
create or replace function public.act_workflow_task(
  p_task_id uuid,p_action text,p_comment text default null,p_idempotency_key text default null
)
returns uuid language sql security invoker set search_path='' as
$$ select app_private.act_workflow_task(p_task_id,p_action,p_comment,p_idempotency_key) $$;
create or replace function public.withdraw_workflow(p_instance_id uuid,p_comment text default null)
returns void language sql security invoker set search_path='' as
$$ select app_private.withdraw_workflow(p_instance_id,p_comment) $$;
revoke all on function public.save_workflow_definition(jsonb) from public, anon;
revoke all on function public.publish_workflow_definition(uuid) from public, anon;
revoke all on function public.set_workflow_definition_enabled(uuid,boolean) from public, anon;
revoke all on function public.delete_workflow_definition(uuid) from public, anon;
revoke all on function public.start_workflow(text,uuid,text,jsonb,text) from public, anon;
revoke all on function public.act_workflow_task(uuid,text,text,text) from public, anon;
revoke all on function public.withdraw_workflow(uuid,text) from public, anon;
grant execute on function public.save_workflow_definition(jsonb) to authenticated, service_role;
grant execute on function public.publish_workflow_definition(uuid) to authenticated, service_role;
grant execute on function public.set_workflow_definition_enabled(uuid,boolean) to authenticated, service_role;
grant execute on function public.delete_workflow_definition(uuid) to authenticated, service_role;
grant execute on function public.start_workflow(text,uuid,text,jsonb,text) to authenticated, service_role;
grant execute on function public.act_workflow_task(uuid,text,text,text) to authenticated, service_role;
grant execute on function public.withdraw_workflow(uuid,text) to authenticated, service_role;
grant execute on function app_private.save_workflow_definition(jsonb) to authenticated, service_role;
grant execute on function app_private.publish_workflow_definition(uuid) to authenticated, service_role;
grant execute on function app_private.set_workflow_definition_enabled(uuid,boolean) to authenticated, service_role;
grant execute on function app_private.delete_workflow_definition(uuid) to authenticated, service_role;
grant execute on function app_private.start_workflow(text,uuid,text,jsonb,text) to authenticated, service_role;
grant execute on function app_private.act_workflow_task(uuid,text,text,text) to authenticated, service_role;
grant execute on function app_private.withdraw_workflow(uuid,text) to authenticated, service_role;
-- Dictionary catalog for every persisted workflow enum.
with platform as (
  select id from public.sys_tenant where tenant_code='platform' limit 1
)
insert into public.sys_dict_type(id,name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort)
select gen_random_uuid(),'审批流程','workflowEngine','1','624944977@qq.com','624944977@qq.com',id,null,'directory',60
from platform where not exists (select 1 from public.sys_dict_type where code='workflowEngine');
with platform as (select id from public.sys_tenant where tenant_code='platform' limit 1),
parent as (select id,tenant_id from public.sys_dict_type where code='workflowEngine' limit 1),
items(name,code,sort) as (values
 ('流程定义状态','workflowDefinitionStatus',1),('流程实例状态','workflowInstanceStatus',2),
 ('审批任务状态','workflowTaskStatus',3),('审批业务类型','workflowBusinessType',4),
 ('审批人类型','workflowAssigneeType',5),('节点审批方式','workflowApprovalMode',6),
 ('条件运算符','workflowConditionOperator',7),('审批动作类型','workflowActionType',8)
)
insert into public.sys_dict_type(id,parent_id,name,code,status,node_type,sort,tenant_id,create_by,update_by)
select gen_random_uuid(),parent.id,items.name,items.code,'1','dictionary',items.sort,platform.id,
  '624944977@qq.com','624944977@qq.com'
from platform cross join parent cross join items
where not exists (select 1 from public.sys_dict_type d where d.code=items.code);
with rows(dict_code,value,label,sort,tag_type) as (values
 ('workflowDefinitionStatus','draft','草稿',1,'info'),('workflowDefinitionStatus','published','已发布',2,'success'),('workflowDefinitionStatus','disabled','已停用',3,'warning'),
 ('workflowInstanceStatus','running','审批中',1,'warning'),('workflowInstanceStatus','approved','已通过',2,'success'),('workflowInstanceStatus','rejected','已驳回',3,'danger'),('workflowInstanceStatus','withdrawn','已撤回',4,'info'),('workflowInstanceStatus','cancelled','已取消',5,'info'),
 ('workflowTaskStatus','pending','待处理',1,'warning'),('workflowTaskStatus','approved','已同意',2,'success'),('workflowTaskStatus','rejected','已驳回',3,'danger'),('workflowTaskStatus','cancelled','已取消',4,'info'),
 ('workflowBusinessType','generic','通用审批',1,'primary'),('workflowBusinessType','tms_waybill_cost','运单费用',2,'warning'),('workflowBusinessType','tms_invoice','发票复核',3,'primary'),('workflowBusinessType','tms_contract','运输合同',4,'success'),('workflowBusinessType','vehicle_archive','车辆档案',5,'info'),
 ('workflowAssigneeType','users','指定人员',1,'primary'),('workflowAssigneeType','roles','指定角色',2,'success'),('workflowAssigneeType','initiator','发起人',3,'info'),
 ('workflowApprovalMode','any','或签（一人通过）',1,'primary'),('workflowApprovalMode','all','会签（全部通过）',2,'warning'),
 ('workflowConditionOperator','always','无条件',1,'info'),('workflowConditionOperator','eq','等于',2,'primary'),('workflowConditionOperator','ne','不等于',3,'primary'),('workflowConditionOperator','gt','大于',4,'warning'),('workflowConditionOperator','gte','大于等于',5,'warning'),('workflowConditionOperator','lt','小于',6,'warning'),('workflowConditionOperator','lte','小于等于',7,'warning'),('workflowConditionOperator','in','属于集合',8,'primary'),('workflowConditionOperator','contains','包含',9,'primary'),('workflowConditionOperator','not_empty','不为空',10,'success'),
 ('workflowActionType','submit','提交',1,'primary'),('workflowActionType','approve','同意',2,'success'),('workflowActionType','reject','驳回',3,'danger'),('workflowActionType','withdraw','撤回',4,'info'),('workflowActionType','cancel','取消',5,'info'),('workflowActionType','auto_skip','自动跳过',6,'info')
), platform as (select id from public.sys_tenant where tenant_code='platform' limit 1), resolved as (
 select rows.*,t.id type_id,platform.id tenant_id from rows cross join platform
 join public.sys_dict_type t on t.code=rows.dict_code
)
insert into public.sys_dictionary(
 id,type_id,code,status,value,label,sort,tag_type,tenant_id,create_by,update_by
)
select gen_random_uuid(),type_id,dict_code||'_'||value,'1',value,label,sort::bigint,tag_type,tenant_id,
 '624944977@qq.com','624944977@qq.com'
from resolved where not exists (
 select 1 from public.sys_dictionary d where d.type_id=resolved.type_id and d.value=resolved.value
);
-- Backend-driven navigation. All enabled roles can use the workbench; workflow management is limited to admins.
insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,create_by,update_by)
select gen_random_uuid(),null,'WorkflowCenter','/workflow','/index/index',jsonb_build_object(
 'icon','ri:git-merge-line','title','审批中心','is_hide',false,'is_enable',true,'keep_alive',true
),42,'folder','624944977@qq.com','624944977@qq.com'
where not exists (select 1 from public.sys_menu where name='WorkflowCenter');
insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,create_by,update_by)
select gen_random_uuid(),p.id,'WorkflowWorkbench','workbench','/workflow/workbench',jsonb_build_object(
 'icon','ri:inbox-archive-line','title','审批工作台','is_hide',false,'is_enable',true,'keep_alive',true
),1,'menu','624944977@qq.com','624944977@qq.com'
from public.sys_menu p where p.name='WorkflowCenter'
and not exists (select 1 from public.sys_menu where name='WorkflowWorkbench');
insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,create_by,update_by)
select gen_random_uuid(),p.id,'WorkflowDefinition','definition','/workflow/definition',jsonb_build_object(
 'icon','ri:flow-chart','title','流程管理','roles',jsonb_build_array('R_SUPER','R_ADMIN','YQ_ADMIN'),
 'is_hide',false,'is_enable',true,'keep_alive',true,
 'authList',jsonb_build_array(
   jsonb_build_object('title','新建流程','authMark','create'),
   jsonb_build_object('title','编辑流程','authMark','edit'),
   jsonb_build_object('title','发布流程','authMark','publish')
 )
),2,'menu','624944977@qq.com','624944977@qq.com'
from public.sys_menu p where p.name='WorkflowCenter'
and not exists (select 1 from public.sys_menu where name='WorkflowDefinition');
insert into public.sys_role_menu(id,role_id,menu_id,permission,create_by,update_by,tenant_id)
select gen_random_uuid(),r.id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
from public.sys_role r cross join public.sys_menu m
where r.enabled and m.name in ('WorkflowCenter','WorkflowWorkbench')
on conflict (role_id,menu_id) do nothing;
insert into public.sys_role_menu(id,role_id,menu_id,permission,create_by,update_by,tenant_id)
select gen_random_uuid(),r.id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
from public.sys_role r cross join public.sys_menu m
where r.enabled and r.role_code in ('R_SUPER','R_ADMIN','YQ_ADMIN') and m.name='WorkflowDefinition'
on conflict (role_id,menu_id) do nothing;
-- Ship one usable published flow per ordinary tenant for the first real integration.
with tenant_admin as (
  select t.id tenant_id,
         coalesce((array_agg(r.role_code order by case when r.role_code in ('R_ADMIN','YQ_ADMIN') then 0 else 1 end))[1],'R_ADMIN') role_code
  from public.sys_tenant t left join public.sys_role r on r.tenant_id=t.id and r.enabled
  where t.tenant_code<>'platform'
  group by t.id
), inserted_definition as (
  insert into public.wf_definition(
    code,name,business_type,description,status,published_at,published_by,tenant_id,create_by,update_by
  )
  select 'tms-waybill-cost-approval','运单费用审批','tms_waybill_cost',
    '费用提交后由租户管理员审核；后续可在流程管理中新增版本。','published',now(),
    '624944977@qq.com',tenant_id,'624944977@qq.com','624944977@qq.com'
  from tenant_admin
  where not exists (
    select 1 from public.wf_definition d where d.tenant_id=tenant_admin.tenant_id and d.code='tms-waybill-cost-approval'
  ) returning id,tenant_id
), inserted_version as (
  insert into public.wf_version(
    definition_id,version_no,status,config,change_note,published_at,published_by,tenant_id,create_by,update_by
  )
  select d.id,1,'published',jsonb_build_object('nodes',jsonb_build_array(jsonb_build_object(
    'key','finance-review','name','财务审核','order',1,'approvalMode','any','allowSelfApproval',false,
    'dueHours',24,'assignee',jsonb_build_object('type','roles','roleCodes',jsonb_build_array(a.role_code)),
    'condition',jsonb_build_object('operator','always')
  ))),'系统初始化版本',now(),'624944977@qq.com',d.tenant_id,'624944977@qq.com','624944977@qq.com'
  from inserted_definition d join tenant_admin a on a.tenant_id=d.tenant_id
  returning id,definition_id
)
update public.wf_definition d set current_version_id=v.id
from inserted_version v where d.id=v.definition_id;
