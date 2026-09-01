-- Tenant-scoped field permission foundation.
-- Stored access levels are intentionally limited to hidden/masked/read/edit.
-- Record ownership is evaluated by the resolver and is never persisted as an access level.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sys_user_id_tenant_key'
      and conrelid = 'public.sys_user'::regclass
  ) then
    alter table public.sys_user
      add constraint sys_user_id_tenant_key unique (id, tenant_id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sys_role_id_tenant_key'
      and conrelid = 'public.sys_role'::regclass
  ) then
    alter table public.sys_role
      add constraint sys_role_id_tenant_key unique (id, tenant_id);
  end if;
end
$$;

create table if not exists public.sys_permission_resource (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  resource_key text not null,
  resource_label text not null,
  menu_name text not null,
  owner_column text,
  enabled boolean not null default true,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_permission_resource_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_permission_resource_key_check
    check (resource_key ~ '^[a-z][a-z0-9_.]*$'),
  constraint sys_permission_resource_menu_check
    check (btrim(menu_name) <> ''),
  constraint sys_permission_resource_tenant_key unique (tenant_id, resource_key),
  constraint sys_permission_resource_id_tenant_key unique (id, tenant_id)
);

create table if not exists public.sys_permission_field (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  resource_id uuid not null,
  field_key text not null,
  field_label text not null,
  sensitive boolean not null default true,
  default_access text not null default 'hidden',
  mask_strategy text not null default 'none',
  owner_override_enabled boolean not null default true,
  sort integer not null default 0,
  enabled boolean not null default true,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_permission_field_resource_tenant_fkey
    foreign key (resource_id, tenant_id)
    references public.sys_permission_resource(id, tenant_id)
    on delete cascade,
  constraint sys_permission_field_key_check
    check (field_key ~ '^[a-z][A-Za-z0-9.]*$'),
  constraint sys_permission_field_access_check
    check (default_access in ('hidden', 'masked', 'read', 'edit')),
  constraint sys_permission_field_mask_check
    check (mask_strategy in ('none', 'amount', 'phone', 'id_card', 'bank_account', 'address')),
  constraint sys_permission_field_sort_check check (sort >= 0),
  constraint sys_permission_field_tenant_key unique (tenant_id, resource_id, field_key),
  constraint sys_permission_field_id_resource_tenant_key unique (id, resource_id, tenant_id)
);

create table if not exists public.sys_role_field_permission (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  role_id uuid not null,
  resource_id uuid not null,
  field_id uuid not null,
  access_level text not null,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_role_field_permission_role_tenant_fkey
    foreign key (role_id, tenant_id)
    references public.sys_role(id, tenant_id)
    on delete cascade,
  constraint sys_role_field_permission_field_tenant_fkey
    foreign key (field_id, resource_id, tenant_id)
    references public.sys_permission_field(id, resource_id, tenant_id)
    on delete cascade,
  constraint sys_role_field_permission_access_check
    check (access_level in ('hidden', 'masked', 'read', 'edit')),
  constraint sys_role_field_permission_tenant_key
    unique (tenant_id, role_id, resource_id, field_id)
);

create table if not exists public.sys_user_field_permission (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  user_id uuid not null,
  resource_id uuid not null,
  field_id uuid not null,
  access_level text not null,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_user_field_permission_user_tenant_fkey
    foreign key (user_id, tenant_id)
    references public.sys_user(id, tenant_id)
    on delete cascade,
  constraint sys_user_field_permission_field_tenant_fkey
    foreign key (field_id, resource_id, tenant_id)
    references public.sys_permission_field(id, resource_id, tenant_id)
    on delete cascade,
  constraint sys_user_field_permission_access_check
    check (access_level in ('hidden', 'masked', 'read', 'edit')),
  constraint sys_user_field_permission_tenant_key
    unique (tenant_id, user_id, resource_id, field_id)
);

