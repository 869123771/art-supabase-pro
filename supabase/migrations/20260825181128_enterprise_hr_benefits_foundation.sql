-- Enterprise HR benefits administration foundation.
-- HR owns plans, eligibility windows and employee elections. Payroll and FMS
-- may consume approved contribution snapshots, but never mutate benefit state.

create table public.hr_benefit_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_code text not null,
  plan_name text not null,
  plan_type text not null,
  provider_name text,
  enrollment_method text not null default 'election',
  coverage_scope text not null default 'employee',
  currency_code text not null default 'CNY',
  effective_from date not null,
  effective_to date,
  status text not null default 'draft',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_benefit_plan_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_benefit_plan_id_tenant_unique unique (id, tenant_id),
  constraint hr_benefit_plan_code_not_blank check (btrim(plan_code) <> ''),
  constraint hr_benefit_plan_name_not_blank check (btrim(plan_name) <> ''),
  constraint hr_benefit_plan_type_check check (
    plan_type in ('social_insurance', 'housing_fund', 'commercial_insurance',
      'allowance', 'flexible_benefit', 'wellness', 'other')
  ),
  constraint hr_benefit_plan_enrollment_method_check check (
    enrollment_method in ('automatic', 'election')
  ),
  constraint hr_benefit_plan_coverage_scope_check check (
    coverage_scope in ('employee', 'employee_family')
  ),
  constraint hr_benefit_plan_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_benefit_plan_dates_check check (
    effective_to is null or effective_to >= effective_from
  ),
  constraint hr_benefit_plan_status_check check (
    status in ('draft', 'active', 'inactive', 'cancelled')
  )
);

create unique index hr_benefit_plan_tenant_code_unique
  on public.hr_benefit_plan(tenant_id, lower(plan_code));
create index hr_benefit_plan_tenant_status_effective_idx
  on public.hr_benefit_plan(tenant_id, status, effective_from desc);
create index hr_benefit_plan_active_effective_idx
  on public.hr_benefit_plan(tenant_id, effective_from, effective_to)
  where status = 'active';

create table public.hr_benefit_option (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_id uuid not null,
  option_code text not null,
  option_name text not null,
  coverage_level text not null default 'employee',
  contribution_type text not null default 'fixed',
  employee_contribution numeric(18,2) not null default 0,
  employer_contribution numeric(18,2) not null default 0,
  employee_rate numeric(12,6),
  employer_rate numeric(12,6),
  pay_component_id uuid,
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_benefit_option_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_benefit_option_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_benefit_plan(id, tenant_id) on delete cascade,
  constraint hr_benefit_option_pay_component_fkey foreign key (pay_component_id, tenant_id)
    references public.hr_pay_component(id, tenant_id) on delete restrict,
  constraint hr_benefit_option_id_tenant_unique unique (id, tenant_id),
  constraint hr_benefit_option_plan_code_unique unique (plan_id, option_code),
  constraint hr_benefit_option_code_not_blank check (btrim(option_code) <> ''),
  constraint hr_benefit_option_name_not_blank check (btrim(option_name) <> ''),
  constraint hr_benefit_option_coverage_level_check check (
    coverage_level in ('employee', 'employee_spouse', 'employee_children', 'family')
  ),
  constraint hr_benefit_option_contribution_type_check check (
    contribution_type in ('fixed', 'salary_rate')
  ),
  constraint hr_benefit_option_amounts_nonnegative check (
    employee_contribution >= 0 and employer_contribution >= 0
    and (employee_rate is null or employee_rate >= 0)
    and (employer_rate is null or employer_rate >= 0)
  ),
  constraint hr_benefit_option_contribution_shape_check check (
    (contribution_type = 'fixed' and employee_rate is null and employer_rate is null)
    or contribution_type = 'salary_rate'
  )
);

create index hr_benefit_option_plan_enabled_sort_idx
  on public.hr_benefit_option(tenant_id, plan_id, enabled, sort, option_name);
create index hr_benefit_option_pay_component_idx
  on public.hr_benefit_option(tenant_id, pay_component_id)
  where pay_component_id is not null;

