begin;

create temporary table hr_performance_test_context (
  tenant_id uuid not null,
  organization_id uuid,
  employee_id uuid not null,
  reviewer_employee_id uuid not null,
  ordinary_auth_user_id uuid,
  cycle_id uuid,
  review_id uuid,
  session_id uuid
) on commit drop;

create temporary table hr_performance_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_performance_test_context(
  tenant_id, organization_id, employee_id, reviewer_employee_id, ordinary_auth_user_id
)
select e.tenant_id, e.organization_id, e.id,
  coalesce((select r.id from public.hr_employee r where r.tenant_id=e.tenant_id and r.id<>e.id order by r.employee_no limit 1), e.id),
  coalesce((
    select u.auth_user_id from public.sys_user u
    where u.auth_user_id is not null
      and not ('R_SUPER'=any(coalesce(u.user_roles,array[]::text[])))
      and cardinality(coalesce(u.user_roles,array[]::text[]))=0
    order by u.create_time limit 1
  ), gen_random_uuid())
from public.hr_employee e
where e.employment_status not in ('left','terminated')
order by e.employee_no
limit 1;

grant select, update on hr_performance_test_context to authenticated;
grant select, insert, update on hr_performance_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER'=any(user_roles) or user_type='0')
    order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated'
)::text,true);
set local role authenticated;

do $test$
declare
  v_context hr_performance_test_context%rowtype;
  v_cycle_id uuid;
  v_review_id uuid;
  v_goal_one uuid;
  v_goal_two uuid;
  v_invalid_cycle uuid;
  v_invalid_review uuid;
  v_session_id uuid;
  v_item_id uuid;
  v_direct_blocked boolean:=false;
  v_weight_blocked boolean:=false;
