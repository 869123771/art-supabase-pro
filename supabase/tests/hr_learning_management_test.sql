begin;

create temporary table hr_learning_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  competency_id uuid not null,
  ordinary_auth_user_id uuid,
  plan_id uuid,
  course_id uuid,
  session_id uuid,
  enrollment_id uuid
) on commit drop;

create temporary table hr_learning_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_learning_test_context(tenant_id, employee_id, competency_id, ordinary_auth_user_id)
select employee.tenant_id, employee.id,
  coalesce((
    select competency.id from public.hr_competency competency
    where competency.tenant_id = employee.tenant_id and competency.enabled
    order by competency.competency_code
    limit 1
  ), gen_random_uuid()),
  coalesce((
    select app_user.auth_user_id from public.sys_user app_user
    where app_user.auth_user_id is not null
      and not ('R_SUPER' = any(coalesce(app_user.user_roles, array[]::text[])))
      and cardinality(coalesce(app_user.user_roles, array[]::text[])) = 0
    order by app_user.create_time
    limit 1
  ), gen_random_uuid())
from public.hr_employee employee
where employee.employment_status in ('probation', 'active', 'leave')
order by employee.employee_no
limit 1;

insert into public.hr_competency(
  id, tenant_id, competency_code, competency_name, category, description, enabled
)
select context.competency_id, context.tenant_id,
  'TEST-COMP-' || upper(substr(replace(context.competency_id::text, '-', ''), 1, 8)),
  '企业学习闭环测试能力', 'professional', '仅用于事务内自动化验证', true
from hr_learning_test_context context
where not exists (
  select 1 from public.hr_competency competency where competency.id = context.competency_id
);

grant select, update on hr_learning_test_context to authenticated;
grant select, insert, update on hr_learning_test_result to authenticated;
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
  v_context hr_learning_test_context%rowtype;
  v_plan_id uuid;
  v_course_id uuid;
  v_mapping_id uuid;
  v_session_id uuid;
  v_enrollment_id uuid;
  v_below_standard_blocked boolean := false;
  v_early_session_completion_blocked boolean := false;
  v_direct_blocked boolean := false;