create table public.hr_benefit_life_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  event_type text not null,
  event_date date not null,
  enrollment_window_end date not null,
  status text not null default 'open',
  evidence_urls jsonb not null default '[]'::jsonb,
  remark text,
  processed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_benefit_life_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_benefit_life_event_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_benefit_life_event_id_tenant_unique unique (id, tenant_id),
  constraint hr_benefit_life_event_type_check check (
    event_type in ('hire', 'marriage', 'birth', 'adoption', 'loss_of_coverage',
      'transfer', 'termination', 'annual_enrollment', 'other')
  ),
  constraint hr_benefit_life_event_status_check check (
    status in ('open', 'processed', 'expired', 'cancelled')
  ),
  constraint hr_benefit_life_event_window_check check (
    enrollment_window_end >= event_date
  ),
  constraint hr_benefit_life_event_evidence_array check (
    jsonb_typeof(evidence_urls) = 'array'
  )
);

create index hr_benefit_life_event_employee_date_idx
  on public.hr_benefit_life_event(tenant_id, employee_id, event_date desc);
create index hr_benefit_life_event_open_window_idx
  on public.hr_benefit_life_event(tenant_id, enrollment_window_end, event_date)
  where status = 'open';

create table public.hr_employee_benefit_enrollment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  plan_id uuid not null,
  option_id uuid not null,
  life_event_id uuid,
  enrollment_no text not null,
  coverage_from date not null,
  coverage_to date,
  status text not null default 'draft',
  waiver_reason text,
  employee_contribution numeric(18,2) not null default 0,
  employer_contribution numeric(18,2) not null default 0,
  currency_code text not null default 'CNY',
  payroll_sync_status text not null default 'not_ready',
  approved_by text,
  approved_at timestamptz,
  ended_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_benefit_enrollment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_benefit_enrollment_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_benefit_enrollment_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_benefit_plan(id, tenant_id) on delete restrict,
  constraint hr_employee_benefit_enrollment_option_fkey foreign key (option_id, tenant_id)
    references public.hr_benefit_option(id, tenant_id) on delete restrict,
  constraint hr_employee_benefit_enrollment_event_fkey foreign key (life_event_id, tenant_id)
    references public.hr_benefit_life_event(id, tenant_id) on delete restrict,
  constraint hr_employee_benefit_enrollment_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_benefit_enrollment_no_unique unique (tenant_id, enrollment_no),
  constraint hr_employee_benefit_enrollment_no_not_blank check (btrim(enrollment_no) <> ''),
  constraint hr_employee_benefit_enrollment_dates_check check (
    coverage_to is null or coverage_to >= coverage_from
  ),
  constraint hr_employee_benefit_enrollment_status_check check (
    status in ('draft', 'pending', 'active', 'waived', 'ended', 'cancelled')
  ),
  constraint hr_employee_benefit_enrollment_waiver_check check (
    status <> 'waived' or nullif(btrim(waiver_reason), '') is not null
  ),
  constraint hr_employee_benefit_enrollment_amounts_nonnegative check (
    employee_contribution >= 0 and employer_contribution >= 0
  ),
  constraint hr_employee_benefit_enrollment_currency_check check (
    currency_code ~ '^[A-Z]{3}$'
  ),
  constraint hr_employee_benefit_enrollment_payroll_status_check check (
    payroll_sync_status in ('not_ready', 'ready', 'exported', 'stopped')
  )
);

create index hr_employee_benefit_enrollment_employee_idx
  on public.hr_employee_benefit_enrollment(tenant_id, employee_id, coverage_from desc);
create index hr_employee_benefit_enrollment_plan_status_idx
  on public.hr_employee_benefit_enrollment(tenant_id, plan_id, status, coverage_from desc);
create index hr_employee_benefit_enrollment_option_idx
  on public.hr_employee_benefit_enrollment(tenant_id, option_id);
create index hr_employee_benefit_enrollment_event_idx
  on public.hr_employee_benefit_enrollment(tenant_id, life_event_id)
  where life_event_id is not null;
create index hr_employee_benefit_enrollment_payroll_ready_idx
  on public.hr_employee_benefit_enrollment(tenant_id, coverage_from, coverage_to)
  where status = 'active' and payroll_sync_status in ('ready', 'exported');
create unique index hr_employee_benefit_enrollment_active_unique
  on public.hr_employee_benefit_enrollment(tenant_id, employee_id, plan_id)
  where status in ('pending', 'active');

create table public.hr_benefit_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  summary text not null,
  payload jsonb not null default '{}'::jsonb,
  actor_user_id uuid,
  actor_name text,
  create_time timestamptz not null default now(),
  constraint hr_benefit_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_benefit_event_actor_fkey foreign key (actor_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete set null,
  constraint hr_benefit_event_entity_type_check check (
    entity_type in ('plan', 'option', 'life_event', 'enrollment')
  ),
  constraint hr_benefit_event_type_not_blank check (btrim(event_type) <> ''),
  constraint hr_benefit_event_summary_not_blank check (btrim(summary) <> ''),
  constraint hr_benefit_event_payload_object check (jsonb_typeof(payload) = 'object')
);

