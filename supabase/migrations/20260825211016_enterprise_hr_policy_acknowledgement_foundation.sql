-- Enterprise HR policy versioning and acknowledgement foundation.

create table public.hr_policy_document (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  policy_code text not null,
  policy_title text not null,
  category text not null,
  version_no integer not null default 1,
  effective_date date not null,
  acknowledgement_due_days integer not null default 7,
  audience_type text not null default 'all',
  audience_organization_id uuid,
  audience_employment_type text,
  document_reference text not null,
  content_summary text not null,
  status text not null default 'draft',
  supersedes_policy_id uuid,
  published_at timestamptz,
  published_by text,
  retired_at timestamptz,
  retired_by text,
  decision_note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_policy_document_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_policy_document_audience_organization_fkey
    foreign key (audience_organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_policy_document_supersedes_fkey
    foreign key (supersedes_policy_id, tenant_id)
    references public.hr_policy_document(id, tenant_id) on delete restrict,
  constraint hr_policy_document_id_tenant_unique unique (id, tenant_id),
  constraint hr_policy_document_code_not_blank check (btrim(policy_code) <> ''),
  constraint hr_policy_document_title_not_blank check (btrim(policy_title) <> ''),
  constraint hr_policy_document_category_not_blank check (btrim(category) <> ''),
  constraint hr_policy_document_reference_not_blank check (btrim(document_reference) <> ''),
  constraint hr_policy_document_summary_not_blank check (btrim(content_summary) <> ''),
  constraint hr_policy_document_version_positive check (version_no > 0),
  constraint hr_policy_document_due_days_check check (acknowledgement_due_days between 0 and 365),
  constraint hr_policy_document_audience_type_check check (
    audience_type in ('all', 'organization', 'employment_type')
  ),
  constraint hr_policy_document_audience_scope_check check (
    (audience_type = 'all' and audience_organization_id is null and audience_employment_type is null)
    or (audience_type = 'organization' and audience_organization_id is not null and audience_employment_type is null)
    or (audience_type = 'employment_type' and audience_organization_id is null and nullif(btrim(audience_employment_type), '') is not null)
  ),
  constraint hr_policy_document_status_check check (
    status in ('draft', 'published', 'retired', 'cancelled')
  ),
  constraint hr_policy_document_publish_check check (
    (status in ('published', 'retired') and published_at is not null and published_by is not null)
    or (status in ('draft', 'cancelled') and published_at is null and published_by is null)
  ),
  constraint hr_policy_document_retire_check check (
    (status = 'retired' and retired_at is not null and retired_by is not null)
    or (status <> 'retired' and retired_at is null and retired_by is null)
  ),
  constraint hr_policy_document_not_self_supersede check (supersedes_policy_id is distinct from id)
);

create unique index hr_policy_document_tenant_code_version_unique
  on public.hr_policy_document(tenant_id, lower(policy_code), version_no);
create index hr_policy_document_tenant_status_effective_idx
  on public.hr_policy_document(tenant_id, status, effective_date desc);
create index hr_policy_document_audience_organization_idx
  on public.hr_policy_document(audience_organization_id, tenant_id)
  where audience_organization_id is not null;
create index hr_policy_document_supersedes_idx
  on public.hr_policy_document(supersedes_policy_id, tenant_id)
  where supersedes_policy_id is not null;

create table public.hr_policy_receipt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  policy_id uuid not null,
  employee_id uuid not null,
  delivered_at timestamptz not null default now(),
  due_date date not null,
  status text not null default 'pending',
  acknowledged_at timestamptz,
  acknowledged_by text,
  acknowledgement_note text,
  evidence_reference text,
  waived_at timestamptz,
  waived_by text,
  waiver_reason text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_policy_receipt_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_policy_receipt_policy_fkey foreign key (policy_id, tenant_id)
    references public.hr_policy_document(id, tenant_id) on delete cascade,
  constraint hr_policy_receipt_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_policy_receipt_id_tenant_unique unique (id, tenant_id),
  constraint hr_policy_receipt_status_check check (status in ('pending', 'acknowledged', 'waived')),
  constraint hr_policy_receipt_acknowledged_check check (
    (status = 'acknowledged' and acknowledged_at is not null and acknowledged_by is not null
      and nullif(btrim(acknowledgement_note), '') is not null)
    or (status <> 'acknowledged' and acknowledged_at is null and acknowledged_by is null)
  ),
  constraint hr_policy_receipt_waiver_check check (
    (status = 'waived' and waived_at is not null and waived_by is not null
      and nullif(btrim(waiver_reason), '') is not null)
    or (status <> 'waived' and waived_at is null and waived_by is null)
  )
);

