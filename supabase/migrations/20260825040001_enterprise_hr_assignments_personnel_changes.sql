-- Effective-dated assignments and authoritative personnel-change snapshots.

create table public.hr_employee_assignment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  job_profile_id uuid not null,
  grade_id uuid,
  business_title text,
  assignment_status text not null default 'active',
  primary_assignment boolean not null default true,
  fte numeric(5,4) not null default 1,
  effective_start date not null,
  effective_end date,
  source_type text not null default 'employee_profile',
  source_change_id uuid,
  version integer not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_assignment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_assignment_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_assignment_organization_fkey foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_employee_assignment_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_employee_assignment_job_profile_fkey foreign key (job_profile_id, tenant_id)
    references public.hr_job_profile(id, tenant_id) on delete restrict,
  constraint hr_employee_assignment_grade_fkey foreign key (grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_employee_assignment_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_assignment_status_check check (
    assignment_status in ('active', 'suspended', 'ended')
  ),
  constraint hr_employee_assignment_dates_check check (
    effective_end is null or effective_end >= effective_start
  ),
  constraint hr_employee_assignment_fte_check check (fte > 0 and fte <= 1),
  constraint hr_employee_assignment_version_positive check (version > 0)
);
create unique index hr_employee_assignment_current_primary_unique
  on public.hr_employee_assignment(tenant_id, employee_id)
  where primary_assignment and effective_end is null;
create index hr_employee_assignment_employee_period_idx
  on public.hr_employee_assignment(tenant_id, employee_id, effective_start desc, effective_end);
create index hr_employee_assignment_position_current_idx
  on public.hr_employee_assignment(tenant_id, position_id, effective_end)
  where effective_end is null;
create index hr_employee_assignment_organization_current_idx
  on public.hr_employee_assignment(tenant_id, organization_id, effective_end)
  where effective_end is null;
create index hr_employee_assignment_job_profile_idx
  on public.hr_employee_assignment(job_profile_id, tenant_id);
create index hr_employee_assignment_grade_idx
  on public.hr_employee_assignment(grade_id, tenant_id) where grade_id is not null;
create index hr_employee_assignment_source_change_idx
  on public.hr_employee_assignment(source_change_id, tenant_id) where source_change_id is not null;
create trigger hr_employee_assignment_create_audit before insert on public.hr_employee_assignment
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_assignment_update_audit before update on public.hr_employee_assignment
for each row execute function public.trg_set_update_time_and_by();
alter table public.hr_employee_assignment enable row level security;
revoke all on public.hr_employee_assignment from anon, authenticated;
grant select on public.hr_employee_assignment to authenticated;
create policy hr_employee_assignment_tenant_select
on public.hr_employee_assignment for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Employee:View'))
      or (select app_private.has_permission('Hr:PersonnelChange:View'))
      or (select app_private.has_permission('Hr:OrganizationPosition:View'))
    )
  )
);
-- Existing employee fields remain a current-state projection during the transition.
insert into public.hr_employee_assignment (
  tenant_id, employee_id, organization_id, position_id, job_profile_id, grade_id,
  business_title, assignment_status, primary_assignment, fte,
  effective_start, effective_end, source_type, create_by, update_by
)
select
  employee_row.tenant_id,
  employee_row.id,
  employee_row.organization_id,
  employee_row.position_id,
  position_row.job_profile_id,
  position_row.grade_id,
  case when nullif(btrim(employee_row.job_title), '') is distinct from profile_row.job_name
    then nullif(btrim(employee_row.job_title), '') else null end,
  case when employee_row.employment_status = 'leave' then 'suspended'
       when employee_row.employment_status = 'terminated' then 'ended'
       else 'active' end,
  true,
  1,
  coalesce(employee_row.hire_date, employee_row.create_time::date, current_date),
  case when employee_row.employment_status = 'terminated'
    then coalesce(employee_row.leave_date, current_date) else null end,
  'migration',
  '624944977@qq.com',
  '624944977@qq.com'
