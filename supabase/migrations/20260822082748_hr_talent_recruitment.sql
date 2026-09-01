-- HR P2: performance, talent development and recruitment.

create table public.hr_performance_cycle (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  cycle_code text not null, cycle_name text not null, start_date date not null, end_date date not null,
  status text not null default 'draft', description text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint hr_performance_cycle_dates_check check(end_date>=start_date),
  constraint hr_performance_cycle_status_check check(status in ('draft','active','reviewing','completed','cancelled')),
  unique(tenant_id,cycle_code), unique(id,tenant_id)
);
create table public.hr_performance_review (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  cycle_id uuid not null, employee_id uuid not null, reviewer_user_id uuid,
  status text not null default 'draft', total_score numeric(8,2), performance_level text,
  employee_summary text, reviewer_comment text, confirmed_at timestamptz,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(cycle_id,tenant_id) references public.hr_performance_cycle(id,tenant_id) on delete cascade,
  foreign key(employee_id,tenant_id) references public.hr_employee(id,tenant_id) on delete cascade,
  foreign key(tenant_id,reviewer_user_id) references public.sys_user(tenant_id,id) on delete restrict,
  constraint hr_performance_review_status_check check(status in ('draft','self_review','manager_review','confirmed','completed','cancelled')),
  constraint hr_performance_review_score_check check(total_score is null or total_score between 0 and 100),
  unique(tenant_id,cycle_id,employee_id), unique(id,tenant_id)
);
create table public.hr_performance_goal (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  review_id uuid not null, goal_name text not null, target_description text not null,
  weight numeric(6,2) not null default 0, actual_result text, score numeric(8,2), evidence_source text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(review_id,tenant_id) references public.hr_performance_review(id,tenant_id) on delete cascade,
  constraint hr_performance_goal_weight_check check(weight between 0 and 100),
  constraint hr_performance_goal_score_check check(score is null or score between 0 and 100)
);

create table public.hr_training_plan (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_code text not null, plan_name text not null, training_type text not null,
  start_date date not null, end_date date, provider_name text, budget numeric(14,2),
  status text not null default 'draft', objective text, remark text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint hr_training_plan_dates_check check(end_date is null or end_date>=start_date),
  constraint hr_training_plan_budget_check check(budget is null or budget>=0),
  constraint hr_training_plan_status_check check(status in ('draft','published','in_progress','completed','cancelled')),
  unique(tenant_id,plan_code), unique(id,tenant_id)
);
create table public.hr_training_enrollment (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_id uuid not null, employee_id uuid not null, status text not null default 'enrolled',
  score numeric(8,2), result text, completed_at timestamptz, certificate_no text, remark text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(plan_id,tenant_id) references public.hr_training_plan(id,tenant_id) on delete cascade,
  foreign key(employee_id,tenant_id) references public.hr_employee(id,tenant_id) on delete cascade,
  constraint hr_training_enrollment_status_check check(status in ('enrolled','attending','passed','failed','withdrawn')),
  constraint hr_training_enrollment_score_check check(score is null or score between 0 and 100),
  unique(tenant_id,plan_id,employee_id)
);
create table public.hr_competency (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  competency_code text not null, competency_name text not null, category text not null,
  description text, enabled boolean not null default true,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  unique(tenant_id,competency_code), unique(id,tenant_id)
);
create table public.hr_position_competency (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  position_id uuid not null, competency_id uuid not null, required_level text not null, weight numeric(6,2) not null default 0,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(position_id,tenant_id) references public.hr_position(id,tenant_id) on delete cascade,
  foreign key(competency_id,tenant_id) references public.hr_competency(id,tenant_id) on delete cascade,
  constraint hr_position_competency_weight_check check(weight between 0 and 100),
  unique(tenant_id,position_id,competency_id)
);
create table public.hr_employee_competency (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null, competency_id uuid not null, current_level text not null,
  assessed_date date not null default current_date, assessor_user_id uuid, evidence text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(employee_id,tenant_id) references public.hr_employee(id,tenant_id) on delete cascade,
  foreign key(competency_id,tenant_id) references public.hr_competency(id,tenant_id) on delete cascade,
  foreign key(tenant_id,assessor_user_id) references public.sys_user(tenant_id,id) on delete restrict,
  unique(tenant_id,employee_id,competency_id)
);

