begin;

set local timezone = 'Asia/Shanghai';

create temporary table hr_compensation_review_test_context (
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  employee_id uuid not null,
  cycle_id uuid,
  item_id uuid,
  budget_id uuid,
  current_compensation_id uuid
) on commit drop;

create temporary table hr_compensation_review_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_compensation_review_test_context(
  tenant_id, ordinary_auth_user_id, employee_id
)
select user_row.tenant_id, user_row.auth_user_id, employee_row.id
from public.sys_user user_row
join lateral (
  select employee.id
  from public.hr_employee employee
  where employee.tenant_id = user_row.tenant_id
    and employee.employment_status in ('probation', 'active', 'leave')
  order by employee.employee_no
  limit 1
) employee_row on true
where user_row.auth_user_id is not null
  and user_row.status = '1'
  and 'R_REGISTER' = any(user_row.user_roles)
order by user_row.create_time
limit 1;

grant select, update on hr_compensation_review_test_context to authenticated;
grant select, insert, update on hr_compensation_review_test_result to anon, authenticated;

set local role anon;
do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_compensation_review_overview_secure(null, null);
  exception when insufficient_privilege then v_denied := true;
  end;
  insert into hr_compensation_review_test_result values
    ('anon_denied', v_denied, '匿名账号不能读取调薪复核');
end;
$test$;
reset role;

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
  v_employee_id uuid;
  v_component_id uuid;
  v_plan_id uuid;
  v_compensation_id uuid;
  v_cycle_id uuid;
  v_item_id uuid;
  v_budget_id uuid;
  v_payload jsonb;
  v_items jsonb;
  v_budgets jsonb;
  v_pending_guard boolean := false;
  v_budget_guard boolean := false;
  v_duplicate_blocked boolean := false;
begin
  select tenant_id, employee_id into v_tenant_id, v_employee_id
  from hr_compensation_review_test_context limit 1;
  if v_tenant_id is null then raise exception 'No ordinary HR tenant test fixture'; end if;

  v_component_id := public.hr_save_compensation_master_secure(
    'component', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'component_code', 'REVIEW_TEST_BASE',
      'component_name', '调薪复核测试项目',
      'category', 'earning',
      'amount_type', 'fixed',
      'taxable', true,
      'enabled', true,
      'sort', 999
    )
  );
  v_plan_id := public.hr_save_compensation_master_secure(
    'plan', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'plan_code', 'REVIEW_TEST_PLAN',
      'plan_name', '调薪复核测试方案',
      'currency_code', 'CNY',
      'pay_frequency', 'monthly',
      'enabled', true,
      'sort', 999,
      'items', jsonb_build_array(jsonb_build_object(
        'component_id', v_component_id,
        'default_amount', 100,
        'required', true,
        'sort', 1
      ))
    )
  );
  v_compensation_id := public.hr_save_employee_compensation_secure(
    null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'employee_id', v_employee_id,
      'plan_id', v_plan_id,
      'base_amount', 10000,
      'currency_code', 'CNY',
      'pay_frequency', 'monthly',
      'effective_from', current_date - 30,
      'change_reason', '调薪复核自动化测试基线'
    )
  );
  perform public.hr_act_compensation_record_secure('employee', v_compensation_id, 'approve', null);

  v_cycle_id := public.hr_save_compensation_review_record_secure(
    'cycle', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'cycle_code', 'REVIEW_TEST_2026',
      'cycle_name', '企业调薪复核自动化测试',
      'review_year', extract(year from current_date)::integer,
      'effective_date', current_date,
      'recommendation_due_date', current_date,
      'calibration_due_date', current_date,
      'currency_code', 'CNY',
      'default_budget_percent', 5,
      'guideline_min_percent', 0,
      'guideline_max_percent', 10,
      'description', '验证预算、建议、校准、审批和生效闭环'
    )
  );
  perform public.hr_transition_compensation_review_cycle_secure(v_cycle_id, 'open', null);

  v_items := public.hr_list_compensation_review_records_secure(
    'item', 0, 49, null, null, v_cycle_id, v_tenant_id
  );
  v_budgets := public.hr_list_compensation_review_records_secure(
    'budget', 0, 49, null, null, v_cycle_id, v_tenant_id
  );
  v_item_id := (v_items->'records'->0->>'id')::uuid;
  v_budget_id := (v_budgets->'records'->0->>'id')::uuid;
  update hr_compensation_review_test_context set
    cycle_id = v_cycle_id,
    item_id = v_item_id,
    budget_id = v_budget_id,
    current_compensation_id = v_compensation_id;

  v_payload := public.hr_compensation_review_overview_secure(v_cycle_id, v_tenant_id);
  insert into hr_compensation_review_test_result values (
    'snapshot_and_budget',
    v_item_id is not null and v_budget_id is not null
      and (v_payload->>'eligible_count')::integer >= 1
      and (v_payload->>'amount_access')::boolean,
    '开放周期自动快照员工薪酬并生成组织预算'
  );

  begin
    perform public.hr_transition_compensation_review_cycle_secure(v_cycle_id, 'calibrate', null);
  exception when others then v_pending_guard := true;
  end;
  insert into hr_compensation_review_test_result values
    ('pending_gate', v_pending_guard, '存在未建议员工时不能进入校准');

  perform public.hr_save_compensation_review_record_secure(
    'item', v_item_id, jsonb_build_object(
      'proposed_base_amount', 10600,
      'recommendation_reason', '绩效与市场校正'
    )
  );
  begin
    perform public.hr_transition_compensation_review_cycle_secure(v_cycle_id, 'calibrate', null);
  exception when others then v_budget_guard := true;
  end;
  insert into hr_compensation_review_test_result values
    ('budget_guard', v_budget_guard, '组织建议金额超过预算时阻断进入校准');

  perform public.hr_save_compensation_review_record_secure(
    'budget', v_budget_id, jsonb_build_object(
      'cycle_id', v_cycle_id,
      'budget_amount', 700,
      'note', '测试批准预算'
    )
  );
  perform public.hr_transition_compensation_review_cycle_secure(v_cycle_id, 'calibrate', null);
  perform public.hr_save_compensation_review_record_secure(
    'item', v_item_id, jsonb_build_object(
      'proposed_base_amount', 10500,
      'recommendation_reason', '绩效与市场校正',
      'calibration_note', '校准委员会统一调整为 5%'
    )
  );
  perform public.hr_transition_compensation_review_cycle_secure(
    v_cycle_id, 'approve', '预算内批准，按统一校准结果执行'
  );
  v_payload := public.hr_compensation_review_overview_secure(v_cycle_id, v_tenant_id);
  v_items := public.hr_list_compensation_review_records_secure(
    'item', 0, 49, null, null, v_cycle_id, v_tenant_id
  );
  insert into hr_compensation_review_test_result values (
    'calibration_approval',
    v_payload->'selected_cycle'->>'status' = 'approved'
      and v_items->'records'->0->>'status' = 'approved',
    '建议完成后进入校准并经独立审批定案'
  );

  perform public.hr_transition_compensation_review_cycle_secure(
    v_cycle_id, 'effect', '到期批量生效'
  );

  begin
    perform public.hr_transition_compensation_review_cycle_secure(v_cycle_id, 'effect', null);
  exception when others then v_duplicate_blocked := true;
  end;
  insert into hr_compensation_review_test_result values (
    'idempotent_effect', v_duplicate_blocked,
    '重复生效被状态机和来源唯一约束共同阻断'
  );
