create or replace function app_private.can_manage_vehicle_reminders()
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
        && array['R_SUPER', 'R_ADMIN', 'YQ_ADMIN', 'R_REGISTER']::text[]
  );
$$;
revoke execute on function app_private.can_manage_vehicle_reminders()
  from public, anon;
grant execute on function app_private.can_manage_vehicle_reminders()
  to authenticated, service_role;
create table if not exists public.vehicle_reminder_work_order (
  id uuid primary key default gen_random_uuid(),
  source_type text not null,
  source_key text not null,
  source_version text not null,
  source_id uuid,
  vehicle_id uuid not null references public.vehicle_archive(id) on delete restrict,
  plate_no_snapshot text not null,
  company_name_snapshot text,
  title text not null,
  status text not null default 'pending',
  priority text not null default 'normal',
  due_date date,
  remaining_days_snapshot integer,
  assignee_name text,
  resolution text,
  evidence jsonb not null default '[]'::jsonb,
  started_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint vehicle_reminder_work_order_source_type_check
    check (source_type in ('insurance', 'inspection', 'maintenance', 'part', 'vehicle')),
  constraint vehicle_reminder_work_order_status_check
    check (status in ('pending', 'in_progress', 'resolved', 'closed', 'cancelled')),
  constraint vehicle_reminder_work_order_priority_check
    check (priority in ('low', 'normal', 'high', 'urgent')),
  constraint vehicle_reminder_work_order_source_unique
    unique (tenant_id, source_type, source_key, source_version)
);
create index if not exists vehicle_reminder_work_order_vehicle_id_idx
  on public.vehicle_reminder_work_order(vehicle_id);
create index if not exists vehicle_reminder_work_order_tenant_status_due_idx
  on public.vehicle_reminder_work_order(tenant_id, status, due_date);
create or replace function public.trg_validate_vehicle_reminder_work_order()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_operator text;
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.source_type is distinct from old.source_type
     or new.source_key is distinct from old.source_key
     or new.source_version is distinct from old.source_version
     or new.source_id is distinct from old.source_id
     or new.vehicle_id is distinct from old.vehicle_id then
    raise exception '提醒来源和租户归属创建后不可修改';
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'pending' and new.status in ('in_progress', 'cancelled'))
    or (old.status = 'in_progress' and new.status in ('resolved', 'cancelled'))
    or (old.status = 'resolved' and new.status in ('in_progress', 'closed'))
  ) then
    raise exception '提醒处置单状态不允许从 % 直接变更为 %', old.status, new.status;
  end if;

  select coalesce(u.user_name, u.nick_name, u.user_email, (select auth.uid())::text)
    into v_operator
  from public.sys_user u
  where u.auth_user_id = (select auth.uid())
  limit 1;

  if new.status = 'in_progress' then
    new.assignee_name := coalesce(new.assignee_name, v_operator);
    new.started_at := coalesce(old.started_at, now());
    new.resolved_at := null;
    new.closed_at := null;
  elsif new.status = 'resolved' then
    if btrim(coalesce(new.resolution, '')) = '' then
      raise exception '标记为已解决前必须填写处置结果';
    end if;
    new.resolved_at := now();
    new.closed_at := null;
  elsif new.status = 'closed' then
    new.closed_at := now();
  end if;

  return new;
end;
$$;
revoke execute on function public.trg_validate_vehicle_reminder_work_order()
  from public, anon, authenticated;
drop trigger if exists vehicle_reminder_work_order_validate
  on public.vehicle_reminder_work_order;
create trigger vehicle_reminder_work_order_validate
before update on public.vehicle_reminder_work_order
for each row execute function public.trg_validate_vehicle_reminder_work_order();
drop trigger if exists vehicle_reminder_work_order_create_audit
  on public.vehicle_reminder_work_order;
create trigger vehicle_reminder_work_order_create_audit
before insert on public.vehicle_reminder_work_order
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists vehicle_reminder_work_order_update_audit
  on public.vehicle_reminder_work_order;
create trigger vehicle_reminder_work_order_update_audit
before update on public.vehicle_reminder_work_order
for each row execute function public.trg_set_update_time_and_by();
alter table public.vehicle_reminder_work_order enable row level security;
drop policy if exists vehicle_reminder_work_order_tenant_select
  on public.vehicle_reminder_work_order;
create policy vehicle_reminder_work_order_tenant_select
on public.vehicle_reminder_work_order
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
drop policy if exists vehicle_reminder_work_order_tenant_insert
  on public.vehicle_reminder_work_order;