create table public.hr_recruitment_requisition (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  requisition_no text not null, organization_id uuid not null, position_id uuid not null,
  opening_count integer not null default 1, hired_count integer not null default 0,
  expected_onboard_date date, employment_type text not null default 'full_time',
  status text not null default 'draft', reason text not null, requirements text,
  workflow_instance_id uuid, reviewed_at timestamptz, reviewed_by text, review_comment text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(organization_id) references public.sys_organization(id) on delete restrict,
  foreign key(position_id,tenant_id) references public.hr_position(id,tenant_id) on delete restrict,
  constraint hr_recruitment_requisition_count_check check(opening_count>0 and hired_count between 0 and opening_count),
  constraint hr_recruitment_requisition_status_check check(status in ('draft','pending','approved','effective','rejected','cancelled')),
  unique(tenant_id,requisition_no), unique(id,tenant_id)
);
create table public.hr_candidate (
  id uuid primary key default gen_random_uuid(), tenant_id uuid not null default app_private.current_user_tenant_id(),
  requisition_id uuid not null, candidate_name text not null, phone text, email text,
  source text not null default 'referral', stage text not null default 'new',
  expected_salary numeric(14,2), resume_url text, interview_feedback text,
  offer_date date, onboard_employee_id uuid, remark text,
  create_by text, create_time timestamptz not null default now(), update_by text, update_time timestamptz not null default now(),
  foreign key(tenant_id) references public.sys_tenant(id) on delete restrict,
  foreign key(requisition_id,tenant_id) references public.hr_recruitment_requisition(id,tenant_id) on delete cascade,
  foreign key(onboard_employee_id,tenant_id) references public.hr_employee(id,tenant_id) on delete restrict,
  constraint hr_candidate_salary_check check(expected_salary is null or expected_salary>=0)
);

create index idx_hr_performance_review_cycle on public.hr_performance_review(tenant_id,cycle_id,status);
create index idx_hr_performance_goal_review on public.hr_performance_goal(tenant_id,review_id);
create index idx_hr_training_enrollment_plan on public.hr_training_enrollment(tenant_id,plan_id,status);
create index idx_hr_position_competency_position on public.hr_position_competency(tenant_id,position_id);
create index idx_hr_employee_competency_employee on public.hr_employee_competency(tenant_id,employee_id);
create index idx_hr_recruitment_requisition_status on public.hr_recruitment_requisition(tenant_id,status,expected_onboard_date);
create index idx_hr_candidate_requisition on public.hr_candidate(tenant_id,requisition_id,stage);

do $$ declare v_table text; begin
  foreach v_table in array array['hr_performance_cycle','hr_performance_review','hr_performance_goal','hr_training_plan',
    'hr_training_enrollment','hr_competency','hr_position_competency','hr_employee_competency',
    'hr_recruitment_requisition','hr_candidate'] loop
    execute format('create trigger %I_create_audit before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'',''true'')',v_table,v_table);
    execute format('create trigger %I_update_audit before update on public.%I for each row execute function public.trg_set_update_time_and_by()',v_table,v_table);
    execute format('alter table public.%I enable row level security',v_table);
    execute format('grant select,insert,update,delete on public.%I to authenticated',v_table);
  end loop;
end $$;
create trigger hr_recruitment_requisition_guard before update or delete on public.hr_recruitment_requisition
for each row execute function app_private.hr_guard_approval_record();