end;
$test$;

reset role;
do $test$
declare
  v_item_id uuid;
  v_current_compensation_id uuid;
  v_new_count integer;
begin
  select item_id, current_compensation_id
  into v_item_id, v_current_compensation_id
  from hr_compensation_review_test_context limit 1;

  select count(*) into v_new_count
  from public.hr_employee_compensation
  where source_review_item_id = v_item_id and base_amount = 10500 and status = 'approved';
  insert into hr_compensation_review_test_result values (
    'effective_history',
    v_new_count = 1
      and exists(select 1 from public.hr_employee_compensation where id = v_current_compensation_id and effective_to = current_date - 1)
      and exists(select 1 from public.hr_compensation_review_item where id = v_item_id and status = 'effected'),
    '生效动作关闭旧薪酬版本并创建可追溯的新版本'
  );
end;
$test$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select ordinary_auth_user_id from hr_compensation_review_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_cycle_id uuid := (select cycle_id from hr_compensation_review_test_context limit 1);
  v_payload jsonb;
  v_records jsonb;
  v_write_denied boolean := false;
  v_direct_denied boolean := false;
begin
  v_payload := public.hr_compensation_review_overview_secure(v_cycle_id, null);
  v_records := public.hr_list_compensation_review_records_secure(
    'item', 0, 49, null, null, v_cycle_id, null
  );
  insert into hr_compensation_review_test_result values (
    'ordinary_masked_read',
    coalesce((v_payload->>'amount_access')::boolean, true) = false
      and exists (
        select 1 from jsonb_array_elements(v_records->'records') record_row
        where record_row->>'current_base_amount' = '***'
          and record_row->>'proposed_base_amount' = '***'
      ),
    '普通用户可租户内只读，但金额由服务端脱敏'
  );

  begin
    perform public.hr_save_compensation_review_record_secure(
      'cycle', null, jsonb_build_object(
        'cycle_code', 'DENIED', 'cycle_name', '不应创建',
        'review_year', 2026, 'effective_date', current_date,
        'recommendation_due_date', current_date, 'calibration_due_date', current_date
      )
    );
  exception when insufficient_privilege then v_write_denied := true;
  end;
  insert into hr_compensation_review_test_result values
    ('ordinary_write_denied', v_write_denied, '普通用户不能创建调薪周期或执行受控写入');

  begin
    perform count(*) from public.hr_compensation_review_item;
  exception when insufficient_privilege then v_direct_denied := true;
  end;
  insert into hr_compensation_review_test_result values
    ('direct_table_denied', v_direct_denied, '业务表不向 authenticated 直接开放');
end;
$test$;

reset role;
select check_name, passed, detail
from hr_compensation_review_test_result
order by check_name;

do $test$
declare v_failed text;
begin
  select string_agg(check_name || ': ' || coalesce(detail, ''), '; ')
  into v_failed
  from hr_compensation_review_test_result
  where not passed;
  if v_failed is not null then
    raise exception 'HR compensation review test failed: %', v_failed;
  end if;
end;
$test$;

rollback;