create index hr_benefit_event_entity_time_idx
  on public.hr_benefit_event(tenant_id, entity_type, entity_id, create_time desc);
create index hr_benefit_event_actor_idx
  on public.hr_benefit_event(tenant_id, actor_user_id, create_time desc)
  where actor_user_id is not null;

create trigger trg_hr_benefit_plan_update
before update on public.hr_benefit_plan for each row
execute function public.trg_set_update_time_and_by();
create trigger trg_hr_benefit_option_update
before update on public.hr_benefit_option for each row
execute function public.trg_set_update_time_and_by();
create trigger trg_hr_benefit_life_event_update
before update on public.hr_benefit_life_event for each row
execute function public.trg_set_update_time_and_by();
create trigger trg_hr_employee_benefit_enrollment_update
before update on public.hr_employee_benefit_enrollment for each row
execute function public.trg_set_update_time_and_by();

alter table public.hr_benefit_plan enable row level security;
alter table public.hr_benefit_option enable row level security;
alter table public.hr_benefit_life_event enable row level security;
alter table public.hr_employee_benefit_enrollment enable row level security;
alter table public.hr_benefit_event enable row level security;

create policy hr_benefit_plan_direct_deny on public.hr_benefit_plan for all using (false) with check (false);
create policy hr_benefit_option_direct_deny on public.hr_benefit_option for all using (false) with check (false);
create policy hr_benefit_life_event_direct_deny on public.hr_benefit_life_event for all using (false) with check (false);
create policy hr_employee_benefit_enrollment_direct_deny on public.hr_employee_benefit_enrollment for all using (false) with check (false);
create policy hr_benefit_event_direct_deny on public.hr_benefit_event for all using (false) with check (false);

revoke all on public.hr_benefit_plan, public.hr_benefit_option,
  public.hr_benefit_life_event, public.hr_employee_benefit_enrollment,
  public.hr_benefit_event from public, anon, authenticated;
