begin;

create temporary table hr_recruitment_test_context (
  tenant_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  employee_id uuid not null,
  ordinary_auth_user_id uuid,
  requisition_id uuid,
  candidate_id uuid,
  offer_id uuid,
  handoff_id uuid
) on commit drop;

create temporary table hr_recruitment_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_recruitment_test_context(
  tenant_id, organization_id, position_id, employee_id, ordinary_auth_user_id
)
select position.tenant_id, position.organization_id, position.id, employee.id,
  (
    select app_user.auth_user_id from public.sys_user app_user
    where app_user.tenant_id = position.tenant_id
      and app_user.auth_user_id is not null and 'R_REGISTER' = any(app_user.user_roles)
    limit 1
  )
from public.hr_position position
join lateral (
  select employee.id from public.hr_employee employee
  where employee.tenant_id = position.tenant_id
    and employee.employment_status in ('probation', 'active', 'leave')
  order by employee.employee_no limit 1
) employee on true
where position.enabled and position.organization_id is not null
order by position.create_time
limit 1;

grant select, update on hr_recruitment_test_context to authenticated;
grant select, insert, update on hr_recruitment_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (
    select auth_user_id from public.sys_user
    where auth_user_id is not null and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end limit 1
  ),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_recruitment_test_context%rowtype;
  v_requisition_id uuid;
  v_candidate_id uuid;
  v_interview_id uuid;
  v_offer_id uuid;
  v_handoff_id uuid;
  v_payload jsonb;
  v_task jsonb;
  v_incomplete_blocked boolean := false;
  v_direct_blocked boolean := false;
  v_illegal_stage_blocked boolean := false;
