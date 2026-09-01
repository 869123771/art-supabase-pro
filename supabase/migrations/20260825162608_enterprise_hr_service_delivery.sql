create table public.hr_service_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  service_code text not null,
  service_name text not null,
  category text not null,
  description text,
  service_mode text not null default 'case',
  route_path text,
  routing_group text,
  first_response_hours integer not null default 8,
  resolution_hours integer not null default 40,
  enabled boolean not null default true,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_service_catalog_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_service_catalog_id_tenant_unique unique (id, tenant_id),
  constraint hr_service_catalog_code_unique unique (tenant_id, service_code),
  constraint hr_service_catalog_code_not_blank check (nullif(btrim(service_code), '') is not null),
  constraint hr_service_catalog_name_not_blank check (nullif(btrim(service_name), '') is not null),
  constraint hr_service_catalog_mode_check check (service_mode in ('case', 'redirect')),
  constraint hr_service_catalog_route_check check (
    (service_mode = 'case')
    or (service_mode = 'redirect' and nullif(btrim(route_path), '') is not null)
  ),
  constraint hr_service_catalog_sla_check check (
    first_response_hours between 0 and 720
    and resolution_hours between 0 and 2160
    and (service_mode = 'redirect' or resolution_hours >= first_response_hours)
  )
);

alter table public.hr_self_service_request
  add column if not exists service_id uuid,
  add column if not exists priority text not null default 'normal',
  add column if not exists channel text not null default 'self_service',
  add column if not exists assigned_employee_id uuid,
  add column if not exists first_response_due_at timestamptz,
  add column if not exists resolution_due_at timestamptz,
  add column if not exists first_responded_at timestamptz,
  add column if not exists resolved_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists waiting_started_at timestamptz,
  add column if not exists last_activity_at timestamptz not null default now(),
  add column if not exists waiting_reason text,
  add column if not exists resolution text,
  add column if not exists attachment_urls jsonb not null default '[]'::jsonb,
  add column if not exists reopen_count integer not null default 0;

update public.hr_self_service_request
set status = case status
  when 'pending' then 'submitted'
  when 'approved' then 'resolved'
  when 'effective' then 'closed'
  when 'rejected' then 'cancelled'
  else status
end,
resolved_at = case when status = 'approved' then coalesce(reviewed_at, update_time) else resolved_at end,
closed_at = case when status = 'effective' then coalesce(reviewed_at, update_time) else closed_at end,
resolution = case when status in ('approved', 'effective')
  then coalesce(nullif(btrim(review_comment), ''), '历史申请已完成审批')
  else resolution end,
last_activity_at = coalesce(update_time, create_time, now());

