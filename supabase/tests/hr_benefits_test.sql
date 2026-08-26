begin;

create temporary table hr_benefits_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  other_employee_id uuid not null,
  employee_status text not null,
  ordinary_auth_user_id uuid not null,
  ordinary_sys_user_id uuid not null,
  ordinary_role_id uuid not null,
  ordinary_role_code text not null,
  plan_id uuid,
  option_id uuid,
  life_event_id uuid,
  enrollment_id uuid
) on commit drop;

create temporary table hr_benefits_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_benefits_test_context(
  tenant_id, employee_id, other_employee_id, employee_status,
  ordinary_auth_user_id, ordinary_sys_user_id, ordinary_role_id,
  ordinary_role_code
)
select employee.tenant_id, employee.id, other_employee.id,
  employee.employment_status, app_user.auth_user_id, app_user.id,
  gen_random_uuid(),
  'TEST_BEN_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
from public.sys_user app_user
join public.hr_employee employee
  on employee.id = app_user.hr_employee_id
  and employee.tenant_id = app_user.tenant_id
join lateral (
  select candidate.id
  from public.hr_employee candidate
  where candidate.tenant_id = employee.tenant_id
    and candidate.id <> employee.id
    and candidate.employment_status not in ('left', 'terminated')
  order by candidate.employee_no
  limit 1
) other_employee on true
where app_user.auth_user_id is not null
  and app_user.deleted_at is null
  and coalesce(app_user.user_type, '') <> '0'
  and not ('R_SUPER' = any(coalesce(app_user.user_roles, '{}'::text[])))
  and employee.employment_status not in ('left', 'terminated')
order by employee.employee_no
limit 1;

do $test$
begin
  if not exists(select 1 from hr_benefits_test_context) then
    raise exception 'No ordinary linked HR employee fixture with a second tenant employee';
  end if;
end
$test$;

insert into public.sys_role(
  id, tenant_id, role_name, role_code, description, enabled, create_by, update_by
)
select ordinary_role_id, tenant_id, '福利脱敏测试角色', ordinary_role_code,
  '事务回滚内的福利金额与附件脱敏验证角色', true,
  'automated-test', 'automated-test'
from hr_benefits_test_context;

update public.sys_user app_user
set user_roles = array[context.ordinary_role_code], update_by = 'automated-test'
from hr_benefits_test_context context
where app_user.id = context.ordinary_sys_user_id;

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select context.ordinary_role_id, target.menu_id, context.tenant_id,
  '{}'::jsonb, 'automated-test', 'automated-test'
from hr_benefits_test_context context
cross join (values
  ('c0de0000-0000-4000-8000-000000000208'::uuid),
  ('c0de0000-0000-4000-8208-000000000001'::uuid)
) target(menu_id);

grant select, update on hr_benefits_test_context to authenticated;
grant select, insert on hr_benefits_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id
    from public.sys_user
    where auth_user_id is not null
      and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end
    limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_benefits_test_context%rowtype;
  v_plan_id uuid;
  v_option_id uuid;
  v_event_id uuid;
  v_enrollment_id uuid;
  v_duplicate_id uuid;
  v_cross_event_blocked boolean := false;
  v_duplicate_blocked boolean := false;
  v_plan_direct_blocked boolean := false;
  v_option_direct_blocked boolean := false;
  v_event_direct_blocked boolean := false;
  v_enrollment_direct_blocked boolean := false;
  v_audit_direct_blocked boolean := false;
  v_detail jsonb;