begin
  select * into v_context from hr_learning_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No learning management test fixture'; end if;

  v_plan_id := public.hr_save_learning_record_secure('plan', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'plan_code', 'TEST-LP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'plan_name', '企业学习闭环自动化计划',
    'training_type', 'professional',
    'start_date', current_date,
    'end_date', current_date + 30,
    'budget', 10000,
    'owner_employee_id', v_context.employee_id,
    'target_audience', '关键岗位员工',
    'mandatory', false,
    'objective', '验证课程、班次、结果、证书与能力回写闭环'
  ));

  v_course_id := public.hr_save_learning_record_secure('course', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'course_code', 'TEST-LC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'course_name', '企业级岗位能力课程',
    'category', 'professional',
    'delivery_mode', 'classroom',
    'duration_hours', 8,
    'credit_hours', 8,
    'passing_score', 70,
    'minimum_attendance_percent', 80,
    'certificate_enabled', true,
    'certificate_valid_months', 24,
    'learning_objectives', '完成后达到目标岗位能力等级',
    'target_audience', '岗位任职人员'
  ));

  v_mapping_id := public.hr_save_learning_record_secure('course_competency', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'course_id', v_course_id,
    'competency_id', v_context.competency_id,
    'target_level', 'advanced'
  ));
  perform public.hr_transition_learning_record_secure('plan', v_plan_id, 'publish', '{}'::jsonb);
  perform public.hr_transition_learning_record_secure('course', v_course_id, 'publish', '{}'::jsonb);

  v_session_id := public.hr_save_learning_record_secure('session', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'session_code', 'TEST-LS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'plan_id', v_plan_id,
    'course_id', v_course_id,
    'start_at', now() + interval '1 day',
    'end_at', now() + interval '1 day 8 hours',
    'enrollment_deadline', now() + interval '12 hours',
    'capacity', 10,
    'instructor_name', '自动化讲师',
    'location', '企业学习中心',
    'estimated_cost', 5000
  ));
  perform public.hr_transition_learning_record_secure('session', v_session_id, 'open', '{}'::jsonb);

  v_enrollment_id := public.hr_save_learning_record_secure('enrollment', null, jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'session_id', v_session_id,
    'employee_id', v_context.employee_id,
    'nominated_by_employee_id', v_context.employee_id,
    'remark', '自动化安排学习'
  ));
  perform public.hr_transition_learning_record_secure('session', v_session_id, 'start', '{}'::jsonb);

  begin
    perform public.hr_transition_learning_record_secure(
      'session', v_session_id, 'complete', jsonb_build_object('actual_cost', 4800, 'comment', '提前结班')
    );
  exception when others then
    v_early_session_completion_blocked := position('仍有学员未登记最终学习结果' in sqlerrm) > 0;
  end;
  insert into hr_learning_test_result values(
    'incomplete_session_blocked', v_early_session_completion_blocked,
    '存在未登记最终结果的学员时不能完成培训班次'
  );

  perform public.hr_transition_learning_record_secure('enrollment', v_enrollment_id, 'attend', '{}'::jsonb);
  begin
    perform public.hr_transition_learning_record_secure(
      'enrollment', v_enrollment_id, 'pass',
      jsonb_build_object('attendance_percent', 60, 'score', 90, 'comment', '低出勤率非法通过')
    );
  exception when others then
    v_below_standard_blocked := position('出勤率未达到课程通过标准' in sqlerrm) > 0;
  end;
  insert into hr_learning_test_result values(
    'passing_standard_enforced', v_below_standard_blocked,
    '出勤率或成绩未达到课程标准时不能登记通过'
  );

  perform public.hr_transition_learning_record_secure(
    'enrollment', v_enrollment_id, 'pass',
    jsonb_build_object('attendance_percent', 95, 'score', 88, 'comment', '完成课程并通过考核')
  );
  perform public.hr_transition_learning_record_secure(
    'session', v_session_id, 'complete', jsonb_build_object('actual_cost', 4800, 'comment', '培训班次完成')
  );
  perform public.hr_transition_learning_record_secure('plan', v_plan_id, 'start', '{}'::jsonb);
  perform public.hr_transition_learning_record_secure('plan', v_plan_id, 'complete', '{}'::jsonb);

  begin
    perform 1 from public.hr_learning_certificate limit 1;
  exception when insufficient_privilege then
    v_direct_blocked := true;
  end;
  insert into hr_learning_test_result values(
    'direct_learning_table_access_denied', v_direct_blocked,
    '签入用户不能绕过受控 RPC 直读学习证书数据'
  );

  update hr_learning_test_context set
    plan_id = v_plan_id, course_id = v_course_id, session_id = v_session_id, enrollment_id = v_enrollment_id;
end
$test$;

reset role;

insert into hr_learning_test_result values(
  'completion_creates_certificate',
  exists(
    select 1 from public.hr_learning_certificate certificate
    join hr_learning_test_context context on context.enrollment_id = certificate.enrollment_id
    where certificate.status = 'valid'
      and certificate.expires_on = (current_date + interval '2 years')::date
  ),
  '通过启用证书的课程后自动签发带有效期的证书'
);

insert into hr_learning_test_result values(
  'completion_updates_employee_learning',
  exists(
    select 1 from public.hr_employee_training training
    join hr_learning_test_context context on context.employee_id = training.employee_id
    where training.remark like '由学习发展闭环自动回写%'
      and training.training_result = 'passed'
  ),
  '课程通过结果自动回写员工培训履历'
);

insert into hr_learning_test_result values(
  'completion_updates_competency',
  exists(
    select 1 from public.hr_employee_competency employee_competency
    join hr_learning_test_context context
      on context.employee_id = employee_competency.employee_id
      and context.competency_id = employee_competency.competency_id
    where employee_competency.current_level = 'advanced'
      and employee_competency.evidence like '完成课程%'
  ),
  '课程能力映射在通过后回写员工能力档案并保留证据'
);

insert into hr_learning_test_result values(
  'plan_cost_closed_loop',
  exists(
    select 1 from public.hr_training_plan plan
    join hr_learning_test_context context on context.plan_id = plan.id
    where plan.status = 'completed' and plan.actual_cost = 4800
  ),
  '培训班次实际成本汇总回培训计划形成预算执行闭环'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_learning_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_learning_overview_secure(null);
  exception when insufficient_privilege then
    v_denied := true;
  end;
  insert into hr_learning_test_result values(
    'ordinary_user_denied', v_denied,
    '未授权普通用户不能读取企业学习运营数据'
  );
end
$test$;

reset role;
select check_name, passed, detail from hr_learning_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_learning_test_result where not passed) then
    raise exception 'HR learning management verification failed';
  end if;
end
$test$;

rollback;
