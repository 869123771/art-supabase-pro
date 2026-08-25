begin;

create temporary table hr_absence_test_context (
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  employee_id uuid not null,
  request_id uuid
) on commit drop;

create temporary table hr_absence_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_absence_test_context(tenant_id, ordinary_auth_user_id, employee_id)
select user_row.tenant_id, user_row.auth_user_id, employee_row.id
from public.sys_user user_row
join lateral (
  select id from public.hr_employee
  where tenant_id = user_row.tenant_id
    and employment_status in ('probation', 'active', 'leave')
  order by employee_no limit 1
) employee_row on true
where user_row.auth_user_id is not null
  and user_row.status = '1'
  and 'R_REGISTER' = any(user_row.user_roles)
order by user_row.create_time
limit 1;

grant select, update on hr_absence_test_context to authenticated;
grant select, insert on hr_absence_test_result to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (
      select auth_user_id from public.sys_user
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
  v_employee_id uuid;
  v_type_id uuid;
  v_policy_id uuid;
  v_balance_id uuid;
  v_request_id uuid;
  v_overlap_request_id uuid;
  v_overlap_blocked boolean := false;
  v_balance jsonb;
  v_payload jsonb;
begin
  select tenant_id, employee_id into v_tenant_id, v_employee_id
  from hr_absence_test_context limit 1;
  if v_tenant_id is null then raise exception 'No HR absence test fixture'; end if;

  v_type_id := public.hr_save_absence_master_secure(
    'type', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'leave_code', 'TEST_ANNUAL',
      'leave_name', '测试年休假',
      'category', 'annual',
      'unit', 'day',
      'paid_ratio', 1,
      'minimum_increment', 0.5,
      'enabled', true
    )
  );
  v_policy_id := public.hr_save_absence_master_secure(
    'policy', null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'leave_type_id', v_type_id,
      'policy_code', 'TEST_ANNUAL_ALL',
      'policy_name', '测试全员年休假政策',
      'scope_type', 'all',
      'entitlement_method', 'annual',
      'annual_quota', 10,
      'effective_from', make_date(extract(year from current_date)::integer, 1, 1),
      'status', 'active'
    )
  );

  v_balance_id := public.hr_adjust_leave_balance_secure(
    v_employee_id, v_type_id, extract(year from current_date)::integer,
    5, '企业假勤自动化测试调整', v_tenant_id
  );

  v_request_id := public.hr_save_leave_request_secure(
    null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'employee_id', v_employee_id,
      'leave_type_id', v_type_id,
      'start_date', current_date + 10,
      'end_date', current_date + 11,
      'requested_amount', 2,
      'reason', '自动化休假隐私原因'
    )
  );
  perform public.hr_act_leave_request_secure(v_request_id, 'submit', null);
  v_payload := public.hr_list_absence_records_secure(
    'balance', 0, 49, null, null, extract(year from current_date)::integer, v_tenant_id
  );
  select record_row into v_balance
  from jsonb_array_elements(v_payload->'records') record_row
  where record_row->>'id' = v_balance_id::text;
  insert into hr_absence_test_result values (
    'submit_reserves_balance',
    (v_balance->>'pending_amount')::numeric = 2
      and (v_balance->>'used_amount')::numeric = 0,
    '提交申请占用 2 天余额但不计入已使用'
  );

  perform public.hr_act_leave_request_secure(v_request_id, 'approve', '自动化批准');
  v_payload := public.hr_list_absence_records_secure(
    'balance', 0, 49, null, null, extract(year from current_date)::integer, v_tenant_id
  );
  select record_row into v_balance
  from jsonb_array_elements(v_payload->'records') record_row
  where record_row->>'id' = v_balance_id::text;
  insert into hr_absence_test_result values (
    'approval_posts_usage',
    (v_balance->>'pending_amount')::numeric = 0
      and (v_balance->>'used_amount')::numeric = 2
      and exists (
        select 1 from jsonb_array_elements(
          public.hr_list_absence_records_secure(
            'ledger', 0, 49, null, 'usage', extract(year from current_date)::integer, v_tenant_id
          )->'records'
        ) record_row
        where record_row->>'request_id' = v_request_id::text
      ),
    '批准后占用转为使用并写入不可变台账'
  );

  v_overlap_request_id := public.hr_save_leave_request_secure(
    null,
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'employee_id', v_employee_id,
      'leave_type_id', v_type_id,
      'start_date', current_date + 11,
      'end_date', current_date + 12,
      'requested_amount', 1,
      'reason', '重叠区间测试'
    )
  );
  begin
    perform public.hr_act_leave_request_secure(v_overlap_request_id, 'submit', null);
  exception when exclusion_violation then
    v_overlap_blocked := true;
  end;
  insert into hr_absence_test_result values (
    'overlap_blocked', v_overlap_blocked,
    '同一员工重叠的待审批或已批准休假被数据库约束阻断'
  );

  v_payload := public.hr_list_absence_records_secure(
    'request', 0, 49, null, null, extract(year from current_date)::integer, v_tenant_id
  );
  insert into hr_absence_test_result values (
    'approved_request_visible',
    exists (select 1 from jsonb_array_elements(v_payload->'records') record_row
      where record_row->>'id' = v_request_id::text and record_row->>'status' = 'approved'),
    '批准记录可在受控列表中追溯'
  );

  update hr_absence_test_context set request_id = v_request_id;
end;
$test$;

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select ordinary_auth_user_id from hr_absence_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_request_id uuid;
  v_payload jsonb;
  v_direct_blocked boolean := false;
begin
  select request_id into v_request_id from hr_absence_test_context limit 1;
  v_payload := public.hr_list_absence_records_secure('request', 0, 49, null, null, null, null);
  begin
    perform 1 from public.hr_leave_request limit 1;
  exception when insufficient_privilege then
    v_direct_blocked := true;
  end;
  insert into hr_absence_test_result values
    ('ordinary_reason_masked',
      coalesce((v_payload->>'reason_access')::boolean, true) = false
      and exists (select 1 from jsonb_array_elements(v_payload->'records') record_row
        where record_row->>'id' = v_request_id::text and record_row->>'reason' = '***'),
      '普通查看权限仅返回脱敏休假原因'),
    ('direct_table_access_denied', v_direct_blocked,
      '签入用户不能绕过受控 RPC 直读休假表');
end;
$test$;

reset role;

select check_name, passed, detail
from hr_absence_test_result
order by check_name;

do $test$
begin
  if exists (select 1 from hr_absence_test_result where not passed) then
    raise exception 'HR absence management verification failed';
  end if;
end;
$test$;

rollback;
