begin;

set local timezone = 'Asia/Shanghai';

create temporary table hr_contingent_workforce_test_context (
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  sponsor_employee_id uuid not null,
  organization_id uuid not null,
  vendor_id uuid,
  worker_id uuid,
  engagement_id uuid
) on commit drop;

create temporary table hr_contingent_workforce_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_contingent_workforce_test_context(
  tenant_id, ordinary_auth_user_id, sponsor_employee_id, organization_id
)
select user_row.tenant_id, user_row.auth_user_id, employee.id, employee.organization_id
from public.sys_user user_row
join lateral (
  select employee_row.id, employee_row.organization_id
  from public.hr_employee employee_row
  where employee_row.tenant_id = user_row.tenant_id
    and employee_row.employment_status = 'active'
    and employee_row.organization_id is not null
  order by employee_row.employee_no
  limit 1
) employee on true
where user_row.auth_user_id is not null
  and user_row.status = '1'
  and 'R_REGISTER' = any(user_row.user_roles)
order by user_row.create_time
limit 1;

grant select, update on hr_contingent_workforce_test_context to authenticated;
grant select, insert, update on hr_contingent_workforce_test_result to anon, authenticated;

set local role anon;
do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_contingent_workforce_overview_secure(null);
  exception when insufficient_privilege then v_denied := true;
  end;
  insert into hr_contingent_workforce_test_result values
    ('anon_denied', v_denied, '匿名账号不能读取外部用工');
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
  v_sponsor_id uuid;
  v_organization_id uuid;
  v_vendor_id uuid;
  v_worker_id uuid;
  v_engagement_id uuid;
  v_controls jsonb;
  v_engagements jsonb;
  v_workers jsonb;
  v_control jsonb;
  v_overview jsonb;
  v_pending_blocked boolean := false;
  v_exit_blocked boolean := false;
