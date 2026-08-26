begin;
set local timezone='Asia/Shanghai';

create temporary table hr_org_design_test_context(
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  organization_id uuid not null,
  organization_name text not null,
  scenario_id uuid,
  change_id uuid
) on commit drop;
create temporary table hr_org_design_test_result(
  check_name text primary key,passed boolean not null,detail text
) on commit drop;

insert into hr_org_design_test_context(tenant_id,ordinary_auth_user_id,organization_id,organization_name)
select user_row.tenant_id,user_row.auth_user_id,organization.id,organization.organization_name
from public.sys_user user_row
join public.sys_organization organization on organization.tenant_id=user_row.tenant_id
where user_row.auth_user_id is not null and user_row.status='1'
  and 'R_REGISTER'=any(user_row.user_roles) and organization.status='1'
order by user_row.create_time,organization.is_system,organization.sort limit 1;
grant select,update on hr_org_design_test_context to authenticated;
grant select,insert,update on hr_org_design_test_result to anon,authenticated;

set local role anon;
do $test$ declare v_denied boolean:=false; begin
  begin perform public.hr_organization_design_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true; end;
  insert into hr_org_design_test_result values('anon_denied',v_denied,'匿名账号不能读取组织变革方案');
end $test$;
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER'=any(user_roles) or user_type='0') order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid:=(select tenant_id from hr_org_design_test_context limit 1);
  v_org_id uuid:=(select organization_id from hr_org_design_test_context limit 1);
  v_scenario_id uuid; v_change_id uuid; v_records jsonb; v_self_parent_guard boolean:=false;
begin
  if v_tenant_id is null then raise exception 'No ordinary organization design tenant fixture'; end if;
  v_scenario_id:=public.hr_save_organization_design_scenario_secure(null,jsonb_build_object(
    'tenant_id',v_tenant_id,'scenario_code','ORG_DESIGN_TEST','scenario_name','组织变革自动化测试',
    'objective','验证影响快照、审批、移交与组织主数据隔离。','effective_date',current_date+30
  ));
  v_change_id:=public.hr_save_organization_design_change_secure(null,jsonb_build_object(
    'scenario_id',v_scenario_id,'change_type','create','proposed_code','ORG_DESIGN_TEST_NODE',
    'proposed_name','组织规划测试节点','proposed_type','department',
    'rationale','验证新增组织规划不会直接写入组织主数据','sequence',10
  ));
  update hr_org_design_test_context set scenario_id=v_scenario_id,change_id=v_change_id;
  begin
    perform public.hr_save_organization_design_change_secure(null,jsonb_build_object(
      'scenario_id',v_scenario_id,'change_type','rename','organization_id',v_org_id,
      'proposed_name','不应修改系统根组织','rationale','系统根组织不能纳入变革方案','sequence',20
    ));
  exception when others then v_self_parent_guard:=true; end;
  insert into hr_org_design_test_result values('system_root_guard',v_self_parent_guard,'系统根组织不能纳入组织变革方案');

  perform public.hr_transition_organization_design_secure(v_scenario_id,'submit','提交影响评审自动化测试');
  v_records:=public.hr_list_organization_design_records_secure('change',0,9,null,null,v_scenario_id,v_tenant_id);
  insert into hr_org_design_test_result values(
    'impact_snapshot',(v_records->>'total')::integer=1
      and v_records->'records'->0->>'impact_captured_at' is not null,
    '提交评审时固化员工、岗位、招聘、权限账号和政策范围影响'
  );
  insert into hr_org_design_test_result values(
    'master_data_isolation',not exists(select 1 from public.sys_organization where tenant_id=v_tenant_id and organization_code='ORG_DESIGN_TEST_NODE'),
    '情景方案不会直接改写组织主数据'
  );
  perform public.hr_transition_organization_design_secure(v_scenario_id,'approve','影响评估完整，同意进入执行移交');
  perform public.hr_transition_organization_design_secure(v_scenario_id,'handoff','由平台组织管理员在维护窗口执行并复核权限');
  v_records:=public.hr_list_organization_design_records_secure('scenario',0,9,'ORG_DESIGN_TEST',null,null,v_tenant_id);
  insert into hr_org_design_test_result values(
    'governed_handoff',v_records->'records'->0->>'status'='handed_off'
      and v_records->'records'->0->>'handed_off_by' is not null,
    '方案经影响评审、批准后才可移交组织主数据执行'
  );
end $test$;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_org_design_test_context limit 1),'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare v_records jsonb; v_write_denied boolean:=false; v_direct_denied boolean:=false;
begin
  v_records:=public.hr_list_organization_design_records_secure('scenario',0,9,'ORG_DESIGN_TEST',null,null,null);
  insert into hr_org_design_test_result values(
    'ordinary_tenant_read',(v_records->>'total')::integer=1,
    '普通用户可读取本租户组织变革方案'
  );
  begin perform public.hr_transition_organization_design_secure(
    (select scenario_id from hr_org_design_test_context limit 1),'cancel','不应执行'
  ); exception when insufficient_privilege then v_write_denied:=true; end;
  insert into hr_org_design_test_result values('ordinary_write_denied',v_write_denied,'普通用户不能流转组织变革方案');
  begin perform count(*) from public.hr_organization_design_scenario;
  exception when insufficient_privilege then v_direct_denied:=true; end;
  insert into hr_org_design_test_result values('direct_table_denied',v_direct_denied,'组织变革业务表不向 authenticated 直接开放');
end $test$;

reset role;
select check_name,passed,detail from hr_org_design_test_result order by check_name;
do $test$ declare v_failed text; begin
  select string_agg(check_name||': '||detail,'; ') into v_failed from hr_org_design_test_result where not passed;
  if v_failed is not null then raise exception 'HR organization design test failed: %',v_failed; end if;
end $test$;
rollback;
