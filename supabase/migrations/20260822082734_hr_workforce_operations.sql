-- HR P1: headcount, attendance/scheduling and employee self service.

create table if not exists public.hr_position_headcount (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  organization_id uuid not null,
  position_id uuid not null,
  approved_count integer not null default 0,
  effective_from date not null default current_date,
  effective_to date,
  enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_position_headcount_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_position_headcount_organization_fkey foreign key (organization_id)
    references public.sys_organization(id) on delete restrict,
  constraint hr_position_headcount_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_position_headcount_count_check check (approved_count >= 0),
  constraint hr_position_headcount_dates_check check (effective_to is null or effective_to >= effective_from),
  constraint hr_position_headcount_scope_unique unique (tenant_id,organization_id,position_id,effective_from)
);

create table if not exists public.hr_shift (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  shift_code text not null,
  shift_name text not null,
  shift_type text not null default 'regular',
  start_time time not null,
  end_time time not null,
  break_minutes integer not null default 0,
  cross_day boolean not null default false,
  enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_shift_tenant_fkey foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint hr_shift_break_check check (break_minutes between 0 and 720),
  constraint hr_shift_code_unique unique (tenant_id,shift_code),
  constraint hr_shift_id_tenant_unique unique (id,tenant_id)
);

create table if not exists public.hr_shift_assignment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  shift_id uuid not null,
  work_date date not null,
  assignment_status text not null default 'scheduled',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_shift_assignment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_shift_assignment_employee_fkey foreign key (employee_id,tenant_id)
    references public.hr_employee(id,tenant_id) on delete cascade,
  constraint hr_shift_assignment_shift_fkey foreign key (shift_id,tenant_id)
    references public.hr_shift(id,tenant_id) on delete restrict,
  constraint hr_shift_assignment_status_check check (assignment_status in ('scheduled','worked','leave','cancelled')),
  constraint hr_shift_assignment_unique unique (tenant_id,employee_id,work_date)
);

create table if not exists public.hr_attendance_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  shift_id uuid,
  work_date date not null,
  clock_in_at timestamptz,
  clock_out_at timestamptz,
  work_minutes integer not null default 0,
  overtime_minutes integer not null default 0,
  attendance_status text not null default 'normal',
  source text not null default 'manual',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_attendance_record_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_attendance_record_employee_fkey foreign key (employee_id,tenant_id)
    references public.hr_employee(id,tenant_id) on delete cascade,
  constraint hr_attendance_record_shift_fkey foreign key (shift_id,tenant_id)
    references public.hr_shift(id,tenant_id) on delete restrict,
  constraint hr_attendance_minutes_check check (work_minutes >= 0 and overtime_minutes >= 0),
  constraint hr_attendance_clock_check check (clock_out_at is null or clock_in_at is null or clock_out_at >= clock_in_at),
  constraint hr_attendance_record_unique unique (tenant_id,employee_id,work_date)
);

create table if not exists public.hr_self_service_request (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  request_no text not null,
  employee_id uuid not null,
  request_type text not null,
  title text not null,
  start_at timestamptz,
  end_at timestamptz,
  duration_hours numeric(10,2),
  reason text not null,
  request_data jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  workflow_instance_id uuid,
  reviewed_at timestamptz,
  reviewed_by text,
  review_comment text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_self_service_request_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_self_service_request_employee_fkey foreign key (employee_id,tenant_id)
    references public.hr_employee(id,tenant_id) on delete cascade,
  constraint hr_self_service_request_status_check check (
    status in ('draft','pending','approved','effective','rejected','cancelled')
  ),
  constraint hr_self_service_request_dates_check check (end_at is null or start_at is null or end_at >= start_at),
  constraint hr_self_service_request_duration_check check (duration_hours is null or duration_hours >= 0),
  constraint hr_self_service_request_no_unique unique (tenant_id,request_no)
);

create index if not exists idx_hr_position_headcount_scope
  on public.hr_position_headcount(tenant_id,organization_id,position_id,enabled);