begin
  select * into v_context from hr_recruitment_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No recruitment test fixture'; end if;

  v_requisition_id := public.hr_save_recruitment_record_secure(
    'requisition', null, jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'requisition_no', 'TEST-REC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      'organization_id', v_context.organization_id,
      'position_id', v_context.position_id,
      'opening_count', 1,
      'expected_onboard_date', current_date + 30,
      'employment_type', 'full_time',
      'reason', '企业招聘闭环自动化测试',
      'requirements', '验证面试、Offer 与入职交接状态机'
    )
  );
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);
  update public.hr_recruitment_requisition set status = 'effective' where id = v_requisition_id;

  v_candidate_id := public.hr_save_recruitment_record_secure(
    'candidate', null, jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'requisition_id', v_requisition_id,
      'candidate_name', '自动化候选人',
      'phone', '13800000000',
      'email', 'recruitment-test@example.com',
      'source', 'referral',
      'expected_salary', 12000,
      'consent_status', 'granted',
      'consent_at', now(),
      'retention_until', current_date + 180
    )
  );
  perform public.hr_transition_candidate_stage_secure(v_candidate_id, 'screening', '自动化筛选开始');
  begin
    perform public.hr_transition_candidate_stage_secure(v_candidate_id, 'hired', '非法跳阶段测试');
  exception when others then
    v_illegal_stage_blocked := position('必须由面试、Offer 或入职交接动作推进' in sqlerrm) > 0;
  end;
  insert into hr_recruitment_test_result values(
    'illegal_stage_jump_blocked', v_illegal_stage_blocked,
    '候选人不能通过普通阶段动作直接跳到已录用'
  );

  v_interview_id := public.hr_save_recruitment_record_secure(
    'interview', null, jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'candidate_id', v_candidate_id,
      'round_no', 1,
      'interview_type', 'structured',
      'scheduled_start_at', now() + interval '1 day',
      'scheduled_end_at', now() + interval '1 day 1 hour',
      'location', '自动化会议室',
      'interviewer_employee_id', v_context.employee_id
    )
  );
  perform public.hr_complete_recruitment_interview_secure(
    v_interview_id, 88, 'hire', '岗位能力、业务判断和协作案例满足录用标准。'
  );

  v_offer_id := public.hr_save_recruitment_record_secure(
    'offer', null, jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'candidate_id', v_candidate_id,
      'employment_type', 'full_time',
      'monthly_salary', 12000,
      'target_bonus', 12000,
      'currency', 'CNY',
      'probation_months', 3,
      'proposed_onboard_date', current_date + 30,
      'expires_on', current_date + 7
    )
  );
  perform public.hr_transition_recruitment_offer_secure(v_offer_id, 'submit', null);
  perform public.hr_transition_recruitment_offer_secure(v_offer_id, 'approve', '薪酬方案在岗位预算范围内');
  perform public.hr_transition_recruitment_offer_secure(v_offer_id, 'send', null);
  perform public.hr_transition_recruitment_offer_secure(v_offer_id, 'accept', '候选人书面确认接受');

  v_payload := public.hr_list_recruitment_records_secure(
    'handoff', 0, 20, '自动化候选人', null, v_context.tenant_id
  );
  select (record ->> 'id')::uuid into v_handoff_id
  from jsonb_array_elements(v_payload -> 'records') record limit 1;

  insert into hr_recruitment_test_result values(
    'accepted_offer_creates_handoff',
    v_handoff_id is not null,
    '接受 Offer 后自动建立入职交接并生成四项默认准备任务'
  );

  perform public.hr_save_recruitment_record_secure(
    'handoff', v_handoff_id, jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'offer_id', v_offer_id,
      'planned_onboard_date', current_date + 30,
      'owner_employee_id', v_context.employee_id,
      'onboard_employee_id', v_context.employee_id,
      'handoff_note', '自动化入职交接'
    )
  );
  begin
    perform public.hr_transition_recruitment_handoff_secure(v_handoff_id, 'complete', null);
  exception when others then
    v_incomplete_blocked := position('项入职任务未完成' in sqlerrm) > 0;
  end;
  insert into hr_recruitment_test_result values(
    'incomplete_handoff_blocked', v_incomplete_blocked,
    '存在未完成任务时不能完成入职交接并计入录用'
  );

  v_payload := public.hr_list_recruitment_records_secure(
    'task', 0, 20, '自动化候选人', null, v_context.tenant_id
  );
  update hr_recruitment_test_result
  set passed = passed and jsonb_array_length(v_payload -> 'records') = 4
  where check_name = 'accepted_offer_creates_handoff';
  for v_task in
    select record from jsonb_array_elements(v_payload -> 'records') record
  loop
    perform public.hr_complete_recruitment_task_secure((v_task ->> 'id')::uuid, false, '自动化验收通过');
  end loop;
  perform public.hr_transition_recruitment_handoff_secure(v_handoff_id, 'complete', '全部准备任务完成');

  begin
    perform 1 from public.hr_recruitment_offer limit 1;
  exception when insufficient_privilege then
    v_direct_blocked := true;
  end;
  insert into hr_recruitment_test_result values(
    'direct_sensitive_table_access_denied', v_direct_blocked,
    '签入用户不能绕过受控 RPC 直读 Offer 敏感数据'
  );

  update hr_recruitment_test_context
  set requisition_id = v_requisition_id, candidate_id = v_candidate_id,
      offer_id = v_offer_id, handoff_id = v_handoff_id;
end
$test$;

reset role;
insert into hr_recruitment_test_result values(
  'hire_updates_requisition',
  exists(
    select 1 from public.hr_candidate candidate
    join public.hr_recruitment_requisition requisition on requisition.id = candidate.requisition_id
    join hr_recruitment_test_context context on context.candidate_id = candidate.id
    where candidate.stage = 'hired'
      and candidate.onboard_employee_id = context.employee_id
      and requisition.hired_count = 1 and requisition.status = 'completed'
  ),
  '交接完成后候选人转为已录用并回写需求完成度'
);
insert into hr_recruitment_test_result values(
  'stage_history_traceable',
  (
    select array_agg(history.to_stage order by history.sequence_no)
    from public.hr_candidate_stage_history history
    join hr_recruitment_test_context context on context.candidate_id = history.candidate_id
  ) = array['new', 'screening', 'interview', 'offer', 'hired']::text[],
  '候选人从创建到录用的阶段轨迹完整可追溯'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_recruitment_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_recruitment_overview_secure(null);
  exception when insufficient_privilege then
    v_denied := true;
  end;
  insert into hr_recruitment_test_result values(
    'ordinary_user_denied', v_denied,
    '未授权普通用户不能读取招聘运营数据'
  );
end
$test$;

reset role;
select check_name, passed, detail from hr_recruitment_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_recruitment_test_result where not passed) then
    raise exception 'HR recruitment closure verification failed';
  end if;
end
$test$;
rollback;