create unique index hr_policy_receipt_policy_employee_unique
  on public.hr_policy_receipt(policy_id, employee_id);
create index hr_policy_receipt_tenant_status_due_idx
  on public.hr_policy_receipt(tenant_id, status, due_date);
create index hr_policy_receipt_policy_idx
  on public.hr_policy_receipt(policy_id, tenant_id, status);
create index hr_policy_receipt_employee_idx
  on public.hr_policy_receipt(employee_id, tenant_id, due_date desc);

create trigger hr_policy_document_create_audit before insert
on public.hr_policy_document for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_policy_document_update_audit before update
on public.hr_policy_document for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_policy_receipt_create_audit before insert
on public.hr_policy_receipt for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_policy_receipt_update_audit before update
on public.hr_policy_receipt for each row
execute function public.trg_set_update_time_and_by();

alter table public.hr_policy_document enable row level security;
alter table public.hr_policy_receipt enable row level security;
revoke all on table public.hr_policy_document from public, anon, authenticated;
revoke all on table public.hr_policy_receipt from public, anon, authenticated;
grant all on table public.hr_policy_document to service_role;
grant all on table public.hr_policy_receipt to service_role;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000213'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrPolicyAcknowledgement',
  'policy-acknowledgement',
  '/hr/operations/policy-acknowledgement',
  jsonb_build_object(
    'title', '政策与签收', 'icon', 'ri:file-shield-2-line', 'is_hide', false,
    'is_enable', true, 'keep_alive', true, 'roles', jsonb_build_array()
  ),
  13, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set
  parent_id=excluded.parent_id, name=excluded.name, path=excluded.path,
  component=excluded.component, meta=excluded.meta, sort=excluded.sort,
  type=excluded.type, app_code=excluded.app_code, update_by=excluded.update_by,
  update_time=now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000213'::uuid, seed.name, '', '',
  jsonb_build_object('title',seed.title,'icon','','is_hide',true,'is_enable',true,'roles',jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8213-000000000001'::uuid, 'Hr:PolicyAcknowledgement:View', '查看政策与签收', 1),
  ('c0de0000-0000-4000-8213-000000000002'::uuid, 'Hr:PolicyAcknowledgement:Policy:Manage', '管理政策草稿', 2),
  ('c0de0000-0000-4000-8213-000000000003'::uuid, 'Hr:PolicyAcknowledgement:Publish', '发布与退役政策', 3),
  ('c0de0000-0000-4000-8213-000000000004'::uuid, 'Hr:PolicyAcknowledgement:Receipt:Manage', '管理政策签收', 4),
  ('c0de0000-0000-4000-8213-000000000005'::uuid, 'Hr:PolicyAcknowledgement:Evidence:View', '查看签收凭证', 5)
) as seed(id,name,title,sort)
on conflict (id) do update set
  parent_id=excluded.parent_id, name=excluded.name, meta=excluded.meta,
  sort=excluded.sort, type=excluded.type, app_code=excluded.app_code,
  update_by=excluded.update_by, update_time=now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select distinct existing.role_id, new_menu.menu_id, existing.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('c0de0000-0000-4000-8000-000000000213'::uuid),
  ('c0de0000-0000-4000-8213-000000000001'::uuid)
) new_menu(menu_id)
where existing.menu_id='c0de0000-0000-4000-8000-000000000205'::uuid
on conflict (role_id,menu_id) do nothing;

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select role_row.id, new_menu.menu_id, role_row.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role role_row
cross join (values
  ('c0de0000-0000-4000-8000-000000000213'::uuid),
  ('c0de0000-0000-4000-8213-000000000001'::uuid),
  ('c0de0000-0000-4000-8213-000000000002'::uuid),
  ('c0de0000-0000-4000-8213-000000000003'::uuid),
  ('c0de0000-0000-4000-8213-000000000004'::uuid),
  ('c0de0000-0000-4000-8213-000000000005'::uuid)
) new_menu(menu_id)
where role_row.role_code='R_SUPER'
on conflict (role_id,menu_id) do nothing;

;
