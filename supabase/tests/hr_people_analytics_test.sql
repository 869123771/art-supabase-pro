begin;

create temporary table hr_people_analytics_test_context (
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  ordinary_sys_user_id uuid not null,
  ordinary_role_id uuid not null,
  ordinary_role_code text not null,
  expected_headcount integer not null,
  employee_count bigint not null,
  assignment_count bigint not null
) on commit drop;

create temporary table hr_people_analytics_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_people_analytics_test_context(
  tenant_id, ordinary_auth_user_id, ordinary_sys_user_id,
  ordinary_role_id, ordinary_role_code, expected_headcount,
  employee_count, assignment_count
)
select app_user.tenant_id, app_user.auth_user_id, app_user.id,
  gen_random_uuid(),
  'TEST_ANALYTICS_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  (select count(*)::integer from public.hr_employee_assignment assignment
   where assignment.tenant_id = app_user.tenant_id
     and assignment.primary_assignment
     and assignment.effective_start <= current_date
     and (assignment.effective_end is null or assignment.effective_end >= current_date)),
  (select count(*) from public.hr_employee),
  (select count(*) from public.hr_employee_assignment)
from public.sys_user app_user
where app_user.auth_user_id is not null
  and app_user.deleted_at is null
  and coalesce(app_user.user_type, '') <> '0'
  and not ('R_SUPER' = any(coalesce(app_user.user_roles, '{}'::text[])))
  and exists (
    select 1 from public.hr_employee employee
    where employee.tenant_id = app_user.tenant_id
  )
order by app_user.create_time
limit 1;

do $test$
begin
  if not exists(select 1 from hr_people_analytics_test_context) then
    raise exception 'No ordinary tenant user fixture for People Analytics test';
  end if;
end
$test$;

grant select, update on hr_people_analytics_test_context to authenticated;
grant select, insert on hr_people_analytics_test_result to authenticated;
grant insert on hr_people_analytics_test_result to anon;
grant execute on function public.get_app_user_display_name() to authenticated;

-- Anonymous callers must never reach aggregate workforce data.
select set_config('request.jwt.claims', jsonb_build_object(
  'role', 'anon'
)::text, true);
set local role anon;

do $test$
declare
  v_denied boolean := false;
begin
  begin
    perform public.hr_people_analytics_overview_secure(current_date, 12, null);
  exception when others then
    v_denied := sqlstate = '42501';
  end;
  insert into hr_people_analytics_test_result values(
    'anonymous_is_denied', v_denied,
    '匿名账号不能访问人力聚合分析'
  );
end
$test$;

reset role;

-- An ordinary user without the explicit View permission is denied.
update public.sys_user app_user
set user_roles = '{}'::text[], update_by = 'automated-test'
from hr_people_analytics_test_context context
where app_user.id = context.ordinary_sys_user_id;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_people_analytics_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_denied boolean := false;
begin
  begin
    perform public.hr_people_analytics_overview_secure(current_date, 12, null);
  exception when others then
    v_denied := sqlstate = '42501';
  end;
  insert into hr_people_analytics_test_result values(
    'ordinary_without_permission_is_denied', v_denied,
    '普通账号必须获得人力分析查看权限'
  );
end
$test$;

reset role;

insert into public.sys_role(
  id, tenant_id, role_name, role_code, description, enabled, create_by, update_by
)
select ordinary_role_id, tenant_id, '人力分析测试角色', ordinary_role_code,
  '事务回滚内的人力分析租户与隐私阈值验证角色', true,
  'automated-test', 'automated-test'
from hr_people_analytics_test_context;

update public.sys_user app_user
set user_roles = array[context.ordinary_role_code], update_by = 'automated-test'
from hr_people_analytics_test_context context
where app_user.id = context.ordinary_sys_user_id;

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select context.ordinary_role_id, target.menu_id, context.tenant_id,
  '{}'::jsonb, 'automated-test', 'automated-test'
from hr_people_analytics_test_context context
cross join (values
  ('c0de0000-0000-4000-8000-000000000210'::uuid),
  ('c0de0000-0000-4000-8210-000000000001'::uuid)
) target(menu_id);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_people_analytics_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_people_analytics_test_context%rowtype;
  v_payload jsonb;