begin
  select * into v_context from hr_performance_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No performance management test fixture'; end if;

  v_invalid_cycle:=public.hr_save_performance_record_secure('cycle',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'cycle_code','TEST-PERF-BAD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),
    'cycle_name','权重校验测试','start_date',current_date,'end_date',current_date+90,
    'self_review_due_date',current_date+45,'manager_review_due_date',current_date+60,
    'calibration_due_date',current_date+75
  ));
  v_invalid_review:=public.hr_save_performance_record_secure('review',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'cycle_id',v_invalid_cycle,'employee_id',v_context.employee_id,
    'reviewer_employee_id',v_context.reviewer_employee_id
  ));
  perform public.hr_save_performance_record_secure('goal',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_invalid_review,'goal_name','不完整目标',
    'target_description','用于验证权重必须达到 100%','goal_type','business','weight',80,'due_date',current_date+80
  ));
  begin
    perform public.hr_transition_performance_cycle_secure(v_invalid_cycle,'activate',null);
  exception when others then v_weight_blocked:=position('权重合计必须为 100' in sqlerrm)>0;
  end;
  insert into hr_performance_test_result values(
    'invalid_goal_weight_blocked',v_weight_blocked,'启动周期前逐人校验目标权重必须合计 100%'
  );
  perform public.hr_delete_performance_record_secure('cycle',v_invalid_cycle);

  v_cycle_id:=public.hr_save_performance_record_secure('cycle',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'cycle_code','TEST-PERF-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    'cycle_name','企业绩效闭环自动化测试','start_date',current_date,'end_date',current_date+90,
    'owner_employee_id',v_context.reviewer_employee_id,'check_in_frequency_days',30,
    'self_review_due_date',current_date+45,'manager_review_due_date',current_date+60,
    'calibration_due_date',current_date+75,'description','验证目标、自评、主管评价与校准闭环'
  ));
  v_review_id:=public.hr_save_performance_record_secure('review',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'cycle_id',v_cycle_id,'employee_id',v_context.employee_id,
    'reviewer_employee_id',v_context.reviewer_employee_id
  ));
  v_goal_one:=public.hr_save_performance_record_secure('goal',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'goal_name','业务结果',
    'target_description','完成核心经营目标','goal_type','business','weight',60,'due_date',current_date+80
  ));
  v_goal_two:=public.hr_save_performance_record_secure('goal',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'goal_name','能力发展',
    'target_description','完成关键能力提升','goal_type','development','weight',40,'due_date',current_date+80
  ));

  begin
    perform 1 from public.hr_performance_cycle limit 1;
  exception when insufficient_privilege then v_direct_blocked:=true;
  end;
  insert into hr_performance_test_result values(
    'direct_table_access_denied',v_direct_blocked,'已登录用户不能绕过受控 RPC 直接读取绩效表'
  );

  perform public.hr_transition_performance_cycle_secure(v_cycle_id,'activate',null);
  insert into hr_performance_test_result values(
    'cycle_activation_opens_self_review',
    exists(select 1 from jsonb_array_elements(public.hr_list_performance_records_secure(
      'review',0,19,null,'self_review',v_cycle_id,null,v_context.tenant_id)->'records') row
      where (row->>'id')::uuid=v_review_id and (row->>'goal_weight')::numeric=100),
    '周期启动后自动开放员工自评并保留 100% 目标权重'
  );

  perform public.hr_save_performance_record_secure('goal',v_goal_one,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'progress_percent',90,'status','in_progress',
    'actual_result','完成主要经营结果','evidence_source','经营看板','employee_score',88
  ));
  perform public.hr_save_performance_record_secure('goal',v_goal_two,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'progress_percent',100,'status','completed',
    'actual_result','完成能力提升计划','evidence_source','学习证书','employee_score',92
  ));
  perform public.hr_transition_performance_review_secure(v_review_id,'submit_self','员工阶段总结已完成');

  perform public.hr_save_performance_record_secure('check_in',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'check_in_date',current_date,
    'progress_percent',95,'risk_status','on_track','achievement','主要目标按计划达成',
    'next_action','完成期末成果验收','manager_feedback','保持交付质量',
    'facilitator_employee_id',v_context.reviewer_employee_id
  ));
  perform public.hr_save_performance_record_secure('goal',v_goal_one,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'progress_percent',95,'status','in_progress',
    'actual_result','完成主要经营结果','evidence_source','经营看板','manager_score',86
  ));
  perform public.hr_save_performance_record_secure('goal',v_goal_two,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'review_id',v_review_id,'progress_percent',100,'status','completed',
    'actual_result','完成能力提升计划','evidence_source','学习证书','manager_score',90
  ));
  perform public.hr_transition_performance_review_secure(v_review_id,'submit_manager','主管评价依据充分，建议进入校准');
  insert into hr_performance_test_result values(
    'weighted_manager_score_calculated',
    exists(select 1 from jsonb_array_elements(public.hr_list_performance_records_secure(
      'review',0,19,null,'confirmed',v_cycle_id,null,v_context.tenant_id)->'records') row
      where (row->>'id')::uuid=v_review_id and (row->>'manager_score')::numeric=87.6
        and row->>'performance_level'='a'),
    '主管评分按目标权重自动汇总并映射绩效等级'
  );

  v_session_id:=public.hr_save_performance_record_secure('calibration',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'session_no','TEST-CAL-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    'session_name','企业绩效校准自动化测试','cycle_id',v_cycle_id,
    'organization_id',v_context.organization_id,'facilitator_employee_id',v_context.reviewer_employee_id,
    'scheduled_at',now()+interval '7 days','distribution_note','按统一评分口径进行校准'
  ));
  perform public.hr_transition_performance_calibration_secure(v_session_id,'start',null);
  select (row->>'id')::uuid into v_item_id
  from jsonb_array_elements(public.hr_list_performance_records_secure(
    'calibration_item',0,19,null,null,v_cycle_id,v_session_id,v_context.tenant_id)->'records') row
  where (row->>'review_id')::uuid=v_review_id;
  perform public.hr_save_performance_record_secure('calibration_item',v_item_id,jsonb_build_object(
    'tenant_id',v_context.tenant_id,'calibrated_score',88.6,'calibrated_level','a',
    'adjustment_reason','校准委员会结合跨团队难度统一上调 1 分'
  ));
  perform public.hr_transition_performance_calibration_secure(v_session_id,'approve','校准会议一致通过');
  perform public.hr_transition_performance_cycle_secure(v_cycle_id,'complete','全部结果已完成');

  insert into hr_performance_test_result values(
    'calibration_writes_back_final_result',
    exists(select 1 from jsonb_array_elements(public.hr_list_performance_records_secure(
      'review',0,19,null,'completed',v_cycle_id,null,v_context.tenant_id)->'records') row
      where (row->>'id')::uuid=v_review_id and (row->>'calibrated_score')::numeric=88.6
        and (row->>'total_score')::numeric=88.6 and row->>'performance_level'='a'),
    '校准定案将最终评分和等级回写员工绩效结果'
  );
  insert into hr_performance_test_result values(
    'cycle_lifecycle_completed',
    exists(select 1 from jsonb_array_elements(public.hr_list_performance_records_secure(
      'cycle',0,19,null,'completed',null,null,v_context.tenant_id)->'records') row
      where (row->>'id')::uuid=v_cycle_id and row->>'activated_at' is not null and row->>'completed_at' is not null),
    '绩效周期完整保留启动、评议和完成状态证据'
  );
  update hr_performance_test_context set cycle_id=v_cycle_id,review_id=v_review_id,session_id=v_session_id;
end
$test$;

reset role;

insert into hr_performance_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege('anon','public.hr_performance_overview_secure(uuid)','execute')
    and not has_function_privilege('anon','public.hr_save_performance_record_secure(text,uuid,jsonb)','execute'),
  '匿名角色不能调用绩效读取或写入 RPC'
);

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_performance_test_context limit 1),
  'role','authenticated'
)::text,true);
set local role authenticated;

do $test$
declare v_denied boolean:=false;
begin
  begin
    perform public.hr_performance_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true;
  end;
  insert into hr_performance_test_result values(
    'ordinary_user_denied',v_denied,'未授权普通用户不能读取租户绩效数据'
  );
end
$test$;

reset role;
select check_name,passed,detail from hr_performance_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_performance_test_result where not passed) then
    raise exception 'HR performance management verification failed';
  end if;
end
$test$;

rollback;
