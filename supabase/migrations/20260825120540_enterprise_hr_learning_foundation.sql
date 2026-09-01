alter table public.hr_training_plan
  add column if not exists owner_employee_id uuid,
  add column if not exists target_audience text,
  add column if not exists mandatory boolean not null default false,
  add column if not exists actual_cost numeric(14,2),
  add column if not exists approved_by text,
  add column if not exists approved_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_training_plan_owner_employee_fkey'
      and conrelid = 'public.hr_training_plan'::regclass
  ) then
    alter table public.hr_training_plan
      add constraint hr_training_plan_owner_employee_fkey
      foreign key (owner_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
end
$$;

alter table public.hr_training_plan
  drop constraint if exists hr_training_plan_actual_cost_check;
alter table public.hr_training_plan
  add constraint hr_training_plan_actual_cost_check
  check (actual_cost is null or actual_cost >= 0);

create index if not exists hr_training_plan_owner_employee_fk_idx
  on public.hr_training_plan(owner_employee_id, tenant_id)
  where owner_employee_id is not null;

create table public.hr_learning_course (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  course_code text not null,
  course_name text not null,
  category text not null,
  delivery_mode text not null default 'classroom',
  duration_hours numeric(8,2) not null,
  credit_hours numeric(8,2) not null default 0,
  provider_name text,
  passing_score numeric(5,2),
  minimum_attendance_percent numeric(5,2) not null default 80,
  certificate_enabled boolean not null default false,
  certificate_valid_months integer,
  status text not null default 'draft',
  description text,
  learning_objectives text,
  target_audience text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_learning_course_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_learning_course_id_tenant_unique unique (id, tenant_id),
  constraint hr_learning_course_code_unique unique (tenant_id, course_code),
  constraint hr_learning_course_code_not_blank check (btrim(course_code) <> ''),
  constraint hr_learning_course_name_not_blank check (btrim(course_name) <> ''),
  constraint hr_learning_course_category_check check (
    category in ('onboarding', 'professional', 'leadership', 'compliance', 'safety', 'digital', 'language', 'other')
  ),
  constraint hr_learning_course_delivery_mode_check check (
    delivery_mode in ('classroom', 'virtual', 'elearning', 'blended', 'on_the_job')
  ),
  constraint hr_learning_course_duration_check check (duration_hours > 0 and credit_hours >= 0),
  constraint hr_learning_course_passing_score_check check (passing_score is null or passing_score between 0 and 100),
  constraint hr_learning_course_attendance_check check (minimum_attendance_percent between 0 and 100),
  constraint hr_learning_course_certificate_validity_check check (
    (certificate_enabled and (certificate_valid_months is null or certificate_valid_months between 1 and 600))
    or (not certificate_enabled and certificate_valid_months is null)
  ),
  constraint hr_learning_course_status_check check (status in ('draft', 'published', 'retired'))
);

create index hr_learning_course_status_idx
  on public.hr_learning_course(tenant_id, status, category, course_code);

create table public.hr_learning_course_competency (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  course_id uuid not null,
  competency_id uuid not null,
  target_level text not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_learning_course_competency_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_learning_course_competency_course_fkey foreign key (course_id, tenant_id)
    references public.hr_learning_course(id, tenant_id) on delete cascade,
  constraint hr_learning_course_competency_competency_fkey foreign key (competency_id, tenant_id)
    references public.hr_competency(id, tenant_id) on delete restrict,
  constraint hr_learning_course_competency_id_tenant_unique unique (id, tenant_id),
  constraint hr_learning_course_competency_unique unique (tenant_id, course_id, competency_id),
  constraint hr_learning_course_competency_level_check check (
    target_level in ('basic', 'intermediate', 'advanced', 'expert')
  )
);

create index hr_learning_course_competency_course_fk_idx
  on public.hr_learning_course_competency(course_id, tenant_id);
create index hr_learning_course_competency_competency_fk_idx
  on public.hr_learning_course_competency(competency_id, tenant_id);

create table public.hr_learning_session (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  session_code text not null,
  plan_id uuid not null,
  course_id uuid not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  enrollment_deadline timestamptz,
  capacity integer not null default 30,
  instructor_name text,
  location text,
  meeting_url text,
  estimated_cost numeric(14,2),
  actual_cost numeric(14,2),
  status text not null default 'planned',
  completion_note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_learning_session_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_learning_session_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_training_plan(id, tenant_id) on delete restrict,
  constraint hr_learning_session_course_fkey foreign key (course_id, tenant_id)
    references public.hr_learning_course(id, tenant_id) on delete restrict,
  constraint hr_learning_session_id_tenant_unique unique (id, tenant_id),
  constraint hr_learning_session_code_unique unique (tenant_id, session_code),
  constraint hr_learning_session_code_not_blank check (btrim(session_code) <> ''),
  constraint hr_learning_session_schedule_check check (end_at > start_at),
  constraint hr_learning_session_deadline_check check (enrollment_deadline is null or enrollment_deadline <= start_at),
  constraint hr_learning_session_capacity_check check (capacity between 1 and 100000),
  constraint hr_learning_session_cost_check check (
    (estimated_cost is null or estimated_cost >= 0) and (actual_cost is null or actual_cost >= 0)
  ),
  constraint hr_learning_session_channel_check check (
    nullif(btrim(location), '') is not null or nullif(btrim(meeting_url), '') is not null
  ),
  constraint hr_learning_session_status_check check (
    status in ('planned', 'open', 'in_progress', 'completed', 'cancelled')
  )
);

create index hr_learning_session_plan_fk_idx on public.hr_learning_session(plan_id, tenant_id);
create index hr_learning_session_course_fk_idx on public.hr_learning_session(course_id, tenant_id);
create index hr_learning_session_schedule_idx on public.hr_learning_session(tenant_id, status, start_at);

alter table public.hr_training_enrollment
  add column if not exists session_id uuid,
  add column if not exists attendance_percent numeric(5,2),
  add column if not exists completion_comment text,
  add column if not exists nominated_by_employee_id uuid;

alter table public.hr_training_enrollment
  drop constraint if exists hr_training_enrollment_tenant_id_plan_id_employee_id_key,
  drop constraint if exists hr_training_enrollment_status_check;

update public.hr_training_enrollment
set completed_at = case
  when status in ('passed', 'failed', 'withdrawn') then coalesce(completed_at, update_time, create_time, now())
  else null
end;

alter table public.hr_training_enrollment
  add constraint hr_training_enrollment_status_check
  check (status in ('enrolled', 'attending', 'passed', 'failed', 'withdrawn', 'no_show')),
  add constraint hr_training_enrollment_attendance_check
  check (attendance_percent is null or attendance_percent between 0 and 100),
  add constraint hr_training_enrollment_completion_check
  check (
    (status in ('passed', 'failed', 'withdrawn', 'no_show') and completed_at is not null)
    or (status in ('enrolled', 'attending') and completed_at is null)
  );

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_training_enrollment_id_tenant_unique'
      and conrelid = 'public.hr_training_enrollment'::regclass
  ) then
    alter table public.hr_training_enrollment
      add constraint hr_training_enrollment_id_tenant_unique unique (id, tenant_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_training_enrollment_session_fkey'
      and conrelid = 'public.hr_training_enrollment'::regclass
  ) then
    alter table public.hr_training_enrollment
      add constraint hr_training_enrollment_session_fkey
      foreign key (session_id, tenant_id)
      references public.hr_learning_session(id, tenant_id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_training_enrollment_nominator_fkey'
      and conrelid = 'public.hr_training_enrollment'::regclass
  ) then
    alter table public.hr_training_enrollment
      add constraint hr_training_enrollment_nominator_fkey
      foreign key (nominated_by_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
end
$$;

create unique index hr_training_enrollment_session_employee_unique
  on public.hr_training_enrollment(tenant_id, session_id, employee_id)
  where session_id is not null;
create index hr_training_enrollment_session_fk_idx
  on public.hr_training_enrollment(session_id, tenant_id) where session_id is not null;
create index hr_training_enrollment_nominator_fk_idx
  on public.hr_training_enrollment(nominated_by_employee_id, tenant_id)
  where nominated_by_employee_id is not null;

create table public.hr_learning_certificate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  enrollment_id uuid not null,
  employee_id uuid not null,
  course_id uuid not null,
  certificate_no text not null,
  certificate_name text not null,
  issued_on date not null,
  expires_on date,
  status text not null default 'valid',
  credential_url text,
  revoked_reason text,
  revoked_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_learning_certificate_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_learning_certificate_enrollment_fkey foreign key (enrollment_id, tenant_id)
    references public.hr_training_enrollment(id, tenant_id) on delete restrict,
  constraint hr_learning_certificate_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_learning_certificate_course_fkey foreign key (course_id, tenant_id)
    references public.hr_learning_course(id, tenant_id) on delete restrict,
  constraint hr_learning_certificate_id_tenant_unique unique (id, tenant_id),
  constraint hr_learning_certificate_enrollment_unique unique (tenant_id, enrollment_id),
  constraint hr_learning_certificate_no_unique unique (tenant_id, certificate_no),
  constraint hr_learning_certificate_no_not_blank check (btrim(certificate_no) <> ''),
  constraint hr_learning_certificate_dates_check check (expires_on is null or expires_on >= issued_on),
  constraint hr_learning_certificate_status_check check (status in ('valid', 'expired', 'revoked')),
  constraint hr_learning_certificate_revocation_check check (
    (status = 'revoked' and revoked_at is not null and nullif(btrim(revoked_reason), '') is not null)
    or (status <> 'revoked' and revoked_at is null and revoked_reason is null)
  )
);

