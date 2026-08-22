begin;

create table if not exists public.sys_application (
  app_code text primary key,
  app_name text not null,
  description text,
  base_url text not null,
  menu_root_path text not null,
  enabled boolean not null default true,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sys_application_code_format_chk
    check (app_code ~ '^[a-z][a-z0-9-]*$'),
  constraint sys_application_base_url_chk
    check (base_url ~ '^(/|https?://)'),
  constraint sys_application_menu_root_path_chk
    check (menu_root_path like '/%')
);

comment on table public.sys_application is
  'Platform-owned registry for independently deployed frontend applications.';
comment on column public.sys_application.app_code is
  'Stable application contract identifier used by menu and deployment isolation.';

create or replace function app_private.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_sys_application_touch_updated_at on public.sys_application;
create trigger trg_sys_application_touch_updated_at
before update on public.sys_application
for each row execute function app_private.touch_updated_at();

insert into public.sys_application (
  app_code,
  app_name,
  description,
  base_url,
  menu_root_path,
  sort
)
values
  ('platform', 'Art Supabase Platform', '系统、租户、菜单、权限与数据中心基座', '/', '/dashboard', 0),
  ('finance', 'Art Supabase Finance', '独立财务应用预留仓', '/finance/', '/finance', 10),
  ('fms', 'Art Supabase FMS', '财务管理系统', '/fms/', '/fms', 20),
  ('hr', 'Art Supabase HR', '人力资源管理系统', '/hr/', '/hr', 30),
  ('smis', 'Art Supabase SMIS', '安全生产管理系统', '/smis/', '/smis', 40),
  ('vms', 'Art Supabase VMS', '车辆管理系统', '/vms/', '/vms', 50)
on conflict (app_code) do update
set app_name = excluded.app_name,
    description = excluded.description,
    menu_root_path = excluded.menu_root_path,
    sort = excluded.sort;

alter table public.sys_menu
  add column if not exists app_code text;

insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  meta,
  sort,
  type,
  app_code,
  create_by
)
values
  (
    'f1000000-0000-4000-8000-000000000001',
    null,
    'FinanceApplication',
    '/finance',
    '/index/index',
    jsonb_build_object('title', 'Finance 财务应用', 'icon', 'ri:money-cny-circle-line'),
    10,
    'folder',
    'finance',
    'system'
  ),
  (
    'f1000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000001',
    'FinanceApplicationHome',
    'index',
    '/finance/index',
    jsonb_build_object('title', '应用首页', 'icon', 'ri:home-4-line'),
    1,
    'menu',
    'finance',
    'system'
  )
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code;

with recursive classified_menu as (
  select
    menu_row.id,
    case menu_row.path
      when '/finance' then 'finance'
      when '/fms' then 'fms'
      when '/hr' then 'hr'
      when '/smis' then 'smis'
      when '/vms' then 'vms'
      else 'platform'
    end as app_code
  from public.sys_menu menu_row
  where menu_row.parent_id is null

  union all

  select child.id, parent.app_code
  from public.sys_menu child
  join classified_menu parent on parent.id = child.parent_id
)
update public.sys_menu target
set app_code = classified_menu.app_code
from classified_menu
where target.id = classified_menu.id
  and target.app_code is distinct from classified_menu.app_code;

update public.sys_menu set app_code = 'platform' where app_code is null;

alter table public.sys_menu alter column app_code set default 'platform';
alter table public.sys_menu alter column app_code set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sys_menu_app_code_fkey'
      and conrelid = 'public.sys_menu'::regclass
  ) then
    alter table public.sys_menu
      add constraint sys_menu_app_code_fkey
      foreign key (app_code) references public.sys_application(app_code)
      on update cascade on delete restrict;
  end if;
end;
$$;

create index if not exists idx_sys_menu_app_parent_sort
  on public.sys_menu (app_code, parent_id, sort, id);

alter table public.sys_application enable row level security;
alter table public.sys_application force row level security;

drop policy if exists sys_application_platform_manage on public.sys_application;
create policy sys_application_platform_manage
on public.sys_application
for all
to authenticated
using (app_private.is_platform_super())
with check (app_private.is_platform_super());

