begin;

create temporary table hr_fms_test_context (
  platform_super_auth_user_id uuid not null,
  finance_auth_user_id uuid not null,
  tenant_id uuid not null,
  accounting_period_id uuid not null,
  employee_id uuid not null,
  compensation_id uuid,
  payroll_run_id uuid
) on commit drop;

create temporary table hr_fms_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_fms_test_context(
  platform_super_auth_user_id,
  finance_auth_user_id,
  tenant_id,
  accounting_period_id,
  employee_id
)
select
  (
    select auth_user_id from public.sys_user
    where auth_user_id is not null and 'R_SUPER' = any(user_roles)
    limit 1
  ),
  finance_user.auth_user_id,
  period_row.tenant_id,
  period_row.id,
  employee_row.id
from public.fms_accounting_period period_row
join lateral (
  select user_row.auth_user_id
  from public.sys_user user_row
  join public.sys_role role_row
    on role_row.role_code = any(user_row.user_roles)
   and role_row.tenant_id = user_row.tenant_id
  join public.sys_role_menu role_menu on role_menu.role_id = role_row.id
  join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
  where user_row.tenant_id = period_row.tenant_id
    and user_row.auth_user_id is not null
    and user_row.status = '1'
    and menu_row.name = 'FinancePayroll:Calculate'
  order by user_row.create_time
  limit 1
) finance_user on true
join lateral (
  select id
  from public.hr_employee
  where tenant_id = period_row.tenant_id
    and employment_status in ('probation', 'active', 'leave')
  order by employee_no
  limit 1
) employee_row on true
where period_row.status = 'open'
  and period_row.start_date <= current_date
  and period_row.end_date >= current_date
order by period_row.start_date desc
limit 1;

grant select, update on hr_fms_test_context to authenticated;
grant select, insert on hr_fms_test_result to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select platform_super_auth_user_id from hr_fms_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid;
  v_employee_id uuid;
  v_component_id uuid;
  v_plan_id uuid;
  v_compensation_id uuid;
begin
  select tenant_id, employee_id into v_tenant_id, v_employee_id
  from hr_fms_test_context limit 1;

  v_component_id := public.hr_save_compensation_master_secure(
    'component', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'component_code', 'FMS_SYNC_ALLOWANCE',
      'component_name', '核算同步补贴',
      'category', 'earning',
      'amount_type', 'fixed',
      'enabled', true
    )
  );
  v_plan_id := public.hr_save_compensation_master_secure(
    'plan', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'plan_code', 'FMS_SYNC_PLAN',
      'plan_name', '核算同步方案',
      'currency_code', 'CNY',
      'pay_frequency', 'monthly',
      'enabled', true,
      'items', jsonb_build_array(jsonb_build_object(
        'component_id', v_component_id,
        'default_amount', 500,
        'required', true
      ))
    )
  );
  v_compensation_id := public.hr_save_employee_compensation_secure(
    null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'employee_id', v_employee_id,
      'plan_id', v_plan_id,
      'base_amount', 10000,
      'effective_from', current_date,
      'change_reason', 'HR 与 FMS 集成测试'
    )
  );
  perform public.hr_act_compensation_record_secure(
    'employee', v_compensation_id, 'approve', null
  );
  update hr_fms_test_context set compensation_id = v_compensation_id;
end;
$test$;

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select finance_auth_user_id from hr_fms_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_period_id uuid;
  v_run jsonb;
  v_first jsonb;
  v_second jsonb;
begin
  select accounting_period_id into v_period_id from hr_fms_test_context limit 1;
  v_run := public.save_fms_payroll_run_secure(jsonb_build_object(
    'accountingPeriodId', v_period_id,
    'remark', 'HR 薪酬同步集成测试'
  ));
  update hr_fms_test_context set payroll_run_id = (v_run->>'id')::uuid;

  v_first := public.fms_import_hr_compensation_lines_secure((v_run->>'id')::uuid);
  v_second := public.fms_import_hr_compensation_lines_secure((v_run->>'id')::uuid);

  insert into hr_fms_test_result values
    ('first_import',
      (v_first->>'eligible_count')::integer >= 1
      and (v_first->>'imported_count')::integer >= 1,
      format('首次同步导入 %s 名员工', v_first->>'imported_count')),
    ('repeat_preserves_finance_lines',
      (v_second->>'imported_count')::integer = 0
      and (v_second->>'skipped_count')::integer >= 1,
      format('重复同步跳过 %s 条已有财务明细', v_second->>'skipped_count'));
end;
$test$;

reset role;
select check_name, passed, detail
from hr_fms_test_result
order by check_name;

do $test$
declare v_failed text;
begin
  select string_agg(check_name || ': ' || detail, '; ')
  into v_failed from hr_fms_test_result where not passed;
  if v_failed is not null then
    raise exception 'HR/FMS compensation integration test failed: %', v_failed;
  end if;
end;
$test$;

rollback;