create table if not exists public.sys_permission_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  actor_user_id uuid,
  target_type text not null,
  target_id uuid,
  resource_id uuid,
  action text not null,
  before_value jsonb,
  after_value jsonb,
  create_by text not null,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_permission_audit_log_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete cascade,
  constraint sys_permission_audit_log_actor_tenant_fkey
    foreign key (actor_user_id, tenant_id)
    references public.sys_user(id, tenant_id)
    on delete set null (actor_user_id),
  constraint sys_permission_audit_log_resource_tenant_fkey
    foreign key (resource_id, tenant_id)
    references public.sys_permission_resource(id, tenant_id)
    on delete set null (resource_id),
  constraint sys_permission_audit_log_target_check
    check (target_type in ('role_field', 'user_field')),
  constraint sys_permission_audit_log_action_check
    check (action in ('replace', 'clear'))
);

create index if not exists sys_permission_field_resource_sort_idx
  on public.sys_permission_field (tenant_id, resource_id, sort, id)
  where enabled is true;
create index if not exists sys_role_field_permission_lookup_idx
  on public.sys_role_field_permission (tenant_id, role_id, resource_id, field_id);
create index if not exists sys_user_field_permission_lookup_idx
  on public.sys_user_field_permission (tenant_id, user_id, resource_id, field_id);
create index if not exists sys_permission_audit_log_tenant_time_idx
  on public.sys_permission_audit_log (tenant_id, create_time desc);

alter table public.sys_permission_resource enable row level security;
alter table public.sys_permission_field enable row level security;
alter table public.sys_role_field_permission enable row level security;
alter table public.sys_user_field_permission enable row level security;
alter table public.sys_permission_audit_log enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'sys_permission_resource',
    'sys_permission_field',
    'sys_role_field_permission',
    'sys_user_field_permission',
    'sys_permission_audit_log'
  ]
  loop
    execute format('drop policy if exists tenant_select on public.%I', table_name);
    execute format(
      'create policy tenant_select on public.%I for select to authenticated using (' ||
      '(select app_private.is_platform_super()) or ' ||
      'tenant_id = (select app_private.current_user_tenant_id()))',
      table_name
    );
  end loop;
end
$$;

revoke all on table public.sys_permission_resource from public, anon, authenticated;
revoke all on table public.sys_permission_field from public, anon, authenticated;
revoke all on table public.sys_role_field_permission from public, anon, authenticated;
revoke all on table public.sys_user_field_permission from public, anon, authenticated;
revoke all on table public.sys_permission_audit_log from public, anon, authenticated;