create index hr_learning_certificate_enrollment_fk_idx
  on public.hr_learning_certificate(enrollment_id, tenant_id);
create index hr_learning_certificate_employee_fk_idx
  on public.hr_learning_certificate(employee_id, tenant_id);
create index hr_learning_certificate_course_fk_idx
  on public.hr_learning_certificate(course_id, tenant_id);
create index hr_learning_certificate_expiry_idx
  on public.hr_learning_certificate(tenant_id, status, expires_on);

create trigger hr_learning_course_create_audit before insert on public.hr_learning_course
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_learning_course_update_audit before update on public.hr_learning_course
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_learning_course_competency_create_audit before insert on public.hr_learning_course_competency
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_learning_course_competency_update_audit before update on public.hr_learning_course_competency
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_learning_session_create_audit before insert on public.hr_learning_session
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_learning_session_update_audit before update on public.hr_learning_session
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_learning_certificate_create_audit before insert on public.hr_learning_certificate
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_learning_certificate_update_audit before update on public.hr_learning_certificate
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_learning_course enable row level security;
alter table public.hr_learning_course_competency enable row level security;
alter table public.hr_learning_session enable row level security;
alter table public.hr_learning_certificate enable row level security;

create policy hr_learning_course_deny_direct_access on public.hr_learning_course
  for all to authenticated using (false) with check (false);