-- Talent policies are permission-scoped and tenant isolated.
do $$ declare v_table text; v_prefix text; begin
  foreach v_table in array array['hr_performance_cycle','hr_performance_review','hr_performance_goal'] loop
    execute format('create policy %I_tenant_select on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Performance:View''))))',v_table,v_table);
    execute format('create policy %I_tenant_insert on public.%I for insert to authenticated with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Performance:Add'')))',v_table,v_table);
    execute format('create policy %I_tenant_update on public.%I for update to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Performance:Edit'')))) with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))',v_table,v_table);
    execute format('create policy %I_tenant_delete on public.%I for delete to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Performance:Delete''))))',v_table,v_table);
  end loop;
  foreach v_table in array array['hr_training_plan','hr_training_enrollment','hr_competency','hr_position_competency','hr_employee_competency'] loop
    execute format('create policy %I_tenant_select on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Talent:View''))))',v_table,v_table);
    execute format('create policy %I_tenant_insert on public.%I for insert to authenticated with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Talent:Add'')))',v_table,v_table);
    execute format('create policy %I_tenant_update on public.%I for update to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Talent:Edit'')))) with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))',v_table,v_table);
    execute format('create policy %I_tenant_delete on public.%I for delete to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Talent:Delete''))))',v_table,v_table);
  end loop;
  foreach v_table in array array['hr_recruitment_requisition','hr_candidate'] loop
    execute format('create policy %I_tenant_select on public.%I for select to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Recruitment:View''))))',v_table,v_table);
    execute format('create policy %I_tenant_insert on public.%I for insert to authenticated with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Recruitment:Add'')))',v_table,v_table);
    execute format('create policy %I_tenant_update on public.%I for update to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Recruitment:Edit'')))) with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))',v_table,v_table);
    execute format('create policy %I_tenant_delete on public.%I for delete to authenticated using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission(''Hr:Recruitment:Delete''))))',v_table,v_table);
  end loop;
end $$;

create or replace function app_private.execute_hr_recruitment_workflow_callback(
  p_business_id uuid,p_status text,p_actor text,p_comment text
) returns void language plpgsql security definer set search_path=''
as $$ begin
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  update public.hr_recruitment_requisition
  set status=case p_status when 'running' then 'pending' when 'approved' then 'approved'
      when 'rejected' then 'rejected' when 'withdrawn' then 'draft' when 'cancelled' then 'cancelled' else status end,
    workflow_instance_id=coalesce(workflow_instance_id,(select i.id from public.wf_instance i
      where i.tenant_id=hr_recruitment_requisition.tenant_id and i.business_type='hr_recruitment_requisition'
        and i.business_id=p_business_id order by i.started_at desc limit 1)),
    reviewed_at=case when p_status in ('approved','rejected') then now() else reviewed_at end,
    reviewed_by=case when p_status in ('approved','rejected') then p_actor else reviewed_by end,
    review_comment=case when p_status in ('approved','rejected','cancelled')
      then nullif(btrim(coalesce(p_comment,'')),'') else review_comment end
  where id=p_business_id;
  if not found then raise exception '招聘需求不存在或已删除'; end if;
end $$;

alter function app_private.execute_workflow_business_callback(text,uuid,text,text,text)
  rename to execute_workflow_business_callback_before_hr_p2;
create function app_private.execute_workflow_business_callback(
  p_business_type text,p_business_id uuid,p_status text,p_actor text,p_comment text
) returns void language plpgsql security definer set search_path=''
as $$ begin
  if p_business_type='hr_recruitment_requisition' then
    perform app_private.execute_hr_recruitment_workflow_callback(p_business_id,p_status,p_actor,p_comment);
  else
    perform app_private.execute_workflow_business_callback_before_hr_p2(p_business_type,p_business_id,p_status,p_actor,p_comment);
  end if;
end $$;