create or replace view public.hr_position_headcount_overview
with (security_invoker=true)
as
select h.*,
  jsonb_build_object('id',o.id,'organizationCode',o.organization_code,
    'organizationName',o.organization_name) as organization,
  jsonb_build_object('id',p.id,'positionCode',p.position_code,
    'positionName',p.position_name) as position,
  count(e.id) filter (where e.employment_status<>'terminated')::integer as occupied_count,
  greatest(h.approved_count-count(e.id) filter (where e.employment_status<>'terminated'),0)::integer
    as vacancy_count
from public.hr_position_headcount h
join public.sys_organization o on o.id=h.organization_id
join public.hr_position p on p.id=h.position_id and p.tenant_id=h.tenant_id
left join public.hr_employee e on e.tenant_id=h.tenant_id and e.organization_id=h.organization_id
  and e.position_id=h.position_id
group by h.id,o.id,o.organization_code,o.organization_name,p.id,p.position_code,p.position_name;
grant select on public.hr_position_headcount_overview to authenticated;
create index if not exists idx_hr_shift_assignment_date
  on public.hr_shift_assignment(tenant_id,work_date,employee_id);
create index if not exists idx_hr_attendance_record_date
  on public.hr_attendance_record(tenant_id,work_date,attendance_status);
create index if not exists idx_hr_self_service_request_employee
  on public.hr_self_service_request(tenant_id,employee_id,create_time desc);
create index if not exists idx_hr_self_service_request_status
  on public.hr_self_service_request(tenant_id,status,request_type,create_time desc);

create trigger hr_position_headcount_create_audit before insert on public.hr_position_headcount
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger hr_position_headcount_update_audit before update on public.hr_position_headcount
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_shift_create_audit before insert on public.hr_shift
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger hr_shift_update_audit before update on public.hr_shift
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_shift_assignment_create_audit before insert on public.hr_shift_assignment
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger hr_shift_assignment_update_audit before update on public.hr_shift_assignment
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_attendance_record_create_audit before insert on public.hr_attendance_record
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger hr_attendance_record_update_audit before update on public.hr_attendance_record
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_self_service_request_create_audit before insert on public.hr_self_service_request
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger hr_self_service_request_update_audit before update on public.hr_self_service_request
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_self_service_request_guard before update or delete on public.hr_self_service_request
for each row execute function app_private.hr_guard_approval_record();

alter table public.hr_position_headcount enable row level security;
alter table public.hr_shift enable row level security;
alter table public.hr_shift_assignment enable row level security;
alter table public.hr_attendance_record enable row level security;
alter table public.hr_self_service_request enable row level security;

grant select,insert,update,delete on public.hr_position_headcount,public.hr_shift,
  public.hr_shift_assignment,public.hr_attendance_record,public.hr_self_service_request to authenticated;

create policy hr_position_headcount_tenant_select on public.hr_position_headcount for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Headcount:View'))));
create policy hr_position_headcount_tenant_insert on public.hr_position_headcount for insert to authenticated
with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission('Hr:Headcount:Add')));
create policy hr_position_headcount_tenant_update on public.hr_position_headcount for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Headcount:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()));
create policy hr_position_headcount_tenant_delete on public.hr_position_headcount for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Headcount:Delete'))));

create policy hr_shift_tenant_select on public.hr_shift for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:View'))));
create policy hr_shift_tenant_insert on public.hr_shift for insert to authenticated
with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission('Hr:Attendance:Add')));
create policy hr_shift_tenant_update on public.hr_shift for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()));
create policy hr_shift_tenant_delete on public.hr_shift for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Delete'))));

create policy hr_shift_assignment_tenant_select on public.hr_shift_assignment for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:View'))));
create policy hr_shift_assignment_tenant_insert on public.hr_shift_assignment for insert to authenticated
with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission('Hr:Attendance:Add')));
create policy hr_shift_assignment_tenant_update on public.hr_shift_assignment for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()));
create policy hr_shift_assignment_tenant_delete on public.hr_shift_assignment for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Delete'))));

create policy hr_attendance_record_tenant_select on public.hr_attendance_record for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and ((select app_private.has_permission('Hr:Attendance:View')) or employee_id=(
    select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
  ))));
