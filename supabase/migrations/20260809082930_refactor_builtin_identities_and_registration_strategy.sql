
alter table public.sys_tenant
  add column if not exists builtin_type text;

alter table public.sys_role
  add column if not exists builtin_type text;

update public.sys_tenant
set builtin_type = case lower(tenant_code)
  when 'platform' then 'platform'
  when 'public-register' then 'public_register'
  else builtin_type
end
where lower(tenant_code) in ('platform', 'public-register');

update public.sys_role r
set builtin_type = case
  when upper(r.role_code) = 'R_SUPER' and t.builtin_type = 'platform'
    then 'platform_super'
  when upper(r.role_code) = 'R_REGISTER' and t.builtin_type = 'public_register'
    then 'default_register'
  else r.builtin_type
end
from public.sys_tenant t
where t.id = r.tenant_id
  and (
    (upper(r.role_code) = 'R_SUPER' and t.builtin_type = 'platform')
    or (upper(r.role_code) = 'R_REGISTER' and t.builtin_type = 'public_register')
  );

alter table public.sys_tenant
  drop constraint if exists sys_tenant_builtin_type_check;

alter table public.sys_tenant
  add constraint sys_tenant_builtin_type_check
  check (builtin_type is null or builtin_type in ('platform', 'public_register'));

alter table public.sys_role
  drop constraint if exists sys_role_builtin_type_check;

alter table public.sys_role
  add constraint sys_role_builtin_type_check
  check (builtin_type is null or builtin_type in ('platform_super', 'default_register'));

create unique index if not exists sys_tenant_builtin_type_uidx
  on public.sys_tenant (builtin_type)
  where builtin_type is not null;

create unique index if not exists sys_role_builtin_type_uidx
  on public.sys_role (builtin_type)
  where builtin_type is not null;

comment on column public.sys_tenant.builtin_type is
  'Immutable system identity. platform and public_register are reserved tenant identities.';

comment on column public.sys_role.builtin_type is
  'Immutable system identity. platform_super and default_register are reserved role identities.';

create or replace function app_private.default_register_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select t.id
  from public.sys_tenant t
  where t.builtin_type = 'public_register'
    and t.status = '1'
  limit 1
$function$;

create or replace function public.trg_default_system_organization()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.organization_id is null then
    select o.id
    into new.organization_id
    from public.sys_organization o
    where o.tenant_id = new.tenant_id
      and o.is_system is true
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
$function$;

create or replace function public.prevent_platform_tenant_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    if old.builtin_type is not null then
      raise exception '系统预置租户“%”不可删除', old.tenant_name;
    end if;
    return old;
  end if;

  if old.builtin_type is not null then
    if new.builtin_type is distinct from old.builtin_type then
      raise exception '系统预置租户身份不可修改';
    end if;
    if new.tenant_code is distinct from old.tenant_code then
      raise exception '系统预置租户编码不可修改';
    end if;
    if new.status is distinct from '1' then
      raise exception '系统预置租户不可停用';
    end if;
  elsif new.builtin_type is not null then
    raise exception '不能将普通租户改为系统预置租户';
  end if;

  return new;
end;
$function$;

create or replace function app_private.enforce_system_role_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_builtin_type text;
  v_configured_as_default boolean := false;
begin
  if tg_op = 'DELETE' then
    if old.builtin_type is not null then
      raise exception '系统预置角色“%”不可删除', old.role_name;
    end if;

    select exists (
      select 1
      from public.sys_param p
      where p.param_key = 'registration.default_role_id'
        and p.enabled is true
        and p.param_value = old.id::text
    ) into v_configured_as_default;

    if v_configured_as_default then
      raise exception '角色“%”正在作为默认注册角色使用，请先修改注册策略', old.role_name;
    end if;

    return old;
  end if;

  select t.builtin_type
  into v_tenant_builtin_type
  from public.sys_tenant t
  where t.id = new.tenant_id;

  if new.builtin_type = 'platform_super' and v_tenant_builtin_type is distinct from 'platform' then
    raise exception '平台超级角色只能属于平台租户';
  end if;

  if new.builtin_type = 'default_register'
    and v_tenant_builtin_type is distinct from 'public_register'
  then
    raise exception '默认注册角色只能属于注册公共租户';
  end if;

  if new.builtin_type is not null and new.enabled is false then
    raise exception '系统预置角色不可停用';
  end if;

  if tg_op = 'UPDATE' then
    if old.builtin_type is not null then
      if new.builtin_type is distinct from old.builtin_type then
        raise exception '系统预置角色身份不可修改';
      end if;
      if new.tenant_id is distinct from old.tenant_id then
        raise exception '系统预置角色所属租户不可修改';
      end if;
      if new.role_code is distinct from old.role_code then
        raise exception '系统预置角色编码不可修改';
      end if;
      if new.enabled is false then
        raise exception '系统预置角色不可停用';
      end if;
    elsif new.builtin_type is not null then
      raise exception '不能将普通角色改为系统预置角色';
    end if;

    select exists (
      select 1
      from public.sys_param p
      where p.param_key = 'registration.default_role_id'
        and p.enabled is true
        and p.param_value = old.id::text
    ) into v_configured_as_default;

    if v_configured_as_default and (
      new.tenant_id is distinct from old.tenant_id
      or new.role_code is distinct from old.role_code
      or new.enabled is false
    ) then
      raise exception '当前角色正在作为默认注册角色使用，不能改租户、改编码或停用';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function app_private.enforce_system_organization_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    if old.is_system is true then
      raise exception '系统预置根组织“%”不可删除', old.organization_name;
    end if;
    return old;
  end if;

  if old.is_system is true then
    if new.is_system is not true
      or new.tenant_id is distinct from old.tenant_id
      or new.parent_id is distinct from old.parent_id
      or new.organization_code is distinct from old.organization_code
      or new.organization_type is distinct from old.organization_type
      or new.status is distinct from '1'
    then
      raise exception '系统预置根组织的身份、租户、父级、编码、类型和启用状态不可修改';
    end if;
  elsif new.is_system is true then
    raise exception '不能将普通组织改为系统预置根组织';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_enforce_system_organization_rules on public.sys_organization;