alter function public.hr_submit_approval(text,uuid) rename to hr_submit_approval_before_hr_p2;
create function public.hr_submit_approval(p_business_type text,p_business_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_title text; v_context jsonb; begin
  if p_business_type='hr_recruitment_requisition' then
    if not (select app_private.is_platform_super()) and not (select app_private.has_permission('Hr:Recruitment:Submit')) then
      raise exception '当前账号没有提交招聘需求的权限' using errcode='42501';
    end if;
    select '招聘需求 '||r.requisition_no,jsonb_build_object('requisitionNo',r.requisition_no,
      'organizationId',r.organization_id,'positionId',r.position_id,'openingCount',r.opening_count,
      'expectedOnboardDate',r.expected_onboard_date) into v_title,v_context
    from public.hr_recruitment_requisition r where r.id=p_business_id
      and ((select app_private.is_platform_super()) or r.tenant_id=(select app_private.current_user_tenant_id()))
      and r.status in ('draft','rejected');
    if v_title is null then raise exception '招聘需求不存在或当前状态不可提交'; end if;
    return app_private.start_workflow(p_business_type,p_business_id,v_title,v_context,gen_random_uuid()::text);
  end if;
  return public.hr_submit_approval_before_hr_p2(p_business_type,p_business_id);
end $$;
revoke all on function public.hr_submit_approval(text,uuid) from public,anon;
grant execute on function public.hr_submit_approval(text,uuid) to authenticated;

create or replace function public.hr_effect_recruitment_requisition(p_requisition_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_requisition public.hr_recruitment_requisition;
begin
  if not (select app_private.is_platform_super())
     and not (select app_private.has_permission('Hr:Recruitment:Effect')) then
    raise exception '当前账号没有启动招聘的权限' using errcode='42501';
  end if;
  select * into v_requisition from public.hr_recruitment_requisition
  where id=p_requisition_id
    and ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()))
  for update;
  if not found then raise exception '招聘需求不存在'; end if;
  if v_requisition.status<>'approved' then raise exception '只有已批准的招聘需求可以启动'; end if;
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  update public.hr_recruitment_requisition
  set status='effective',update_by=coalesce((select app_private.current_user_email()),'system')
  where id=v_requisition.id;
  return true;
end $$;
revoke all on function public.hr_effect_recruitment_requisition(uuid) from public,anon;
grant execute on function public.hr_effect_recruitment_requisition(uuid) to authenticated;

