alter table public.hr_shift
  add column if not exists time_zone text not null default 'Asia/Shanghai',
  add column if not exists late_grace_minutes integer not null default 0,
  add column if not exists early_leave_grace_minutes integer not null default 0;

alter table public.hr_shift
  drop constraint if exists hr_shift_time_zone_not_blank,
  drop constraint if exists hr_shift_grace_minutes_check;
alter table public.hr_shift
  add constraint hr_shift_time_zone_not_blank check (nullif(btrim(time_zone), '') is not null),
  add constraint hr_shift_grace_minutes_check check (
    late_grace_minutes between 0 and 240
    and early_leave_grace_minutes between 0 and 240
  );

alter table public.hr_attendance_record
  add column if not exists scheduled_minutes integer not null default 0,
  add column if not exists late_minutes integer not null default 0,
  add column if not exists early_leave_minutes integer not null default 0,
  add column if not exists absence_minutes integer not null default 0,
  add column if not exists payable_minutes integer not null default 0,
  add column if not exists exception_status text not null default 'clear',
  add column if not exists valuation_note text,
  add column if not exists locked_at timestamptz,
  add column if not exists locked_by text,
  add column if not exists source_reference text;

alter table public.hr_attendance_record
  add constraint hr_attendance_record_id_tenant_unique unique (id, tenant_id);

alter table public.hr_attendance_record
  drop constraint if exists hr_attendance_valuation_minutes_check,
  drop constraint if exists hr_attendance_exception_status_check,
  drop constraint if exists hr_attendance_lock_check;
alter table public.hr_attendance_record
  add constraint hr_attendance_valuation_minutes_check check (
    scheduled_minutes >= 0 and late_minutes >= 0 and early_leave_minutes >= 0
    and absence_minutes >= 0 and payable_minutes >= 0
  ),
  add constraint hr_attendance_exception_status_check check (
    exception_status in ('clear', 'open', 'resolved', 'waived')
  ),
  add constraint hr_attendance_lock_check check (
    (locked_at is null and locked_by is null)
    or (locked_at is not null and nullif(btrim(locked_by), '') is not null)
  );

create index if not exists hr_attendance_record_exception_idx
  on public.hr_attendance_record(tenant_id, exception_status, work_date)
  where exception_status = 'open';
create index if not exists hr_attendance_record_lock_idx
  on public.hr_attendance_record(tenant_id, locked_at, work_date)
  where locked_at is not null;

create table public.hr_attendance_correction (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  correction_no text not null,
  attendance_record_id uuid not null,
  employee_id uuid not null,
  requested_clock_in_at timestamptz,
  requested_clock_out_at timestamptz,
  reason text not null,
  proof_urls jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by text,
  review_comment text,
  original_snapshot jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_attendance_correction_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_attendance_correction_record_fkey foreign key (attendance_record_id, tenant_id)
    references public.hr_attendance_record(id, tenant_id) on delete restrict,
  constraint hr_attendance_correction_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_attendance_correction_id_tenant_unique unique (id, tenant_id),
  constraint hr_attendance_correction_no_unique unique (tenant_id, correction_no),
  constraint hr_attendance_correction_no_not_blank check (btrim(correction_no) <> ''),
  constraint hr_attendance_correction_reason_not_blank check (btrim(reason) <> ''),
  constraint hr_attendance_correction_clock_check check (
    requested_clock_out_at is null or requested_clock_in_at is null
    or requested_clock_out_at >= requested_clock_in_at
  ),
  constraint hr_attendance_correction_status_check check (
    status in ('draft', 'submitted', 'approved', 'rejected', 'cancelled')
  ),
  constraint hr_attendance_correction_review_check check (
    (status in ('approved', 'rejected') and reviewed_at is not null
      and nullif(btrim(reviewed_by), '') is not null)
    or (status not in ('approved', 'rejected') and reviewed_at is null and reviewed_by is null)
  )
);

create index hr_attendance_correction_record_fk_idx
  on public.hr_attendance_correction(attendance_record_id, tenant_id);
create index hr_attendance_correction_employee_fk_idx
  on public.hr_attendance_correction(employee_id, tenant_id);
create index hr_attendance_correction_status_idx
  on public.hr_attendance_correction(tenant_id, status, create_time desc);
create unique index hr_attendance_correction_active_unique
  on public.hr_attendance_correction(tenant_id, attendance_record_id)
  where status in ('draft', 'submitted');