create trigger sys_permission_resource_create_audit
before insert on public.sys_permission_resource
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_permission_resource_update_audit
before update on public.sys_permission_resource
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_permission_field_create_audit
before insert on public.sys_permission_field
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_permission_field_update_audit
before update on public.sys_permission_field
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_role_field_permission_create_audit
before insert on public.sys_role_field_permission
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_role_field_permission_update_audit
before update on public.sys_role_field_permission
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_user_field_permission_create_audit
before insert on public.sys_user_field_permission
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger sys_user_field_permission_update_audit
before update on public.sys_user_field_permission
for each row execute function public.trg_set_update_time_and_by();
create trigger sys_permission_audit_log_create_audit
before insert on public.sys_permission_audit_log
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create or replace function app_private.permission_access_rank(p_access text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_access
    when 'edit' then 3
    when 'read' then 2
    when 'masked' then 1
    else 0
  end;
$$;

create or replace function app_private.can_manage_field_permissions()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (
      app_private.is_platform_super()
      or app_private.has_permission('System:FieldPermission:Manage')
    );
$$;

create or replace function app_private.resolve_field_access(
  p_resource_key text,
  p_field_key text,
  p_record_owner_id uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_field public.sys_permission_field%rowtype;
  v_user_access text;
  v_role_access text;
begin
  if (select auth.uid()) is null or v_tenant_id is null or v_user_id is null then
    return 'hidden';
  end if;

  if app_private.is_platform_super() then
    return 'edit';
  end if;

  select field_row.*
    into v_field
  from public.sys_permission_resource resource_row
  join public.sys_permission_field field_row
    on field_row.resource_id = resource_row.id
   and field_row.tenant_id = resource_row.tenant_id
  where resource_row.tenant_id = v_tenant_id
    and resource_row.resource_key = p_resource_key
    and resource_row.enabled is true
    and field_row.field_key = p_field_key
    and field_row.sensitive is true
    and field_row.enabled is true;

  if not found then
    return 'hidden';
  end if;

  if v_field.owner_override_enabled
     and p_record_owner_id is not null
     and p_record_owner_id = v_user_id then
    return 'edit';
  end if;

  select permission_row.access_level
    into v_user_access
  from public.sys_user_field_permission permission_row
  where permission_row.tenant_id = v_tenant_id
    and permission_row.user_id = v_user_id
    and permission_row.resource_id = v_field.resource_id
    and permission_row.field_id = v_field.id;

  if found then
    return v_user_access;
  end if;

  select case max(app_private.permission_access_rank(permission_row.access_level))
    when 3 then 'edit'
    when 2 then 'read'
    when 1 then 'masked'
    when 0 then 'hidden'
    else null
  end
    into v_role_access
  from public.sys_user current_user_row
  join public.sys_role role_row
    on role_row.tenant_id = current_user_row.tenant_id
   and role_row.enabled is true
   and role_row.role_code = any(coalesce(current_user_row.user_roles, array[]::text[]))
  join public.sys_role_field_permission permission_row
    on permission_row.tenant_id = role_row.tenant_id
   and permission_row.role_id = role_row.id
   and permission_row.resource_id = v_field.resource_id
   and permission_row.field_id = v_field.id
  where current_user_row.id = v_user_id
    and current_user_row.tenant_id = v_tenant_id
    and current_user_row.status = '1'
    and current_user_row.deleted_at is null;

  return coalesce(v_role_access, v_field.default_access, 'hidden');
end;
$$;

create or replace function app_private.field_access_map(
  p_resource_key text,
  p_record_owner_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(
      field_row.field_key,
      app_private.resolve_field_access(
        resource_row.resource_key,
        field_row.field_key,
        p_record_owner_id
      )
      order by field_row.sort, field_row.id
    ),
    '{}'::jsonb
  )
  from public.sys_permission_resource resource_row
  join public.sys_permission_field field_row
    on field_row.resource_id = resource_row.id
   and field_row.tenant_id = resource_row.tenant_id
  where resource_row.tenant_id = app_private.current_user_tenant_id()
    and resource_row.resource_key = p_resource_key
    and resource_row.enabled is true
    and field_row.enabled is true
    and field_row.sensitive is true;
$$;

create or replace function app_private.mask_permission_value(
  p_value text,
  p_strategy text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_length integer := char_length(coalesce(p_value, ''));
begin
  if p_value is null then
    return null;
  end if;

  return case p_strategy
    when 'phone' then
      case when v_length >= 7
        then left(p_value, 3) || repeat('*', greatest(v_length - 7, 4)) || right(p_value, 4)
        else repeat('*', greatest(v_length, 4))
      end
    when 'id_card' then
      case when v_length >= 8
        then left(p_value, 4) || repeat('*', v_length - 8) || right(p_value, 4)
        else repeat('*', greatest(v_length, 4))
      end
    when 'bank_account' then
      case when v_length >= 8
        then left(p_value, 4) || repeat('*', v_length - 8) || right(p_value, 4)
        else repeat('*', greatest(v_length, 4))
      end
    when 'address' then
      case when v_length > 6 then left(p_value, 6) || '***' else '***' end
    when 'amount' then '***'
    else '***'
  end;
end;
$$;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.sys_tenant where id = p_tenant_id
  ) then
    raise exception 'Tenant not found';
  end if;

  insert into public.sys_permission_resource (
    tenant_id,
    resource_key,
    resource_label,
    menu_name,
    owner_column,
    create_by,
    update_by
  )
  values (
    p_tenant_id,
    'tms.contract',
    '运输合同',
    'TmsContract',
    'created_by_user_id',
    '624944977@qq.com',
    '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id,
    resource_id,
    field_key,
    field_label,
    default_access,
    mask_strategy,
    owner_override_enabled,
    sort,
    create_by,
    update_by
  )
  values
    (p_tenant_id, v_resource_id, 'contractAmount', '合同金额', 'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportUnitPrice', '运输单价', 'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'roadConsumptionRate', '路耗标准', 'hidden', 'amount', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'lossDeductionPrice', '亏扣价', 'hidden', 'amount', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportDetailsPricing', '明细单价与运费', 'hidden', 'amount', true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'partyContactPhone', '相对方联系电话', 'hidden', 'phone', false, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'attachments', '合同附件', 'hidden', 'none', true, 70, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

create or replace function app_private.seed_field_permission_catalog_for_new_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.seed_field_permission_catalog(new.id);
  return new;
end;
$$;

drop trigger if exists sys_tenant_seed_field_permission_catalog on public.sys_tenant;
create trigger sys_tenant_seed_field_permission_catalog
after insert on public.sys_tenant
for each row execute function app_private.seed_field_permission_catalog_for_new_tenant();

do $$
declare
  tenant_row record;
begin
  for tenant_row in select id from public.sys_tenant loop
    perform app_private.seed_field_permission_catalog(tenant_row.id);
  end loop;
end
$$;

-- Existing contract roles keep their current field capability during rollout.
-- New roles and missing grants remain fail-closed until configured.
insert into public.sys_role_field_permission (
  tenant_id,
  role_id,
  resource_id,
  field_id,
  access_level,
  create_by,
  update_by
)
select distinct
  role_row.tenant_id,
  role_row.id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role role_row
join public.sys_role_menu role_menu
  on role_menu.role_id = role_row.id
 and role_menu.tenant_id = role_row.tenant_id
join public.sys_menu menu_row
  on menu_row.id = role_menu.menu_id
 and menu_row.name = 'TmsContract'
join public.sys_permission_resource resource_row
  on resource_row.tenant_id = role_row.tenant_id
 and resource_row.resource_key = 'tms.contract'
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
where role_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

-- Field permission administration lives under System Management.
do $$
declare
  v_system_menu_id uuid;
  v_page_menu_id uuid;
  v_manage_button_id uuid;
begin
  select id into v_system_menu_id
  from public.sys_menu
  where name = 'System'
  order by create_time
  limit 1;

  if v_system_menu_id is null then
    raise exception 'System menu not found';
  end if;

  select id into v_page_menu_id
  from public.sys_menu
  where name = 'FieldPermission'
  order by create_time
  limit 1;

  if v_page_menu_id is null then
    insert into public.sys_menu (
      parent_id, name, path, component, meta, sort, type,
      create_by, update_by
    )
    values (
      v_system_menu_id,
      'FieldPermission',
      'field-permission',
      '/system/field-permission',
      jsonb_build_object(
        'icon', 'ri:shield-keyhole-line',
        'link', '',
        'roles', '[]'::jsonb,
        'title', '字段权限',
        'is_hide', false,
        'fixed_tab', false,
        'is_enable', true,
        'is_iframe', false,
        'keep_alive', true,
        'show_badge', false,
        'active_path', '',
        'is_hide_tab', false,
        'is_full_page', false,
        'is_auth_button', false,
        'show_text_badge', ''
      ),
      14,
      'menu',
      '624944977@qq.com',
      '624944977@qq.com'
    )
    returning id into v_page_menu_id;
  end if;

  select id into v_manage_button_id
  from public.sys_menu
  where parent_id = v_page_menu_id
    and name = 'System:FieldPermission:Manage'
    and type = 'button'
  limit 1;

  if v_manage_button_id is null then
    insert into public.sys_menu (
      parent_id, name, path, component, meta, sort, type,
      create_by, update_by
    )
    values (
      v_page_menu_id,
      'System:FieldPermission:Manage',
      '',
      '',
      jsonb_build_object(
        'icon', '',
        'link', '',
        'roles', '[]'::jsonb,
        'title', '配置字段权限',
        'is_hide', false,
        'fixed_tab', false,
        'is_enable', true,
        'is_iframe', false,
        'keep_alive', false,
        'show_badge', false,
        'active_path', '',
        'is_hide_tab', false,
        'is_full_page', false,
        'is_auth_button', true,
        'show_text_badge', ''
      ),
      1,
      'button',
      '624944977@qq.com',
      '624944977@qq.com'
    )
    returning id into v_manage_button_id;
  end if;

  insert into public.sys_role_menu (tenant_id, role_id, menu_id, create_by, update_by)
  select distinct role_menu.tenant_id, role_menu.role_id, selected_menu.menu_id,
         '624944977@qq.com', '624944977@qq.com'
  from public.sys_role_menu role_menu
  join public.sys_menu permission_menu
    on permission_menu.id = role_menu.menu_id
   and permission_menu.name = 'System:Role:AssignPermission'
  cross join lateral (
    values (v_system_menu_id), (v_page_menu_id), (v_manage_button_id)
  ) selected_menu(menu_id)
  on conflict (role_id, menu_id) do nothing;
end
$$;

create or replace function public.get_field_permission_resources()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_manage_field_permissions() then
    raise exception 'Missing permission: System:FieldPermission:Manage';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', resource_row.id,
        'resourceKey', resource_row.resource_key,
        'resourceLabel', resource_row.resource_label,
        'menuName', resource_row.menu_name,
        'fieldCount', (
          select count(*)
          from public.sys_permission_field field_row
          where field_row.tenant_id = resource_row.tenant_id
            and field_row.resource_id = resource_row.id
            and field_row.enabled is true
        )
      )
      order by resource_row.resource_label, resource_row.resource_key
    )
    from public.sys_permission_resource resource_row
    where resource_row.tenant_id = app_private.current_user_tenant_id()
      and resource_row.enabled is true
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_field_permission_configuration(
  p_resource_key text,
  p_subject_type text,
  p_subject_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_resource public.sys_permission_resource%rowtype;
begin
  if not app_private.can_manage_field_permissions() then
    raise exception 'Missing permission: System:FieldPermission:Manage';
  end if;

  if p_subject_type not in ('role', 'user') then
    raise exception 'Invalid permission subject type';
  end if;

  select * into v_resource
  from public.sys_permission_resource
  where tenant_id = v_tenant_id
    and resource_key = p_resource_key
    and enabled is true;

  if not found then
    raise exception 'Permission resource not found';
  end if;

  if p_subject_type = 'role' and not exists (
    select 1 from public.sys_role
    where id = p_subject_id and tenant_id = v_tenant_id and enabled is true
  ) then
    raise exception 'Role not found or access denied';
  end if;

  if p_subject_type = 'user' and not exists (
    select 1 from public.sys_user
    where id = p_subject_id
      and tenant_id = v_tenant_id
      and status = '1'
      and deleted_at is null
  ) then
    raise exception 'User not found or access denied';
  end if;

  return jsonb_build_object(
    'resourceId', v_resource.id,
    'resourceKey', v_resource.resource_key,
    'resourceLabel', v_resource.resource_label,
    'subjectType', p_subject_type,
    'subjectId', p_subject_id,
    'fields', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', field_row.id,
          'fieldKey', field_row.field_key,
          'fieldLabel', field_row.field_label,
          'defaultAccess', field_row.default_access,
          'maskStrategy', field_row.mask_strategy,
          'ownerOverrideEnabled', field_row.owner_override_enabled,
          'inheritedAccess', case
            when p_subject_type = 'user' then coalesce((
              select case max(app_private.permission_access_rank(role_permission.access_level))
                when 3 then 'edit'
                when 2 then 'read'
                when 1 then 'masked'
                when 0 then 'hidden'
                else null
              end
              from public.sys_user subject_user
              join public.sys_role role_row
                on role_row.tenant_id = subject_user.tenant_id
               and role_row.enabled is true
               and role_row.role_code = any(coalesce(subject_user.user_roles, array[]::text[]))
              join public.sys_role_field_permission role_permission
                on role_permission.tenant_id = role_row.tenant_id
               and role_permission.role_id = role_row.id
               and role_permission.resource_id = v_resource.id
               and role_permission.field_id = field_row.id
              where subject_user.id = p_subject_id
                and subject_user.tenant_id = v_tenant_id
            ), field_row.default_access)
            else field_row.default_access
          end,
          'explicitAccess', case
            when p_subject_type = 'role' then (
              select role_permission.access_level
              from public.sys_role_field_permission role_permission
              where role_permission.tenant_id = v_tenant_id
                and role_permission.role_id = p_subject_id
                and role_permission.resource_id = v_resource.id
                and role_permission.field_id = field_row.id
            )
            else (
              select user_permission.access_level
              from public.sys_user_field_permission user_permission
              where user_permission.tenant_id = v_tenant_id
                and user_permission.user_id = p_subject_id
                and user_permission.resource_id = v_resource.id
                and user_permission.field_id = field_row.id
            )
          end
        )
        order by field_row.sort, field_row.id
      )
      from public.sys_permission_field field_row
      where field_row.tenant_id = v_tenant_id
        and field_row.resource_id = v_resource.id
        and field_row.enabled is true
        and field_row.sensitive is true
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.set_field_permissions(
  p_resource_key text,
  p_subject_type text,
  p_subject_id uuid,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_actor_user_id uuid := app_private.current_app_user_id();
  v_resource public.sys_permission_resource%rowtype;
  v_before jsonb;
  v_after jsonb;
begin
  if not app_private.can_manage_field_permissions() then
    raise exception 'Missing permission: System:FieldPermission:Manage';
  end if;

  if p_subject_type not in ('role', 'user') then
    raise exception 'Invalid permission subject type';
  end if;

  if p_permissions is null or jsonb_typeof(p_permissions) <> 'object' then
    raise exception 'Permissions must be a JSON object';
  end if;

  select * into v_resource
  from public.sys_permission_resource
  where tenant_id = v_tenant_id
    and resource_key = p_resource_key
    and enabled is true;

  if not found then
    raise exception 'Permission resource not found';
  end if;

  if p_subject_type = 'role' then
    if not exists (
      select 1 from public.sys_role
      where id = p_subject_id and tenant_id = v_tenant_id and enabled is true
    ) then
      raise exception 'Role not found or access denied';
    end if;

    select coalesce(jsonb_object_agg(field_row.field_key, permission_row.access_level), '{}'::jsonb)
      into v_before
    from public.sys_role_field_permission permission_row
    join public.sys_permission_field field_row on field_row.id = permission_row.field_id
    where permission_row.tenant_id = v_tenant_id
      and permission_row.role_id = p_subject_id
      and permission_row.resource_id = v_resource.id;

    delete from public.sys_role_field_permission
    where tenant_id = v_tenant_id
      and role_id = p_subject_id
      and resource_id = v_resource.id;

    insert into public.sys_role_field_permission (
      tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
    )
    select v_tenant_id, p_subject_id, v_resource.id, field_row.id,
           permission_item.value, '624944977@qq.com', '624944977@qq.com'
    from jsonb_each_text(p_permissions) permission_item
    join public.sys_permission_field field_row
      on field_row.tenant_id = v_tenant_id
     and field_row.resource_id = v_resource.id
     and field_row.field_key = permission_item.key
     and field_row.enabled is true
     and field_row.sensitive is true
    where permission_item.value in ('hidden', 'masked', 'read', 'edit');
  else
    if not exists (
      select 1 from public.sys_user
      where id = p_subject_id
        and tenant_id = v_tenant_id
        and status = '1'
        and deleted_at is null
    ) then
      raise exception 'User not found or access denied';
    end if;

    select coalesce(jsonb_object_agg(field_row.field_key, permission_row.access_level), '{}'::jsonb)
      into v_before
    from public.sys_user_field_permission permission_row
    join public.sys_permission_field field_row on field_row.id = permission_row.field_id
    where permission_row.tenant_id = v_tenant_id
      and permission_row.user_id = p_subject_id
      and permission_row.resource_id = v_resource.id;

    delete from public.sys_user_field_permission
    where tenant_id = v_tenant_id
      and user_id = p_subject_id
      and resource_id = v_resource.id;

    insert into public.sys_user_field_permission (
      tenant_id, user_id, resource_id, field_id, access_level, create_by, update_by
    )
    select v_tenant_id, p_subject_id, v_resource.id, field_row.id,
           permission_item.value, '624944977@qq.com', '624944977@qq.com'
    from jsonb_each_text(p_permissions) permission_item
    join public.sys_permission_field field_row
      on field_row.tenant_id = v_tenant_id
     and field_row.resource_id = v_resource.id
     and field_row.field_key = permission_item.key
     and field_row.enabled is true
     and field_row.sensitive is true
    where permission_item.value in ('hidden', 'masked', 'read', 'edit');
  end if;

  if exists (
    select 1
    from jsonb_each_text(p_permissions) permission_item
    where permission_item.value is null
       or permission_item.value not in ('hidden', 'masked', 'read', 'edit')
  ) or (
    select count(*) from jsonb_each_text(p_permissions)
  ) <> (
    select count(*)
    from jsonb_each_text(p_permissions) permission_item
    join public.sys_permission_field field_row
      on field_row.tenant_id = v_tenant_id
     and field_row.resource_id = v_resource.id
     and field_row.field_key = permission_item.key
     and field_row.enabled is true
     and field_row.sensitive is true
  ) then
    raise exception 'Permissions contain an unknown field or access level';
  end if;

  v_after := p_permissions;

  insert into public.sys_permission_audit_log (
    tenant_id,
    actor_user_id,
    target_type,
    target_id,
    resource_id,
    action,
    before_value,
    after_value,
    create_by
  )
  values (
    v_tenant_id,
    v_actor_user_id,
    p_subject_type || '_field',
    p_subject_id,
    v_resource.id,
    case when p_permissions = '{}'::jsonb then 'clear' else 'replace' end,
    v_before,
    v_after,
    coalesce((select auth.jwt() ->> 'email'), 'unknown')
  );
end;
$$;

create or replace function public.get_current_field_access(
  p_resource_key text,
  p_record_owner_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then '{}'::jsonb
    else app_private.field_access_map(p_resource_key, p_record_owner_id)
  end;
$$;

revoke all on function app_private.permission_access_rank(text) from public, anon, authenticated;
revoke all on function app_private.can_manage_field_permissions() from public, anon, authenticated;
revoke all on function app_private.resolve_field_access(text, text, uuid) from public, anon, authenticated;
revoke all on function app_private.field_access_map(text, uuid) from public, anon, authenticated;
revoke all on function app_private.mask_permission_value(text, text) from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog_for_new_tenant() from public, anon, authenticated;
revoke all on function public.get_field_permission_resources() from public, anon;
revoke all on function public.get_field_permission_configuration(text, text, uuid) from public, anon;
revoke all on function public.set_field_permissions(text, text, uuid, jsonb) from public, anon;
revoke all on function public.get_current_field_access(text, uuid) from public, anon;
grant execute on function public.get_field_permission_resources() to authenticated;
grant execute on function public.get_field_permission_configuration(text, text, uuid) to authenticated;
grant execute on function public.set_field_permissions(text, text, uuid, jsonb) to authenticated;
grant execute on function public.get_current_field_access(text, uuid) to authenticated;

;
