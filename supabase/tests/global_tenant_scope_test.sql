begin;

create temporary table global_tenant_scope_test_context (
  platform_auth_user_id uuid not null,
  ordinary_auth_user_id uuid not null,
  ordinary_tenant_id uuid not null,
  active_organization_total integer not null,
  ordinary_organization_total integer not null,
  employee_total integer not null
) on commit drop;

create temporary table global_tenant_scope_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

insert into global_tenant_scope_test_context
select
  platform_user.auth_user_id,
  ordinary_user.auth_user_id,
  ordinary_user.tenant_id,
  (select count(*)::integer from public.sys_organization where status = '1'),
  (
    select count(*)::integer
    from public.sys_organization
    where tenant_id = ordinary_user.tenant_id and status = '1'
  ),
  (select count(*)::integer from public.hr_employee)
from lateral (
  select user_row.auth_user_id
  from public.sys_user user_row
  join public.sys_tenant tenant_row on tenant_row.id = user_row.tenant_id
  join public.sys_role role_row
    on role_row.tenant_id = user_row.tenant_id
   and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
   and role_row.builtin_type = 'platform_super'
   and role_row.enabled is true
  where user_row.auth_user_id is not null
    and user_row.status = '1'
    and tenant_row.builtin_type = 'platform'
  order by user_row.create_time
  limit 1
) platform_user
cross join lateral (
  select user_row.auth_user_id, user_row.tenant_id
  from public.sys_user user_row
  join public.sys_tenant tenant_row on tenant_row.id = user_row.tenant_id
  join public.sys_role role_row
    on role_row.tenant_id = user_row.tenant_id
   and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
   and role_row.enabled is true
  join public.sys_role_menu role_menu_row
    on role_menu_row.role_id = role_row.id
   and role_menu_row.tenant_id = role_row.tenant_id
  join public.sys_menu menu_row
    on menu_row.id = role_menu_row.menu_id
   and menu_row.type = 'button'
  where user_row.auth_user_id is not null
    and user_row.status = '1'
    and tenant_row.builtin_type is distinct from 'platform'
    and menu_row.name in ('Hr:Employee:View', 'Hr:Position:View')
  group by user_row.id, user_row.auth_user_id, user_row.tenant_id, user_row.create_time
  having count(distinct menu_row.name) = 2
  order by user_row.create_time
  limit 1
) ordinary_user;

grant select on global_tenant_scope_test_context to authenticated;
grant select, insert on global_tenant_scope_test_result to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select platform_auth_user_id from global_tenant_scope_test_context),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_position_scope jsonb := public.hr_list_position_organization_scope_secure(null);
  v_employee_scope jsonb := public.hr_list_employee_organization_scope_secure(null);
  v_employee_list jsonb := public.hr_list_employees_secure(0, 999, null);
  v_expected_organizations integer;
  v_expected_employees integer;
begin
  select active_organization_total, employee_total
  into v_expected_organizations, v_expected_employees
  from global_tenant_scope_test_context;

  insert into global_tenant_scope_test_result values
    (
      'platform_position_scope_is_global',
      jsonb_array_length(v_position_scope) = v_expected_organizations,
      '平台超级管理员在空租户参数下可读取全部启用组织'
    ),
    (
      'platform_employee_scope_is_global',
      jsonb_array_length(v_employee_scope) = v_expected_organizations,
      '员工组织导航与岗位组织导航采用一致的全局范围'
    ),
    (
      'platform_employee_list_is_global',
      (v_employee_list->>'total')::integer = v_expected_employees,
      '员工花名册在全部租户范围返回全部租户记录'
    ),
    (
      'global_scope_exposes_tenant_dimension',
      not exists (
        select 1
        from jsonb_array_elements(v_position_scope) organization_row
        where nullif(organization_row#>>'{tenant,tenant_name}', '') is null
      ),
      '跨租户组织节点均携带租户名称'
    );
end;
$test$;

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select ordinary_auth_user_id from global_tenant_scope_test_context),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid;
  v_expected_organizations integer;
  v_position_scope jsonb;
  v_employee_scope jsonb;
  v_employee_list jsonb;
begin
  select ordinary_tenant_id, ordinary_organization_total
  into v_tenant_id, v_expected_organizations
  from global_tenant_scope_test_context;

  v_position_scope := public.hr_list_position_organization_scope_secure(null);
  v_employee_scope := public.hr_list_employee_organization_scope_secure(null);
  v_employee_list := public.hr_list_employees_secure(0, 999, null);

  insert into global_tenant_scope_test_result values
    (
      'ordinary_position_scope_is_tenant_bound',
      jsonb_array_length(v_position_scope) = v_expected_organizations
      and not exists (
        select 1
        from jsonb_array_elements(v_position_scope) organization_row
        where organization_row->>'tenant_id' <> v_tenant_id::text
      ),
      '普通租户用户即使传空租户参数也只能读取本租户岗位组织'
    ),
    (
      'ordinary_employee_scope_is_tenant_bound',
      jsonb_array_length(v_employee_scope) = v_expected_organizations
      and not exists (
        select 1
        from jsonb_array_elements(v_employee_scope) organization_row
        where organization_row->>'tenant_id' <> v_tenant_id::text
      ),
      '普通租户用户即使传空租户参数也只能读取本租户员工组织'
    ),
    (
      'ordinary_employee_list_is_tenant_bound',
      not exists (
        select 1
        from jsonb_array_elements(v_employee_list->'records') employee_row
        where employee_row->>'tenant_id' <> v_tenant_id::text
      ),
      '普通租户员工列表不存在跨租户记录'
    );
end;
$test$;

reset role;

select check_name, passed, detail
from global_tenant_scope_test_result
order by check_name;

do $test$
begin
  if exists (select 1 from global_tenant_scope_test_result where not passed) then
    raise exception 'Global tenant scope verification failed';
  end if;
end;
$test$;

rollback;
