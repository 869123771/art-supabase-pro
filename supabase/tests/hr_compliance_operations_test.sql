begin;

create temporary table hr_compliance_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  contract_id uuid,
  renewed_contract_id uuid,
  qualification_id uuid
) on commit drop;

create temporary table hr_compliance_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_compliance_test_context(tenant_id, employee_id)
select employee.tenant_id, employee.id
from public.hr_employee employee
where employee.employment_status not in ('left', 'terminated')
order by employee.employee_no
limit 1;

grant select, update on hr_compliance_test_context to authenticated;
grant select, insert on hr_compliance_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_compliance_test_context%rowtype;
  v_contract_id uuid;
  v_new_contract_id uuid;
  v_qualification_id uuid;
  v_detail jsonb;
  v_direct_blocked boolean := false;
begin
  select * into v_context from hr_compliance_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No HR compliance test fixture'; end if;

  v_contract_id := public.hr_save_compliance_record_secure('contract', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'employee_id', v_context.employee_id,
    'contract_no', 'TEST-CON-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'contract_type', 'fixed_term',
    'contract_status', 'active',
    'sign_date', current_date,
    'start_date', current_date - 365,
    'end_date', current_date + 5,
    'renewal_reminder_days', 30,
    'renewal_owner_id', v_context.employee_id,
    'work_location', '自动化测试地点'
  ));
  update hr_compliance_test_context set contract_id = v_contract_id;

  insert into hr_compliance_test_result values(
    'contract_risk_is_computed',
    exists(
      select 1 from jsonb_array_elements(public.hr_list_compliance_records_secure(
        'risk', 0, 19, null, 'contract', 'critical', v_context.tenant_id
      ) -> 'records') row
      where (row ->> 'record_id')::uuid = v_contract_id
        and row ->> 'risk_status' = 'critical'
    ),
    '合同到期风险由结束日期与提醒天数实时计算'
  );

  perform public.hr_transition_compliance_record_secure(
    'contract', v_contract_id, 'start_renewal',
    jsonb_build_object('renewal_owner_id', v_context.employee_id, 'comment', '进入续签评估')
  );
  v_new_contract_id := public.hr_transition_compliance_record_secure(
    'contract', v_contract_id, 'renew', jsonb_build_object(
      'contract_no', 'TEST-RENEW-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      'contract_type', 'fixed_term',
      'contract_status', 'active',
      'sign_date', current_date,
      'start_date', current_date + 6,
      'end_date', current_date + 371,
      'renewal_reminder_days', 45,
      'renewal_owner_id', v_context.employee_id,
      'comment', '续签评审通过'
    )
  );
  update hr_compliance_test_context set renewed_contract_id = v_new_contract_id;
  v_detail := public.hr_get_compliance_detail_secure('contract', v_contract_id);

  insert into hr_compliance_test_result values(
    'renewal_creates_new_version',
    v_detail ->> 'contract_status' = 'renewed'
      and exists(
        select 1 from jsonb_array_elements(public.hr_list_compliance_records_secure(
          'contract', 0, 99, null, null, null, v_context.tenant_id
        ) -> 'records') row
        where (row ->> 'id')::uuid = v_new_contract_id
          and (row ->> 'previous_contract_id')::uuid = v_contract_id
      ),
    '续签创建新合同版本并保留原合同'
  );

  insert into hr_compliance_test_result values(
    'contract_lifecycle_is_audited',
    jsonb_array_length(v_detail -> 'events') >= 3,
    '创建、启动续签与完成续签均写入审计事件'
  );

  v_qualification_id := public.hr_save_compliance_record_secure(
    'qualification', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'employee_id', v_context.employee_id,
      'qualification_type', 'professional',
      'qualification_name', '自动化职业资格',
      'certificate_no', 'TEST-CERT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      'issuer', '自动化测试机构',
      'issue_date', current_date - 100,
      'expiry_date', current_date + 5,
      'reminder_days', 30,
      'responsible_employee_id', v_context.employee_id
    )
  );
  update hr_compliance_test_context set qualification_id = v_qualification_id;
  perform public.hr_transition_compliance_record_secure(
    'qualification', v_qualification_id, 'verify', jsonb_build_object('comment', '材料核验通过')
  );
  perform public.hr_transition_compliance_record_secure(
    'qualification', v_qualification_id, 'revoke', jsonb_build_object('comment', '测试撤销原因')
  );
  v_detail := public.hr_get_compliance_detail_secure('qualification', v_qualification_id);

  insert into hr_compliance_test_result values(
    'qualification_verify_and_revoke_audited',
    v_detail ->> 'status' = 'revoked'
      and v_detail ->> 'verification_status' = 'verified'
      and v_detail ->> 'revocation_reason' = '测试撤销原因'
      and jsonb_array_length(v_detail -> 'events') >= 3,
    '资质核验与撤销状态分离且完整留痕'
  );

  begin
    perform 1 from public.hr_compliance_event limit 1;
  exception when insufficient_privilege then v_direct_blocked := true;
  end;
  insert into hr_compliance_test_result values(
    'compliance_events_deny_direct_access', v_direct_blocked,
    '已登录用户不能绕过受控 RPC 读取审计事件'
  );
end
$test$;

reset role;
insert into hr_compliance_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege(
    'anon', 'public.hr_compliance_overview_secure(uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_save_compliance_record_secure(text,jsonb)', 'execute'
  ),
  '匿名角色不能调用用工合规 RPC'
);

select check_name, passed, detail from hr_compliance_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_compliance_test_result where not passed) then
    raise exception 'HR compliance operations verification failed';
  end if;
end
$test$;

rollback;