do $$
declare v_platform uuid:=app_private.platform_tenant_id(); v_parent uuid; v_type uuid; v_group record; v_item record;
begin
  select id into v_parent from public.sys_dict_type where code='hrManage';
  for v_group in select * from (values
    ('hrPerformanceCycleStatus','绩效周期状态',140),('hrPerformanceReviewStatus','绩效考核状态',141),
    ('hrPerformanceLevel','绩效等级',142),('hrTrainingPlanStatus','培训计划状态',143),
    ('hrTrainingEnrollmentStatus','培训参与状态',144),('hrCompetencyCategory','能力类别',145),
    ('hrCompetencyLevel','能力等级',146),('hrRecruitmentStatus','招聘需求状态',147),
    ('hrCandidateStage','候选人阶段',148),('hrCandidateSource','候选人来源',149)
  ) as x(code,name,sort) loop
    insert into public.sys_dict_type(name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort)
    values(v_group.name,v_group.code,'1','624944977@qq.com','624944977@qq.com',v_platform,v_parent,'dictionary',v_group.sort)
    on conflict(code) do update set name=excluded.name,status='1',parent_id=excluded.parent_id,
      sort=excluded.sort,update_by='624944977@qq.com',update_time=now();
  end loop;
  for v_item in select * from (values
    ('hrPerformanceCycleStatus','draft','草稿',1,'info'),('hrPerformanceCycleStatus','active','进行中',2,'primary'),
    ('hrPerformanceCycleStatus','reviewing','评议中',3,'warning'),('hrPerformanceCycleStatus','completed','已完成',4,'success'),
    ('hrPerformanceCycleStatus','cancelled','已取消',5,'info'),
    ('hrPerformanceReviewStatus','draft','草稿',1,'info'),('hrPerformanceReviewStatus','self_review','员工自评',2,'primary'),
    ('hrPerformanceReviewStatus','manager_review','主管评价',3,'warning'),('hrPerformanceReviewStatus','confirmed','结果确认',4,'success'),
    ('hrPerformanceReviewStatus','completed','已归档',5,'success'),('hrPerformanceReviewStatus','cancelled','已取消',6,'info'),
    ('hrPerformanceLevel','s','卓越',1,'success'),('hrPerformanceLevel','a','优秀',2,'success'),
    ('hrPerformanceLevel','b','良好',3,'primary'),('hrPerformanceLevel','c','待改进',4,'warning'),
    ('hrPerformanceLevel','d','不合格',5,'danger'),
    ('hrTrainingPlanStatus','draft','草稿',1,'info'),('hrTrainingPlanStatus','published','已发布',2,'primary'),
    ('hrTrainingPlanStatus','in_progress','进行中',3,'warning'),('hrTrainingPlanStatus','completed','已完成',4,'success'),
    ('hrTrainingPlanStatus','cancelled','已取消',5,'info'),
    ('hrTrainingEnrollmentStatus','enrolled','已报名',1,'primary'),('hrTrainingEnrollmentStatus','attending','学习中',2,'warning'),
    ('hrTrainingEnrollmentStatus','passed','通过',3,'success'),('hrTrainingEnrollmentStatus','failed','未通过',4,'danger'),
    ('hrTrainingEnrollmentStatus','withdrawn','已退出',5,'info'),
    ('hrCompetencyCategory','professional','专业能力',1,'primary'),('hrCompetencyCategory','management','管理能力',2,'warning'),
    ('hrCompetencyCategory','safety','安全能力',3,'danger'),('hrCompetencyCategory','general','通用能力',4,'info'),
    ('hrCompetencyLevel','basic','基础',1,'info'),('hrCompetencyLevel','intermediate','熟练',2,'primary'),
    ('hrCompetencyLevel','advanced','高级',3,'success'),('hrCompetencyLevel','expert','专家',4,'warning'),
    ('hrRecruitmentStatus','draft','草稿',1,'info'),('hrRecruitmentStatus','pending','审批中',2,'warning'),
    ('hrRecruitmentStatus','approved','已批准',3,'success'),('hrRecruitmentStatus','effective','招聘中',4,'primary'),
    ('hrRecruitmentStatus','rejected','已驳回',5,'danger'),('hrRecruitmentStatus','cancelled','已取消',6,'info'),
    ('hrCandidateStage','new','新候选人',1,'info'),('hrCandidateStage','screening','简历筛选',2,'primary'),
    ('hrCandidateStage','interview','面试中',3,'warning'),('hrCandidateStage','offer','Offer',4,'success'),
    ('hrCandidateStage','hired','已录用',5,'success'),('hrCandidateStage','rejected','未录用',6,'danger'),
    ('hrCandidateStage','withdrawn','已放弃',7,'info'),
    ('hrCandidateSource','referral','内部推荐',1,'success'),('hrCandidateSource','job_board','招聘平台',2,'primary'),
    ('hrCandidateSource','campus','校园招聘',3,'warning'),('hrCandidateSource','agency','猎头机构',4,'info'),
    ('hrCandidateSource','other','其他',5,'info')
  ) as x(type_code,value,label,sort,tag_type) loop
    select id into v_type from public.sys_dict_type where code=v_item.type_code;
    update public.sys_dictionary set label=v_item.label,sort=v_item.sort,tag_type=v_item.tag_type,status='1',
      update_by='624944977@qq.com',update_time=now() where type_id=v_type and value=v_item.value;
    if not found then insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
      values(v_type,v_item.type_code||'_'||v_item.value,'1','624944977@qq.com','624944977@qq.com',
        v_item.value,v_item.label,v_item.sort,v_platform,v_item.tag_type); end if;
  end loop;
  select id into v_type from public.sys_dict_type where code='workflowBusinessType';
  if v_type is not null and not exists(select 1 from public.sys_dictionary where type_id=v_type and value='hr_recruitment_requisition') then
    insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
    values(v_type,'workflowBusinessType_hr_recruitment_requisition','1','624944977@qq.com','624944977@qq.com',
      'hr_recruitment_requisition','招聘需求',83,v_platform,'warning');
  end if;