create policy hr_attendance_record_tenant_insert on public.hr_attendance_record for insert to authenticated
with check (tenant_id=(select app_private.current_user_tenant_id()) and (select app_private.has_permission('Hr:Attendance:Add')));
create policy hr_attendance_record_tenant_update on public.hr_attendance_record for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Edit'))))
with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()));
create policy hr_attendance_record_tenant_delete on public.hr_attendance_record for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Attendance:Delete'))));

create policy hr_self_service_request_tenant_select on public.hr_self_service_request for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (
  (select app_private.has_permission('Hr:SelfService:View')) or employee_id=(
    select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
  ))));
create policy hr_self_service_request_tenant_insert on public.hr_self_service_request for insert to authenticated
with check (tenant_id=(select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:SelfService:Add'))
  and ((select app_private.has_permission('Hr:SelfService:Manage')) or employee_id=(
    select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
  )));
create policy hr_self_service_request_tenant_update on public.hr_self_service_request for update to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (
  (select app_private.has_permission('Hr:SelfService:Manage')) or employee_id=(
    select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
  ))))
with check ((select app_private.is_platform_super()) or tenant_id=(select app_private.current_user_tenant_id()));
create policy hr_self_service_request_tenant_delete on public.hr_self_service_request for delete to authenticated
using ((select app_private.is_platform_super()) or (tenant_id=(select app_private.current_user_tenant_id()) and (
  (select app_private.has_permission('Hr:SelfService:Manage')) or employee_id=(
    select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
  ))));

create or replace function app_private.execute_hr_self_service_workflow_callback(
  p_business_id uuid,p_status text,p_actor text,p_comment text
) returns void language plpgsql security definer set search_path=''
as $$
begin
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  update public.hr_self_service_request
  set status=case p_status when 'running' then 'pending' when 'approved' then 'approved'
      when 'rejected' then 'rejected' when 'withdrawn' then 'draft'
      when 'cancelled' then 'cancelled' else status end,
    workflow_instance_id=coalesce(workflow_instance_id,(
      select i.id from public.wf_instance i where i.tenant_id=hr_self_service_request.tenant_id
        and i.business_type='hr_self_service_request' and i.business_id=p_business_id
      order by i.started_at desc limit 1)),
    reviewed_at=case when p_status in ('approved','rejected') then now() else reviewed_at end,
    reviewed_by=case when p_status in ('approved','rejected') then p_actor else reviewed_by end,
    review_comment=case when p_status in ('approved','rejected','cancelled')
      then nullif(btrim(coalesce(p_comment,'')),'') else review_comment end
  where id=p_business_id;
  if not found then raise exception '员工自助申请不存在或已删除'; end if;
end $$;

alter function app_private.execute_workflow_business_callback(text,uuid,text,text,text)
  rename to execute_workflow_business_callback_before_hr_p1;
create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,p_business_id uuid,p_status text,p_actor text,p_comment text
) returns void language plpgsql security definer set search_path=''
as $$
begin
  if p_business_type='hr_self_service_request' then
    perform app_private.execute_hr_self_service_workflow_callback(p_business_id,p_status,p_actor,p_comment);
  else
    perform app_private.execute_workflow_business_callback_before_hr_p1(
      p_business_type,p_business_id,p_status,p_actor,p_comment);
  end if;
end $$;

