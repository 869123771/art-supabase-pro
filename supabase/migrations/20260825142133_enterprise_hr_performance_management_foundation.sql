alter table public.hr_performance_cycle
  add column if not exists owner_employee_id uuid,
  add column if not exists check_in_frequency_days integer not null default 30,
  add column if not exists self_review_due_date date,
  add column if not exists manager_review_due_date date,
  add column if not exists calibration_due_date date,
  add column if not exists activated_at timestamptz,
  add column if not exists completed_at timestamptz;

alter table public.hr_performance_review
  add column if not exists reviewer_employee_id uuid,
  add column if not exists self_score numeric(5,2),
  add column if not exists manager_score numeric(5,2),
  add column if not exists calibrated_score numeric(5,2),
  add column if not exists calibrated_level text,
  add column if not exists submitted_at timestamptz,
  add column if not exists manager_reviewed_at timestamptz,
  add column if not exists completed_at timestamptz;

alter table public.hr_performance_goal
  add column if not exists goal_type text not null default 'business',
  add column if not exists progress_percent numeric(5,2) not null default 0,
  add column if not exists status text not null default 'draft',
  add column if not exists due_date date,
  add column if not exists employee_score numeric(5,2),
  add column if not exists manager_score numeric(5,2);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_performance_cycle_owner_employee_fkey'
      and conrelid = 'public.hr_performance_cycle'::regclass
  ) then
    alter table public.hr_performance_cycle
      add constraint hr_performance_cycle_owner_employee_fkey
      foreign key (owner_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_performance_review_reviewer_employee_fkey'
      and conrelid = 'public.hr_performance_review'::regclass
  ) then
    alter table public.hr_performance_review
      add constraint hr_performance_review_reviewer_employee_fkey
      foreign key (reviewer_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
end
$$;

alter table public.hr_performance_cycle
  drop constraint if exists hr_performance_cycle_check_in_frequency_check,
  drop constraint if exists hr_performance_cycle_milestones_check;
alter table public.hr_performance_cycle
  add constraint hr_performance_cycle_check_in_frequency_check
    check (check_in_frequency_days between 7 and 365),
  add constraint hr_performance_cycle_milestones_check check (
    (self_review_due_date is null or self_review_due_date between start_date and end_date)
    and (manager_review_due_date is null or manager_review_due_date between start_date and end_date)
    and (calibration_due_date is null or calibration_due_date >= start_date)
    and (self_review_due_date is null or manager_review_due_date is null
      or manager_review_due_date >= self_review_due_date)
    and (manager_review_due_date is null or calibration_due_date is null
      or calibration_due_date >= manager_review_due_date)
  );

alter table public.hr_performance_review
  drop constraint if exists hr_performance_review_stage_scores_check,
  drop constraint if exists hr_performance_review_calibrated_level_check;
alter table public.hr_performance_review
  add constraint hr_performance_review_stage_scores_check check (
    (self_score is null or self_score between 0 and 100)
    and (manager_score is null or manager_score between 0 and 100)
    and (calibrated_score is null or calibrated_score between 0 and 100)
  ),
  add constraint hr_performance_review_calibrated_level_check
    check (calibrated_level is null or calibrated_level in ('s', 'a', 'b', 'c', 'd'));

alter table public.hr_performance_goal
  drop constraint if exists hr_performance_goal_type_check,
  drop constraint if exists hr_performance_goal_progress_check,
  drop constraint if exists hr_performance_goal_status_check,
  drop constraint if exists hr_performance_goal_stage_scores_check;
alter table public.hr_performance_goal
  add constraint hr_performance_goal_type_check check (
    goal_type in ('business', 'customer', 'operations', 'safety', 'development')
  ),
  add constraint hr_performance_goal_progress_check check (progress_percent between 0 and 100),
  add constraint hr_performance_goal_status_check check (
    status in ('draft', 'in_progress', 'at_risk', 'completed')
  ),
  add constraint hr_performance_goal_stage_scores_check check (
    (employee_score is null or employee_score between 0 and 100)
    and (manager_score is null or manager_score between 0 and 100)
  );

create index if not exists hr_performance_cycle_owner_employee_fk_idx
  on public.hr_performance_cycle(owner_employee_id, tenant_id)
  where owner_employee_id is not null;
create index if not exists hr_performance_cycle_status_dates_idx
  on public.hr_performance_cycle(tenant_id, status, start_date desc);
create index if not exists hr_performance_review_reviewer_employee_fk_idx
  on public.hr_performance_review(reviewer_employee_id, tenant_id)
  where reviewer_employee_id is not null;
create index if not exists hr_performance_review_cycle_status_idx
  on public.hr_performance_review(tenant_id, cycle_id, status, employee_id);
create index if not exists hr_performance_goal_review_status_idx
  on public.hr_performance_goal(tenant_id, review_id, status, due_date);

create table public.hr_performance_check_in (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  review_id uuid not null,
  check_in_date date not null default current_date,
  progress_percent numeric(5,2) not null default 0,
  risk_status text not null default 'on_track',
  achievement text,
  blocker text,
  next_action text not null,
  manager_feedback text,
  facilitator_employee_id uuid,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_performance_check_in_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_performance_check_in_review_fkey foreign key (review_id, tenant_id)
    references public.hr_performance_review(id, tenant_id) on delete cascade,
  constraint hr_performance_check_in_facilitator_fkey foreign key (facilitator_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_performance_check_in_id_tenant_unique unique (id, tenant_id),
  constraint hr_performance_check_in_progress_check check (progress_percent between 0 and 100),
  constraint hr_performance_check_in_risk_check check (risk_status in ('on_track', 'attention', 'off_track')),
  constraint hr_performance_check_in_next_action_not_blank check (btrim(next_action) <> '')
);

create index hr_performance_check_in_review_date_idx
  on public.hr_performance_check_in(tenant_id, review_id, check_in_date desc);
create index hr_performance_check_in_facilitator_fk_idx
  on public.hr_performance_check_in(facilitator_employee_id, tenant_id)
  where facilitator_employee_id is not null;
create index hr_performance_check_in_risk_idx
  on public.hr_performance_check_in(tenant_id, risk_status, check_in_date desc)
  where risk_status <> 'on_track';

create table public.hr_performance_calibration_session (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  session_no text not null,
  session_name text not null,
  cycle_id uuid not null,
  organization_id uuid,
  facilitator_employee_id uuid,
  scheduled_at timestamptz not null,
  status text not null default 'setup',
  distribution_note text,
  decision_note text,
  approved_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_performance_calibration_session_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_performance_calibration_session_cycle_fkey foreign key (cycle_id, tenant_id)
    references public.hr_performance_cycle(id, tenant_id) on delete restrict,
  constraint hr_performance_calibration_session_organization_fkey foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_performance_calibration_session_facilitator_fkey foreign key (facilitator_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_performance_calibration_session_id_tenant_unique unique (id, tenant_id),
  constraint hr_performance_calibration_session_no_unique unique (tenant_id, session_no),
  constraint hr_performance_calibration_session_no_not_blank check (btrim(session_no) <> ''),
  constraint hr_performance_calibration_session_name_not_blank check (btrim(session_name) <> ''),
  constraint hr_performance_calibration_session_status_check check (
    status in ('setup', 'in_progress', 'approved', 'deactivated')
  )
);

create index hr_performance_calibration_session_cycle_idx
  on public.hr_performance_calibration_session(tenant_id, cycle_id, status, scheduled_at desc);
create index hr_performance_calibration_session_organization_fk_idx
  on public.hr_performance_calibration_session(organization_id, tenant_id)
  where organization_id is not null;
create index hr_performance_calibration_session_facilitator_fk_idx
  on public.hr_performance_calibration_session(facilitator_employee_id, tenant_id)
  where facilitator_employee_id is not null;

create table public.hr_performance_calibration_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  session_id uuid not null,
  review_id uuid not null,
  original_score numeric(5,2) not null,
  original_level text not null,
  calibrated_score numeric(5,2) not null,
  calibrated_level text not null,
  adjustment_reason text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_performance_calibration_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_performance_calibration_item_session_fkey foreign key (session_id, tenant_id)
    references public.hr_performance_calibration_session(id, tenant_id) on delete cascade,
  constraint hr_performance_calibration_item_review_fkey foreign key (review_id, tenant_id)
    references public.hr_performance_review(id, tenant_id) on delete restrict,
  constraint hr_performance_calibration_item_id_tenant_unique unique (id, tenant_id),
  constraint hr_performance_calibration_item_unique unique (tenant_id, session_id, review_id),
  constraint hr_performance_calibration_item_scores_check check (
    original_score between 0 and 100 and calibrated_score between 0 and 100
  ),
  constraint hr_performance_calibration_item_levels_check check (
    original_level in ('s', 'a', 'b', 'c', 'd')
    and calibrated_level in ('s', 'a', 'b', 'c', 'd')
  ),
  constraint hr_performance_calibration_item_reason_check check (
    (calibrated_score = original_score and calibrated_level = original_level)
    or nullif(btrim(adjustment_reason), '') is not null
  )
);

create index hr_performance_calibration_item_session_idx
  on public.hr_performance_calibration_item(tenant_id, session_id, calibrated_level);
create index hr_performance_calibration_item_review_fk_idx
  on public.hr_performance_calibration_item(review_id, tenant_id);

create trigger hr_performance_check_in_create_audit before insert on public.hr_performance_check_in
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_performance_check_in_update_audit before update on public.hr_performance_check_in
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_performance_calibration_session_create_audit before insert on public.hr_performance_calibration_session
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_performance_calibration_session_update_audit before update on public.hr_performance_calibration_session
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_performance_calibration_item_create_audit before insert on public.hr_performance_calibration_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_performance_calibration_item_update_audit before update on public.hr_performance_calibration_item
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_performance_check_in enable row level security;
alter table public.hr_performance_calibration_session enable row level security;
alter table public.hr_performance_calibration_item enable row level security;

create policy hr_performance_check_in_deny_direct_access on public.hr_performance_check_in
  for all to authenticated using (false) with check (false);
create policy hr_performance_calibration_session_deny_direct_access on public.hr_performance_calibration_session
  for all to authenticated using (false) with check (false);
create policy hr_performance_calibration_item_deny_direct_access on public.hr_performance_calibration_item
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_performance_cycle from public, anon, authenticated;
revoke all on table public.hr_performance_review from public, anon, authenticated;
revoke all on table public.hr_performance_goal from public, anon, authenticated;
revoke all on table public.hr_performance_check_in from public, anon, authenticated;
revoke all on table public.hr_performance_calibration_session from public, anon, authenticated;
revoke all on table public.hr_performance_calibration_item from public, anon, authenticated;
grant all on table public.hr_performance_cycle to service_role;
grant all on table public.hr_performance_review to service_role;
grant all on table public.hr_performance_goal to service_role;
grant all on table public.hr_performance_check_in to service_role;
grant all on table public.hr_performance_calibration_session to service_role;
grant all on table public.hr_performance_calibration_item to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('绩效目标类型', 'hrPerformanceGoalType', 101),
  ('绩效目标状态', 'hrPerformanceGoalStatus', 102),
  ('绩效沟通风险', 'hrPerformanceCheckInRisk', 103),
  ('绩效校准状态', 'hrPerformanceCalibrationStatus', 104)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 绩效管理字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set
  name = excluded.name, status = excluded.status, update_by = excluded.update_by,
  update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrPerformanceGoalType', 'business', '经营目标', 1, 'primary'),
  ('hrPerformanceGoalType', 'customer', '客户目标', 2, 'success'),
  ('hrPerformanceGoalType', 'operations', '运营目标', 3, 'primary'),
  ('hrPerformanceGoalType', 'safety', '安全目标', 4, 'danger'),
  ('hrPerformanceGoalType', 'development', '发展目标', 5, 'warning'),
  ('hrPerformanceGoalStatus', 'draft', '待启动', 1, 'info'),
  ('hrPerformanceGoalStatus', 'in_progress', '推进中', 2, 'primary'),
  ('hrPerformanceGoalStatus', 'at_risk', '存在风险', 3, 'warning'),
  ('hrPerformanceGoalStatus', 'completed', '已完成', 4, 'success'),
  ('hrPerformanceCheckInRisk', 'on_track', '进展正常', 1, 'success'),
  ('hrPerformanceCheckInRisk', 'attention', '需要关注', 2, 'warning'),
  ('hrPerformanceCheckInRisk', 'off_track', '已偏离目标', 3, 'danger'),
  ('hrPerformanceCalibrationStatus', 'setup', '筹备中', 1, 'info'),
  ('hrPerformanceCalibrationStatus', 'in_progress', '校准中', 2, 'warning'),
  ('hrPerformanceCalibrationStatus', 'approved', '已定案', 3, 'success'),
  ('hrPerformanceCalibrationStatus', 'deactivated', '已停用', 4, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 绩效管理字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

update public.sys_dictionary d
set label = case d.value when 'confirmed' then '待校准' when 'completed' then '已完成' else d.label end,
    update_by = '624944977@qq.com', update_time = now()
from public.sys_dict_type t
where t.id = d.type_id and t.code = 'hrPerformanceReviewStatus'
  and d.value in ('confirmed', 'completed');

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000301'::uuid, seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8601-000000000005'::uuid, 'Hr:Performance:Activate', '启动或推进绩效周期', 5),
  ('c0de0000-0000-4000-8601-000000000006'::uuid, 'Hr:Performance:Review', '提交自评或主管评价', 6),
  ('c0de0000-0000-4000-8601-000000000007'::uuid, 'Hr:Performance:Calibrate', '执行绩效校准', 7),
  ('c0de0000-0000-4000-8601-000000000008'::uuid, 'Hr:Performance:Complete', '完成绩效结果', 8)
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
  ('c0de0000-0000-4000-8601-000000000005'::uuid),
  ('c0de0000-0000-4000-8601-000000000006'::uuid),
  ('c0de0000-0000-4000-8601-000000000007'::uuid),
  ('c0de0000-0000-4000-8601-000000000008'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000301'::uuid
on conflict (role_id, menu_id) do nothing;

;