from public.hr_employee employee_row
join public.hr_position position_row
  on position_row.id = employee_row.position_id and position_row.tenant_id = employee_row.tenant_id
join public.hr_job_profile profile_row
  on profile_row.id = position_row.job_profile_id and profile_row.tenant_id = position_row.tenant_id
where employee_row.organization_id is not null;
alter table public.hr_personnel_change
  add column from_job_profile_id uuid,
  add column to_job_profile_id uuid,
  add column from_grade_id uuid,
  add column to_grade_id uuid,
  add column from_business_title text,
  add column to_business_title text,
  add column base_assignment_id uuid,
  add column base_assignment_updated_at timestamptz,
  add column before_assignment_snapshot jsonb not null default '{}'::jsonb,
  add column after_assignment_snapshot jsonb not null default '{}'::jsonb,
  add constraint hr_personnel_change_from_job_profile_fkey
    foreign key (from_job_profile_id, tenant_id)
    references public.hr_job_profile(id, tenant_id) on delete restrict,
  add constraint hr_personnel_change_to_job_profile_fkey
    foreign key (to_job_profile_id, tenant_id)
    references public.hr_job_profile(id, tenant_id) on delete restrict,
  add constraint hr_personnel_change_from_grade_fkey
    foreign key (from_grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  add constraint hr_personnel_change_to_grade_fkey
    foreign key (to_grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  add constraint hr_personnel_change_base_assignment_fkey
    foreign key (base_assignment_id, tenant_id)
    references public.hr_employee_assignment(id, tenant_id) on delete restrict;
create index hr_personnel_change_from_job_profile_idx
  on public.hr_personnel_change(from_job_profile_id, tenant_id) where from_job_profile_id is not null;
create index hr_personnel_change_to_job_profile_idx
  on public.hr_personnel_change(to_job_profile_id, tenant_id) where to_job_profile_id is not null;
create index hr_personnel_change_from_grade_idx
  on public.hr_personnel_change(from_grade_id, tenant_id) where from_grade_id is not null;
create index hr_personnel_change_to_grade_idx
  on public.hr_personnel_change(to_grade_id, tenant_id) where to_grade_id is not null;
create index hr_personnel_change_base_assignment_idx
  on public.hr_personnel_change(base_assignment_id, tenant_id) where base_assignment_id is not null;
create or replace function app_private.hr_assignment_snapshot(p_assignment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'assignmentId', assignment_row.id,
    'assignmentUpdatedAt', assignment_row.update_time,
    'organizationId', assignment_row.organization_id,
    'organizationCode', organization_row.organization_code,
    'organizationName', organization_row.organization_name,
    'positionId', assignment_row.position_id,
    'positionCode', position_row.position_code,
    'positionName', position_row.position_name,
    'jobProfileId', assignment_row.job_profile_id,
    'jobCode', profile_row.job_code,
    'jobName', profile_row.job_name,
    'gradeId', assignment_row.grade_id,
    'gradeCode', grade_row.grade_code,
    'gradeName', grade_row.grade_name,
    'businessTitle', assignment_row.business_title,
    'assignmentStatus', assignment_row.assignment_status,
    'employmentStatus', employee_row.employment_status,
    'effectiveStart', assignment_row.effective_start,
    'fte', assignment_row.fte
  )
  from public.hr_employee_assignment assignment_row
  join public.hr_employee employee_row
    on employee_row.id = assignment_row.employee_id and employee_row.tenant_id = assignment_row.tenant_id
  join public.sys_organization organization_row
    on organization_row.id = assignment_row.organization_id and organization_row.tenant_id = assignment_row.tenant_id
  join public.hr_position position_row
    on position_row.id = assignment_row.position_id and position_row.tenant_id = assignment_row.tenant_id
  join public.hr_job_profile profile_row
    on profile_row.id = assignment_row.job_profile_id and profile_row.tenant_id = assignment_row.tenant_id
  left join public.hr_grade grade_row
    on grade_row.id = assignment_row.grade_id and grade_row.tenant_id = assignment_row.tenant_id
  where assignment_row.id = p_assignment_id;
$function$;
revoke all on function app_private.hr_assignment_snapshot(uuid) from public,anon,authenticated;
create or replace function app_private.sync_hr_employee_primary_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_current public.hr_employee_assignment%rowtype;
  v_effective_date date := current_date;
  v_assignment_status text;
begin
  if coalesce(current_setting('app.hr_assignment_engine', true), '') = 'on' then return new; end if;
  if new.organization_id is null then return new; end if;
  if tg_op = 'UPDATE'
     and new.organization_id is not distinct from old.organization_id
     and new.position_id is not distinct from old.position_id
     and new.employment_status is not distinct from old.employment_status then return new; end if;

  select * into v_position from public.hr_position
  where id = new.position_id and tenant_id = new.tenant_id;
  if not found then raise exception '员工当前岗位不存在或不属于当前租户'; end if;
  v_assignment_status := case when new.employment_status='leave' then 'suspended'
    when new.employment_status='terminated' then 'ended' else 'active' end;

  select * into v_current from public.hr_employee_assignment
  where tenant_id=new.tenant_id and employee_id=new.id and primary_assignment and effective_end is null
  for update;

  if found and v_current.effective_start >= v_effective_date then
    update public.hr_employee_assignment set
      organization_id=new.organization_id, position_id=new.position_id,
      job_profile_id=v_position.job_profile_id, grade_id=v_position.grade_id,
      assignment_status=v_assignment_status,
      effective_end=case when new.employment_status='terminated' then coalesce(new.leave_date,v_effective_date) else null end,
      version=version+1
    where id=v_current.id;
  else
    if found then update public.hr_employee_assignment
      set effective_end=v_effective_date-1,assignment_status='ended',version=version+1
      where id=v_current.id; end if;
    insert into public.hr_employee_assignment(
      tenant_id,employee_id,organization_id,position_id,job_profile_id,grade_id,
      business_title,assignment_status,primary_assignment,fte,effective_start,effective_end,source_type
    ) values(
      new.tenant_id,new.id,new.organization_id,new.position_id,v_position.job_profile_id,v_position.grade_id,
      null,v_assignment_status,true,1,v_effective_date,
      case when new.employment_status='terminated' then coalesce(new.leave_date,v_effective_date) else null end,
      'employee_profile'
    );
  end if;
  return new;
end;
$function$;
revoke all on function app_private.sync_hr_employee_primary_assignment() from public,anon,authenticated;
create trigger hr_employee_sync_primary_assignment
after insert or update of organization_id,position_id,employment_status on public.hr_employee
for each row execute function app_private.sync_hr_employee_primary_assignment();
create or replace function public.hr_list_personnel_change_employees_secure(
  p_from integer default 0, p_to integer default 19, p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from,0),0);
  v_limit integer := least(greatest(coalesce(p_to,19)-greatest(coalesce(p_from,0),0)+1,1),200);
  v_keyword text := nullif(btrim(p_keyword),'');
begin
  if not (
    app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Add',null,false)
    or app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Edit',null,false)
  ) then raise exception 'Missing personnel change write permission' using errcode='42501'; end if;
  return (with filtered as materialized (
    select employee_row.id,employee_row.tenant_id,employee_row.employee_no,employee_row.employee_name,
      employee_row.avatar_url,employee_row.job_title,employee_row.employment_status,
      assignment_row.id as assignment_id,assignment_row.update_time as assignment_updated_at,
      app_private.hr_assignment_snapshot(assignment_row.id) as assignment_snapshot
    from public.hr_employee employee_row
    join public.hr_employee_assignment assignment_row
      on assignment_row.employee_id=employee_row.id and assignment_row.tenant_id=employee_row.tenant_id
     and assignment_row.primary_assignment and assignment_row.effective_end is null
    where employee_row.tenant_id=v_tenant_id and employee_row.employment_status<>'terminated'
      and (v_keyword is null or employee_row.employee_no ilike '%'||v_keyword||'%' or employee_row.employee_name ilike '%'||v_keyword||'%' or employee_row.job_title ilike '%'||v_keyword||'%')
  ), paged as (select * from filtered order by employee_name,employee_no,id offset v_from limit v_limit)
  select jsonb_build_object('records',coalesce((select jsonb_agg(jsonb_build_object(
    'id',id,'tenant_id',tenant_id,'employee_no',employee_no,'employee_name',employee_name,
    'avatar_url',avatar_url,'job_title',job_title,'employment_status',employment_status,
    'assignment_id',assignment_id,'assignment_updated_at',assignment_updated_at,
    'assignment_snapshot',assignment_snapshot
  ) order by employee_name,employee_no,id) from paged),'[]'::jsonb),'total',(select count(*) from filtered)));
end;
$function$;
create or replace function public.hr_list_assignment_position_options_secure(p_organization_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id();
begin
  if not (
    app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Add',null,false)
    or app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Edit',null,false)
    or app_private.can_execute_business_action('HrEmployeeRoster','Hr:Employee:Add',null,false)
    or app_private.can_execute_business_action('HrEmployeeRoster','Hr:Employee:Edit',null,false)
  ) then raise exception 'Missing assignment position permission' using errcode='42501'; end if;
  if p_organization_id is not null and not exists(select 1 from public.sys_organization where id=p_organization_id and tenant_id=v_tenant_id and status='1') then raise exception '所选组织不可用'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',position_row.id,'organization_id',position_row.organization_id,
    'position_code',position_row.position_code,'position_name',position_row.position_name,
    'position_kind',position_row.position_kind,'job_profile_id',position_row.job_profile_id,
    'grade_id',position_row.grade_id,'headcount_limit',position_row.headcount_limit,
    'multiple_incumbents_allowed',position_row.multiple_incumbents_allowed,
    'job_profile',jsonb_build_object('id',profile_row.id,'job_code',profile_row.job_code,'job_name',profile_row.job_name),
    'grade',case when grade_row.id is null then null else jsonb_build_object('id',grade_row.id,'grade_code',grade_row.grade_code,'grade_name',grade_row.grade_name) end
  ) order by position_row.sort,position_row.position_name)
  from public.hr_position position_row
  join public.hr_job_profile profile_row on profile_row.id=position_row.job_profile_id and profile_row.tenant_id=position_row.tenant_id
  left join public.hr_grade grade_row on grade_row.id=position_row.grade_id and grade_row.tenant_id=position_row.tenant_id
  where position_row.tenant_id=v_tenant_id and position_row.enabled
    and (p_organization_id is null or position_row.organization_id=p_organization_id or position_row.organization_id is null)
  ),'[]'::jsonb);