create table public.hr_attendance_period (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  period_month date not null,
  status text not null default 'open',
  record_count integer not null default 0,
  exception_count integer not null default 0,
  total_scheduled_minutes bigint not null default 0,
  total_payable_minutes bigint not null default 0,
  total_overtime_minutes bigint not null default 0,
  reviewed_at timestamptz,
  reviewed_by text,
  closed_at timestamptz,
  closed_by text,
  close_note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_attendance_period_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_attendance_period_id_tenant_unique unique (id, tenant_id),
  constraint hr_attendance_period_month_unique unique (tenant_id, period_month),
  constraint hr_attendance_period_month_check check (
    period_month = date_trunc('month', period_month)::date
  ),
  constraint hr_attendance_period_status_check check (
    status in ('open', 'reviewing', 'closed')
  ),
  constraint hr_attendance_period_counts_check check (
    record_count >= 0 and exception_count >= 0
    and total_scheduled_minutes >= 0 and total_payable_minutes >= 0
    and total_overtime_minutes >= 0
  ),
  constraint hr_attendance_period_review_check check (
    status = 'open'
    or (reviewed_at is not null and nullif(btrim(reviewed_by), '') is not null)
  ),
  constraint hr_attendance_period_close_check check (
    status <> 'closed'
    or (closed_at is not null and nullif(btrim(closed_by), '') is not null)
  )
);

create index hr_attendance_period_status_idx
  on public.hr_attendance_period(tenant_id, status, period_month desc);

create trigger hr_attendance_correction_create_audit before insert on public.hr_attendance_correction
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_attendance_correction_update_audit before update on public.hr_attendance_correction
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_attendance_period_create_audit before insert on public.hr_attendance_period
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_attendance_period_update_audit before update on public.hr_attendance_period
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_attendance_correction enable row level security;
alter table public.hr_attendance_period enable row level security;
create policy hr_attendance_correction_deny_direct_access on public.hr_attendance_correction
  for all to authenticated using (false) with check (false);
create policy hr_attendance_period_deny_direct_access on public.hr_attendance_period
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_shift from public, anon, authenticated;
revoke all on table public.hr_shift_assignment from public, anon, authenticated;
revoke all on table public.hr_attendance_record from public, anon, authenticated;
revoke all on table public.hr_attendance_correction from public, anon, authenticated;
revoke all on table public.hr_attendance_period from public, anon, authenticated;
grant all on table public.hr_shift to service_role;
grant all on table public.hr_shift_assignment to service_role;
grant all on table public.hr_attendance_record to service_role;
grant all on table public.hr_attendance_correction to service_role;
grant all on table public.hr_attendance_period to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('考勤异常处理状态', 'hrAttendanceExceptionStatus', 109),
  ('考勤修正单状态', 'hrAttendanceCorrectionStatus', 110),
  ('考勤期间状态', 'hrAttendancePeriodStatus', 111)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 考勤工时字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrAttendanceExceptionStatus','clear','无异常',1,'success'),
  ('hrAttendanceExceptionStatus','open','待处理',2,'danger'),
  ('hrAttendanceExceptionStatus','resolved','已修正',3,'success'),
  ('hrAttendanceExceptionStatus','waived','已豁免',4,'info'),
  ('hrAttendanceCorrectionStatus','draft','草稿',1,'info'),
  ('hrAttendanceCorrectionStatus','submitted','待审核',2,'warning'),
  ('hrAttendanceCorrectionStatus','approved','已批准',3,'success'),
  ('hrAttendanceCorrectionStatus','rejected','已驳回',4,'danger'),
  ('hrAttendanceCorrectionStatus','cancelled','已取消',5,'info'),
  ('hrAttendancePeriodStatus','open','开放',1,'primary'),
  ('hrAttendancePeriodStatus','reviewing','核对中',2,'warning'),
  ('hrAttendancePeriodStatus','closed','已封账',3,'success')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 考勤工时字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, 'hrAttendanceSource_correction',
  '1', '624944977@qq.com', '624944977@qq.com', '考勤修正审批回写',
  'correction', '修正审批', platform_tenant.id, 'warning', 5
from public.sys_dict_type dictionary_type
join public.sys_tenant platform_tenant on platform_tenant.tenant_code = 'platform'
where dictionary_type.code = 'hrAttendanceSource'
  and not exists (
    select 1 from public.sys_dictionary existing
    where existing.type_id = dictionary_type.id and existing.value = 'correction'
  );

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000202'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8202-000000000005'::uuid, 'Hr:Attendance:Evaluate', '执行工时核算', 5),
  ('c0de0000-0000-4000-8202-000000000006'::uuid, 'Hr:Attendance:ReviewCorrection', '审核考勤修正', 6),
  ('c0de0000-0000-4000-8202-000000000007'::uuid, 'Hr:Attendance:ClosePeriod', '考勤期间封账', 7)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8202-000000000005'::uuid),
  ('c0de0000-0000-4000-8202-000000000006'::uuid),
  ('c0de0000-0000-4000-8202-000000000007'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000202'::uuid
on conflict (role_id, menu_id) do nothing;