create policy vehicle_reminder_work_order_tenant_insert
on public.vehicle_reminder_work_order
for insert
to authenticated
with check (
  (select app_private.can_manage_vehicle_reminders())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists vehicle_reminder_work_order_tenant_update
  on public.vehicle_reminder_work_order;
create policy vehicle_reminder_work_order_tenant_update
on public.vehicle_reminder_work_order
for update
to authenticated
using (
  (select app_private.can_manage_vehicle_reminders())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
)
with check (
  (select app_private.can_manage_vehicle_reminders())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
revoke all on table public.vehicle_reminder_work_order from public, anon;
grant select, insert, update on table public.vehicle_reminder_work_order to authenticated;
grant all on table public.vehicle_reminder_work_order to service_role;
create or replace function public.get_or_create_vehicle_reminder_work_order(p_reminder jsonb)
returns public.vehicle_reminder_work_order
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_work_order public.vehicle_reminder_work_order;
  v_vehicle_id uuid;
  v_source_id uuid;
  v_source_type text;
  v_source_key text;
  v_source_version text;
  v_remaining_days integer;
  v_tenant_id uuid;
  v_record_tenant_id uuid;
begin
  if not (select app_private.can_manage_vehicle_reminders()) then
    raise exception '当前角色无权建立车辆提醒处置单';
  end if;

  if p_reminder is null or jsonb_typeof(p_reminder) <> 'object' then
    raise exception '提醒资料格式不正确';
  end if;

  begin
    v_vehicle_id := nullif(p_reminder ->> 'vehicle_id', '')::uuid;
    v_source_id := nullif(p_reminder ->> 'source_id', '')::uuid;
    v_remaining_days := nullif(p_reminder ->> 'remaining_days', '')::integer;
  exception
    when invalid_text_representation then
      raise exception '提醒车辆、来源或剩余天数格式不正确';
  end;

  v_source_type := btrim(coalesce(p_reminder ->> 'source_type', ''));
  v_source_key := btrim(coalesce(p_reminder ->> 'source_key', ''));
  v_source_version := btrim(coalesce(p_reminder ->> 'source_version', ''));
  v_tenant_id := (select app_private.current_user_tenant_id());

  if v_source_type not in ('insurance', 'inspection', 'maintenance', 'part', 'vehicle')
     or v_source_key = '' or v_source_version = '' or v_vehicle_id is null then
    raise exception '提醒来源标识不完整';
  end if;

  select v.tenant_id
    into v_record_tenant_id
    from public.vehicle_archive v
    where v.id = v_vehicle_id
      and (
        (select app_private.is_platform_super())
        or v.tenant_id = v_tenant_id
      );

  if not found then
    raise exception '车辆不存在或当前用户无权访问';
  end if;

  insert into public.vehicle_reminder_work_order (
    source_type,
    source_key,
    source_version,
    source_id,
    vehicle_id,
    plate_no_snapshot,
    company_name_snapshot,
    title,
    priority,
    due_date,
    remaining_days_snapshot,
    tenant_id
  )
  values (
    v_source_type,
    v_source_key,
    v_source_version,
    v_source_id,
    v_vehicle_id,
    btrim(coalesce(p_reminder ->> 'plate_no', '')),
    nullif(btrim(coalesce(p_reminder ->> 'company_name', '')), ''),
    btrim(coalesce(p_reminder ->> 'title', '车辆到期提醒处置')),
    case
      when v_remaining_days is null then 'normal'
      when v_remaining_days < 0 then 'urgent'
      when v_remaining_days <= 30 then 'high'
      when v_remaining_days <= 90 then 'normal'
      else 'low'
    end,
    nullif(p_reminder ->> 'due_date', '')::date,
    v_remaining_days,
    v_record_tenant_id
  )
  on conflict (tenant_id, source_type, source_key, source_version)
  do update set
    plate_no_snapshot = excluded.plate_no_snapshot,
    company_name_snapshot = excluded.company_name_snapshot,
    remaining_days_snapshot = excluded.remaining_days_snapshot
  returning * into v_work_order;

  return v_work_order;
end;
$$;
revoke execute on function public.get_or_create_vehicle_reminder_work_order(jsonb)
  from public, anon;
grant execute on function public.get_or_create_vehicle_reminder_work_order(jsonb)
  to authenticated, service_role;
create or replace function public.transition_vehicle_reminder_work_order(
  p_work_order_id uuid,
  p_next_status text,
  p_resolution text default null
)
returns public.vehicle_reminder_work_order
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_work_order public.vehicle_reminder_work_order;
begin
  if not (select app_private.can_manage_vehicle_reminders()) then
    raise exception '当前角色无权流转车辆提醒处置单';
  end if;

  select * into v_work_order
  from public.vehicle_reminder_work_order
  where id = p_work_order_id
  for update;

  if not found then
    raise exception '处置单不存在或当前用户无权访问';
  end if;

  update public.vehicle_reminder_work_order
  set status = p_next_status,
      resolution = case
        when p_resolution is null then resolution
        else nullif(btrim(p_resolution), '')
      end
  where id = p_work_order_id
  returning * into v_work_order;

  return v_work_order;
end;
$$;
revoke execute on function public.transition_vehicle_reminder_work_order(uuid, text, text)
  from public, anon;
grant execute on function public.transition_vehicle_reminder_work_order(uuid, text, text)
  to authenticated, service_role;
with platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), parent as (
  select parent_id
  from public.sys_dict_type
  where code = 'commonBoolean' and tenant_id = (select id from platform)
  limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(), '车辆提醒处置单状态', 'vehicleReminderWorkOrderStatus', '1',
  '624944977@qq.com', '624944977@qq.com', platform.id, parent.parent_id, 'dictionary', 30
from platform cross join parent
where not exists (
  select 1 from public.sys_dict_type existing
  where existing.code = 'vehicleReminderWorkOrderStatus'
    and existing.tenant_id = platform.id
);
with platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), rows(code, label, sort, tag_type) as (values
  ('pending', '待处理', 1::bigint, 'warning'),
  ('in_progress', '处理中', 2::bigint, 'primary'),
  ('resolved', '已解决', 3::bigint, 'success'),
  ('closed', '已关闭', 4::bigint, 'info'),
  ('cancelled', '已取消', 5::bigint, 'info')
), resolved as (
  select rows.*, dict_type.id type_id, platform.id tenant_id
  from rows cross join platform
  join public.sys_dict_type dict_type
    on dict_type.code = 'vehicleReminderWorkOrderStatus'
   and dict_type.tenant_id = platform.id
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, value, label,
  i18n_scope, sort, tenant_id, tag_type
)
select
  gen_random_uuid(), type_id, code, '1', '624944977@qq.com', '624944977@qq.com',
  code, label, '1', sort, tenant_id, tag_type
from resolved
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = resolved.type_id
    and existing.value = resolved.code
    and existing.tenant_id = resolved.tenant_id
);
