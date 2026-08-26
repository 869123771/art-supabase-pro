begin;
set local timezone='Asia/Shanghai';

create temporary table hr_internal_mobility_test_context(
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  organization_id uuid not null,
  employee_id uuid not null,
  opportunity_id uuid,
  application_id uuid
) on commit drop;
create temporary table hr_internal_mobility_test_result(
  check_name text primary key,passed boolean not null,detail text
) on commit drop;

insert into hr_internal_mobility_test_context(
  tenant_id,ordinary_auth_user_id,organization_id,employee_id
)
select user_row.tenant_id,user_row.auth_user_id,employee.organization_id,employee.id
from public.sys_user user_row
join public.hr_employee employee on employee.tenant_id=user_row.tenant_id
join public.sys_organization organization on organization.id=employee.organization_id
where user_row.auth_user_id is not null
  and user_row.status='1'
  and 'R_REGISTER'=any(user_row.user_roles)
  and user_row.hr_employee_id is null
  and employee.employment_status in ('probation','active')
  and employee.hire_date is not null
  and organization.status='1'
order by user_row.create_time,employee.employee_no
limit 1;
grant select,update on hr_internal_mobility_test_context to authenticated;
grant select,insert,update on hr_internal_mobility_test_result to anon,authenticated;

set local role anon;
do $test$ declare v_denied boolean:=false; begin
  begin perform public.hr_internal_mobility_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true; end;
  insert into hr_internal_mobility_test_result values(
    'anon_denied',v_denied,'匿名账号不能读取内部人才市场'
  );
end $test$;
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER'=any(user_roles) or user_type='0')
    order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid:=(select tenant_id from hr_internal_mobility_test_context limit 1);
  v_org_id uuid:=(select organization_id from hr_internal_mobility_test_context limit 1);
  v_employee_id uuid:=(select employee_id from hr_internal_mobility_test_context limit 1);
  v_opportunity_id uuid;
  v_application_id uuid;
  v_records jsonb;
  v_score_guard boolean:=false;
  v_temporary_conversion_guard boolean:=false;
begin
  if v_tenant_id is null then raise exception 'No internal mobility fixture'; end if;

  v_opportunity_id:=public.hr_save_internal_opportunity_secure(null,jsonb_build_object(
    'tenant_id',v_tenant_id,
    'opportunity_code','IM_TEST_PROJECT',
    'opportunity_title','跨部门流程优化项目负责人',
    'opportunity_type','project',
    'organization_id',v_org_id,
    'hiring_manager_employee_id',v_employee_id,
    'capacity',1,
    'work_mode','hybrid',
    'work_location','总部',
    'expected_start_date',current_date+14,
    'expected_end_date',current_date+104,
    'application_open_date',current_date,
    'application_close_date',current_date+10,
    'min_tenure_months',0,
    'role_summary','负责跨部门流程梳理、改进方案推进与阶段成果复盘。',
    'required_skills','流程分析、项目管理、跨团队协作',
    'eligibility_notes','面向在职员工开放，需与直属经理完成知会。'
  ));
  perform public.hr_transition_internal_mobility_secure(
    'opportunity',v_opportunity_id,'publish','自动化测试发布',null
  );

  v_application_id:=public.hr_save_internal_mobility_application_secure(null,jsonb_build_object(
    'opportunity_id',v_opportunity_id,
    'employee_id',v_employee_id,
    'motivation','希望通过跨部门项目应用流程改进经验，并承担可量化的交付责任。',
    'relevant_experience','参与过部门流程标准化和协同机制建设。',
    'preferred_start_date',current_date+14,
    'manager_awareness','informed'
  ));
  update hr_internal_mobility_test_context
  set opportunity_id=v_opportunity_id,application_id=v_application_id;

  perform public.hr_transition_internal_mobility_secure(
    'application',v_application_id,'submit',null,null
  );
  perform public.hr_transition_internal_mobility_secure(
    'application',v_application_id,'review','具备项目经历，进入结构化评估。',82
  );
  begin
    perform public.hr_transition_internal_mobility_secure(
      'application',v_application_id,'shortlist','缺少分数不应进入候选名单',null
    );
  exception when others then v_score_guard:=true; end;
  insert into hr_internal_mobility_test_result values(
    'shortlist_score_guard',v_score_guard,'进入候选名单必须有 0-100 分和评估依据'
  );

  perform public.hr_transition_internal_mobility_secure(
    'application',v_application_id,'shortlist','能力与项目要求匹配，建议进入候选名单。',88
  );
  perform public.hr_transition_internal_mobility_secure(
    'application',v_application_id,'offer','综合评估通过，发出项目机会意向。',null
  );
  perform public.hr_transition_internal_mobility_secure(
    'application',v_application_id,'accept',null,null
  );
  begin
    perform public.hr_transition_internal_mobility_secure(
      'application',v_application_id,'convert','不应转换临时项目',null
    );
  exception when others then v_temporary_conversion_guard:=true; end;
  insert into hr_internal_mobility_test_result values(
    'temporary_conversion_guard',v_temporary_conversion_guard,
    '项目、轮岗与短期任务不会被误转为永久人事异动'
  );

  v_records:=public.hr_list_internal_mobility_records_secure(
    'application',0,9,'IM_TEST_PROJECT',null,v_opportunity_id,v_tenant_id
  );
  insert into hr_internal_mobility_test_result values(
    'governed_application_flow',
    (v_records->>'total')::integer=1
      and v_records->'records'->0->>'status'='accepted'
      and v_records->'records'->0->>'personnel_change_id' is null,
    '申请经过提交、评审、候选、意向和接受，且不会直接修改任职数据'
  );
