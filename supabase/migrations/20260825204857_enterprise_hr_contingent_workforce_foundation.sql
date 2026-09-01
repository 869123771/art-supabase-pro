-- Enterprise contingent workforce foundation.
-- External workers remain separate from the employee master so they do not
-- pollute employee headcount, payroll, benefits or statutory reporting.

create table public.hr_external_vendor (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  vendor_code text not null,
  vendor_name text not null,
  registration_no text,
  contact_name text,
  contact_phone text,
  contact_email text,
  service_scope text,
  contract_no text,
  contract_start_date date,
  contract_end_date date,
  compliance_status text not null default 'pending',
  risk_level text not null default 'medium',
  status text not null default 'draft',
  note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_external_vendor_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_external_vendor_id_tenant_unique unique (id, tenant_id),
  constraint hr_external_vendor_code_not_blank check (btrim(vendor_code) <> ''),
  constraint hr_external_vendor_name_not_blank check (btrim(vendor_name) <> ''),
  constraint hr_external_vendor_dates_check check (
    contract_start_date is null or contract_end_date is null
    or contract_start_date <= contract_end_date
  ),
  constraint hr_external_vendor_compliance_check check (
    compliance_status in ('pending', 'verified', 'rejected', 'expired')
  ),
  constraint hr_external_vendor_risk_check check (risk_level in ('low', 'medium', 'high')),
  constraint hr_external_vendor_status_check check (
    status in ('draft', 'active', 'suspended', 'expired', 'inactive')
  )
);

create unique index hr_external_vendor_tenant_code_unique
  on public.hr_external_vendor(tenant_id, lower(vendor_code));

create index hr_external_vendor_tenant_status_idx
  on public.hr_external_vendor(tenant_id, status, compliance_status, contract_end_date);

create table public.hr_external_worker (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  worker_no text not null,
  worker_name text not null,
  worker_type text not null,
  vendor_id uuid,
  vendor_worker_no text,
  phone text,
  email text,
  identity_check_status text not null default 'pending',
  status text not null default 'candidate',
  note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_external_worker_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_external_worker_vendor_fkey foreign key (vendor_id, tenant_id)
    references public.hr_external_vendor(id, tenant_id) on delete restrict,
  constraint hr_external_worker_id_tenant_unique unique (id, tenant_id),
  constraint hr_external_worker_no_not_blank check (btrim(worker_no) <> ''),
  constraint hr_external_worker_name_not_blank check (btrim(worker_name) <> ''),
  constraint hr_external_worker_type_check check (
    worker_type in ('outsourced', 'dispatch', 'contractor', 'consultant', 'temporary')
  ),
  constraint hr_external_worker_identity_check check (
    identity_check_status in ('pending', 'passed', 'failed', 'expired')
  ),
  constraint hr_external_worker_status_check check (
    status in ('candidate', 'ready', 'active', 'inactive', 'blocked')
  )
);

create unique index hr_external_worker_tenant_no_unique
  on public.hr_external_worker(tenant_id, lower(worker_no));

create index hr_external_worker_tenant_status_idx
  on public.hr_external_worker(tenant_id, status, worker_type);

create index hr_external_worker_vendor_idx
  on public.hr_external_worker(vendor_id, tenant_id)
  where vendor_id is not null;