begin
  select tenant_id, sponsor_employee_id, organization_id
  into v_tenant_id, v_sponsor_id, v_organization_id
  from hr_contingent_workforce_test_context limit 1;
  if v_tenant_id is null then raise exception 'No ordinary HR tenant test fixture'; end if;

  v_vendor_id := public.hr_save_contingent_workforce_record_secure(
    'vendor', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'vendor_code', 'CW_TEST_VENDOR',
      'vendor_name', '外部用工自动化测试供应商',
      'contact_name', '测试联系人',
      'contact_phone', '13800138000',
      'contact_email', 'vendor-test@example.com',
      'contract_no', 'CW-CONTRACT-001',
      'contract_start_date', current_date - 30,
      'contract_end_date', current_date + 365,
      'risk_level', 'low'
    )
  );
  perform public.hr_transition_contingent_workforce_record_secure(
    'vendor', v_vendor_id, 'verify', '合规资料已核验', null
  );
  perform public.hr_transition_contingent_workforce_record_secure(
    'vendor', v_vendor_id, 'activate', '合同已生效', null
  );

  v_worker_id := public.hr_save_contingent_workforce_record_secure(
    'worker', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_no', 'CW_TEST_001',
      'worker_name', '外部人员测试一号',
      'worker_type', 'outsourced',
      'vendor_id', v_vendor_id,
      'vendor_worker_no', 'V-1001',
      'phone', '13900139000',
      'email', 'worker-test@example.com'
    )
  );
  perform public.hr_transition_contingent_workforce_record_secure(
    'worker', v_worker_id, 'verify_identity', '实名核验通过', null
  );

  v_engagement_id := public.hr_save_contingent_workforce_record_secure(
    'engagement', null, jsonb_build_object(
      'tenant_id', v_tenant_id,
      'engagement_no', 'CW_ENG_TEST_001',
      'worker_id', v_worker_id,
      'vendor_id', v_vendor_id,
      'organization_id', v_organization_id,
      'sponsor_employee_id', v_sponsor_id,
      'service_title', '测试外部专业服务',
      'work_location', '测试办公区',
      'start_date', current_date,
      'end_date', current_date + 30,
      'access_expiry_date', current_date + 30,
      'fte', 1,
      'billing_rate', 1200,
      'billing_unit', 'day',
      'currency_code', 'CNY'
    )
  );
  update hr_contingent_workforce_test_context set
    vendor_id = v_vendor_id, worker_id = v_worker_id, engagement_id = v_engagement_id;

  v_controls := public.hr_list_contingent_workforce_records_secure(
    'control', 0, 49, null, null, v_engagement_id, v_tenant_id
  );
  insert into hr_contingent_workforce_test_result values (
    'default_controls_seeded',
    (v_controls ->> 'total')::integer = 6,
    '建立用工任务时自动生成身份、合同、保密、安全、门禁和账号控制项'
  );

  perform public.hr_transition_contingent_workforce_record_secure(
    'engagement', v_engagement_id, 'submit', '提交准入审核', null
  );
  begin
    perform public.hr_transition_contingent_workforce_record_secure(
      'engagement', v_engagement_id, 'activate', '不应激活', null
    );
  exception when others then v_pending_blocked := true;
  end;
  insert into hr_contingent_workforce_test_result values
    ('pending_control_gate', v_pending_blocked, '必需控制项未完成时阻断激活');

  for v_control in select value from jsonb_array_elements(v_controls -> 'records') loop
    perform public.hr_save_contingent_workforce_record_secure(
      'control', (v_control ->> 'id')::uuid, jsonb_build_object(
        'tenant_id', v_tenant_id,
        'engagement_id', v_engagement_id,
        'control_type', v_control ->> 'control_type',
        'control_name', v_control ->> 'control_name',
        'required', (v_control ->> 'required')::boolean,
        'status', 'completed',
        'due_date', v_control ->> 'due_date',
        'evidence_reference', 'TEST-EVIDENCE'
      )
    );
  end loop;
  perform public.hr_transition_contingent_workforce_record_secure(
    'engagement', v_engagement_id, 'activate', '准入控制全部完成', null
  );

  v_overview := public.hr_contingent_workforce_overview_secure(v_tenant_id);
  v_engagements := public.hr_list_contingent_workforce_records_secure(
    'engagement', 0, 9, 'CW_ENG_TEST_001', null, null, v_tenant_id
  );
  insert into hr_contingent_workforce_test_result values (
    'activation_closure',
    (v_overview ->> 'active_vendor_count')::integer >= 1
      and (v_overview ->> 'active_worker_count')::integer >= 1
      and (v_overview ->> 'active_engagement_count')::integer >= 1
      and v_engagements -> 'records' -> 0 ->> 'status' = 'active'
      and v_engagements -> 'records' -> 0 ->> 'compliance_status' = 'cleared',
    '供应商、人员和准入均有效后任务进入在场状态'
  );

  perform public.hr_transition_contingent_workforce_record_secure(
    'engagement', v_engagement_id, 'begin_exit', '项目按计划结束', current_date + 1
  );
  begin
    perform public.hr_transition_contingent_workforce_record_secure(
      'engagement', v_engagement_id, 'end', '不应完成退场', current_date + 1
    );
  exception when others then v_exit_blocked := true;
  end;
  insert into hr_contingent_workforce_test_result values
    ('offboarding_gate', v_exit_blocked, '门禁、账号和设备未回收时阻断退场');

  v_controls := public.hr_list_contingent_workforce_records_secure(
    'control', 0, 49, '回收', null, v_engagement_id, v_tenant_id
  );
  for v_control in select value from jsonb_array_elements(v_controls -> 'records') loop
    perform public.hr_save_contingent_workforce_record_secure(
      'control', (v_control ->> 'id')::uuid, jsonb_build_object(
        'tenant_id', v_tenant_id,
        'engagement_id', v_engagement_id,
        'control_type', v_control ->> 'control_type',
        'control_name', v_control ->> 'control_name',
        'required', (v_control ->> 'required')::boolean,
        'status', 'completed',
        'due_date', v_control ->> 'due_date',
        'evidence_reference', 'EXIT-EVIDENCE'
      )
    );
  end loop;
  v_controls := public.hr_list_contingent_workforce_records_secure(
    'control', 0, 49, '停用', null, v_engagement_id, v_tenant_id
  );
  for v_control in select value from jsonb_array_elements(v_controls -> 'records') loop
    perform public.hr_save_contingent_workforce_record_secure(
      'control', (v_control ->> 'id')::uuid, jsonb_build_object(
        'tenant_id', v_tenant_id,
        'engagement_id', v_engagement_id,
        'control_type', v_control ->> 'control_type',
        'control_name', v_control ->> 'control_name',
        'required', (v_control ->> 'required')::boolean,
        'status', 'completed',
        'due_date', v_control ->> 'due_date',
        'evidence_reference', 'EXIT-EVIDENCE'
      )
    );
  end loop;
  v_controls := public.hr_list_contingent_workforce_records_secure(
    'control', 0, 49, '归还', null, v_engagement_id, v_tenant_id
  );
  for v_control in select value from jsonb_array_elements(v_controls -> 'records') loop
    perform public.hr_save_contingent_workforce_record_secure(
      'control', (v_control ->> 'id')::uuid, jsonb_build_object(
        'tenant_id', v_tenant_id,
        'engagement_id', v_engagement_id,
        'control_type', v_control ->> 'control_type',
        'control_name', v_control ->> 'control_name',
        'required', (v_control ->> 'required')::boolean,
        'status', 'completed',
        'due_date', v_control ->> 'due_date',
        'evidence_reference', 'EXIT-EVIDENCE'
      )
    );
  end loop;
  perform public.hr_transition_contingent_workforce_record_secure(
    'engagement', v_engagement_id, 'end', '资产与权限已全部回收', current_date + 1
  );
  v_engagements := public.hr_list_contingent_workforce_records_secure(
    'engagement', 0, 9, 'CW_ENG_TEST_001', null, null, v_tenant_id
  );
  v_workers := public.hr_list_contingent_workforce_records_secure(
    'worker', 0, 9, 'CW_TEST_001', null, null, v_tenant_id
  );
  insert into hr_contingent_workforce_test_result values (
    'effective_exit',
    v_engagements -> 'records' -> 0 ->> 'status' = 'ended'
      and (v_engagements -> 'records' -> 0 ->> 'actual_exit_date')::date = current_date + 1
      and v_workers -> 'records' -> 0 ->> 'status' = 'inactive',
    '退场完成后记录实际日期并在无其他任务时停用外部人员'
  );