create policy hr_learning_course_competency_deny_direct_access on public.hr_learning_course_competency
  for all to authenticated using (false) with check (false);
create policy hr_learning_session_deny_direct_access on public.hr_learning_session
  for all to authenticated using (false) with check (false);
create policy hr_learning_certificate_deny_direct_access on public.hr_learning_certificate
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_training_plan from public, anon, authenticated;
revoke all on table public.hr_training_enrollment from public, anon, authenticated;
revoke all on table public.hr_learning_course from public, anon, authenticated;
revoke all on table public.hr_learning_course_competency from public, anon, authenticated;
revoke all on table public.hr_learning_session from public, anon, authenticated;
revoke all on table public.hr_learning_certificate from public, anon, authenticated;
grant all on table public.hr_training_plan to service_role;
grant all on table public.hr_training_enrollment to service_role;
grant all on table public.hr_learning_course to service_role;
grant all on table public.hr_learning_course_competency to service_role;
grant all on table public.hr_learning_session to service_role;
grant all on table public.hr_learning_certificate to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('课程类别', 'hrLearningCourseCategory', 90),
  ('授课方式', 'hrLearningDeliveryMode', 91),
  ('课程状态', 'hrLearningCourseStatus', 92),
  ('培训班次状态', 'hrLearningSessionStatus', 93),
  ('学习参与状态', 'hrLearningEnrollmentStatus', 94),
  ('学习证书状态', 'hrLearningCertificateStatus', 95),
  ('课程能力等级', 'hrLearningCompetencyLevel', 96)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 学习发展字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set
  name = excluded.name, status = excluded.status, update_by = excluded.update_by,
  update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrLearningCourseCategory', 'onboarding', '入职融入', 1, 'primary'),
  ('hrLearningCourseCategory', 'professional', '专业能力', 2, 'success'),
  ('hrLearningCourseCategory', 'leadership', '领导力', 3, 'warning'),
  ('hrLearningCourseCategory', 'compliance', '合规必修', 4, 'danger'),
  ('hrLearningCourseCategory', 'safety', '安全培训', 5, 'danger'),
  ('hrLearningCourseCategory', 'digital', '数字化', 6, 'primary'),
  ('hrLearningCourseCategory', 'language', '语言能力', 7, 'info'),
  ('hrLearningCourseCategory', 'other', '其他', 8, 'info'),
  ('hrLearningDeliveryMode', 'classroom', '线下面授', 1, 'primary'),
  ('hrLearningDeliveryMode', 'virtual', '在线直播', 2, 'success'),
  ('hrLearningDeliveryMode', 'elearning', '在线自学', 3, 'info'),
  ('hrLearningDeliveryMode', 'blended', '混合学习', 4, 'warning'),
  ('hrLearningDeliveryMode', 'on_the_job', '在岗带教', 5, 'primary'),
  ('hrLearningCourseStatus', 'draft', '草稿', 1, 'info'),
  ('hrLearningCourseStatus', 'published', '已发布', 2, 'success'),
  ('hrLearningCourseStatus', 'retired', '已停用', 3, 'warning'),
  ('hrLearningSessionStatus', 'planned', '待开放', 1, 'info'),
  ('hrLearningSessionStatus', 'open', '报名中', 2, 'success'),
  ('hrLearningSessionStatus', 'in_progress', '进行中', 3, 'primary'),
  ('hrLearningSessionStatus', 'completed', '已完成', 4, 'success'),
  ('hrLearningSessionStatus', 'cancelled', '已取消', 5, 'danger'),
  ('hrLearningEnrollmentStatus', 'enrolled', '已报名', 1, 'info'),
  ('hrLearningEnrollmentStatus', 'attending', '学习中', 2, 'primary'),
  ('hrLearningEnrollmentStatus', 'passed', '已通过', 3, 'success'),
  ('hrLearningEnrollmentStatus', 'failed', '未通过', 4, 'danger'),
  ('hrLearningEnrollmentStatus', 'withdrawn', '已退出', 5, 'warning'),
  ('hrLearningEnrollmentStatus', 'no_show', '未到场', 6, 'danger'),
  ('hrLearningCertificateStatus', 'valid', '有效', 1, 'success'),
  ('hrLearningCertificateStatus', 'expired', '已过期', 2, 'warning'),
  ('hrLearningCertificateStatus', 'revoked', '已撤销', 3, 'danger'),
  ('hrLearningCompetencyLevel', 'basic', '基础', 1, 'info'),
  ('hrLearningCompetencyLevel', 'intermediate', '熟练', 2, 'primary'),
  ('hrLearningCompetencyLevel', 'advanced', '高级', 3, 'success'),
  ('hrLearningCompetencyLevel', 'expert', '专家', 4, 'warning')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 学习发展字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000302'::uuid, seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8502-000000000005'::uuid, 'Hr:Talent:Plan:Transition', '推进培训计划', 5),
  ('c0de0000-0000-4000-8502-000000000006'::uuid, 'Hr:Talent:Course:Add', '新增课程', 6),
  ('c0de0000-0000-4000-8502-000000000007'::uuid, 'Hr:Talent:Course:Edit', '编辑课程', 7),
  ('c0de0000-0000-4000-8502-000000000008'::uuid, 'Hr:Talent:Course:Publish', '发布或停用课程', 8),
  ('c0de0000-0000-4000-8502-000000000009'::uuid, 'Hr:Talent:Session:Add', '新增培训班次', 9),
  ('c0de0000-0000-4000-8502-000000000010'::uuid, 'Hr:Talent:Session:Edit', '编辑培训班次', 10),
  ('c0de0000-0000-4000-8502-000000000011'::uuid, 'Hr:Talent:Session:Transition', '推进培训班次', 11),
  ('c0de0000-0000-4000-8502-000000000012'::uuid, 'Hr:Talent:Enrollment:Add', '安排员工学习', 12),
  ('c0de0000-0000-4000-8502-000000000013'::uuid, 'Hr:Talent:Enrollment:Manage', '登记学习结果', 13),
  ('c0de0000-0000-4000-8502-000000000014'::uuid, 'Hr:Talent:Certificate:Manage', '管理学习证书', 14),
  ('c0de0000-0000-4000-8502-000000000015'::uuid, 'Hr:Talent:Course:Competency', '维护课程能力映射', 15)
) seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8502-000000000005'::uuid),
  ('c0de0000-0000-4000-8502-000000000006'::uuid),
  ('c0de0000-0000-4000-8502-000000000007'::uuid),
  ('c0de0000-0000-4000-8502-000000000008'::uuid),
  ('c0de0000-0000-4000-8502-000000000009'::uuid),
  ('c0de0000-0000-4000-8502-000000000010'::uuid),
  ('c0de0000-0000-4000-8502-000000000011'::uuid),
  ('c0de0000-0000-4000-8502-000000000012'::uuid),
  ('c0de0000-0000-4000-8502-000000000013'::uuid),
  ('c0de0000-0000-4000-8502-000000000014'::uuid),
  ('c0de0000-0000-4000-8502-000000000015'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000302'::uuid
on conflict (role_id, menu_id) do nothing;

;