create table public.hr_external_engagement (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  engagement_no text not null,
  worker_id uuid not null,
  vendor_id uuid,
  organization_id uuid not null,
  position_id uuid,
  sponsor_employee_id uuid not null,
  service_title text not null,
  work_location text,
  start_date date not null,
  end_date date not null,
  access_expiry_date date not null,
  actual_exit_date date,
  fte numeric(5, 4) not null default 1,
  billing_rate numeric(18, 2),
  billing_unit text,
  currency_code text not null default 'CNY',
  compliance_status text not null default 'pending',
  status text not null default 'draft',
  activation_note text,
  end_reason text,
  version integer not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_external_engagement_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_external_engagement_worker_fkey foreign key (worker_id, tenant_id)
    references public.hr_external_worker(id, tenant_id) on delete restrict,
  constraint hr_external_engagement_vendor_fkey foreign key (vendor_id, tenant_id)
    references public.hr_external_vendor(id, tenant_id) on delete restrict,
  constraint hr_external_engagement_organization_fkey
    foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_external_engagement_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_external_engagement_sponsor_fkey foreign key (sponsor_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_external_engagement_id_tenant_unique unique (id, tenant_id),
  constraint hr_external_engagement_no_not_blank check (btrim(engagement_no) <> ''),
  constraint hr_external_engagement_title_not_blank check (btrim(service_title) <> ''),
  constraint hr_external_engagement_dates_check check (
    start_date <= end_date
    and access_expiry_date between start_date and end_date
    and (actual_exit_date is null or actual_exit_date >= start_date)
  ),
  constraint hr_external_engagement_fte_check check (fte > 0 and fte <= 1),
  constraint hr_external_engagement_rate_check check (
    billing_rate is null or billing_rate >= 0
  ),
  constraint hr_external_engagement_billing_unit_check check (
    billing_unit is null or billing_unit in ('hour', 'day', 'month', 'fixed')
  ),
  constraint hr_external_engagement_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_external_engagement_compliance_check check (
    compliance_status in ('pending', 'cleared', 'blocked', 'expired')
  ),
  constraint hr_external_engagement_status_check check (
    status in ('draft', 'pending_review', 'active', 'offboarding', 'ended', 'cancelled')
  ),
  constraint hr_external_engagement_version_positive check (version > 0)
);

create unique index hr_external_engagement_tenant_no_unique
  on public.hr_external_engagement(tenant_id, lower(engagement_no));

create index hr_external_engagement_tenant_status_end_idx
  on public.hr_external_engagement(tenant_id, status, end_date, access_expiry_date);

create index hr_external_engagement_worker_idx
  on public.hr_external_engagement(worker_id, tenant_id, start_date desc);

create index hr_external_engagement_vendor_idx
  on public.hr_external_engagement(vendor_id, tenant_id)
  where vendor_id is not null;

create index hr_external_engagement_organization_idx
  on public.hr_external_engagement(organization_id, tenant_id, status);

create index hr_external_engagement_position_idx
  on public.hr_external_engagement(position_id, tenant_id)
  where position_id is not null;

create index hr_external_engagement_sponsor_idx
  on public.hr_external_engagement(sponsor_employee_id, tenant_id, status);

create table public.hr_external_engagement_control (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  engagement_id uuid not null,
  control_type text not null,
  control_name text not null,
  required boolean not null default true,
  status text not null default 'pending',
  due_date date,
  completed_at timestamptz,
  completed_by text,
  evidence_reference text,
  note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_external_control_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_external_control_engagement_fkey foreign key (engagement_id, tenant_id)
    references public.hr_external_engagement(id, tenant_id) on delete cascade,
  constraint hr_external_control_id_tenant_unique unique (id, tenant_id),
  constraint hr_external_control_name_not_blank check (btrim(control_name) <> ''),
  constraint hr_external_control_type_check check (
    control_type in (
      'identity', 'contract', 'nda', 'insurance', 'safety_training',
      'access_badge', 'system_account', 'equipment', 'other'
    )
  ),
  constraint hr_external_control_status_check check (
    status in ('pending', 'completed', 'waived', 'failed')
  ),
  constraint hr_external_control_completion_check check (
    (status = 'completed' and completed_at is not null)
    or status <> 'completed'
  ),
  constraint hr_external_control_waiver_check check (
    status <> 'waived' or nullif(btrim(note), '') is not null
  )
);

create unique index hr_external_control_engagement_name_unique
  on public.hr_external_engagement_control(engagement_id, lower(control_name));

create index hr_external_control_tenant_status_idx
  on public.hr_external_engagement_control(tenant_id, status, due_date);

create index hr_external_control_engagement_idx
  on public.hr_external_engagement_control(engagement_id, tenant_id, required, status);

create trigger hr_external_vendor_create_audit before insert
on public.hr_external_vendor for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_external_vendor_update_audit before update
on public.hr_external_vendor for each row
execute function public.trg_set_update_time_and_by();

create trigger hr_external_worker_create_audit before insert
on public.hr_external_worker for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_external_worker_update_audit before update
on public.hr_external_worker for each row
execute function public.trg_set_update_time_and_by();

create trigger hr_external_engagement_create_audit before insert
on public.hr_external_engagement for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_external_engagement_update_audit before update
on public.hr_external_engagement for each row
execute function public.trg_set_update_time_and_by();

create trigger hr_external_control_create_audit before insert
on public.hr_external_engagement_control for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger hr_external_control_update_audit before update
on public.hr_external_engagement_control for each row
execute function public.trg_set_update_time_and_by();

alter table public.hr_external_vendor enable row level security;
alter table public.hr_external_worker enable row level security;
alter table public.hr_external_engagement enable row level security;
alter table public.hr_external_engagement_control enable row level security;

revoke all on table public.hr_external_vendor from public, anon, authenticated;
revoke all on table public.hr_external_worker from public, anon, authenticated;
revoke all on table public.hr_external_engagement from public, anon, authenticated;
revoke all on table public.hr_external_engagement_control from public, anon, authenticated;

grant all on table public.hr_external_vendor to service_role;
grant all on table public.hr_external_worker to service_role;
grant all on table public.hr_external_engagement to service_role;
grant all on table public.hr_external_engagement_control to service_role;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000212'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrContingentWorkforce',
  'contingent-workforce',
  '/hr/operations/contingent-workforce',
  jsonb_build_object(
    'title', '外部用工',
    'icon', 'ri:team-line',
    'is_hide', false,
    'is_enable', true,
    'keep_alive', true,
    'roles', jsonb_build_array()
  ),
  12,
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
  'c0de0000-0000-4000-8000-000000000212'::uuid,
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
  ('c0de0000-0000-4000-8212-000000000001'::uuid, 'Hr:ContingentWorkforce:View', '查看外部用工', 1),
  ('c0de0000-0000-4000-8212-000000000002'::uuid, 'Hr:ContingentWorkforce:Vendor:Manage', '管理用工供应商', 2),
  ('c0de0000-0000-4000-8212-000000000003'::uuid, 'Hr:ContingentWorkforce:Worker:Manage', '管理外部人员', 3),
  ('c0de0000-0000-4000-8212-000000000004'::uuid, 'Hr:ContingentWorkforce:Engagement:Manage', '管理用工任务', 4),
  ('c0de0000-0000-4000-8212-000000000005'::uuid, 'Hr:ContingentWorkforce:Control:Manage', '管理准入控制', 5),
  ('c0de0000-0000-4000-8212-000000000006'::uuid, 'Hr:ContingentWorkforce:Activate', '激活外部用工', 6),
  ('c0de0000-0000-4000-8212-000000000007'::uuid, 'Hr:ContingentWorkforce:End', '执行外部人员退场', 7),
  ('c0de0000-0000-4000-8212-000000000008'::uuid, 'Hr:ContingentWorkforce:PII:View', '查看外部人员联系方式', 8),
  ('c0de0000-0000-4000-8212-000000000009'::uuid, 'Hr:ContingentWorkforce:Cost:View', '查看外部用工成本', 9),
  ('c0de0000-0000-4000-8212-000000000010'::uuid, 'Hr:ContingentWorkforce:Cost:Edit', '编辑外部用工成本', 10)
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

-- Enabled ordinary users inherit only the page and tenant-scoped read action
-- from existing HR operations access. Controlled writes and sensitive fields
-- remain platform-super-only until a specialist role is explicitly assigned.
insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select distinct
  existing.role_id,
  new_menu.menu_id,
  existing.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('c0de0000-0000-4000-8000-000000000212'::uuid),
  ('c0de0000-0000-4000-8212-000000000001'::uuid)
) as new_menu(menu_id)
where existing.menu_id = 'c0de0000-0000-4000-8000-000000000205'::uuid
on conflict (role_id, menu_id) do nothing;

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select
  role_row.id,
  new_menu.menu_id,
  role_row.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role role_row
cross join (values
  ('c0de0000-0000-4000-8000-000000000212'::uuid),
  ('c0de0000-0000-4000-8212-000000000001'::uuid),
  ('c0de0000-0000-4000-8212-000000000002'::uuid),
  ('c0de0000-0000-4000-8212-000000000003'::uuid),
  ('c0de0000-0000-4000-8212-000000000004'::uuid),
  ('c0de0000-0000-4000-8212-000000000005'::uuid),
  ('c0de0000-0000-4000-8212-000000000006'::uuid),
  ('c0de0000-0000-4000-8212-000000000007'::uuid),
  ('c0de0000-0000-4000-8212-000000000008'::uuid),
  ('c0de0000-0000-4000-8212-000000000009'::uuid),
  ('c0de0000-0000-4000-8212-000000000010'::uuid)
) as new_menu(menu_id)
where role_row.role_code = 'R_SUPER'
on conflict (role_id, menu_id) do nothing;

;
