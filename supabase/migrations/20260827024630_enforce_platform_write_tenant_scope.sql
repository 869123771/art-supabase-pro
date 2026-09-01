create or replace function app_private.resolve_write_tenant_id(p_requested_tenant_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_tenant_id uuid := app_private.auth_user_tenant_id();
  v_effective_tenant_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护租户数据' using errcode = '42501';
  end if;
  if v_current_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    if p_requested_tenant_id is null then
      raise exception '平台管理员维护数据前必须选择具体租户' using errcode = '22023';
    end if;

    v_effective_tenant_id := app_private.current_user_tenant_id();
    if v_effective_tenant_id <> p_requested_tenant_id then
      raise exception '写入目标与当前租户范围不一致，请重新选择租户' using errcode = '42501';
    end if;

    if not exists (
      select 1
      from public.sys_tenant tenant
      where tenant.id = p_requested_tenant_id
        and tenant.status = '1'
        and tenant.builtin_type is distinct from 'platform'
        and (
          tenant.service_start_date is null
          or tenant.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
        )
        and (
          tenant.service_end_date is null
          or tenant.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
        )
    ) then
      raise exception '所选业务租户不存在或已停用' using errcode = '22023';
    end if;
    return p_requested_tenant_id;
  end if;

  if p_requested_tenant_id is not null and p_requested_tenant_id <> v_current_tenant_id then
    raise exception '不能维护当前租户之外的数据' using errcode = '42501';
  end if;
  return v_current_tenant_id;
end;
$function$;

revoke all on function app_private.resolve_write_tenant_id(uuid) from public, anon, authenticated;
grant execute on function app_private.resolve_write_tenant_id(uuid) to service_role;

;