end $$;

do $$
declare v_root uuid:='1acf51bb-89c8-4353-be35-aca6aefd9e37';
  v_talent uuid:='c0de0000-0000-4000-8000-000000000300';
  v_recruit uuid:='c0de0000-0000-4000-8000-000000000400'; v_page record; v_button record;
begin
  insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by) values
  (v_talent,v_root,'HrTalent','talent','','folder',3,
    jsonb_build_object('title','人才发展','icon','ri:graduation-cap-line','roles',jsonb_build_array('R_SUPER','R_ADMIN'),
      'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,
      'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
    '624944977@qq.com','624944977@qq.com'),
  (v_recruit,v_root,'HrRecruitmentFolder','recruitment','','folder',4,
    jsonb_build_object('title','招聘管理','icon','ri:user-search-line','roles',jsonb_build_array('R_SUPER','R_ADMIN'),
      'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,
      'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
    '624944977@qq.com','624944977@qq.com')
  on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,type=excluded.type,
    sort=excluded.sort,meta=excluded.meta,update_by='624944977@qq.com',update_time=now();
  for v_page in select * from (values
    ('c0de0000-0000-4000-8000-000000000301'::uuid,v_talent,'HrPerformance','performance','/hr/talent/performance','绩效考核','ri:bar-chart-box-line',1),
    ('c0de0000-0000-4000-8000-000000000302'::uuid,v_talent,'HrTalentDevelopment','development','/hr/talent/development','培训与能力','ri:book-open-line',2),
    ('c0de0000-0000-4000-8000-000000000401'::uuid,v_recruit,'HrRecruitment','workbench','/hr/recruitment/workbench','招聘工作台','ri:user-add-line',1)
  ) as x(id,parent_id,name,path,component,title,icon,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_page.id,v_page.parent_id,v_page.name,v_page.path,v_page.component,'menu',v_page.sort,
      jsonb_build_object('title',v_page.title,'icon',v_page.icon,'roles',jsonb_build_array('R_SUPER','R_ADMIN'),
        'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,
        'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,
      component=excluded.component,type=excluded.type,sort=excluded.sort,meta=excluded.meta,
      update_by='624944977@qq.com',update_time=now();
  end loop;
  for v_button in select * from (values
    ('c0de0000-0000-4000-8301-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000301'::uuid,'Hr:Performance:View','查看绩效',1),
    ('c0de0000-0000-4000-8301-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000301'::uuid,'Hr:Performance:Add','新增绩效',2),
    ('c0de0000-0000-4000-8301-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000301'::uuid,'Hr:Performance:Edit','编辑绩效',3),
    ('c0de0000-0000-4000-8301-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000301'::uuid,'Hr:Performance:Delete','删除绩效',4),
    ('c0de0000-0000-4000-8302-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000302'::uuid,'Hr:Talent:View','查看人才发展',1),
    ('c0de0000-0000-4000-8302-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000302'::uuid,'Hr:Talent:Add','新增人才发展记录',2),
    ('c0de0000-0000-4000-8302-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000302'::uuid,'Hr:Talent:Edit','编辑人才发展记录',3),
    ('c0de0000-0000-4000-8302-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000302'::uuid,'Hr:Talent:Delete','删除人才发展记录',4),
    ('c0de0000-0000-4000-8401-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:View','查看招聘',1),
    ('c0de0000-0000-4000-8401-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:Add','新增招聘记录',2),
    ('c0de0000-0000-4000-8401-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:Edit','编辑招聘记录',3),
    ('c0de0000-0000-4000-8401-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:Delete','删除招聘记录',4),
    ('c0de0000-0000-4000-8401-000000000005'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:Submit','提交招聘审批',5),
    ('c0de0000-0000-4000-8401-000000000006'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid,'Hr:Recruitment:Effect','启动招聘',6)
  ) as x(id,parent_id,name,title,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_button.id,v_button.parent_id,v_button.name,'','','button',v_button.sort,
      jsonb_build_object('title',v_button.title,'icon','','roles',jsonb_build_array('R_SUPER','R_ADMIN'),'is_enable',true),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,type='button',sort=excluded.sort,
      meta=excluded.meta,update_by='624944977@qq.com',update_time=now();
  end loop;
  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm join public.sys_role r on r.id=rm.role_id
  join public.sys_menu m on m.id in (v_talent,v_recruit,
    'c0de0000-0000-4000-8000-000000000301'::uuid,'c0de0000-0000-4000-8000-000000000302'::uuid,
    'c0de0000-0000-4000-8000-000000000401'::uuid)
  where rm.menu_id=v_root on conflict(role_id,menu_id) do nothing;
  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,b.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm join public.sys_role r on r.id=rm.role_id
  join public.sys_menu b on b.parent_id=rm.menu_id and b.type='button'
  where rm.menu_id in ('c0de0000-0000-4000-8000-000000000301'::uuid,
    'c0de0000-0000-4000-8000-000000000302'::uuid,'c0de0000-0000-4000-8000-000000000401'::uuid)
  on conflict(role_id,menu_id) do nothing;
end $$;

do $$
declare v_tenant record; v_def uuid; v_ver uuid; v_config jsonb;
begin
  for v_tenant in select distinct r.tenant_id,r.role_code from public.sys_role r
    join public.sys_role_menu rm on rm.role_id=r.id
    where r.enabled and rm.menu_id='c0de0000-0000-4000-8401-000000000005'::uuid
      and r.tenant_id<>app_private.platform_tenant_id()
      and not exists(select 1 from public.sys_role x join public.sys_role_menu xm on xm.role_id=x.id
        where x.tenant_id=r.tenant_id and x.enabled and xm.menu_id=rm.menu_id and x.role_code<r.role_code)
  loop
    if not exists(select 1 from public.wf_definition where tenant_id=v_tenant.tenant_id and code='HRRecruitmentDefault') then
      v_def:=gen_random_uuid(); v_ver:=gen_random_uuid();
      v_config:=jsonb_build_object('allowAutoApprove',false,'nodes',jsonb_build_array(jsonb_build_object(
        'key','node_hr_recruitment','name','招聘编制审批','order',1,'approvalMode','any','approvalThresholdPercent',100,
        'rejectVetoEnabled',true,'allowSelfApproval',true,'dueHours',24,'reminderBeforeMinutes',60,
        'escalationEnabled',true,'escalateAfterHours',4,
        'assignee',jsonb_build_object('type','roles','userIds','[]'::jsonb,'roleCodes',jsonb_build_array(v_tenant.role_code)),
        'condition',jsonb_build_object('operator','always'))));
      insert into public.wf_definition(id,code,name,business_type,description,status,published_at,published_by,
        create_by,update_by,tenant_id) values(v_def,'HRRecruitmentDefault','招聘需求默认审批','hr_recruitment_requisition',
        '招聘需求和编制确认默认审批。','published',now(),'624944977@qq.com','624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
      insert into public.wf_version(id,definition_id,version_no,status,config,change_note,published_at,published_by,
        create_by,update_by,tenant_id) values(v_ver,v_def,1,'published',v_config,'初始化 HR 默认流程',now(),
        '624944977@qq.com','624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
      update public.wf_definition set current_version_id=v_ver where id=v_def;
    end if;
  end loop;
end $$;
;
