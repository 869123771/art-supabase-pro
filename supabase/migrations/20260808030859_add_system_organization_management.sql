begin;

create table if not exists public.sys_organization (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  parent_id uuid,
  organization_code text not null,
  organization_name text not null,
  organization_type text not null default 'department',
  leader_user_id uuid references public.sys_user(id) on delete set null,
  status text not null default '1',
  sort integer not null default 0,
  phone text,
  email text,
  address text,
  description text,
  is_system boolean not null default false,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_organization_tenant_code_key unique (tenant_id, organization_code),
  constraint sys_organization_tenant_id_id_key unique (tenant_id, id),
  constraint sys_organization_status_check check (status in ('0', '1')),
  constraint sys_organization_type_check check (
    organization_type in ('company', 'division', 'department', 'team')
  ),
  constraint sys_organization_system_root_check check (
    not is_system
    or (
      parent_id is null
      and organization_code = 'ROOT'
      and organization_type = 'company'
      and status = '1'
    )
  ),
  constraint sys_organization_tenant_parent_fkey
    foreign key (tenant_id, parent_id)
    references public.sys_organization(tenant_id, id)
    on delete restrict
);

alter table public.sys_user
  add column if not exists organization_id uuid;

alter table public.sys_role
  add column if not exists organization_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sys_user_organization_id_fkey'
      and conrelid = 'public.sys_user'::regclass
  ) then
    alter table public.sys_user
      add constraint sys_user_organization_id_fkey
      foreign key (organization_id)
      references public.sys_organization(id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sys_role_organization_id_fkey'
      and conrelid = 'public.sys_role'::regclass
  ) then
    alter table public.sys_role
      add constraint sys_role_organization_id_fkey
      foreign key (organization_id)
      references public.sys_organization(id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists idx_sys_organization_tenant_parent_sort
  on public.sys_organization(tenant_id, parent_id, sort, organization_name);
create index if not exists idx_sys_organization_leader_user_id
  on public.sys_organization(leader_user_id);
create index if not exists idx_sys_user_organization_id
  on public.sys_user(organization_id);
create index if not exists idx_sys_role_organization_id
  on public.sys_role(organization_id);

create or replace function public.trg_validate_sys_organization()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_id = new.id then
    raise exception '组织不能将自身设置为上级组织';
  end if;

  if new.leader_user_id is not null and not exists (
    select 1
    from public.sys_user u
    where u.id = new.leader_user_id
      and u.tenant_id = new.tenant_id
  ) then
    raise exception '组织负责人必须属于同一租户';
  end if;

  if new.parent_id is not null and exists (
    with recursive ancestors as (
      select o.id, o.parent_id
      from public.sys_organization o
      where o.id = new.parent_id

      union all

      select parent.id, parent.parent_id
      from public.sys_organization parent
      join ancestors child on child.parent_id = parent.id
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception '组织层级不能形成循环';
  end if;

  return new;
end;
$$;

create or replace function public.trg_guard_system_organization()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and old.is_system then
    raise exception '租户根组织不允许删除';
  end if;

  if tg_op = 'UPDATE' and old.is_system and (
    new.tenant_id is distinct from old.tenant_id
    or new.parent_id is distinct from old.parent_id
    or new.organization_code is distinct from old.organization_code
    or new.organization_type is distinct from old.organization_type
    or new.status is distinct from old.status
    or not new.is_system
  ) then
    raise exception '租户根组织的编码、类型、层级和状态受系统保护';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists sys_organization_validate on public.sys_organization;
create trigger sys_organization_validate
before insert or update on public.sys_organization
for each row execute function public.trg_validate_sys_organization();

drop trigger if exists sys_organization_guard_system on public.sys_organization;
create trigger sys_organization_guard_system
before update or delete on public.sys_organization
for each row execute function public.trg_guard_system_organization();

drop trigger if exists sys_organization_create_audit on public.sys_organization;
create trigger sys_organization_create_audit
before insert on public.sys_organization
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists sys_organization_update_audit on public.sys_organization;
create trigger sys_organization_update_audit
before update on public.sys_organization
for each row execute function public.trg_set_update_time_and_by();

alter table public.sys_organization enable row level security;

drop policy if exists tenant_select on public.sys_organization;
create policy tenant_select on public.sys_organization
for select to authenticated
using (
  app_private.is_platform_super()
  or tenant_id = app_private.current_user_tenant_id()
);

drop policy if exists tenant_insert on public.sys_organization;
create policy tenant_insert on public.sys_organization
for insert to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

drop policy if exists tenant_update on public.sys_organization;
create policy tenant_update on public.sys_organization
for update to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
)
with check (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

drop policy if exists tenant_delete on public.sys_organization;
create policy tenant_delete on public.sys_organization
for delete to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

insert into public.sys_organization (
  tenant_id,
  parent_id,
  organization_code,
  organization_name,
  organization_type,
  status,
  sort,
  description,
  is_system,
  create_by,
  update_by
)
select
  t.id,
  null,
  'ROOT',
  t.tenant_name,
  'company',
  '1',
  0,
  '租户根组织，由系统自动维护',
  true,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_tenant t
where not exists (
  select 1
  from public.sys_organization o
  where o.tenant_id = t.id
    and o.organization_code = 'ROOT'
);

update public.sys_user u
set organization_id = root.id
from public.sys_organization root
where u.organization_id is null
  and root.tenant_id = u.tenant_id
  and root.organization_code = 'ROOT';

update public.sys_role r
set organization_id = root.id
from public.sys_organization root
where r.organization_id is null
  and root.tenant_id = r.tenant_id
  and root.organization_code = 'ROOT';

create or replace function public.trg_create_tenant_root_organization()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.sys_organization (
    tenant_id,
    organization_code,
    organization_name,
    organization_type,
    status,
    sort,
    description,
    is_system,
    create_by,
    update_by
  ) values (
    new.id,
    'ROOT',
    new.tenant_name,
    'company',
    '1',
    0,
    '租户根组织，由系统自动维护',
    true,
    coalesce(new.create_by, '624944977@qq.com'),
    coalesce(new.update_by, new.create_by, '624944977@qq.com')
  )
  on conflict (tenant_id, organization_code) do nothing;

  return new;
end;
$$;

drop trigger if exists sys_tenant_create_root_organization on public.sys_tenant;
create trigger sys_tenant_create_root_organization
after insert on public.sys_tenant
for each row execute function public.trg_create_tenant_root_organization();

create or replace function public.trg_default_system_organization()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organization_id is null then
    select o.id
    into new.organization_id
    from public.sys_organization o
    where o.tenant_id = new.tenant_id
      and o.organization_code = 'ROOT'
    limit 1;
  end if;

  if new.organization_id is not null and not exists (
    select 1
    from public.sys_organization o
    where o.id = new.organization_id
      and o.tenant_id = new.tenant_id
  ) then
    raise exception '用户或角色不能关联到其他租户的组织';
  end if;

  return new;
end;
$$;

drop trigger if exists sys_user_default_organization on public.sys_user;
create trigger sys_user_default_organization
before insert or update of tenant_id, organization_id on public.sys_user
for each row execute function public.trg_default_system_organization();

drop trigger if exists sys_role_default_organization on public.sys_role;
create trigger sys_role_default_organization
before insert or update of tenant_id, organization_id on public.sys_role
for each row execute function public.trg_default_system_organization();

do $$
declare
  v_platform_tenant_id uuid;
  v_type_id uuid;
begin
  select id into v_platform_tenant_id
  from public.sys_tenant
  where tenant_code = 'platform'
  limit 1;

  if v_platform_tenant_id is null then
    raise exception 'Platform tenant is required for organization dictionaries';
  end if;

  insert into public.sys_dict_type (
    name,
    code,
    status,
    create_by,
    update_by,
    tenant_id,
    node_type,
    sort,
    remark
  ) values (
    '组织类型',
    'organizationType',
    '1',
    '624944977@qq.com',
    '624944977@qq.com',
    v_platform_tenant_id,
    'dictionary',
    30,
    '系统管理组织层级类型'
  )
  on conflict (code) do update set
    name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id,
    remark = excluded.remark
  returning id into v_type_id;

  insert into public.sys_dictionary (
    type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
  )
  select
    v_type_id,
    item.value,
    '1',
    '624944977@qq.com',
    '624944977@qq.com',
    item.value,
    item.label,
    item.sort,
    v_platform_tenant_id,
    item.tag_type
  from (
    values
      ('company', '公司', 1::bigint, 'primary'),
      ('division', '事业部', 2::bigint, 'warning'),
      ('department', '部门', 3::bigint, 'success'),
      ('team', '团队', 4::bigint, 'info')
  ) as item(value, label, sort, tag_type)
  where not exists (
    select 1
    from public.sys_dictionary d
    where d.type_id = v_type_id
      and d.value = item.value
  );
end;
$$;

do $$
declare
  v_system_menu_id uuid;
  v_organization_menu_id uuid;
  v_button_id uuid;
  v_action record;
begin
  select id into v_system_menu_id
  from public.sys_menu
  where name = 'System'
    and parent_id is null
  limit 1;

  if v_system_menu_id is null then
    raise exception 'System management menu is required';
  end if;

  select id into v_organization_menu_id
  from public.sys_menu
  where name = 'Organization'
    and parent_id = v_system_menu_id
  limit 1;

  if v_organization_menu_id is null then
    v_organization_menu_id := gen_random_uuid();
    insert into public.sys_menu (
      id, name, path, component, meta, sort, parent_id, type, create_by, update_by
    ) values (
      v_organization_menu_id,
      'Organization',
      'organization',
      '/system/organization',
      '{"icon":"ri:organization-chart","roles":[],"title":"组织管理","is_enable":true,"keep_alive":true}'::jsonb,
      2,
      v_system_menu_id,
      'menu',
      '624944977@qq.com',
      '624944977@qq.com'
    );
  else
    update public.sys_menu
    set path = 'organization',
        component = '/system/organization',
        meta = meta || '{"icon":"ri:organization-chart","title":"组织管理","is_enable":true,"keep_alive":true}'::jsonb,
        sort = 2,
        update_by = '624944977@qq.com',
        update_time = now()
    where id = v_organization_menu_id;
  end if;

  update public.sys_menu
  set sort = case name when 'Role' then 3 when 'Menu' then 4 else sort end,
      update_by = '624944977@qq.com',
      update_time = now()
  where parent_id = v_system_menu_id
    and name in ('Role', 'Menu');

  for v_action in
    select * from (
      values
        ('System:Organization:Add', '新增', 1),
        ('System:Organization:Edit', '编辑', 2),
        ('System:Organization:Delete', '删除', 3)
    ) as actions(name, title, sort)
  loop
    select id into v_button_id
    from public.sys_menu
    where name = v_action.name
      and parent_id = v_organization_menu_id
    limit 1;

    if v_button_id is null then
      insert into public.sys_menu (
        name, path, component, meta, sort, parent_id, type, create_by, update_by
      ) values (
        v_action.name,
        '',
        '',
        jsonb_build_object('title', v_action.title, 'is_auth_button', true),
        v_action.sort,
        v_organization_menu_id,
        'button',
        '624944977@qq.com',
        '624944977@qq.com'
      );
    end if;

    v_button_id := null;
  end loop;

  insert into public.sys_role_menu (
    tenant_id, role_id, menu_id, permission, create_by, update_by
  )
  select
    r.tenant_id,
    r.id,
    m.id,
    '{}'::jsonb,
    '624944977@qq.com',
    '624944977@qq.com'
  from public.sys_role r
  join public.sys_menu m on (
    m.id in (v_system_menu_id, v_organization_menu_id)
    or (
      m.parent_id = v_organization_menu_id
      and m.type = 'button'
    )
  )
  where upper(r.role_code) = 'R_ADMIN'
  on conflict (role_id, menu_id) do nothing;
end;
$$;

drop policy if exists tenant_insert on public.sys_user;
create policy tenant_insert on public.sys_user
for insert to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

drop policy if exists tenant_insert on public.sys_role;
create policy tenant_insert on public.sys_role
for insert to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

drop policy if exists tenant_insert on public.sys_role_menu;
create policy tenant_insert on public.sys_role_menu
for insert to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = app_private.current_user_tenant_id()
    and app_private.is_tenant_admin()
  )
);

create or replace function public.trg_guard_sys_user_authorization_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_is_service_role boolean := current_user in ('postgres', 'service_role')
    or coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if not v_is_service_role
    and not app_private.is_platform_super()
    and not app_private.is_tenant_admin()
    and (
      new.tenant_id is distinct from old.tenant_id
      or new.organization_id is distinct from old.organization_id
      or new.user_roles is distinct from old.user_roles
      or new.user_type is distinct from old.user_type
      or new.status is distinct from old.status
      or new.auth_user_id is distinct from old.auth_user_id
    )
  then
    raise exception '普通用户不能修改租户、组织、角色或账号状态';
  end if;

  return new;
end;
$$;

drop trigger if exists sys_user_guard_authorization_fields on public.sys_user;
create trigger sys_user_guard_authorization_fields
before update on public.sys_user
for each row execute function public.trg_guard_sys_user_authorization_fields();

grant select, insert, update, delete on public.sys_organization to authenticated;
revoke all on public.sys_organization from anon;

revoke all on function public.trg_validate_sys_organization() from public, anon, authenticated;
revoke all on function public.trg_guard_system_organization() from public, anon, authenticated;
revoke all on function public.trg_create_tenant_root_organization() from public, anon, authenticated;
revoke all on function public.trg_default_system_organization() from public, anon, authenticated;
revoke all on function public.trg_guard_sys_user_authorization_fields() from public, anon, authenticated;

comment on table public.sys_organization is
  '租户组织树；连接用户归属、角色职责与菜单权限治理';
comment on column public.sys_organization.is_system is
  '系统根组织标记；根组织不可删除或改变层级、编码、类型和状态';
comment on column public.sys_user.organization_id is
  '用户直接所属组织；为空时由数据库归入租户根组织';
comment on column public.sys_role.organization_id is
  '角色主要适用组织；菜单权限仍由 sys_role_menu 统一维护';

commit;

;