alter table public.hr_self_service_request
  drop constraint if exists hr_self_service_request_status_check,
  add constraint hr_self_service_request_status_check check (
    status in ('draft', 'submitted', 'assigned', 'in_progress', 'waiting_employee',
      'resolved', 'closed', 'cancelled')
  ),
  add constraint hr_self_service_request_priority_check check (
    priority in ('low', 'normal', 'high', 'urgent')
  ),
  add constraint hr_self_service_request_channel_check check (
    channel in ('self_service', 'agent', 'email', 'phone')
  ),
  add constraint hr_self_service_request_reopen_count_check check (reopen_count >= 0),
  add constraint hr_self_service_request_attachment_urls_check check (
    jsonb_typeof(attachment_urls) = 'array'
  ),
  add constraint hr_self_service_request_resolution_check check (
    status not in ('resolved', 'closed') or nullif(btrim(resolution), '') is not null
  ),
  add constraint hr_self_service_request_waiting_check check (
    (status = 'waiting_employee' and waiting_started_at is not null
      and nullif(btrim(waiting_reason), '') is not null)
    or (status <> 'waiting_employee' and waiting_started_at is null)
  ),
  add constraint hr_self_service_request_id_tenant_unique unique (id, tenant_id),
  add constraint hr_self_service_request_service_fkey foreign key (service_id, tenant_id)
    references public.hr_service_catalog(id, tenant_id) on delete restrict,
  add constraint hr_self_service_request_assignee_fkey foreign key (assigned_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict;

create table public.hr_service_request_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  request_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  actor_employee_id uuid,
  comment text,
  event_data jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_service_request_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_service_request_event_request_fkey foreign key (request_id, tenant_id)
    references public.hr_self_service_request(id, tenant_id) on delete cascade,
  constraint hr_service_request_event_actor_fkey foreign key (actor_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_service_request_event_type_check check (
    event_type in ('created', 'submitted', 'assigned', 'started', 'waiting', 'resumed',
      'resolved', 'closed', 'reopened', 'cancelled', 'commented', 'updated')
  ),
  constraint hr_service_request_event_status_check check (
    from_status is null or from_status in ('draft', 'submitted', 'assigned', 'in_progress',
      'waiting_employee', 'resolved', 'closed', 'cancelled')
  ),
  constraint hr_service_request_event_to_status_check check (
    to_status is null or to_status in ('draft', 'submitted', 'assigned', 'in_progress',
      'waiting_employee', 'resolved', 'closed', 'cancelled')
  )
);

create index hr_service_catalog_enabled_idx
  on public.hr_service_catalog(tenant_id, enabled, sort, service_name);
create index hr_self_service_request_service_fk_idx
  on public.hr_self_service_request(service_id, tenant_id);
create index hr_self_service_request_assignee_fk_idx
  on public.hr_self_service_request(assigned_employee_id, tenant_id);
create index hr_self_service_request_status_idx
  on public.hr_self_service_request(tenant_id, status, last_activity_at desc);
create index hr_self_service_request_owner_idx
  on public.hr_self_service_request(tenant_id, employee_id, last_activity_at desc);
create index hr_self_service_request_sla_idx
  on public.hr_self_service_request(tenant_id, resolution_due_at)
  where status in ('submitted', 'assigned', 'in_progress', 'waiting_employee');
create index hr_service_request_event_request_idx
  on public.hr_service_request_event(tenant_id, request_id, create_time desc);
create index hr_service_request_event_actor_fk_idx
  on public.hr_service_request_event(actor_employee_id, tenant_id)
  where actor_employee_id is not null;

create trigger hr_service_catalog_create_audit
before insert on public.hr_service_catalog for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_service_catalog_update_audit
before update on public.hr_service_catalog for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_service_request_event_create_audit
before insert on public.hr_service_request_event for each row
execute function public.trg_set_create_time_and_by('true', 'true');

alter table public.hr_service_catalog enable row level security;
alter table public.hr_service_request_event enable row level security;
create policy hr_service_catalog_deny_direct_access on public.hr_service_catalog
  for all to authenticated using (false) with check (false);
create policy hr_service_request_event_deny_direct_access on public.hr_service_request_event
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_service_catalog from public, anon, authenticated;
revoke all on table public.hr_self_service_request from public, anon, authenticated;
revoke all on table public.hr_service_request_event from public, anon, authenticated;
grant all on table public.hr_service_catalog to service_role;
grant all on table public.hr_self_service_request to service_role;
grant all on table public.hr_service_request_event to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('员工服务类别', 'hrServiceCategory', 115),
  ('员工服务工单状态', 'hrServiceRequestStatus', 116),
  ('员工服务优先级', 'hrServicePriority', 117),
  ('员工服务受理渠道', 'hrServiceChannel', 118)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 员工服务交付字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrServiceCategory','certificate','证明与文件',1,'primary'),
  ('hrServiceCategory','employee_data','员工信息',2,'success'),
  ('hrServiceCategory','payroll','薪酬与个税',3,'warning'),
  ('hrServiceCategory','benefit','福利与社保',4,'success'),
  ('hrServiceCategory','policy','制度咨询',5,'info'),
  ('hrServiceCategory','absence','假勤服务',6,'primary'),
  ('hrServiceCategory','career','任职与发展',7,'primary'),
  ('hrServiceCategory','other','其他服务',8,'info'),
  ('hrServiceRequestStatus','draft','草稿',1,'info'),
  ('hrServiceRequestStatus','submitted','待受理',2,'warning'),
  ('hrServiceRequestStatus','assigned','已分派',3,'primary'),
  ('hrServiceRequestStatus','in_progress','处理中',4,'primary'),
  ('hrServiceRequestStatus','waiting_employee','待员工补充',5,'warning'),
  ('hrServiceRequestStatus','resolved','已解决',6,'success'),
  ('hrServiceRequestStatus','closed','已关闭',7,'info'),
  ('hrServiceRequestStatus','cancelled','已取消',8,'info'),
  ('hrServicePriority','low','低',1,'info'),
  ('hrServicePriority','normal','普通',2,'primary'),
  ('hrServicePriority','high','高',3,'warning'),
  ('hrServicePriority','urgent','紧急',4,'danger'),
  ('hrServiceChannel','self_service','员工自助',1,'primary'),
  ('hrServiceChannel','agent','HR 代建',2,'success'),
  ('hrServiceChannel','email','邮件',3,'info'),
  ('hrServiceChannel','phone','电话',4,'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 员工服务交付字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.hr_service_catalog(
  tenant_id, service_code, service_name, category, description, service_mode, route_path,
  routing_group, first_response_hours, resolution_hours, enabled, sort,
  create_by, update_by
)
select tenant.id, seed.service_code, seed.service_name, seed.category, seed.description,
  seed.service_mode, seed.route_path, seed.routing_group, seed.first_response_hours,
  seed.resolution_hours, true, seed.sort, '624944977@qq.com', '624944977@qq.com'
from public.sys_tenant tenant
cross join (values
  ('EMP_CERTIFICATE','在职/收入证明','certificate','申请常用员工证明并跟踪交付进度。','case',null,'员工档案',4,24,1),
  ('EMP_DATA_CORRECTION','员工信息更正','employee_data','申请更正无法在个人资料中直接维护的信息。','case',null,'员工档案',8,40,2),
  ('PAYROLL_INQUIRY','薪酬与个税咨询','payroll','提交薪资、个税或发薪结果相关咨询。','case',null,'薪酬服务',8,40,3),
  ('BENEFIT_INQUIRY','福利与社保咨询','benefit','提交社保、公积金、商业保险和福利问题。','case',null,'福利服务',8,40,4),
  ('POLICY_INQUIRY','人事制度咨询','policy','咨询公司人事制度、流程与适用口径。','case',null,'HR 服务台',8,40,5),
  ('ABSENCE_REQUEST','请假与销假','absence','前往专业假勤模块提交请假、销假和查看余额。','redirect','/hr/operations/absence',null,0,0,6),
  ('ATTENDANCE_CORRECTION','考勤修正','absence','前往考勤与工时模块发起打卡或工时修正。','redirect','/hr/operations/attendance',null,0,0,7),
  ('PERSONNEL_CHANGE','人事异动','career','前往人事异动中心办理调动、晋升、停复职与离职。','redirect','/hr/personnel/personnel-change',null,0,0,8)
) seed(service_code,service_name,category,description,service_mode,route_path,routing_group,
  first_response_hours,resolution_hours,sort)
where tenant.tenant_code = 'public-register'
on conflict (tenant_id, service_code) do nothing;

update public.sys_menu
set meta = jsonb_set(meta, '{title}', '"员工服务中心"'::jsonb, true),
    update_by = '624944977@qq.com', update_time = now()
where id = 'c0de0000-0000-4000-8000-000000000203'::uuid;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000203'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8203-000000000007'::uuid, 'Hr:SelfService:Assign', '分派员工服务工单', 7),
  ('c0de0000-0000-4000-8203-000000000008'::uuid, 'Hr:SelfService:Resolve', '处理员工服务工单', 8),
  ('c0de0000-0000-4000-8203-000000000009'::uuid, 'Hr:SelfService:Catalog:Manage', '维护员工服务目录', 9)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select manage_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu manage_grant
join public.sys_role role on role.id = manage_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8203-000000000007'::uuid),
  ('c0de0000-0000-4000-8203-000000000008'::uuid),
  ('c0de0000-0000-4000-8203-000000000009'::uuid)
) button(id)
where manage_grant.menu_id = 'c0de0000-0000-4000-8203-000000000006'::uuid
on conflict (role_id, menu_id) do nothing;

;