end;
$function$;
create or replace function public.hr_save_personnel_change_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid:=nullif(p_payload->>'id','')::uuid;
  v_existing public.hr_personnel_change%rowtype;
  v_assignment public.hr_employee_assignment%rowtype;
  v_employee public.hr_employee%rowtype;
  v_position public.hr_position%rowtype;
  v_profile public.hr_job_profile%rowtype;
  v_grade public.hr_grade%rowtype;
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_employee_id uuid:=nullif(p_payload->>'employee_id','')::uuid;
  v_change_type text:=nullif(btrim(p_payload->>'change_type'),'');
  v_effective_date date:=nullif(p_payload->>'effective_date','')::date;
  v_to_organization_id uuid:=nullif(p_payload->>'to_organization_id','')::uuid;
  v_to_position_id uuid:=nullif(p_payload->>'to_position_id','')::uuid;
  v_to_job_profile_id uuid:=nullif(p_payload->>'to_job_profile_id','')::uuid;
  v_to_grade_id uuid:=nullif(p_payload->>'to_grade_id','')::uuid;
  v_to_business_title text:=nullif(btrim(p_payload->>'to_business_title'),'');
  v_to_employment_status text:=nullif(btrim(p_payload->>'to_employment_status'),'');
  v_before jsonb;
  v_after jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception '异动数据格式不正确'; end if;
  if v_id is null then
    if not app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Add',null,false) then raise exception 'Missing personnel change create permission' using errcode='42501'; end if;
    select employee_row.* into v_employee from public.hr_employee employee_row
    where employee_row.id=v_employee_id and employee_row.tenant_id=v_tenant_id and employee_row.employment_status<>'terminated'
    for update;
    if not found then raise exception '员工不存在、已离职或超出当前租户'; end if;
    select assignment_row.* into v_assignment from public.hr_employee_assignment assignment_row
    where assignment_row.employee_id=v_employee_id and assignment_row.tenant_id=v_tenant_id and assignment_row.primary_assignment and assignment_row.effective_end is null
    for update;
    if not found then raise exception '员工没有当前有效的主任职记录'; end if;
    v_before:=app_private.hr_assignment_snapshot(v_assignment.id);
  else
    if not app_private.can_execute_business_action('HrPersonnelChange','Hr:PersonnelChange:Edit',null,false) then raise exception 'Missing personnel change edit permission' using errcode='42501'; end if;
    select * into v_existing from public.hr_personnel_change where id=v_id and tenant_id=v_tenant_id for update;
    if not found then raise exception '异动单不存在或无权编辑'; end if;
    if v_existing.status not in ('draft','rejected') then raise exception '仅草稿或已驳回异动单允许编辑'; end if;
    v_employee_id:=v_existing.employee_id;
    v_before:=v_existing.before_assignment_snapshot;
    select * into v_assignment from public.hr_employee_assignment where id=v_existing.base_assignment_id;
    select * into v_employee from public.hr_employee where id=v_employee_id and tenant_id=v_tenant_id;
  end if;

  if v_change_type not in ('regularization','transfer','position_change','promotion','demotion','suspension','reinstatement','termination') then raise exception '请选择有效的异动类型'; end if;
  if v_effective_date is null then raise exception '请选择生效日期'; end if;
  if nullif(btrim(p_payload->>'reason'),'') is null then raise exception '请填写异动原因'; end if;

  if v_to_position_id is not null then
    select * into v_position from public.hr_position where id=v_to_position_id and tenant_id=v_tenant_id and enabled;
    if not found then raise exception '所选新岗位不可用'; end if;
    if v_position.organization_id is not null then v_to_organization_id:=v_position.organization_id; end if;
    v_to_job_profile_id:=v_position.job_profile_id;
    v_to_grade_id:=coalesce(v_to_grade_id,v_position.grade_id);
  end if;
  v_to_organization_id:=coalesce(v_to_organization_id,v_assignment.organization_id);
  v_to_position_id:=coalesce(v_to_position_id,v_assignment.position_id);
  v_to_job_profile_id:=coalesce(v_to_job_profile_id,v_assignment.job_profile_id);
  v_to_grade_id:=coalesce(v_to_grade_id,v_assignment.grade_id);
  v_to_business_title:=coalesce(v_to_business_title,v_assignment.business_title);
  v_to_employment_status:=coalesce(v_to_employment_status,v_employee.employment_status);

  if v_change_type='regularization' then v_to_employment_status:='active'; end if;
  if v_change_type='suspension' then v_to_employment_status:='leave'; end if;
  if v_change_type='reinstatement' then v_to_employment_status:='active'; end if;
  if v_change_type='termination' then v_to_employment_status:='terminated'; end if;
  if v_change_type in ('transfer','position_change') and nullif(p_payload->>'to_position_id','') is null then raise exception '调动或调岗必须选择新岗位'; end if;
  if v_change_type in ('promotion','demotion')
     and nullif(p_payload->>'to_position_id','') is null
     and nullif(p_payload->>'to_job_profile_id','') is null
     and nullif(p_payload->>'to_grade_id','') is null then raise exception '晋升或降职至少需要调整岗位、标准职务或职级'; end if;
  if not exists(select 1 from public.sys_organization where id=v_to_organization_id and tenant_id=v_tenant_id and status='1') then raise exception '目标组织不可用'; end if;
  if not exists(select 1 from public.hr_job_profile where id=v_to_job_profile_id and tenant_id=v_tenant_id and enabled) then raise exception '目标标准职务不可用'; end if;
  if v_to_grade_id is not null and not exists(select 1 from public.hr_grade where id=v_to_grade_id and tenant_id=v_tenant_id and enabled) then raise exception '目标职级不可用'; end if;

  select * into v_position from public.hr_position where id=v_to_position_id and tenant_id=v_tenant_id;
  select * into v_profile from public.hr_job_profile where id=v_to_job_profile_id and tenant_id=v_tenant_id;
  if v_to_grade_id is not null then select * into v_grade from public.hr_grade where id=v_to_grade_id and tenant_id=v_tenant_id; end if;
  v_after:=jsonb_build_object(
    'organizationId',v_to_organization_id,
    'organizationCode',(select organization_code from public.sys_organization where id=v_to_organization_id),
    'organizationName',(select organization_name from public.sys_organization where id=v_to_organization_id),
    'positionId',v_to_position_id,'positionCode',v_position.position_code,'positionName',v_position.position_name,
    'jobProfileId',v_to_job_profile_id,'jobCode',v_profile.job_code,'jobName',v_profile.job_name,
    'gradeId',v_to_grade_id,'gradeCode',v_grade.grade_code,'gradeName',v_grade.grade_name,
    'businessTitle',v_to_business_title,'employmentStatus',v_to_employment_status,
    'effectiveStart',v_effective_date,'fte',v_assignment.fte
  );

  if v_id is null then
    insert into public.hr_personnel_change(
      tenant_id,change_no,employee_id,change_type,effective_date,status,
      from_organization_id,to_organization_id,from_position_id,to_position_id,
      from_employment_status,to_employment_status,from_job_title,to_job_title,
      from_job_profile_id,to_job_profile_id,from_grade_id,to_grade_id,
      from_business_title,to_business_title,base_assignment_id,base_assignment_updated_at,
      before_assignment_snapshot,after_assignment_snapshot,reason,remark
    ) values(
      v_tenant_id,btrim(p_payload->>'change_no'),v_employee_id,v_change_type,v_effective_date,'draft',
      v_assignment.organization_id,v_to_organization_id,v_assignment.position_id,v_to_position_id,
      v_employee.employment_status,v_to_employment_status,v_before->>'jobName',v_after->>'jobName',
      v_assignment.job_profile_id,v_to_job_profile_id,v_assignment.grade_id,v_to_grade_id,
      v_assignment.business_title,v_to_business_title,v_assignment.id,v_assignment.update_time,
      v_before,v_after,btrim(p_payload->>'reason'),nullif(btrim(p_payload->>'remark'),'')
    ) returning id into v_id;
  else
    update public.hr_personnel_change set
      change_no=btrim(p_payload->>'change_no'),change_type=v_change_type,effective_date=v_effective_date,
      to_organization_id=v_to_organization_id,to_position_id=v_to_position_id,
      to_employment_status=v_to_employment_status,to_job_title=v_after->>'jobName',
      to_job_profile_id=v_to_job_profile_id,to_grade_id=v_to_grade_id,
      to_business_title=v_to_business_title,after_assignment_snapshot=v_after,
      reason=btrim(p_payload->>'reason'),remark=nullif(btrim(p_payload->>'remark'),'')
    where id=v_id;
  end if;
  return v_id;