create trigger trg_enforce_system_organization_rules
before delete or update of tenant_id, parent_id, organization_code, organization_type, status, is_system
on public.sys_organization
for each row execute function app_private.enforce_system_organization_rules();

create or replace function app_private.validate_registration_strategy_param()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role_id uuid;
  v_role record;
begin
  if new.param_key <> 'registration.default_role_id' or new.enabled is not true then
    return new;
  end if;

  begin
    v_role_id := new.param_value::uuid;
  exception when invalid_text_representation then
    raise exception '默认注册角色必须选择有效角色，不能手工填写编码';
  end;

  select r.id, r.role_name, r.role_code, r.enabled, r.builtin_type,
         t.builtin_type as tenant_builtin_type
  into v_role
  from public.sys_role r
  join public.sys_tenant t on t.id = r.tenant_id
  where r.id = v_role_id;

  if v_role.id is null then
    raise exception '默认注册角色不存在';
  end if;
  if v_role.tenant_builtin_type is distinct from 'public_register' then
    raise exception '默认注册角色必须属于注册公共租户';
  end if;
  if v_role.enabled is not true then
    raise exception '默认注册角色必须处于启用状态';
  end if;
  if v_role.builtin_type = 'platform_super'
    or upper(v_role.role_code) ~ '(SUPER|ADMIN)'
  then
    raise exception '管理员或超级管理员角色不能作为默认注册角色';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_validate_registration_strategy_param on public.sys_param;
create trigger trg_validate_registration_strategy_param
before insert or update of param_key, param_value, enabled
on public.sys_param
for each row execute function app_private.validate_registration_strategy_param();

delete from public.sys_param
where param_key in (
  'system.role.default_register_tenant_code',
  'system.role.default_register_role_code',
  'system.role.super_role_code'
);

insert into public.sys_param (
  tenant_id, param_name, param_key, group_code, group_name, param_type,
  default_value, param_value, extend_config, enabled, builtin, sort, remark,
  create_by, update_by
)
select
  platform_tenant.id,
  '默认注册角色',
  'registration.default_role_id',
  'security',
  '安全策略',
  'single_text',
  default_role.id::text,
  default_role.id::text,
  jsonb_build_object('control', 'registration_role_select'),
  true,
  true,
  7,
  '新用户注册成功后自动分配的安全角色；只能选择注册公共租户中的非管理员启用角色',
  'system',
  'system'
from public.sys_tenant platform_tenant
cross join public.sys_role default_role
join public.sys_tenant register_tenant on register_tenant.id = default_role.tenant_id
where platform_tenant.builtin_type = 'platform'
  and default_role.builtin_type = 'default_register'
  and register_tenant.builtin_type = 'public_register'
on conflict (tenant_id, param_key) do update set
  param_name = excluded.param_name,
  group_code = excluded.group_code,
  group_name = excluded.group_name,
  param_type = excluded.param_type,
  default_value = excluded.default_value,
  param_value = excluded.param_value,
  extend_config = excluded.extend_config,
  enabled = true,
  builtin = true,
  sort = excluded.sort,
  remark = excluded.remark,
  update_by = 'system',
  update_time = now();

insert into public.sys_param (
  tenant_id, param_name, param_key, group_code, group_name, param_type,
  default_value, param_value, extend_config, enabled, builtin, sort, remark,
  create_by, update_by
)
select
  t.id,
  '注册账号自动启用',
  'registration.auto_enable_user',
  'security',
  '安全策略',
  'boolean',
  'true',
  'true',
  '{}'::jsonb,
  true,
  true,
  8,
  '开启后新注册账号立即启用；关闭后新账号保留为停用状态，需管理员审核启用',
  'system',
  'system'
from public.sys_tenant t
where t.builtin_type = 'platform'
on conflict (tenant_id, param_key) do update set
  param_name = excluded.param_name,
  group_code = excluded.group_code,
  group_name = excluded.group_name,
  param_type = excluded.param_type,
  default_value = excluded.default_value,
  extend_config = excluded.extend_config,
  enabled = true,
  builtin = true,
  sort = excluded.sort,
  remark = excluded.remark,
  update_by = 'system',
  update_time = now();

create or replace function public.get_registration_role_options()
returns table (
  id uuid,
  role_name text,
  role_code text,
  builtin_type text
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select r.id, r.role_name, r.role_code, r.builtin_type
  from public.sys_role r
  join public.sys_tenant t on t.id = r.tenant_id
  where app_private.is_platform_super()
    and t.builtin_type = 'public_register'
    and t.status = '1'
    and r.enabled is true
    and r.builtin_type is distinct from 'platform_super'
    and upper(r.role_code) !~ '(SUPER|ADMIN)'
  order by (r.builtin_type = 'default_register') desc, r.role_name, r.role_code
$function$;

comment on function public.get_registration_role_options() is
  'Returns enabled non-admin roles from the public registration tenant for platform-super configuration.';

revoke all on function public.get_registration_role_options() from public, anon;
grant execute on function public.get_registration_role_options() to authenticated;
;