begin
  select * into v_context from hr_people_analytics_test_context limit 1;

  v_payload := public.hr_people_analytics_overview_secure(
    current_date + 30, 99, gen_random_uuid()
  );

  insert into hr_people_analytics_test_result values(
    'ordinary_scope_is_forced_to_own_tenant',
    (v_payload #>> '{overview,ending_headcount}')::integer = v_context.expected_headcount,
    '传入其他租户标识也只能看到当前租户聚合结果'
  );

  insert into hr_people_analytics_test_result values(
    'input_window_is_safely_clamped',
    (v_payload ->> 'period_months')::integer = 36
      and (v_payload ->> 'as_of_date')::date =
        (clock_timestamp() at time zone 'Asia/Shanghai')::date,
    '分析窗口限制为 3 至 36 个月且不能读取未来快照'
  );

  insert into hr_people_analytics_test_result values(
    'payload_contains_complete_analytics_sections',
    jsonb_typeof(v_payload -> 'flow_trend') = 'array'
      and jsonb_typeof(v_payload -> 'organization_distribution') = 'array'
      and jsonb_typeof(v_payload -> 'employment_distribution') = 'array'
      and jsonb_typeof(v_payload -> 'tenure_distribution') = 'array'
      and jsonb_typeof(v_payload -> 'data_quality') = 'array',
    '趋势、组织、用工、任期和数据质量区均有稳定契约'
  );

  insert into hr_people_analytics_test_result values(
    'organization_cohorts_respect_privacy_threshold',
    not exists (
      select 1
      from jsonb_array_elements(v_payload -> 'organization_distribution') item
      where not coalesce((item ->> 'protected')::boolean, false)
        and (item ->> 'headcount')::integer < (v_payload ->> 'privacy_threshold')::integer
    ) and not exists (
      select 1
      from jsonb_array_elements(v_payload -> 'organization_distribution') item
      where coalesce((item ->> 'protected')::boolean, false)
        and item ->> 'name' <> '其他受保护组织'
    ),
    '少于 5 人的组织被合并且不暴露组织名称'
  );

  insert into hr_people_analytics_test_result values(
    'payload_has_no_person_or_assignment_identifiers',
    v_payload::text not like '%"employee_id"%'
      and v_payload::text not like '%"employee_name"%'
      and v_payload::text not like '%"employee_no"%'
      and v_payload::text not like '%"assignment_id"%',
    '聚合响应不包含员工或任职明细标识'
  );

end
$test$;

reset role;

insert into hr_people_analytics_test_result
select 'analytics_is_read_only',
  context.employee_count = (select count(*) from public.hr_employee)
    and context.assignment_count = (select count(*) from public.hr_employee_assignment),
  '读取分析不会改变员工与任职源数据'
from hr_people_analytics_test_context context;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id from public.sys_user
    where auth_user_id is not null
      and ('R_SUPER' = any(coalesce(user_roles, '{}'::text[])) or user_type = '0')
    order by case when 'R_SUPER' = any(coalesce(user_roles, '{}'::text[])) then 0 else 1 end
    limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_people_analytics_test_context%rowtype;
  v_payload jsonb;
begin
  select * into v_context from hr_people_analytics_test_context limit 1;
  v_payload := public.hr_people_analytics_overview_secure(
    current_date, 12, v_context.tenant_id
  );
  insert into hr_people_analytics_test_result values(
    'platform_super_can_select_explicit_tenant',
    (v_payload #>> '{overview,ending_headcount}')::integer = v_context.expected_headcount,
    '平台超级管理员可显式切换到指定租户聚合视图'
  );
end
$test$;

reset role;

do $test$
declare
  v_total integer;
  v_passed integer;
begin
  select count(*), count(*) filter (where passed)
  into v_total, v_passed
  from hr_people_analytics_test_result;

  if v_total <> 9 or v_passed <> v_total then
    raise exception 'People Analytics regression failed: %/% passed. Failures: %',
      v_passed, v_total,
      coalesce((select string_agg(check_name || ': ' || detail, '; ')
        from hr_people_analytics_test_result where not passed), 'unknown');
  end if;

  raise notice 'People Analytics regression passed: %/% checks', v_passed, v_total;
end
$test$;

rollback;
