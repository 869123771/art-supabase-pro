
create or replace function app_private.is_platform_super()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.sys_user u
    join public.sys_tenant t on t.id = u.tenant_id
    join public.sys_role r
      on r.tenant_id = u.tenant_id
     and r.builtin_type = 'platform_super'
     and r.role_code = any(coalesce(u.user_roles, array[]::text[]))
    where u.auth_user_id = auth.uid()
      and lower(u.user_email) = '869123771@qq.com'
      and t.builtin_type = 'platform'
      and u.status = '1'
      and r.enabled is true
  )
$function$;

create or replace function app_private.enforce_platform_super_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_platform_tenant_id uuid;
  v_super_role_code text;
  v_is_platform_tenant boolean;
  v_has_super_role boolean;
  v_old_is_protected boolean;
begin
  select t.id
  into v_platform_tenant_id
  from public.sys_tenant t
  where t.builtin_type = 'platform'
  limit 1;

  select r.role_code
  into v_super_role_code
  from public.sys_role r
  where r.builtin_type = 'platform_super'
  limit 1;

  if v_platform_tenant_id is null or v_super_role_code is null then
    raise exception '平台租户或平台超级角色缺失';
  end if;

  if tg_op = 'DELETE' then
    v_old_is_protected :=
      lower(old.user_email) = '869123771@qq.com'
      or (
        old.tenant_id = v_platform_tenant_id
        and v_super_role_code = any(coalesce(old.user_roles, array[]::text[]))
      );

    if v_old_is_protected then
      raise exception '平台超级管理员账号不可删除';
    end if;

    return old;
  end if;

  v_is_platform_tenant := new.tenant_id = v_platform_tenant_id;
  v_has_super_role := v_super_role_code = any(coalesce(new.user_roles, array[]::text[]));

  if v_is_platform_tenant and lower(new.user_email) <> '869123771@qq.com' then
    raise exception '平台租户只允许系统超级管理员账号';
  end if;

  if v_has_super_role and (
    not v_is_platform_tenant
    or lower(new.user_email) <> '869123771@qq.com'
  ) then
    raise exception '平台超级角色只能分配给平台租户的系统超级管理员';
  end if;

  if tg_op = 'UPDATE' then
    v_old_is_protected :=
      lower(old.user_email) = '869123771@qq.com'
      or (
        old.tenant_id = v_platform_tenant_id
        and v_super_role_code = any(coalesce(old.user_roles, array[]::text[]))
      );

    if v_old_is_protected and (
      new.tenant_id is distinct from old.tenant_id
      or lower(new.user_email) is distinct from lower(old.user_email)
      or not (v_super_role_code = any(coalesce(new.user_roles, array[]::text[])))
      or new.status is distinct from '1'
    ) then
      raise exception '平台超级管理员的租户、邮箱、角色和启用状态受系统保护';
    end if;
  end if;

  return new;
end;
$function$;
;
