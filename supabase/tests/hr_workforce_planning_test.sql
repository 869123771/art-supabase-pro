begin;

create temporary table hr_workforce_test_context (
  tenant_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  baseline_count integer not null,
  original_limit integer not null,
  ordinary_auth_user_id uuid,
  cycle_id uuid,
  line_id uuid
) on commit drop;

create temporary table hr_workforce_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_workforce_test_context(
  tenant_id, organization_id, position_id, baseline_count, original_limit, ordinary_auth_user_id
)
select p.tenant_id, p.organization_id, p.id, count(a.id)::integer, p.headcount_limit,
  coalesce((
    select u.auth_user_id from public.sys_user u
    where u.auth_user_id is not null
      and not ('R_SUPER' = any(coalesce(u.user_roles,array[]::text[])))
      and cardinality(coalesce(u.user_roles,array[]::text[])) = 0
    order by u.create_time limit 1
  ), gen_random_uuid())
from public.hr_position p
join public.hr_employee_assignment a on a.tenant_id=p.tenant_id and a.position_id=p.id
  and a.primary_assignment and a.effective_end is null and a.assignment_status <> 'ended'
where p.enabled
group by p.id
order by count(a.id) desc, p.position_code
limit 1;

grant select, update on hr_workforce_test_context to authenticated;
grant select, insert, update on hr_workforce_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (
    select auth_user_id from public.sys_user
    where auth_user_id is not null and ('R_SUPER' = any(user_roles) or user_type='0')
    order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1
  ),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_workforce_test_context%rowtype;
  v_cycle_id uuid;
  v_line_id uuid;
  v_overlap_cycle uuid;
  v_overlap_line uuid;
  v_direct_blocked boolean := false;
  v_overlap_blocked boolean := false;
begin
  select * into v_context from hr_workforce_test_context limit 1;
  if v_context.tenant_id is null then raise exception 'No workforce planning test fixture'; end if;

  v_cycle_id := public.hr_save_workforce_record_secure('cycle',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,
    'plan_no','TEST-WFP-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    'plan_name','企业人力规划闭环自动化测试',
    'scenario','growth',
    'period_start',current_date,
    'period_end',current_date+30,
    'baseline_date',current_date,
    'budget_amount',1200000,
    'currency_code','CNY',
    'objective','验证规划审批、启用与岗位容量同步'
  ));
  v_line_id := public.hr_save_workforce_record_secure('line',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,
    'plan_id',v_cycle_id,
    'organization_id',v_context.organization_id,
    'position_id',v_context.position_id,
    'planned_hires',1,
    'planned_exits',0,
    'annual_cost_per_head',180000,
    'demand_date',current_date+10,
    'priority','high',
    'rationale','业务增长需要增加岗位容量'
  ));

  insert into hr_workforce_test_result values(
    'baseline_snapshot_captured',
    exists(
      select 1 from jsonb_array_elements(
        public.hr_list_workforce_records_secure(
          'line',0,19,null,null,v_cycle_id,v_context.tenant_id
        )->'records'
      ) record
      where (record->>'id')::uuid=v_line_id
        and (record->>'baseline_count')::integer=v_context.baseline_count
        and (record->>'target_count')::integer=v_context.baseline_count+1
    ),
    '新增岗位需求自动快照当前主岗人数并计算目标编制'
  );

  begin
    perform 1 from public.hr_workforce_plan_cycle limit 1;
  exception when insufficient_privilege then v_direct_blocked := true;
  end;
  insert into hr_workforce_test_result values(
    'direct_planning_table_access_denied',v_direct_blocked,
    '签入用户不能绕过受控 RPC 直接读取规划表'
  );

  perform public.hr_transition_workforce_plan_secure(v_cycle_id,'submit',null);
  perform public.hr_transition_workforce_plan_secure(v_cycle_id,'approve','预算与岗位需求核验通过');
  perform public.hr_transition_workforce_plan_secure(v_cycle_id,'activate','按规划周期启用');

  insert into hr_workforce_test_result values(
    'activation_syncs_effective_headcount',
    exists(select 1 from public.hr_position_headcount h
      where h.source_plan_line_id=v_line_id and h.approved_count=v_context.baseline_count+1
        and h.effective_from=current_date and h.enabled),
    '启用计划生成带来源追溯的有效编制记录'
  );
  insert into hr_workforce_test_result values(
    'activation_syncs_position_capacity',
    exists(
      select 1 from jsonb_array_elements(
        public.hr_list_workforce_options_secure('position',v_context.tenant_id)
      ) option
      where (option->>'id')::uuid=v_context.position_id
        and (option->>'headcount_limit')::integer=v_context.baseline_count+1
    ),
    '启用计划同步岗位实时容量硬上限'
  );

  v_overlap_cycle := public.hr_save_workforce_record_secure('cycle',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,
    'plan_no','TEST-WFP-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    'plan_name','重叠规划校验',
    'scenario','baseline',
    'period_start',current_date+1,
    'period_end',current_date+20,
    'baseline_date',current_date
  ));
  v_overlap_line := public.hr_save_workforce_record_secure('line',null,jsonb_build_object(
    'tenant_id',v_context.tenant_id,
    'plan_id',v_overlap_cycle,
    'organization_id',v_context.organization_id,
    'position_id',v_context.position_id,
    'planned_hires',0,
    'planned_exits',0,
    'priority','normal',
    'rationale','验证同岗位重叠周期拦截'
  ));
  begin
    perform public.hr_transition_workforce_plan_secure(v_overlap_cycle,'submit',null);
  exception when others then
    v_overlap_blocked := position('同岗位计划重叠' in sqlerrm) > 0;
  end;
  insert into hr_workforce_test_result values(
    'overlapping_position_plan_blocked',v_overlap_blocked,
    '同一岗位不能存在周期重叠的已批准或执行中规划'
  );

  perform public.hr_transition_workforce_plan_secure(v_cycle_id,'close','自动化测试提前关闭');
  update hr_workforce_test_context set cycle_id=v_cycle_id,line_id=v_line_id;
end
$test$;

reset role;

insert into hr_workforce_test_result values(
  'cycle_lifecycle_closed',
  exists(select 1 from public.hr_workforce_plan_cycle c
    join hr_workforce_test_context x on x.cycle_id=c.id
    where c.status='closed' and c.approved_at is not null
      and c.activated_at is not null and c.closed_at is not null),
  '规划完整保留审批、启用与关闭时间证据'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_workforce_test_context limit 1),
  'role','authenticated'
)::text,true);
set local role authenticated;

do $test$
declare v_denied boolean := false;
begin
  begin
    perform public.hr_workforce_overview_secure(null);
  exception when insufficient_privilege then v_denied := true;
  end;
  insert into hr_workforce_test_result values(
    'ordinary_user_denied',v_denied,
    '未授权普通用户不能读取租户人力规划数据'
  );
end
$test$;

reset role;
select check_name,passed,detail from hr_workforce_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_workforce_test_result where not passed) then
    raise exception 'HR workforce planning verification failed';
  end if;
end
$test$;

rollback;
