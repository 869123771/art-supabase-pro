-- Read-only regression checks for tenant scope and business write permissions.
-- A permissive FOR ALL policy also grants SELECT, so a restrictive SELECT policy
-- must enforce the selected tenant even when the user is platform super.
do $tenant_scope_test$
declare
  v_missing text[];
  v_invalid text[];
begin
  select array_agg(p.tablename order by p.tablename)
    into v_missing
  from pg_policies p
  where p.schemaname = 'public'
    and p.policyname = 'canonical_platform_super_write'
    and p.cmd = 'ALL'
    and not exists (
      select 1
      from pg_policies scope
      where scope.schemaname = p.schemaname
        and scope.tablename = p.tablename
        and scope.policyname = 'canonical_tenant_read_scope'
        and scope.permissive = 'RESTRICTIVE'
        and scope.cmd = 'SELECT'
        and scope.roles = '{authenticated}'::name[]
    );

  if v_missing is not null then
    raise exception 'Tenant SELECT guard missing on: %', array_to_string(v_missing, ', ');
  end if;

  select array_agg(scope.tablename order by scope.tablename)
    into v_invalid
  from pg_policies scope
  where scope.schemaname = 'public'
    and scope.policyname = 'canonical_tenant_read_scope'
    and scope.permissive = 'RESTRICTIVE'
    and scope.cmd = 'SELECT'
    and (
      (scope.qual not like '%tenant_in_current_read_scope%'
        and scope.qual not like '%current_read_tenant_id%')
      or scope.qual ~* 'is_platform_super'
    );

  if v_invalid is not null then
    raise exception 'Tenant SELECT guard can bypass selected scope on: %',
      array_to_string(v_invalid, ', ');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_cargo'
      and policyname = 'tenant_insert' and cmd = 'INSERT'
      and roles = '{authenticated}'::name[]
      and with_check like '%current_user_tenant_id%'
      and with_check like '%TmsCargo:Add%'
      and with_check like '%TmsCargo:Import%'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_cargo'
      and policyname = 'tenant_update' and cmd = 'UPDATE'
      and roles = '{authenticated}'::name[]
      and qual like '%current_user_tenant_id%'
      and qual like '%TmsCargo:Edit%'
      and with_check like '%TmsCargo:Edit%'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_cargo'
      and policyname = 'tenant_delete' and cmd = 'DELETE'
      and roles = '{authenticated}'::name[]
      and qual like '%current_user_tenant_id%'
      and qual like '%TmsCargo:Delete%'
  ) then
    raise exception 'TMS cargo write permissions are incomplete';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_cargo'
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
      and permissive = 'PERMISSIVE'
      and policyname not in (
        'canonical_platform_super_write', 'tenant_insert', 'tenant_update', 'tenant_delete'
      )
  ) then
    raise exception 'Unexpected permissive TMS cargo write policy';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_station'
      and policyname = 'tenant_insert' and cmd = 'INSERT'
      and roles = '{authenticated}'::name[]
      and with_check like '%TmsStation:Add%'
      and with_check like '%TmsStation:Import%'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_station'
      and policyname = 'tenant_update' and cmd = 'UPDATE'
      and roles = '{authenticated}'::name[]
      and qual like '%TmsStation:Edit%'
      and qual like '%TmsStation:Import%'
      and qual like '%TmsStation:Toggle%'
      and with_check like '%TmsStation:Toggle%'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'mdm_station'
      and policyname = 'tenant_delete' and cmd = 'DELETE'
      and roles = '{authenticated}'::name[]
      and qual like '%TmsStation:Delete%'
  ) then
    raise exception 'TMS station write permissions are incomplete';
  end if;

  if has_table_privilege('authenticated', 'public.tms_station_role', 'INSERT')
    or has_table_privilege('authenticated', 'public.tms_station_role', 'UPDATE')
    or has_table_privilege('authenticated', 'public.tms_station_role', 'DELETE')
    or not has_function_privilege(
      'authenticated', 'public.save_tms_station(jsonb,text[])', 'EXECUTE'
    )
    or has_function_privilege('anon', 'public.save_tms_station(jsonb,text[])', 'EXECUTE')
    or not (
      select prosecdef from pg_proc
      where oid = 'public.save_tms_station(jsonb,text[])'::regprocedure
    )
    or not exists (
      select 1 from pg_trigger
      where tgrelid = 'public.mdm_station'::regclass
        and tgname = 'tms_station_sync_primary_role_insert'
    )
    or not exists (
      select 1 from pg_trigger
      where tgrelid = 'public.mdm_station'::regclass
        and tgname = 'tms_station_permission_guard'
    )
    or not exists (
      select 1 from pg_trigger
      where tgrelid = 'public.mdm_station'::regclass
        and tgname = 'tms_station_delete_guard'
        and (tgtype & 8) = 8
    )
    or not has_function_privilege(
      'authenticated', 'public.get_tms_station_delete_dependency_details(uuid[])', 'EXECUTE'
    )
    or has_function_privilege(
      'anon', 'public.get_tms_station_delete_dependency_details(uuid[])', 'EXECUTE'
    )
    or not (
      select prosecdef from pg_proc
      where oid = 'public.get_tms_station_delete_dependency_details(uuid[])'::regprocedure
    ) then
    raise exception 'TMS station RPC/role/delete boundary is incomplete';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.create_ai_order_master_data(jsonb)', 'EXECUTE'
  )
    or has_function_privilege(
      'anon', 'public.create_ai_order_master_data(jsonb)', 'EXECUTE'
    )
    or (
      select prosecdef or pg_get_functiondef(oid) ~* 'is_platform_super|current_is_super'
      from pg_proc
      where oid = 'public.create_ai_order_master_data(jsonb)'::regprocedure
    )
    or not (
      select pg_get_functiondef(oid) like '%TmsOrderOpen:AiFill%'
        and pg_get_functiondef(oid) like '%TmsStation:Add%'
        and pg_get_functiondef(oid) like '%TmsCustomer:Add%'
        and pg_get_functiondef(oid) like '%TmsCustomerAddress:Add%'
        and pg_get_functiondef(oid) like '%TmsCargo:Add%'
        and pg_get_functiondef(oid) like '%current_read_tenant_id%'
      from pg_proc
      where oid = 'public.create_ai_order_master_data(jsonb)'::regprocedure
    )
    or not (
      select pg_get_functiondef(oid) like '%join public.sys_role_menu%'
        and pg_get_functiondef(oid) like '%current_user_row.auth_user_id = auth.uid()%'
      from pg_proc
      where oid = 'app_private.has_permission(text)'::regprocedure
    )
    or not (
      select pg_get_functiondef(oid) like '%if not app_private.is_platform_super() then%'
        and pg_get_functiondef(oid) like '%app_private.auth_user_tenant_id()%'
      from pg_proc
      where oid = 'app_private.current_read_tenant_id()'::regprocedure
    ) then
    raise exception 'AI master-data RPC ordinary-user permission or tenant boundary is incomplete';
  end if;
end
$tenant_scope_test$;

select count(*) as protected_tenant_tables
from pg_policies
where schemaname = 'public'
  and policyname = 'canonical_tenant_read_scope'
  and permissive = 'RESTRICTIVE'
  and cmd = 'SELECT';