begin
  select * into v_context from hr_benefits_test_context limit 1;

  v_plan_id := public.hr_save_benefit_record_secure('plan', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'plan_code', 'TEST-BEN-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'plan_name', '自动化综合福利计划',
    'plan_type', 'commercial_insurance',
    'provider_name', '自动化测试供应商',
    'enrollment_method', 'election',
    'coverage_scope', 'employee_family',
    'currency_code', 'CNY',
    'effective_from', current_date - 30,
    'effective_to', current_date + 365,
    'description', '验证福利政策、参保审核和薪资输入边界'
  ));

  v_option_id := public.hr_save_benefit_record_secure('option', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'plan_id', v_plan_id,
    'option_code', 'STANDARD',
    'option_name', '标准保障方案',
    'coverage_level', 'employee',
    'contribution_type', 'fixed',
    'employee_contribution', 120.50,
    'employer_contribution', 360.75,
    'currency_code', 'CNY',
    'enabled', true,
    'sort', 10
  ));

  perform public.hr_transition_benefit_record_secure(
    'plan', v_plan_id, 'activate', '启用自动化福利计划'
  );

  v_event_id := public.hr_save_benefit_record_secure('event', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'employee_id', v_context.employee_id,
    'event_type', 'annual_enrollment',
    'event_date', current_date,
    'enrollment_window_end', current_date + 30,
    'evidence_urls', jsonb_build_array('https://example.invalid/private-benefit-evidence'),
    'remark', '自动化参保窗口'
  ));

  v_enrollment_id := public.hr_save_benefit_record_secure('enrollment', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'employee_id', v_context.employee_id,
    'plan_id', v_plan_id,
    'option_id', v_option_id,
    'life_event_id', v_event_id,
    'enrollment_no', 'TEST-ENR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'coverage_from', current_date,
    'coverage_to', current_date + 365,
    'employee_contribution', 120.50,
    'employer_contribution', 360.75,
    'currency_code', 'CNY'
  ));

  perform public.hr_transition_benefit_record_secure(
    'enrollment', v_enrollment_id, 'submit', '提交自动化参保审核'
  );
  perform public.hr_transition_benefit_record_secure(
    'enrollment', v_enrollment_id, 'approve', '审核自动化参保'
  );

  update hr_benefits_test_context set
    plan_id = v_plan_id,
    option_id = v_option_id,
    life_event_id = v_event_id,
    enrollment_id = v_enrollment_id;

  v_detail := public.hr_get_benefit_detail_secure('enrollment', v_enrollment_id);
  insert into hr_benefits_test_result values(
    'plan_to_payroll_lifecycle_is_complete',
    v_detail ->> 'status' = 'active'
      and v_detail ->> 'payroll_sync_status' = 'ready'
      and jsonb_array_length(v_detail -> 'events') >= 3
      and exists(
        select 1
        from jsonb_array_elements(public.hr_benefit_payroll_inputs_secure(
          date_trunc('month', current_date)::date, v_context.tenant_id
        )) input
        where (input ->> 'enrollment_id')::uuid = v_enrollment_id
          and (input ->> 'employee_contribution')::numeric = 120.50
          and (input ->> 'employer_contribution')::numeric = 360.75
      ),
    '计划、方案、人生事件、参保审核和薪资输入形成完整受控链路'
  );

  begin
    perform public.hr_save_benefit_record_secure('enrollment', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'employee_id', v_context.other_employee_id,
      'plan_id', v_plan_id,
      'option_id', v_option_id,
      'life_event_id', v_event_id,
      'coverage_from', current_date,
      'currency_code', 'CNY'
    ));
  exception when others then
    v_cross_event_blocked := position('人生事件不属于该员工' in sqlerrm) > 0;
  end;
  insert into hr_benefits_test_result values(
    'life_event_cannot_cross_employee',
    v_cross_event_blocked,
    '员工参保只能引用属于本人的开放人生事件'
  );

  v_duplicate_id := public.hr_save_benefit_record_secure('enrollment', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'employee_id', v_context.employee_id,
    'plan_id', v_plan_id,
    'option_id', v_option_id,
    'coverage_from', current_date,
    'currency_code', 'CNY'
  ));
  begin
    perform public.hr_transition_benefit_record_secure(
      'enrollment', v_duplicate_id, 'submit', '提交重复参保'
    );
  exception when others then
    v_duplicate_blocked := position('已有待审核或生效中的参保记录' in sqlerrm) > 0;
  end;
  insert into hr_benefits_test_result values(
    'duplicate_active_enrollment_is_blocked',
    v_duplicate_blocked,
    '同一员工在同一福利计划下不能重复进入待审核或生效状态'
  );

  begin
    perform 1 from public.hr_benefit_plan limit 1;
  exception when insufficient_privilege then v_plan_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_benefit_option limit 1;
  exception when insufficient_privilege then v_option_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_benefit_life_event limit 1;
  exception when insufficient_privilege then v_event_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_employee_benefit_enrollment limit 1;
  exception when insufficient_privilege then v_enrollment_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_benefit_event limit 1;
  exception when insufficient_privilege then v_audit_direct_blocked := true;
  end;
  insert into hr_benefits_test_result values(
    'benefit_tables_deny_direct_access',
    v_plan_direct_blocked and v_option_direct_blocked
      and v_event_direct_blocked and v_enrollment_direct_blocked
      and v_audit_direct_blocked,
    '已登录用户不能绕过受控 RPC 直接读取福利业务表或审计表'
  );
end
$test$;

reset role;
insert into hr_benefits_test_result
select 'benefit_actions_do_not_change_employment_status',
  exists(
    select 1
    from public.hr_employee employee
    join hr_benefits_test_context context
      on context.employee_id = employee.id
      and context.tenant_id = employee.tenant_id
    where employee.employment_status = context.employee_status
  ),
  '福利人生事件与参保审核不直接修改员工任职状态';

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_benefits_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_benefits_test_context%rowtype;
  v_enrollment_detail jsonb;
  v_event_detail jsonb;
  v_list_record jsonb;
begin
  select * into v_context from hr_benefits_test_context limit 1;
  v_enrollment_detail := public.hr_get_benefit_detail_secure(
    'enrollment', v_context.enrollment_id
  );
  v_event_detail := public.hr_get_benefit_detail_secure(
    'event', v_context.life_event_id
  );
  select record into v_list_record
  from jsonb_array_elements(public.hr_list_benefit_records_secure(
    'enrollment', 0, 19, null, 'active', null, v_context.tenant_id
  ) -> 'records') record
  where (record ->> 'id')::uuid = v_context.enrollment_id;

  insert into hr_benefits_test_result values(
    'amounts_are_redacted_server_side',
    coalesce((v_enrollment_detail ->> 'amount_visible')::boolean, false) = false
      and not (v_enrollment_detail ? 'employee_contribution')
      and not (v_enrollment_detail ? 'employer_contribution')
      and v_list_record -> 'employee_contribution' = 'null'::jsonb
      and v_list_record -> 'employer_contribution' = 'null'::jsonb,
    '仅有查看权限时，参保详情和列表均由服务端隐藏缴费金额'
  );

  insert into hr_benefits_test_result values(
    'life_event_evidence_is_redacted_server_side',
    coalesce((v_event_detail ->> 'evidence_restricted')::boolean, false)
      and v_event_detail -> 'evidence_urls' = '[]'::jsonb,
    '仅有查看权限时，人生事件附件由服务端返回空数组并标记受限'
  );
end
$test$;

reset role;
insert into hr_benefits_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege(
    'anon', 'public.hr_benefits_overview_secure(uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_save_benefit_record_secure(text,jsonb)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_benefit_payroll_inputs_secure(date,uuid)', 'execute'
  ),
  '匿名角色不能调用福利受控 RPC'
);

select check_name, passed, detail
from hr_benefits_test_result
order by check_name;

do $test$
begin
  if exists(select 1 from hr_benefits_test_result where not passed) then
    raise exception 'HR benefits verification failed';
  end if;
end
$test$;

rollback;