revoke all on table public.sys_application from anon, authenticated;
grant all on table public.sys_application to service_role;

create or replace function public.get_menus_for_current_application(
  p_app_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cur_uid uuid := (select auth.uid());
  v_app_code text := lower(nullif(btrim(p_app_code), ''));
  v_role_ids uuid[] := '{}';
  v_menu_ids uuid[] := '{}';
  v_rec record;
  v_depth_rec record;
  v_node_map jsonb := '{}'::jsonb;
  v_roots jsonb := '[]'::jsonb;
  v_flat jsonb := '[]'::jsonb;
  v_parent_id text;
  v_children jsonb;
begin
  if v_cur_uid is null or not exists (
    select 1
    from public.sys_application application_row
    where application_row.app_code = v_app_code
      and application_row.enabled
  ) then
    return jsonb_build_object('flat', v_flat, 'tree', v_roots);
  end if;

  if app_private.is_platform_super() then
    select array_remove(array_agg(menu_row.id order by menu_row.sort nulls last, menu_row.id), null)
    into v_menu_ids
    from public.sys_menu menu_row
    where menu_row.app_code = v_app_code
      and (menu_row.meta->>'is_enable') is distinct from 'false';
  else
    select array_remove(array_agg(distinct role_row.id), null)
    into v_role_ids
    from public.sys_user current_user_row
    join public.sys_role role_row
      on role_row.role_code = any(coalesce(current_user_row.user_roles, array[]::text[]))
     and role_row.enabled
     and (
       role_row.tenant_id = current_user_row.tenant_id
       or role_row.tenant_id is null
     )
    where current_user_row.auth_user_id = v_cur_uid
      and current_user_row.status = '1'
      and current_user_row.deleted_at is null;

    if v_role_ids is null or array_length(v_role_ids, 1) is null then
      return jsonb_build_object('flat', v_flat, 'tree', v_roots);
    end if;

    select array_remove(array_agg(distinct role_menu.menu_id), null)
    into v_menu_ids
    from public.sys_role_menu role_menu
    join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
    where role_menu.role_id = any(v_role_ids)
      and menu_row.app_code = v_app_code
      and (menu_row.meta->>'is_enable') is distinct from 'false';
  end if;

  if v_menu_ids is null or array_length(v_menu_ids, 1) is null then
    return jsonb_build_object('flat', v_flat, 'tree', v_roots);
  end if;

  for v_rec in
    select menu_row.id, menu_row.parent_id, menu_row.name, menu_row.path,
           menu_row.component, menu_row.meta, menu_row.sort, menu_row.type
    from public.sys_menu menu_row
    where menu_row.id = any(v_menu_ids)
    order by menu_row.sort nulls last, menu_row.id
  loop
    v_flat := v_flat || jsonb_build_object(
      'id', v_rec.id,
      'parentId', v_rec.parent_id,
      'name', v_rec.name,
      'path', v_rec.path,
      'component', v_rec.component,
      'meta', v_rec.meta,
      'sort', v_rec.sort,
      'type', v_rec.type
    );

    v_node_map := v_node_map || jsonb_build_object(v_rec.id::text, jsonb_build_object(
      'id', v_rec.id,
      'parentId', v_rec.parent_id,
      'name', v_rec.name,
      'path', v_rec.path,
      'component', v_rec.component,
      'meta', v_rec.meta,
      'sort', v_rec.sort,
      'type', v_rec.type,
      'children', '[]'::jsonb
    ));
  end loop;

  for v_depth_rec in
    with recursive ancestor_depth as (
      select menu_row.id as node_id, menu_row.parent_id, 0 as depth
      from public.sys_menu menu_row
      where menu_row.id = any(v_menu_ids)

      union all

      select ancestor.node_id, parent.parent_id, ancestor.depth + 1
      from ancestor_depth ancestor
      join public.sys_menu parent on parent.id = ancestor.parent_id
      where parent.id = any(v_menu_ids)
    ), node_depth as (
      select node_id, max(depth) as depth
      from ancestor_depth
      group by node_id
    )
    select menu_row.id, menu_row.parent_id, menu_row.sort, node_depth.depth
    from public.sys_menu menu_row
    join node_depth on node_depth.node_id = menu_row.id
    where menu_row.id = any(v_menu_ids)
    order by node_depth.depth desc, menu_row.sort nulls last, menu_row.id
  loop
    v_parent_id := v_depth_rec.parent_id::text;
    if v_parent_id is not null and v_node_map ? v_parent_id then
      v_children := (v_node_map -> v_parent_id) -> 'children';
      v_children := v_children || (v_node_map -> v_depth_rec.id::text);
      v_node_map := jsonb_set(
        v_node_map,
        array[v_parent_id],
        (v_node_map -> v_parent_id) - 'children' || jsonb_build_object('children', v_children)
      );
    end if;
  end loop;

  for v_rec in
    select menu_row.id, menu_row.parent_id
    from public.sys_menu menu_row
    where menu_row.id = any(v_menu_ids)
      and (menu_row.parent_id is null or not v_node_map ? menu_row.parent_id::text)
    order by menu_row.sort nulls last, menu_row.id
  loop
    v_roots := v_roots || (v_node_map -> v_rec.id::text);
  end loop;

  return jsonb_build_object('flat', v_flat, 'tree', v_roots);
end;
$$;

create or replace function public.get_accessible_applications()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', application_row.app_code,
    'name', application_row.app_name,
    'description', application_row.description,
    'baseUrl', application_row.base_url,
    'sort', application_row.sort
  ) order by application_row.sort, application_row.app_code), '[]'::jsonb)
  from public.sys_application application_row
  where (select auth.uid()) is not null
    and application_row.enabled
    and (
      app_private.is_platform_super()
      or exists (
        select 1
        from public.sys_user current_user_row
        join public.sys_role role_row
          on role_row.role_code = any(coalesce(current_user_row.user_roles, array[]::text[]))
         and role_row.enabled
         and (
           role_row.tenant_id = current_user_row.tenant_id
           or role_row.tenant_id is null
         )
        join public.sys_role_menu role_menu on role_menu.role_id = role_row.id
        join public.sys_menu menu_row
          on menu_row.id = role_menu.menu_id
         and menu_row.app_code = application_row.app_code
        where current_user_row.auth_user_id = (select auth.uid())
          and current_user_row.status = '1'
          and current_user_row.deleted_at is null
      )
    );