end $test$;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_internal_mobility_test_context limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_records jsonb;
  v_profile_guard boolean:=false;
  v_manage_denied boolean:=false;
  v_direct_denied boolean:=false;
begin
  v_records:=public.hr_list_internal_mobility_records_secure(
    'opportunity',0,9,'IM_TEST_PROJECT',null,null,null
  );
  insert into hr_internal_mobility_test_result values(
    'ordinary_open_opportunity_read',(v_records->>'total')::integer=1,
    '普通员工可读取本租户已发布的内部机会'
  );

  v_records:=public.hr_list_internal_mobility_records_secure(
    'application',0,9,null,null,null,null
  );
  insert into hr_internal_mobility_test_result values(
    'ordinary_application_scope',(v_records->>'total')::integer=0,
    '普通员工只能读取与本人员工档案关联的申请'
  );

  begin
    perform public.hr_save_internal_mobility_application_secure(null,jsonb_build_object(
      'opportunity_id',(select opportunity_id from hr_internal_mobility_test_context limit 1),
      'motivation','未关联员工档案时不能提交申请。',
      'manager_awareness','not_informed'
    ));
  exception when others then v_profile_guard:=true; end;
  insert into hr_internal_mobility_test_result values(
    'employee_profile_link_guard',v_profile_guard,'自助申请要求账号关联有效员工档案'
  );

  begin
    perform public.hr_transition_internal_mobility_secure(
      'opportunity',(select opportunity_id from hr_internal_mobility_test_context limit 1),
      'pause','普通员工不应暂停机会',null
    );
  exception when insufficient_privilege then v_manage_denied:=true; end;
  insert into hr_internal_mobility_test_result values(
    'ordinary_manage_denied',v_manage_denied,'普通员工不能发布、暂停或关闭内部机会'
  );

  begin perform count(*) from public.hr_internal_opportunity;
  exception when insufficient_privilege then v_direct_denied:=true; end;
  insert into hr_internal_mobility_test_result values(
    'direct_table_denied',v_direct_denied,'内部人才市场业务表不向 authenticated 直接开放'
  );
end $test$;

reset role;
select check_name,passed,detail from hr_internal_mobility_test_result order by check_name;
do $test$ declare v_failed text; begin
  select string_agg(check_name||': '||detail,'; ') into v_failed
  from hr_internal_mobility_test_result where not passed;
  if v_failed is not null then
    raise exception 'HR internal mobility test failed: %',v_failed;
  end if;
end $test$;
rollback;