grant all on public.hr_benefit_plan, public.hr_benefit_option,
  public.hr_benefit_life_event, public.hr_employee_benefit_enrollment,
  public.hr_benefit_event to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), type_seed(type_name, type_code, sort) as (
  values
    ('福利计划类型', 'hrBenefitPlanType', 132),
    ('福利计划状态', 'hrBenefitPlanStatus', 133),
    ('福利参保方式', 'hrBenefitEnrollmentMethod', 134),
    ('福利覆盖层级', 'hrBenefitCoverageLevel', 135),
    ('福利缴费方式', 'hrBenefitContributionType', 136),
    ('福利人生事件', 'hrBenefitLifeEventType', 137),
    ('福利人生事件状态', 'hrBenefitLifeEventStatus', 138),
    ('员工参保状态', 'hrBenefitEnrollmentStatus', 139),
    ('福利薪资同步状态', 'hrBenefitPayrollSyncStatus', 140)
)
insert into public.sys_dict_type(
  id, name, code, status, remark, tenant_id, create_by, update_by,
  parent_id, node_type, sort
)
select gen_random_uuid(), type_seed.type_name, type_seed.type_code, '1',
  '企业 HR 福利与参保字典', platform_tenant.id,
  '624944977@qq.com', '624944977@qq.com',
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', type_seed.sort
from type_seed cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_seed(type_code, value, label, sort, tag_type) as (
  values
    ('hrBenefitPlanType','social_insurance','社会保险',1,'primary'),
    ('hrBenefitPlanType','housing_fund','住房公积金',2,'success'),
    ('hrBenefitPlanType','commercial_insurance','商业保险',3,'warning'),
    ('hrBenefitPlanType','allowance','员工津贴',4,'info'),
    ('hrBenefitPlanType','flexible_benefit','弹性福利',5,'primary'),
    ('hrBenefitPlanType','wellness','健康关怀',6,'success'),
    ('hrBenefitPlanType','other','其他福利',7,'info'),
    ('hrBenefitPlanStatus','draft','草稿',1,'info'),
    ('hrBenefitPlanStatus','active','生效中',2,'success'),
    ('hrBenefitPlanStatus','inactive','已停用',3,'warning'),
    ('hrBenefitPlanStatus','cancelled','已取消',4,'danger'),
    ('hrBenefitEnrollmentMethod','automatic','自动参保',1,'primary'),
    ('hrBenefitEnrollmentMethod','election','员工选择',2,'warning'),
    ('hrBenefitCoverageLevel','employee','仅员工',1,'primary'),
    ('hrBenefitCoverageLevel','employee_spouse','员工及配偶',2,'success'),
    ('hrBenefitCoverageLevel','employee_children','员工及子女',3,'warning'),
    ('hrBenefitCoverageLevel','family','家庭',4,'primary'),
    ('hrBenefitContributionType','fixed','固定金额',1,'primary'),
    ('hrBenefitContributionType','salary_rate','工资比例',2,'warning'),
    ('hrBenefitLifeEventType','hire','入职',1,'success'),
    ('hrBenefitLifeEventType','marriage','结婚',2,'primary'),
    ('hrBenefitLifeEventType','birth','生育',3,'primary'),
    ('hrBenefitLifeEventType','adoption','收养',4,'primary'),
    ('hrBenefitLifeEventType','loss_of_coverage','失去原保障',5,'warning'),
    ('hrBenefitLifeEventType','transfer','异动',6,'info'),
    ('hrBenefitLifeEventType','termination','离职',7,'danger'),
    ('hrBenefitLifeEventType','annual_enrollment','年度集中参保',8,'success'),
    ('hrBenefitLifeEventType','other','其他',9,'info'),
    ('hrBenefitLifeEventStatus','open','窗口开放',1,'success'),
    ('hrBenefitLifeEventStatus','processed','已处理',2,'primary'),
    ('hrBenefitLifeEventStatus','expired','已过期',3,'warning'),
    ('hrBenefitLifeEventStatus','cancelled','已取消',4,'danger'),
    ('hrBenefitEnrollmentStatus','draft','草稿',1,'info'),
    ('hrBenefitEnrollmentStatus','pending','待审核',2,'warning'),
    ('hrBenefitEnrollmentStatus','active','保障生效',3,'success'),
    ('hrBenefitEnrollmentStatus','waived','员工放弃',4,'info'),
    ('hrBenefitEnrollmentStatus','ended','保障结束',5,'warning'),
    ('hrBenefitEnrollmentStatus','cancelled','已取消',6,'danger'),
    ('hrBenefitPayrollSyncStatus','not_ready','未就绪',1,'info'),
    ('hrBenefitPayrollSyncStatus','ready','待薪资读取',2,'warning'),
    ('hrBenefitPayrollSyncStatus','exported','薪资已读取',3,'success'),
    ('hrBenefitPayrollSyncStatus','stopped','已停止',4,'danger')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, seed.type_code || '_' || seed.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 福利与参保字典项',
  seed.value, seed.label, platform_tenant.id, seed.tag_type, seed.sort
from dictionary_seed seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = seed.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000208'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrBenefits', 'benefits', '/hr/operations/benefits',
  jsonb_build_object('title', '福利与参保', 'icon', 'ri:heart-pulse-line',
    'is_hide', false, 'is_enable', true, 'roles', jsonb_build_array()),
  8, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  path = excluded.path, component = excluded.component, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000208'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8208-000000000001'::uuid, 'Hr:Benefits:View', '查看福利与参保', 1),
  ('c0de0000-0000-4000-8208-000000000002'::uuid, 'Hr:Benefits:Plan:Manage', '管理福利计划', 2),
  ('c0de0000-0000-4000-8208-000000000003'::uuid, 'Hr:Benefits:Enrollment:Manage', '管理员工参保', 3),
  ('c0de0000-0000-4000-8208-000000000004'::uuid, 'Hr:Benefits:Approve', '审核员工参保', 4),
  ('c0de0000-0000-4000-8208-000000000005'::uuid, 'Hr:Benefits:Event:Manage', '管理福利人生事件', 5),
  ('c0de0000-0000-4000-8208-000000000006'::uuid, 'Hr:Benefits:Amount:View', '查看福利缴费金额', 6),
  ('c0de0000-0000-4000-8208-000000000007'::uuid, 'Hr:Benefits:Payroll:Export', '导出福利薪资输入', 7)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select folder_grant.role_id, target.menu_id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu folder_grant
join public.sys_role role on role.id = folder_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8000-000000000208'::uuid),
  ('c0de0000-0000-4000-8208-000000000001'::uuid)
) target(menu_id)
where folder_grant.menu_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
on conflict (role_id, menu_id) do nothing;

;