$$;

create or replace function public.vms_list_hr_employee_options_secure(
  p_keyword text default null,
  p_max_rows integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
begin
  if v_tenant_id is null or not exists (
    select 1
    from public.sys_menu menu_row
    where menu_row.app_code = 'vms'
      and menu_row.type = 'menu'
      and app_private.can_access_business_menu(menu_row.name)
  ) then
    raise exception 'Missing VMS employee reference permission' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', employee_row.id,
      'employeeNo', employee_row.employee_no,
      'employeeName', employee_row.employee_name,
      'organizationId', employee_row.organization_id,
      'jobTitle', employee_row.job_title,
      'employmentStatus', employee_row.employment_status
    ) order by employee_row.employee_name, employee_row.employee_no, employee_row.id)
    from (
      select employee_record.*
      from public.hr_employee employee_record
      where employee_record.tenant_id = v_tenant_id
        and employee_record.employment_status in ('probation', 'active')
        and (
          v_keyword is null
          or employee_record.employee_no ilike '%' || v_keyword || '%'
          or employee_record.employee_name ilike '%' || v_keyword || '%'
          or employee_record.job_title ilike '%' || v_keyword || '%'
        )
      order by employee_record.employee_name, employee_record.employee_no, employee_record.id
      limit least(greatest(coalesce(p_max_rows, 100), 1), 500)
    ) employee_row
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_menus_for_current_application(text) from public, anon;
revoke all on function public.get_accessible_applications() from public, anon;
revoke all on function public.vms_list_hr_employee_options_secure(text, integer) from public, anon;
grant execute on function public.get_menus_for_current_application(text) to authenticated, service_role;
grant execute on function public.get_accessible_applications() to authenticated, service_role;
grant execute on function public.vms_list_hr_employee_options_secure(text, integer)
  to authenticated, service_role;

commit;