end;
$function$;
create or replace function public.hr_effect_personnel_change(p_change_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_change public.hr_personnel_change%rowtype;
  v_employee public.hr_employee%rowtype;
  v_current public.hr_employee_assignment%rowtype;
  v_assignment_status text;
  v_actor text;
begin
  if not app_private.is_platform_super() and not app_private.has_permission('Hr:PersonnelChange:Effect') then raise exception '当前账号没有生效人事异动的权限' using errcode='42501'; end if;
  select * into v_change from public.hr_personnel_change where id=p_change_id and (app_private.is_platform_super() or tenant_id=app_private.current_user_tenant_id()) for update;
  if not found then raise exception '人事异动单不存在'; end if;
  if v_change.status<>'approved' then raise exception '只有已批准异动单可以生效'; end if;
  if v_change.effective_date>current_date then raise exception '尚未到异动生效日期'; end if;
  select * into v_employee from public.hr_employee where id=v_change.employee_id and tenant_id=v_change.tenant_id for update;
  if not found then raise exception '异动员工不存在'; end if;
  select * into v_current from public.hr_employee_assignment where tenant_id=v_change.tenant_id and employee_id=v_change.employee_id and primary_assignment and effective_end is null for update;
  if not found then raise exception '员工没有当前有效的主任职记录'; end if;
  if v_current.id is distinct from v_change.base_assignment_id or v_current.update_time is distinct from v_change.base_assignment_updated_at then raise exception '员工当前任职已发生变化，请撤回后重新创建异动单'; end if;
  if v_change.effective_date<v_current.effective_start then raise exception '生效日期不能早于当前任职开始日期'; end if;

  if v_change.effective_date=v_current.effective_start then
    delete from public.hr_employee_assignment where id=v_current.id;
  else
    update public.hr_employee_assignment set effective_end=v_change.effective_date-1,assignment_status='ended',version=version+1 where id=v_current.id;
  end if;
  v_assignment_status:=case when v_change.to_employment_status='leave' then 'suspended' else 'active' end;
  if v_change.to_employment_status<>'terminated' then
    insert into public.hr_employee_assignment(
      tenant_id,employee_id,organization_id,position_id,job_profile_id,grade_id,business_title,
      assignment_status,primary_assignment,fte,effective_start,source_type,source_change_id
    ) values(
      v_change.tenant_id,v_change.employee_id,v_change.to_organization_id,v_change.to_position_id,
      v_change.to_job_profile_id,v_change.to_grade_id,v_change.to_business_title,
      v_assignment_status,true,v_current.fte,v_change.effective_date,'personnel_change',v_change.id
    );
  end if;

  perform pg_catalog.set_config('app.hr_assignment_engine','on',true);
  update public.hr_employee set
    organization_id=coalesce(v_change.to_organization_id,organization_id),
    position_id=coalesce(v_change.to_position_id,position_id),
    employment_status=coalesce(v_change.to_employment_status,employment_status),
    job_title=coalesce(v_change.to_business_title,v_change.after_assignment_snapshot->>'jobName',job_title),
    leave_date=case when v_change.to_employment_status='terminated' then v_change.effective_date else leave_date end
  where id=v_change.employee_id and tenant_id=v_change.tenant_id;

  v_actor:=coalesce((select user_email from public.sys_user where id=app_private.current_app_user_id()),auth.uid()::text,'system');
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  update public.hr_personnel_change set status='effective',effected_at=now(),effected_by=v_actor where id=v_change.id;
  return true;
end;
$function$;
revoke all on function public.hr_list_personnel_change_employees_secure(integer,integer,text) from public,anon;
revoke all on function public.hr_list_assignment_position_options_secure(uuid) from public,anon;
revoke all on function public.hr_save_personnel_change_secure(jsonb) from public,anon;
revoke all on function public.hr_effect_personnel_change(uuid) from public,anon;
grant execute on function public.hr_list_personnel_change_employees_secure(integer,integer,text) to authenticated,service_role;
grant execute on function public.hr_list_assignment_position_options_secure(uuid) to authenticated,service_role;
grant execute on function public.hr_save_personnel_change_secure(jsonb) to authenticated,service_role;
grant execute on function public.hr_effect_personnel_change(uuid) to authenticated,service_role;