end;
$test$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select ordinary_auth_user_id from hr_contingent_workforce_test_context limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid := (select tenant_id from hr_contingent_workforce_test_context limit 1);
  v_vendor_id uuid := (select vendor_id from hr_contingent_workforce_test_context limit 1);
  v_engagement_id uuid := (select engagement_id from hr_contingent_workforce_test_context limit 1);
  v_vendors jsonb;
  v_engagements jsonb;
  v_write_denied boolean := false;
  v_direct_denied boolean := false;
begin
  v_vendors := public.hr_list_contingent_workforce_records_secure(
    'vendor', 0, 49, 'CW_TEST_VENDOR', null, null, null
  );
  v_engagements := public.hr_list_contingent_workforce_records_secure(
    'engagement', 0, 49, 'CW_ENG_TEST_001', null, null, null
  );
  insert into hr_contingent_workforce_test_result values (
    'ordinary_masked_read',
    coalesce((v_vendors ->> 'pii_access')::boolean, true) = false
      and coalesce((v_engagements ->> 'cost_access')::boolean, true) = false
      and exists (
        select 1 from jsonb_array_elements(v_vendors -> 'records') record_row
        where record_row ->> 'contact_phone' = '138****8000'
      )
      and exists (
        select 1 from jsonb_array_elements(v_engagements -> 'records') record_row
        where record_row ->> 'billing_rate' = '***'
      ),
    '普通用户可租户内只读，但联系方式和成本由服务端脱敏'
  );

  begin
    perform public.hr_save_contingent_workforce_record_secure(
      'vendor', v_vendor_id, jsonb_build_object(
        'vendor_code', 'DENIED', 'vendor_name', '不应更新'
      )
    );
  exception when insufficient_privilege then v_write_denied := true;
  end;
  insert into hr_contingent_workforce_test_result values
    ('ordinary_write_denied', v_write_denied, '普通用户不能执行受控写入');

  begin
    perform count(*) from public.hr_external_engagement where id = v_engagement_id;
  exception when insufficient_privilege then v_direct_denied := true;
  end;
  insert into hr_contingent_workforce_test_result values
    ('direct_table_denied', v_direct_denied, '业务表不向 authenticated 直接开放');
end;
$test$;

reset role;
select check_name, passed, detail
from hr_contingent_workforce_test_result
order by check_name;

do $test$
declare v_failed text;
begin
  select string_agg(check_name || ': ' || coalesce(detail, ''), '; ')
  into v_failed
  from hr_contingent_workforce_test_result
  where not passed;
  if v_failed is not null then
    raise exception 'HR contingent workforce test failed: %', v_failed;
  end if;
end;
$test$;

rollback;
