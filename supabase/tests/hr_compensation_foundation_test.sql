begin;

create temporary table hr_compensation_test_context (
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  employee_id uuid not null,
  compensation_id uuid
) on commit drop;

create temporary table hr_compensation_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_compensation_test_context(tenant_id, ordinary_auth_user_id, employee_id)
select user_row.tenant_id, user_row.auth_user_id, employee_row.id
from public.sys_user user_row
join lateral (
  select id
  from public.hr_employee
  where tenant_id = user_row.tenant_id
    and employment_status in ('probation', 'active', 'leave')
  order by employee_no
  limit 1
) employee_row on true
where user_row.auth_user_id is not null
  and user_row.status = '1'
  and 'R_REGISTER' = any(user_row.user_roles)
order by user_row.create_time
limit 1;

grant select, update on hr_compensation_test_context to authenticated;
grant select, insert, update on hr_compensation_test_result to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (
      select auth_user_id
      from public.sys_user
      where auth_user_id is not null
        and ('R_SUPER' = any(user_roles) or user_type = '0')
      order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end
      limit 1
    ),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid;
  v_ordinary_auth_user_id uuid;
  v_employee_id uuid;
  v_component_id uuid;
  v_plan_id uuid;
  v_grade_id uuid;
  v_grade_tenant_id uuid;
  v_band_id uuid;
  v_overlap_band_id uuid;
  v_compensation_id uuid;
  v_overlap_id uuid;
  v_payroll_count integer := 0;
  v_overlap_blocked boolean := false;
  v_band_overlap_blocked boolean := false;
  v_band_approved_count integer := 0;
  v_band_payload jsonb;
  v_payload jsonb;
begin
  select tenant_id, ordinary_auth_user_id, employee_id
  into v_tenant_id, v_ordinary_auth_user_id, v_employee_id
  from hr_compensation_test_context
  limit 1;

  if v_tenant_id is null then raise exception 'No ordinary HR tenant test fixture'; end if;

  v_grade_tenant_id := v_tenant_id;
  v_grade_id := public.hr_save_grade_secure(
    null,
    jsonb_build_object(
      'tenant_id', v_grade_tenant_id,
      'grade_code', 'TEST_GRADE',
      'grade_name', '测试职级',
      'grade_level', 99,
      'enabled', true,
      'sort', 999
    )
  );

  if v_grade_id is not null then
    v_band_id := public.hr_save_compensation_master_secure(
      'band', null,
      jsonb_build_object(
        'tenant_id', v_grade_tenant_id,
        'grade_id', v_grade_id,
        'currency_code', 'CNY',
        'minimum_amount', 8000,
        'midpoint_amount', 10000,
        'maximum_amount', 12000,
        'effective_from', current_date
      )
    );
    perform public.hr_act_compensation_record_secure('band', v_band_id, 'approve', null);
    v_overlap_band_id := public.hr_save_compensation_master_secure(
      'band', null,
      jsonb_build_object(
        'tenant_id', v_grade_tenant_id,
        'grade_id', v_grade_id,
        'currency_code', 'CNY',
        'minimum_amount', 9000,
        'midpoint_amount', 11000,
        'maximum_amount', 13000,
        'effective_from', current_date
      )
    );
    begin
      perform public.hr_act_compensation_record_secure(
        'band', v_overlap_band_id, 'approve', null
      );
    exception when others then
      v_band_overlap_blocked := true;
    end;
    v_band_payload := public.hr_list_compensation_records_secure(
      'band', 0, 499, null, 'active', v_grade_tenant_id
    );
    select count(*) into v_band_approved_count
    from jsonb_array_elements(v_band_payload->'records') record_row
    where record_row->>'grade_id' = v_grade_id::text;
  end if;

  v_component_id := public.hr_save_compensation_master_secure(
    'component', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'component_code', 'TEST_ALLOWANCE',
      'component_name', '测试补贴',
      'category', 'earning',
      'amount_type', 'fixed',
      'taxable', true,
      'enabled', true,
      'sort', 1
    )
  );

  v_plan_id := public.hr_save_compensation_master_secure(
    'plan', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'plan_code', 'TEST_MONTHLY',
      'plan_name', '测试月薪方案',
      'currency_code', 'CNY',
      'pay_frequency', 'monthly',
      'enabled', true,
      'items', jsonb_build_array(jsonb_build_object(
        'component_id', v_component_id,
        'default_amount', 500,
        'required', true,
        'sort', 1
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
      'change_reason', '企业薪酬自动化测试'
    )
  );
  perform public.hr_act_compensation_record_secure(
    'employee', v_compensation_id, 'approve', null
  );

  select jsonb_array_length(public.hr_compensation_payroll_inputs_secure(
    current_date, v_tenant_id
  )) into v_payroll_count;

  v_overlap_id := public.hr_save_employee_compensation_secure(
    null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'employee_id', v_employee_id,
      'plan_id', v_plan_id,
      'base_amount', 12000,
      'effective_from', current_date,
      'change_reason', '重叠区间阻断测试'
    )
  );
  begin
    perform public.hr_act_compensation_record_secure('employee', v_overlap_id, 'approve', null);
  exception when others then
    v_overlap_blocked := true;
  end;

  update hr_compensation_test_context set compensation_id = v_compensation_id;
  v_payload := public.hr_list_compensation_records_secure(
    'employee', 0, 49, null, null, v_tenant_id
  );
  insert into hr_compensation_test_result values
    ('approved_record', exists(
      select 1 from jsonb_array_elements(v_payload->'records') record_row
      where record_row->>'id' = v_compensation_id::text
        and record_row->>'lifecycle_status' = 'active'
    ), '员工薪酬草稿可批准并锁定'),
    ('payroll_input', v_payroll_count >= 1, '当期已批准薪酬可生成财务核算输入'),
    ('overlap_blocked', v_overlap_blocked, '同员工同日重叠的已批准薪酬被阻断'),
    ('salary_band_overlap_blocked',
      v_grade_id is not null and v_band_approved_count = 1,
      format('同职级同日仅允许一个已批准薪档（异常捕获=%s，批准数=%s）',
        v_band_overlap_blocked, v_band_approved_count));
end;
$test$;

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select ordinary_auth_user_id from hr_compensation_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_payload jsonb;
  v_write_blocked boolean := false;
begin
  v_payload := public.hr_list_compensation_records_secure(
    'employee', 0, 49, null, null, null
  );
  begin
    perform public.hr_save_compensation_master_secure(
      'component', null,
      jsonb_build_object(
        'component_code', 'DENIED',
        'component_name', '不应写入',
        'category', 'earning',
        'amount_type', 'fixed'
      )
    );
  exception when insufficient_privilege then
    v_write_blocked := true;
  end;

  insert into hr_compensation_test_result values
    ('ordinary_masked_read',
      coalesce((v_payload->>'amount_access')::boolean, true) = false
      and exists (
        select 1
        from jsonb_array_elements(v_payload->'records') record_row
        where record_row->>'base_amount' = '***'
      ),
      '普通用户仅获得租户内脱敏金额'),
    ('ordinary_write_denied', v_write_blocked, '普通用户不能新增薪酬政策');
end;
$test$;

reset role;
select check_name, passed, detail
from hr_compensation_test_result
order by check_name;

do $test$
declare v_failed text;
begin
  select string_agg(check_name || ': ' || coalesce(detail, ''), '; ')
  into v_failed
  from hr_compensation_test_result
  where not passed;
  if v_failed is not null then
    raise exception 'HR compensation foundation test failed: %', v_failed;
  end if;
end;
$test$;

rollback;