alter function public.hr_submit_approval(text,uuid) rename to hr_submit_approval_before_hr_p1;
create or replace function public.hr_submit_approval(p_business_type text,p_business_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_permission text; v_title text; v_context jsonb:='{}'::jsonb;
begin
  if p_business_type='hr_self_service_request' then
    v_permission:='Hr:SelfService:Submit';
    select '员工申请 '||r.request_no,jsonb_build_object('requestNo',r.request_no,'requestType',r.request_type,
      'employeeId',r.employee_id,'durationHours',r.duration_hours,'startAt',r.start_at,'endAt',r.end_at)
    into v_title,v_context from public.hr_self_service_request r
    where r.id=p_business_id and r.tenant_id=(select app_private.current_user_tenant_id())
      and r.status in ('draft','rejected') and (
        (select app_private.has_permission('Hr:SelfService:Manage')) or r.employee_id=(
          select u.hr_employee_id from public.sys_user u where u.id=(select app_private.current_app_user_id())
        ));
    if v_title is null then raise exception '申请不存在或当前状态不可提交'; end if;
    if not (select app_private.is_platform_super()) and not (select app_private.has_permission(v_permission)) then
      raise exception '当前账号没有提交员工申请的权限' using errcode='42501';
    end if;
    return app_private.start_workflow(p_business_type,p_business_id,v_title,v_context,gen_random_uuid()::text);
  end if;
  return public.hr_submit_approval_before_hr_p1(p_business_type,p_business_id);
end $$;

revoke all on function public.hr_submit_approval(text,uuid) from public,anon;
grant execute on function public.hr_submit_approval(text,uuid) to authenticated;

do $$
declare v_platform uuid:=app_private.platform_tenant_id(); v_parent uuid; v_type uuid;
  v_group record; v_item record;
begin
  select id into v_parent from public.sys_dict_type where code='hrManage';
  for v_group in select * from (values
    ('hrShiftType','班次类型',120),('hrShiftAssignmentStatus','排班状态',121),
    ('hrAttendanceStatus','考勤状态',122),('hrAttendanceSource','考勤来源',123),
    ('hrSelfServiceRequestType','员工申请类型',124)
  ) as x(code,name,sort) loop
    insert into public.sys_dict_type(name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort)
    values(v_group.name,v_group.code,'1','624944977@qq.com','624944977@qq.com',v_platform,v_parent,'dictionary',v_group.sort)
    on conflict(code) do update set name=excluded.name,status='1',parent_id=excluded.parent_id,
      sort=excluded.sort,update_by='624944977@qq.com',update_time=now();
  end loop;
  for v_item in select * from (values
    ('hrShiftType','regular','常规班',1,'primary'),('hrShiftType','morning','早班',2,'success'),
    ('hrShiftType','evening','晚班',3,'warning'),('hrShiftType','night','夜班',4,'info'),
    ('hrShiftType','flexible','弹性班',5,'primary'),
    ('hrShiftAssignmentStatus','scheduled','已排班',1,'primary'),('hrShiftAssignmentStatus','worked','已出勤',2,'success'),
    ('hrShiftAssignmentStatus','leave','请假',3,'warning'),('hrShiftAssignmentStatus','cancelled','已取消',4,'info'),
    ('hrAttendanceStatus','normal','正常',1,'success'),('hrAttendanceStatus','late','迟到',2,'warning'),
    ('hrAttendanceStatus','early_leave','早退',3,'warning'),('hrAttendanceStatus','absent','缺勤',4,'danger'),
    ('hrAttendanceStatus','leave','请假',5,'info'),('hrAttendanceStatus','business_trip','出差',6,'primary'),
    ('hrAttendanceSource','manual','人工录入',1,'info'),('hrAttendanceSource','device','考勤设备',2,'primary'),
    ('hrAttendanceSource','tms','运输系统汇总',3,'success'),('hrAttendanceSource','import','批量导入',4,'warning'),
    ('hrSelfServiceRequestType','leave','请假',1,'warning'),('hrSelfServiceRequestType','overtime','加班',2,'primary'),
    ('hrSelfServiceRequestType','profile_change','档案信息变更',3,'info'),
    ('hrSelfServiceRequestType','proof','证明申请',4,'success'),
    ('hrSelfServiceRequestType','transfer','调动申请',5,'primary'),
    ('hrSelfServiceRequestType','other','其他申请',6,'info')
  ) as x(type_code,value,label,sort,tag_type) loop
    select id into v_type from public.sys_dict_type where code=v_item.type_code;
    update public.sys_dictionary set label=v_item.label,sort=v_item.sort,tag_type=v_item.tag_type,status='1',
      update_by='624944977@qq.com',update_time=now() where type_id=v_type and value=v_item.value;
    if not found then
      insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
      values(v_type,v_item.type_code||'_'||v_item.value,'1','624944977@qq.com','624944977@qq.com',
        v_item.value,v_item.label,v_item.sort,v_platform,v_item.tag_type);
    end if;
  end loop;
  select id into v_type from public.sys_dict_type where code='workflowBusinessType';
  if v_type is not null and not exists(select 1 from public.sys_dictionary where type_id=v_type and value='hr_self_service_request') then
    insert into public.sys_dictionary(type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type)
    values(v_type,'workflowBusinessType_hr_self_service_request','1','624944977@qq.com','624944977@qq.com',
      'hr_self_service_request','员工自助申请',82,v_platform,'primary');
  end if;
end $$;

do $$
declare v_hr_root uuid:='1acf51bb-89c8-4353-be35-aca6aefd9e37';
  v_operations uuid:='c0de0000-0000-4000-8000-000000000200';
  v_page record; v_button record;
begin
  insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
  values(v_operations,v_hr_root,'HrOperations','operations','','folder',2,
    jsonb_build_object('title','人力运营','icon','ri:calendar-schedule-line','roles',jsonb_build_array('R_SUPER','R_ADMIN'),
      'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,
      'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
    '624944977@qq.com','624944977@qq.com')
  on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,
    type=excluded.type,sort=excluded.sort,meta=excluded.meta,update_by='624944977@qq.com',update_time=now();

  for v_page in select * from (values
    ('c0de0000-0000-4000-8000-000000000201'::uuid,'HrHeadcount','headcount','/hr/operations/headcount','编制管理','ri:organization-chart',1),
    ('c0de0000-0000-4000-8000-000000000202'::uuid,'HrAttendance','attendance','/hr/operations/attendance','考勤排班','ri:calendar-check-line',2),
    ('c0de0000-0000-4000-8000-000000000203'::uuid,'HrSelfService','self-service','/hr/operations/self-service','员工自助','ri:user-shared-line',3)
  ) as x(id,name,path,component,title,icon,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_page.id,v_operations,v_page.name,v_page.path,v_page.component,'menu',v_page.sort,
      jsonb_build_object('title',v_page.title,'icon',v_page.icon,'roles',jsonb_build_array('R_SUPER','R_ADMIN'),
        'is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,
        'show_badge',false,'active_path','','is_hide_tab',false,'is_full_page',false,'show_text_badge',''),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,
      component=excluded.component,type=excluded.type,sort=excluded.sort,meta=excluded.meta,
      update_by='624944977@qq.com',update_time=now();
  end loop;

  for v_button in select * from (values
    ('c0de0000-0000-4000-8201-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000201'::uuid,'Hr:Headcount:View','查看编制',1),
    ('c0de0000-0000-4000-8201-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000201'::uuid,'Hr:Headcount:Add','新增编制',2),
    ('c0de0000-0000-4000-8201-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000201'::uuid,'Hr:Headcount:Edit','编辑编制',3),
    ('c0de0000-0000-4000-8201-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000201'::uuid,'Hr:Headcount:Delete','删除编制',4),
    ('c0de0000-0000-4000-8202-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000202'::uuid,'Hr:Attendance:View','查看考勤',1),
    ('c0de0000-0000-4000-8202-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000202'::uuid,'Hr:Attendance:Add','新增考勤排班',2),
    ('c0de0000-0000-4000-8202-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000202'::uuid,'Hr:Attendance:Edit','编辑考勤排班',3),
    ('c0de0000-0000-4000-8202-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000202'::uuid,'Hr:Attendance:Delete','删除考勤排班',4),
    ('c0de0000-0000-4000-8203-000000000001'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:View','查看员工申请',1),
    ('c0de0000-0000-4000-8203-000000000002'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:Add','新增员工申请',2),
    ('c0de0000-0000-4000-8203-000000000003'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:Edit','编辑员工申请',3),
    ('c0de0000-0000-4000-8203-000000000004'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:Delete','删除员工申请',4),
    ('c0de0000-0000-4000-8203-000000000005'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:Submit','提交员工申请',5),
    ('c0de0000-0000-4000-8203-000000000006'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid,'Hr:SelfService:Manage','管理员工申请',6)
  ) as x(id,parent_id,name,title,sort) loop
    insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
    values(v_button.id,v_button.parent_id,v_button.name,'','','button',v_button.sort,
      jsonb_build_object('title',v_button.title,'icon','','roles',jsonb_build_array('R_SUPER','R_ADMIN'),'is_enable',true),
      '624944977@qq.com','624944977@qq.com')
    on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,type='button',sort=excluded.sort,
      meta=excluded.meta,update_by='624944977@qq.com',update_time=now();
  end loop;

  -- Existing HR holders receive operational management pages.
  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm join public.sys_role r on r.id=rm.role_id
  join public.sys_menu m on m.id in (v_operations,
    'c0de0000-0000-4000-8000-000000000201'::uuid,'c0de0000-0000-4000-8000-000000000202'::uuid,
    'c0de0000-0000-4000-8000-000000000203'::uuid)
  where rm.menu_id=v_hr_root on conflict(role_id,menu_id) do nothing;
  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select distinct rm.role_id,b.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role_menu rm join public.sys_role r on r.id=rm.role_id
  join public.sys_menu b on b.parent_id=rm.menu_id and b.type='button'
  where rm.menu_id in ('c0de0000-0000-4000-8000-000000000201'::uuid,
    'c0de0000-0000-4000-8000-000000000202'::uuid,'c0de0000-0000-4000-8000-000000000203'::uuid)
  on conflict(role_id,menu_id) do nothing;

  -- All enabled ordinary roles receive only the safe employee self-service path.
  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select r.id,m.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',r.tenant_id
  from public.sys_role r cross join public.sys_menu m
  where r.enabled and coalesce(r.builtin_type,'')<>'platform_super'
    and m.id in (v_hr_root,v_operations,'c0de0000-0000-4000-8000-000000000203'::uuid,
      'c0de0000-0000-4000-8203-000000000001'::uuid,'c0de0000-0000-4000-8203-000000000002'::uuid,
      'c0de0000-0000-4000-8203-000000000003'::uuid,'c0de0000-0000-4000-8203-000000000004'::uuid,
      'c0de0000-0000-4000-8203-000000000005'::uuid)
  on conflict(role_id,menu_id) do nothing;
end $$;

do $$
declare v_tenant record; v_definition uuid; v_version uuid; v_config jsonb;
begin
  for v_tenant in
    select distinct r.tenant_id,r.role_code from public.sys_role r
    join public.sys_role_menu rm on rm.role_id=r.id
    where r.enabled and rm.menu_id='c0de0000-0000-4000-8203-000000000006'::uuid
      and r.tenant_id<>app_private.platform_tenant_id()
      and not exists(select 1 from public.sys_role x join public.sys_role_menu xm on xm.role_id=x.id
        where x.tenant_id=r.tenant_id and x.enabled and xm.menu_id=rm.menu_id and x.role_code<r.role_code)
  loop
    if not exists(select 1 from public.wf_definition where tenant_id=v_tenant.tenant_id and code='HRSelfServiceDefault') then
      v_definition:=gen_random_uuid(); v_version:=gen_random_uuid();
      v_config:=jsonb_build_object('allowAutoApprove',false,'nodes',jsonb_build_array(jsonb_build_object(
        'key','node_hr_self_service','name','直属管理员审批','order',1,'approvalMode','any',
        'approvalThresholdPercent',100,'rejectVetoEnabled',true,'allowSelfApproval',true,'dueHours',24,
        'reminderBeforeMinutes',60,'escalationEnabled',true,'escalateAfterHours',4,
        'assignee',jsonb_build_object('type','roles','userIds','[]'::jsonb,'roleCodes',jsonb_build_array(v_tenant.role_code)),
        'condition',jsonb_build_object('operator','always'))));
      insert into public.wf_definition(id,code,name,business_type,description,status,published_at,published_by,
        create_by,update_by,tenant_id) values(v_definition,'HRSelfServiceDefault','员工自助默认审批',
        'hr_self_service_request','员工请假、加班及信息变更默认审批。','published',now(),'624944977@qq.com',
        '624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
      insert into public.wf_version(id,definition_id,version_no,status,config,change_note,published_at,published_by,
        create_by,update_by,tenant_id) values(v_version,v_definition,1,'published',v_config,'初始化 HR 默认流程',
        now(),'624944977@qq.com','624944977@qq.com','624944977@qq.com',v_tenant.tenant_id);
      update public.wf_definition set current_version_id=v_version where id=v_definition;
    end if;
  end loop;
end $$;
;
