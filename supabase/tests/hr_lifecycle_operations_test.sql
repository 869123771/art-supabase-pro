begin;

create temporary table hr_lifecycle_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  ordinary_auth_user_id uuid,
  case_id uuid
) on commit drop;

create temporary table hr_lifecycle_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_lifecycle_test_context(tenant_id, employee_id, ordinary_auth_user_id)
select e.tenant_id, e.id,
  coalesce((
    select u.auth_user_id from public.sys_user u
    where u.auth_user_id is not null
      and not ('R_SUPER' = any(coalesce(u.user_roles, array[]::text[])))
      and cardinality(coalesce(u.user_roles, array[]::text[])) = 0
    order by u.create_time limit 1
  ), gen_random_uuid())
from public.hr_employee e
where e.employment_status not in ('left', 'terminated')
order by e.employee_no
limit 1;

grant select, update on hr_lifecycle_test_context to authenticated;
grant select, insert on hr_lifecycle_test_result to authenticated;
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
  v_context hr_lifecycle_test_context%rowtype;
  v_case_id uuid;
  v_direct_blocked boolean := false;
  v_start_blocked boolean := false;
begin
  select * into v_context from hr_lifecycle_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No lifecycle test fixture'; end if;

  insert into hr_lifecycle_test_result values(
    'default_template_pack_seeded',
    (select count(*) from jsonb_array_elements(public.hr_list_lifecycle_options_secure(
      'template', v_context.tenant_id)) template
      where template ->> 'status' = 'active') >= 4,
    '每个租户至少具备入职、转正、调动和离职四套默认标准任务包'
  );

  v_case_id := public.hr_save_lifecycle_record_secure('case', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'case_no', 'TEST-LC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'employee_id', v_context.employee_id,
    'case_type', 'transfer',
    'planned_effective_date', current_date + 7,
    'priority', 'high',
    'remark', '员工生命周期运营自动化测试'
  ));
  update hr_lifecycle_test_context set case_id = v_case_id;

  insert into hr_lifecycle_test_result values(
    'template_materializes_tasks',
    exists(select 1 from jsonb_array_elements(public.hr_list_lifecycle_records_secure(
      'case', 0, 19, null, null, v_case_id, null, v_context.tenant_id) -> 'records') row
      where (row ->> 'id')::uuid = v_case_id and (row ->> 'task_count')::integer >= 4),
    '建单时把标准任务包固化为实际执行任务'
  );

  begin
    perform 1 from public.hr_lifecycle_case limit 1;
  exception when insufficient_privilege then v_direct_blocked := true;
  end;
  insert into hr_lifecycle_test_result values(
    'direct_table_access_denied', v_direct_blocked,
    '已登录用户不能绕过受控 RPC 直接读取生命周期表'
  );

  begin
    perform public.hr_transition_lifecycle_case_secure(v_case_id, 'start', null, null);
  exception when others then v_start_blocked := position('审批通过' in sqlerrm) > 0;
  end;
  insert into hr_lifecycle_test_result values(
    'unapproved_case_cannot_start', v_start_blocked,
    '审批状态与执行状态分轴，未批准事项不能启动'
  );
end
$test$;

reset role;
select set_config('app.workflow_engine', 'on', true);
update public.hr_lifecycle_case
set status = 'approved', approved_at = now(), approved_by = 'lifecycle_test'
where id = (select case_id from hr_lifecycle_test_context limit 1);
select set_config('app.workflow_engine', 'off', true);

set local role authenticated;
do $test$
declare
  v_context hr_lifecycle_test_context%rowtype;
  v_task jsonb;
  v_ready_blocked boolean := false;
begin
  select * into v_context from hr_lifecycle_test_context limit 1;
  perform public.hr_transition_lifecycle_case_secure(v_context.case_id, 'start', null, null);

  begin
    perform public.hr_transition_lifecycle_case_secure(v_context.case_id, 'ready', null, null);
  exception when others then v_ready_blocked := position('阻断任务' in sqlerrm) > 0;
  end;
  insert into hr_lifecycle_test_result values(
    'blocking_tasks_gate_readiness', v_ready_blocked,
    '阻断任务未关闭时事项不能进入就绪阶段'
  );

  for v_task in
    select value from jsonb_array_elements(public.hr_list_lifecycle_records_secure(
      'task', 0, 99, null, null, v_context.case_id, null, v_context.tenant_id) -> 'records')
  loop
    perform public.hr_transition_lifecycle_task_secure(
      (v_task ->> 'id')::uuid, 'complete', '自动化测试完成证据', null
    );
  end loop;

  perform public.hr_transition_lifecycle_case_secure(v_context.case_id, 'ready', null, null);
  perform public.hr_transition_lifecycle_case_secure(
    v_context.case_id, 'complete', '实际生效并完成归档', current_date + 7
  );

  insert into hr_lifecycle_test_result values(
    'case_lifecycle_completed',
    exists(select 1 from jsonb_array_elements(public.hr_list_lifecycle_records_secure(
      'case', 0, 19, null, 'completed', null, null, v_context.tenant_id) -> 'records') row
      where (row ->> 'id')::uuid = v_context.case_id
        and row ->> 'status' = 'effective'
        and row ->> 'actual_effective_date' = (current_date + 7)::text
        and (row ->> 'closed_task_count')::integer = (row ->> 'task_count')::integer),
    '所有必办任务关闭后，事项才能就绪并按实际日期生效归档'
  );
end
$test$;

reset role;
insert into hr_lifecycle_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege('anon', 'public.hr_lifecycle_overview_secure(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.hr_save_lifecycle_record_secure(text,uuid,jsonb)', 'execute'),
  '匿名角色不能调用生命周期读取或写入 RPC'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_lifecycle_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_lifecycle_overview_secure(null);
  exception when insufficient_privilege then v_denied := true;
  end;
  insert into hr_lifecycle_test_result values(
    'ordinary_user_denied', v_denied,
    '未授权普通用户不能读取租户生命周期运营数据'
  );
end
$test$;

reset role;
select check_name, passed, detail from hr_lifecycle_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_lifecycle_test_result where not passed) then
    raise exception 'HR lifecycle operations verification failed';
  end if;
end
$test$;

rollback;
