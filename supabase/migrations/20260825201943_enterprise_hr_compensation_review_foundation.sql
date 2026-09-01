-- Enterprise compensation review foundation.
-- The review workspace governs annual/periodic pay decisions. The existing
-- compensation module remains the source of effective-dated employee pay.

create table public.hr_compensation_review_cycle (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  cycle_code text not null,
  cycle_name text not null,
  review_year integer not null,
  effective_date date not null,
  recommendation_due_date date not null,
  calibration_due_date date not null,
  scope_organization_id uuid,
  currency_code text not null default 'CNY',
  default_budget_percent numeric(7, 4) not null default 5,
  guideline_min_percent numeric(7, 4) not null default 0,
  guideline_max_percent numeric(7, 4) not null default 10,
  status text not null default 'draft',
  description text,
  decision_note text,
  opened_at timestamptz,
  approved_at timestamptz,
  effected_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_compensation_review_cycle_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compensation_review_cycle_scope_fkey
    foreign key (scope_organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_cycle_id_tenant_unique unique (id, tenant_id),
  constraint hr_compensation_review_cycle_code_not_blank check (btrim(cycle_code) <> ''),
  constraint hr_compensation_review_cycle_name_not_blank check (btrim(cycle_name) <> ''),
  constraint hr_compensation_review_cycle_year_check check (review_year between 2000 and 2200),
  constraint hr_compensation_review_cycle_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_compensation_review_cycle_budget_check
    check (default_budget_percent between 0 and 100),
  constraint hr_compensation_review_cycle_guideline_check check (
    guideline_min_percent between -100 and 500
    and guideline_max_percent between -100 and 500
    and guideline_min_percent <= guideline_max_percent
  ),
  constraint hr_compensation_review_cycle_dates_check check (
    recommendation_due_date <= calibration_due_date
    and calibration_due_date <= effective_date
  ),
  constraint hr_compensation_review_cycle_status_check check (
    status in ('draft', 'open', 'calibrating', 'approved', 'effected', 'cancelled')
  )
);

create unique index hr_compensation_review_cycle_tenant_code_unique
  on public.hr_compensation_review_cycle(tenant_id, lower(cycle_code));

create index hr_compensation_review_cycle_tenant_status_date_idx
  on public.hr_compensation_review_cycle(tenant_id, status, effective_date desc);

create index hr_compensation_review_cycle_scope_idx
  on public.hr_compensation_review_cycle(scope_organization_id, tenant_id)
  where scope_organization_id is not null;

create table public.hr_compensation_review_budget (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  cycle_id uuid not null,
  organization_id uuid,
  budget_amount numeric(18, 2) not null default 0,
  source text not null default 'manual',
  note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_compensation_review_budget_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compensation_review_budget_cycle_fkey foreign key (cycle_id, tenant_id)
    references public.hr_compensation_review_cycle(id, tenant_id) on delete cascade,
  constraint hr_compensation_review_budget_organization_fkey
    foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_budget_id_tenant_unique unique (id, tenant_id),
  constraint hr_compensation_review_budget_amount_check check (budget_amount >= 0),
  constraint hr_compensation_review_budget_source_check check (source in ('auto', 'manual'))
);

create unique index hr_compensation_review_budget_scope_unique
  on public.hr_compensation_review_budget(cycle_id, organization_id) nulls not distinct;

create index hr_compensation_review_budget_cycle_idx
  on public.hr_compensation_review_budget(cycle_id, tenant_id, organization_id);

create index hr_compensation_review_budget_organization_idx
  on public.hr_compensation_review_budget(organization_id, tenant_id)
  where organization_id is not null;

create table public.hr_compensation_review_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  cycle_id uuid not null,
  employee_id uuid not null,
  organization_id uuid,
  current_compensation_id uuid not null,
  current_grade_id uuid,
  current_base_amount numeric(18, 2) not null,
  proposed_base_amount numeric(18, 2) not null,
  performance_level text,
  status text not null default 'pending',
  recommendation_reason text,
  recommended_by text,
  recommended_at timestamptz,
  calibration_note text,
  calibrated_by text,
  calibrated_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  exclusion_reason text,
  new_compensation_id uuid,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_compensation_review_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compensation_review_item_cycle_fkey foreign key (cycle_id, tenant_id)
    references public.hr_compensation_review_cycle(id, tenant_id) on delete cascade,
  constraint hr_compensation_review_item_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_item_organization_fkey
    foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_item_current_compensation_fkey
    foreign key (current_compensation_id, tenant_id)
    references public.hr_employee_compensation(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_item_grade_fkey foreign key (current_grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_item_new_compensation_fkey
    foreign key (new_compensation_id, tenant_id)
    references public.hr_employee_compensation(id, tenant_id) on delete restrict,
  constraint hr_compensation_review_item_id_tenant_unique unique (id, tenant_id),
  constraint hr_compensation_review_item_cycle_employee_unique unique (cycle_id, employee_id),
  constraint hr_compensation_review_item_amounts_check check (
    current_base_amount >= 0 and proposed_base_amount >= 0
  ),
  constraint hr_compensation_review_item_status_check check (
    status in ('pending', 'recommended', 'calibrated', 'approved', 'effected', 'excluded')
  ),
  constraint hr_compensation_review_item_exclusion_reason_check check (
    status <> 'excluded' or nullif(btrim(exclusion_reason), '') is not null
  )
);

create index hr_compensation_review_item_cycle_status_idx
  on public.hr_compensation_review_item(cycle_id, tenant_id, status, organization_id);

create index hr_compensation_review_item_employee_idx
  on public.hr_compensation_review_item(employee_id, tenant_id, cycle_id);

create index hr_compensation_review_item_organization_idx
  on public.hr_compensation_review_item(organization_id, tenant_id)
  where organization_id is not null;

create index hr_compensation_review_item_current_compensation_idx
  on public.hr_compensation_review_item(current_compensation_id, tenant_id);

create unique index hr_compensation_review_item_new_compensation_unique
  on public.hr_compensation_review_item(new_compensation_id)
  where new_compensation_id is not null;

alter table public.hr_employee_compensation
  add column source_review_item_id uuid;

alter table public.hr_employee_compensation
  add constraint hr_employee_compensation_source_review_item_fkey
  foreign key (source_review_item_id, tenant_id)
  references public.hr_compensation_review_item(id, tenant_id) on delete restrict;

create unique index hr_employee_compensation_source_review_item_unique
  on public.hr_employee_compensation(source_review_item_id)
  where source_review_item_id is not null;

create trigger hr_compensation_review_cycle_create_audit before insert
on public.hr_compensation_review_cycle for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_compensation_review_cycle_update_audit before update
on public.hr_compensation_review_cycle for each row
execute function public.trg_set_update_time_and_by();

create trigger hr_compensation_review_budget_create_audit before insert
on public.hr_compensation_review_budget for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_compensation_review_budget_update_audit before update
on public.hr_compensation_review_budget for each row
execute function public.trg_set_update_time_and_by();

create trigger hr_compensation_review_item_create_audit before insert
on public.hr_compensation_review_item for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_compensation_review_item_update_audit before update
on public.hr_compensation_review_item for each row
execute function public.trg_set_update_time_and_by();

alter table public.hr_compensation_review_cycle enable row level security;
alter table public.hr_compensation_review_budget enable row level security;
alter table public.hr_compensation_review_item enable row level security;

revoke all on table public.hr_compensation_review_cycle from public, anon, authenticated;
revoke all on table public.hr_compensation_review_budget from public, anon, authenticated;
revoke all on table public.hr_compensation_review_item from public, anon, authenticated;

grant all on table public.hr_compensation_review_cycle to service_role;
grant all on table public.hr_compensation_review_budget to service_role;
grant all on table public.hr_compensation_review_item to service_role;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000211'::uuid,
  'c0de0000-0000-4000-8000-000000000201'::uuid,
  'HrCompensationReview',
  'compensation-review',
  '/hr/operations/compensation-review',
  jsonb_build_object(
    'title', '调薪复核',
    'icon', 'ri:funds-box-line',
    'is_hide', false,
    'is_enable', true,
    'keep_alive', true,
    'roles', jsonb_build_array()
  ),
  11,
  'menu',
  'hr',
  '624944977@qq.com',
  '624944977@qq.com'
)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select
  seed.id,
  'c0de0000-0000-4000-8000-000000000211'::uuid,
  seed.name,
  '',
  '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ),
  seed.sort,
  'button',
  'hr',
  '624944977@qq.com',
  '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8211-000000000001'::uuid, 'Hr:CompensationReview:View', '查看调薪复核', 1),
  ('c0de0000-0000-4000-8211-000000000002'::uuid, 'Hr:CompensationReview:Cycle:Manage', '管理调薪周期', 2),
  ('c0de0000-0000-4000-8211-000000000003'::uuid, 'Hr:CompensationReview:Budget:Manage', '管理调薪预算', 3),
  ('c0de0000-0000-4000-8211-000000000004'::uuid, 'Hr:CompensationReview:Recommend', '提交调薪建议', 4),
  ('c0de0000-0000-4000-8211-000000000005'::uuid, 'Hr:CompensationReview:Calibrate', '执行调薪校准', 5),
  ('c0de0000-0000-4000-8211-000000000006'::uuid, 'Hr:CompensationReview:Approve', '批准调薪结果', 6),
  ('c0de0000-0000-4000-8211-000000000007'::uuid, 'Hr:CompensationReview:Effect', '批量生效调薪', 7),
  ('c0de0000-0000-4000-8211-000000000008'::uuid, 'Hr:CompensationReview:Amount:View', '查看调薪金额', 8),
  ('c0de0000-0000-4000-8211-000000000009'::uuid, 'Hr:CompensationReview:Amount:Edit', '编辑调薪金额', 9)
) as seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select
  existing.role_id,
  new_menu.menu_id,
  existing.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('c0de0000-0000-4000-8000-000000000211'::uuid),
  ('c0de0000-0000-4000-8211-000000000001'::uuid),
  ('c0de0000-0000-4000-8211-000000000002'::uuid),
  ('c0de0000-0000-4000-8211-000000000003'::uuid),
  ('c0de0000-0000-4000-8211-000000000004'::uuid),
  ('c0de0000-0000-4000-8211-000000000005'::uuid),
  ('c0de0000-0000-4000-8211-000000000006'::uuid),
  ('c0de0000-0000-4000-8211-000000000007'::uuid),
  ('c0de0000-0000-4000-8211-000000000008'::uuid),
  ('c0de0000-0000-4000-8211-000000000009'::uuid)
) as new_menu(menu_id)
where existing.menu_id = 'c0de0000-0000-4000-8000-000000000205'::uuid
on conflict (role_id, menu_id) do nothing;


;
