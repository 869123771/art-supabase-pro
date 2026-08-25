begin;

create temporary table hr_service_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  service_id uuid,
  request_id uuid,
  resolution_due_at timestamptz
) on commit drop;

create temporary table hr_service_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_service_test_context(tenant_id, employee_id)
select employee.tenant_id, employee.id
from public.hr_employee employee
where employee.employment_status not in ('left', 'terminated')
order by employee.employee_no
limit 1;

grant select, update on hr_service_test_context to authenticated;
grant select, insert on hr_service_test_result to authenticated;
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
  v_context hr_service_test_context%rowtype;
  v_service_id uuid;
  v_request_id uuid;
  v_detail jsonb;
  v_direct_blocked boolean := false;
begin
  select * into v_context from hr_service_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No employee service test fixture'; end if;

  v_service_id := public.hr_save_service_catalog_secure(null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'service_code', 'TEST_SERVICE_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'service_name', '自动化员工证明服务',
    'category', 'certificate',
    'description', '员工服务交付自动化测试',
    'service_mode', 'case',
    'routing_group', '员工档案',
    'first_response_hours', 4,
    'resolution_hours', 24,
    'enabled', true,
    'sort', 99
  ));
  update hr_service_test_context set service_id = v_service_id;

  v_request_id := public.hr_save_service_request_secure(null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'employee_id', v_context.employee_id,
    'service_id', v_service_id,
    'request_no', 'TEST-SVC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'title', '申请在职证明',
    'reason', '用于员工服务中心端到端自动化验证',
    'priority', 'high',
    'channel', 'agent',
    'attachment_urls', '[]'::jsonb
  ));
  update hr_service_test_context set request_id = v_request_id;

  perform public.hr_transition_service_request_secure(v_request_id, 'submit', null, '提交服务工单');
  v_detail := public.hr_get_service_request_detail_secure(v_request_id);
  update hr_service_test_context
  set resolution_due_at = (v_detail ->> 'resolution_due_at')::timestamptz;

  insert into hr_service_test_result values(
    'submission_sets_sla',
    v_detail ->> 'status' = 'submitted'
      and v_detail ->> 'first_response_due_at' is not null
      and v_detail ->> 'resolution_due_at' is not null,
    '提交后根据服务目录固化首次响应和解决时限'
  );

  perform public.hr_transition_service_request_secure(
    v_request_id, 'assign', v_context.employee_id, '分派给自动化测试处理人'
  );
  perform public.hr_transition_service_request_secure(v_request_id, 'start', null, '开始处理');
  perform public.hr_transition_service_request_secure(v_request_id, 'wait', null, '请补充用途说明');

  v_detail := public.hr_get_service_request_detail_secure(v_request_id);
  insert into hr_service_test_result values(
    'wait_state_requires_reason',
    v_detail ->> 'status' = 'waiting_employee'
      and v_detail ->> 'waiting_reason' = '请补充用途说明'
      and v_detail ->> 'waiting_started_at' is not null,
    '等待员工补充必须记录原因和暂停起点'
  );

  begin
    perform 1 from public.hr_self_service_request limit 1;
  exception when insufficient_privilege then v_direct_blocked := true;
  end;
  insert into hr_service_test_result values(
    'direct_table_access_denied', v_direct_blocked,
    '已登录用户不能绕过受控 RPC 直接读取员工服务工单'
  );
end
$test$;

reset role;
update public.hr_self_service_request
set waiting_started_at = now() - interval '2 hours'
where id = (select request_id from hr_service_test_context limit 1);

set local role authenticated;
do $test$
declare
  v_context hr_service_test_context%rowtype;
  v_detail jsonb;
begin
  select * into v_context from hr_service_test_context limit 1;
  perform public.hr_transition_service_request_secure(v_context.request_id, 'resume', null, '材料已补充');
  v_detail := public.hr_get_service_request_detail_secure(v_context.request_id);

  insert into hr_service_test_result values(
    'waiting_time_pauses_sla',
    (v_detail ->> 'resolution_due_at')::timestamptz
      >= v_context.resolution_due_at + interval '1 hour 59 minutes',
    '员工补充等待时长从解决 SLA 中扣除'
  );

  perform public.hr_transition_service_request_secure(
    v_context.request_id, 'resolve', null, '在职证明已生成并交付'
  );
  perform public.hr_transition_service_request_secure(v_context.request_id, 'close', null, '员工确认完成');
  perform public.hr_transition_service_request_secure(
    v_context.request_id, 'reopen', null, '证明用途需要调整'
  );
  perform public.hr_transition_service_request_secure(
    v_context.request_id, 'resolve', null, '已按新用途重新生成证明'
  );
  perform public.hr_transition_service_request_secure(v_context.request_id, 'close', null, '再次确认完成');
  v_detail := public.hr_get_service_request_detail_secure(v_context.request_id);

  insert into hr_service_test_result values(
    'resolution_close_and_reopen_audited',
    v_detail ->> 'status' = 'closed'
      and (v_detail ->> 'reopen_count')::integer = 1
      and jsonb_array_length(v_detail -> 'events') >= 10,
    '解决、关闭和重开均进入不可变事件历史'
  );

  insert into hr_service_test_result values(
    'service_list_exposes_operational_context',
    exists(
      select 1
      from jsonb_array_elements(public.hr_list_service_delivery_records_secure(
        'request', 0, 19, null, 'closed', null, 'team', v_context.tenant_id
      ) -> 'records') row
      where (row ->> 'id')::uuid = v_context.request_id
        and row -> 'service' ->> 'name' = '自动化员工证明服务'
        and row -> 'requester' ->> 'id' = v_context.employee_id::text
        and row ->> 'sla_status' = 'clear'
    ),
    '团队视图返回服务、申请人和 SLA 决策上下文'
  );
end
$test$;

reset role;
insert into hr_service_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege('anon', 'public.hr_service_delivery_overview_secure(uuid)', 'execute')
    and not has_function_privilege(
      'anon', 'public.hr_save_service_request_secure(uuid,jsonb)', 'execute'
    ),
  '匿名角色不能调用员工服务交付 RPC'
);

select check_name, passed, detail from hr_service_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_service_test_result where not passed) then
    raise exception 'HR service delivery verification failed';
  end if;
end
$test$;

rollback;
