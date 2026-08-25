begin;

create temporary table hr_succession_test_context (
  tenant_id uuid not null,
  position_id uuid not null,
  incumbent_id uuid,
  candidate_id uuid not null,
  plan_id uuid,
  succession_candidate_id uuid,
  ordinary_auth_user_id uuid
) on commit drop;

create temporary table hr_succession_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_succession_test_context(tenant_id, position_id, incumbent_id, candidate_id, ordinary_auth_user_id)
select p.tenant_id, p.id, incumbent.id, candidate.id,
  (select u.auth_user_id from public.sys_user u where u.tenant_id=p.tenant_id and u.auth_user_id is not null and 'R_REGISTER'=any(u.user_roles) limit 1)
from public.hr_position p
left join lateral (select e.id from public.hr_employee e where e.position_id=p.id and e.tenant_id=p.tenant_id limit 1) incumbent on true
join lateral (select e.id from public.hr_employee e where e.tenant_id=p.tenant_id and e.position_id<>p.id and e.employment_status in ('probation','active','leave') order by e.employee_no limit 1) candidate on true
where p.enabled order by p.create_time limit 1;

grant select, update on hr_succession_test_context to authenticated;
grant select, insert on hr_succession_test_result to authenticated;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null and ('R_SUPER'=any(user_roles) or user_type='0') order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_ctx hr_succession_test_context%rowtype;
  v_plan_id uuid;
  v_candidate_id uuid;
  v_action_id uuid;
  v_draft_plan_id uuid;
  v_draft_candidate_id uuid;
  v_payload jsonb;
  v_incumbent_blocked boolean := false;
  v_direct_blocked boolean := false;
  v_history_protected boolean := false;
begin
  select * into v_ctx from hr_succession_test_context limit 1;
  if v_ctx.tenant_id is null then raise exception 'No succession test fixture'; end if;

  v_plan_id := public.hr_save_succession_plan_secure(null,jsonb_build_object(
    'tenant_id',v_ctx.tenant_id,'plan_code','TEST_SUCCESSION_'||substr(gen_random_uuid()::text,1,8),
    'position_id',v_ctx.position_id,'plan_name','企业继任自动化测试','criticality','critical',
    'vacancy_risk','high','business_impact','critical','target_successors',2,
    'review_cycle_months',6,'next_review_date',current_date+30,'status','active'));

  v_candidate_id := public.hr_save_succession_candidate_secure(null,jsonb_build_object(
    'tenant_id',v_ctx.tenant_id,'plan_id',v_plan_id,'employee_id',v_ctx.candidate_id,
    'readiness','ready_now','potential_level','high','retention_risk','medium','priority',1,
    'nomination_source','talent_review','aspiration_confirmed',true,'status','nominated'));
  perform public.hr_review_succession_candidate_secure(v_candidate_id,'activate','自动化评审通过');

  v_action_id := public.hr_save_succession_action_secure(null,jsonb_build_object(
    'tenant_id',v_ctx.tenant_id,'candidate_id',v_candidate_id,'action_type','stretch_assignment',
    'action_title','主持季度经营复盘','start_date',current_date,'due_date',current_date+60,'status','in_progress'));

  v_payload := public.hr_list_succession_records_secure('plan',0,20,null,null,v_ctx.tenant_id);
  insert into hr_succession_test_result values(
    'plan_candidate_coverage',
    exists(select 1 from jsonb_array_elements(v_payload->'records') r where r->>'id'=v_plan_id::text and (r->>'active_candidate_count')::integer=1 and (r->>'ready_now_count')::integer=1),
    '执行中计划正确统计候选人与立即就绪人数');

  v_payload := public.hr_list_succession_records_secure('action',0,20,null,null,v_ctx.tenant_id);
  insert into hr_succession_test_result values(
    'development_action_traceable',
    exists(select 1 from jsonb_array_elements(v_payload->'records') r where r->>'id'=v_action_id::text and r->>'status'='in_progress'),
    '发展行动可按候选人和目标岗位追溯');

  if v_ctx.incumbent_id is not null then
    begin
      perform public.hr_save_succession_candidate_secure(null,jsonb_build_object(
        'tenant_id',v_ctx.tenant_id,'plan_id',v_plan_id,'employee_id',v_ctx.incumbent_id,
        'readiness','ready_now','potential_level','high','retention_risk','low','status','nominated'));
    exception when others then
      v_incumbent_blocked := position('当前岗位任职者' in sqlerrm)>0;
    end;
  else
    v_incumbent_blocked := true;
  end if;
  insert into hr_succession_test_result values('incumbent_nomination_blocked',v_incumbent_blocked,'当前岗位任职者不能成为同岗位继任人');

  begin perform 1 from public.hr_succession_plan limit 1;
  exception when insufficient_privilege then v_direct_blocked:=true; end;
  insert into hr_succession_test_result values('direct_table_access_denied',v_direct_blocked,'签入用户不能绕过受控 RPC 直读继任表');

  v_draft_plan_id := public.hr_save_succession_plan_secure(null,jsonb_build_object(
    'tenant_id',v_ctx.tenant_id,'plan_code','TEST_DRAFT_'||substr(gen_random_uuid()::text,1,8),
    'position_id',v_ctx.position_id,'plan_name','继任历史保护测试','criticality','high',
    'vacancy_risk','medium','business_impact','high','target_successors',1,
    'review_cycle_months',6,'next_review_date',current_date+60,'status','draft'));
  v_draft_candidate_id := public.hr_save_succession_candidate_secure(null,jsonb_build_object(
    'tenant_id',v_ctx.tenant_id,'plan_id',v_draft_plan_id,'employee_id',v_ctx.candidate_id,
    'readiness','development_needed','potential_level','emerging','retention_risk','low',
    'priority',1,'nomination_source','hr','status','nominated'));
  begin
    perform public.hr_delete_succession_record_secure('plan',v_draft_plan_id);
  exception when others then
    v_history_protected := position('不会级联删除' in sqlerrm)>0;
  end;
  insert into hr_succession_test_result values(
    'succession_history_protected',v_history_protected,
    '含候选人的计划禁止级联删除，继任决策历史得到保留');

  update hr_succession_test_context set plan_id=v_plan_id,succession_candidate_id=v_candidate_id;
end;
$test$;

reset role;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_succession_test_context limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare v_denied boolean:=false;
begin
  begin perform public.hr_succession_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true; end;
  insert into hr_succession_test_result values('ordinary_user_denied',v_denied,'未授权普通用户不能读取敏感继任规划');
end;
$test$;

reset role;
select check_name,passed,detail from hr_succession_test_result order by check_name;
do $test$ begin if exists(select 1 from hr_succession_test_result where not passed) then raise exception 'HR succession verification failed'; end if; end $test$;
rollback;
