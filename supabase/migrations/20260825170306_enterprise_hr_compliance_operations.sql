alter table public.hr_employee_contract
  add column if not exists previous_contract_id uuid,
  add column if not exists renewal_owner_id uuid,
  add column if not exists renewal_decision text not null default 'not_started',
  add column if not exists renewal_started_at timestamptz,
  add column if not exists renewed_at timestamptz,
  add column if not exists termination_date date,
  add column if not exists termination_reason text;

alter table public.hr_employee_qualification
  add column if not exists responsible_employee_id uuid,
  add column if not exists verification_status text not null default 'pending',
  add column if not exists verified_by_employee_id uuid,
  add column if not exists verified_at timestamptz,
  add column if not exists verification_note text,
  add column if not exists next_review_date date,
  add column if not exists revoked_at timestamptz,
  add column if not exists revocation_reason text;

update public.hr_employee_qualification
set verification_status = case when status = 'revoked' then 'rejected' else 'pending' end
where verification_status not in ('pending', 'verified', 'rejected');

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_id_tenant_unique'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_id_tenant_unique unique (id, tenant_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_qualification'::regclass
      and conname = 'hr_employee_qualification_id_tenant_unique'
  ) then
    alter table public.hr_employee_qualification
      add constraint hr_employee_qualification_id_tenant_unique unique (id, tenant_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_status_check'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_status_check check (
        contract_status in ('draft', 'active', 'renewing', 'renewed', 'expired', 'terminated')
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_renewal_decision_check'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_renewal_decision_check check (
        renewal_decision in ('not_started', 'pending', 'renew', 'terminate', 'completed')
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_termination_date_check'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_termination_date_check check (
        termination_date is null or termination_date >= start_date
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_previous_fkey'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_previous_fkey
      foreign key (previous_contract_id, tenant_id)
      references public.hr_employee_contract(id, tenant_id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_contract'::regclass
      and conname = 'hr_employee_contract_renewal_owner_fkey'
  ) then
    alter table public.hr_employee_contract
      add constraint hr_employee_contract_renewal_owner_fkey
      foreign key (renewal_owner_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_qualification'::regclass
      and conname = 'hr_employee_qualification_verification_status_check'
  ) then
    alter table public.hr_employee_qualification
      add constraint hr_employee_qualification_verification_status_check check (
        verification_status in ('pending', 'verified', 'rejected')
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_qualification'::regclass
      and conname = 'hr_employee_qualification_review_date_check'
  ) then
    alter table public.hr_employee_qualification
      add constraint hr_employee_qualification_review_date_check check (
        next_review_date is null or issue_date is null or next_review_date >= issue_date
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_qualification'::regclass
      and conname = 'hr_employee_qualification_responsible_fkey'
  ) then
    alter table public.hr_employee_qualification
      add constraint hr_employee_qualification_responsible_fkey
      foreign key (responsible_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.hr_employee_qualification'::regclass
      and conname = 'hr_employee_qualification_verifier_fkey'
  ) then
    alter table public.hr_employee_qualification
      add constraint hr_employee_qualification_verifier_fkey
      foreign key (verified_by_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
end
$migration$;

create table public.hr_compliance_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  entity_type text not null,
  entity_id uuid not null,
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
  constraint hr_compliance_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compliance_event_actor_fkey foreign key (actor_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_compliance_event_entity_type_check check (
    entity_type in ('contract', 'qualification')
  ),
  constraint hr_compliance_event_type_check check (
    event_type in ('created', 'updated', 'activated', 'renewal_started', 'renewed',
      'terminated', 'verified', 'verification_rejected', 'revoked', 'commented')
  ),
  constraint hr_compliance_event_data_check check (jsonb_typeof(event_data) = 'object')
);

create index hr_employee_contract_previous_fk_idx
  on public.hr_employee_contract(previous_contract_id, tenant_id)
  where previous_contract_id is not null;
create index hr_employee_contract_renewal_owner_fk_idx
  on public.hr_employee_contract(renewal_owner_id, tenant_id)
  where renewal_owner_id is not null;
create index hr_employee_contract_risk_idx
  on public.hr_employee_contract(tenant_id, end_date, contract_status)
  where end_date is not null and contract_status in ('active', 'renewing');
create index hr_employee_qualification_responsible_fk_idx
  on public.hr_employee_qualification(responsible_employee_id, tenant_id)
  where responsible_employee_id is not null;
create index hr_employee_qualification_verifier_fk_idx
  on public.hr_employee_qualification(verified_by_employee_id, tenant_id)
  where verified_by_employee_id is not null;
create index hr_employee_qualification_risk_idx
  on public.hr_employee_qualification(tenant_id, expiry_date, status)
  where expiry_date is not null and status <> 'revoked';
create index hr_employee_qualification_verification_idx
  on public.hr_employee_qualification(tenant_id, verification_status, update_time desc);
create index hr_compliance_event_entity_idx
  on public.hr_compliance_event(tenant_id, entity_type, entity_id, create_time desc);
create index hr_compliance_event_actor_fk_idx
  on public.hr_compliance_event(actor_employee_id, tenant_id)
  where actor_employee_id is not null;

create trigger hr_compliance_event_create_audit
before insert on public.hr_compliance_event for each row
execute function public.trg_set_create_time_and_by('true', 'true');

alter table public.hr_compliance_event enable row level security;
create policy hr_compliance_event_deny_direct_access on public.hr_compliance_event
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_compliance_event from public, anon, authenticated;
grant all on table public.hr_compliance_event to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('合同续签决策', 'hrContractRenewalDecision', 119),
  ('资质核验状态', 'hrQualificationVerificationStatus', 120),
  ('用工合规风险', 'hrComplianceRiskStatus', 121),
  ('用工合规事件', 'hrComplianceEventType', 122)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 用工合规字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrContractStatus','renewed','已续签',6,'success'),
  ('hrContractRenewalDecision','not_started','未启动',1,'info'),
  ('hrContractRenewalDecision','pending','待决策',2,'warning'),
  ('hrContractRenewalDecision','renew','续签',3,'primary'),
  ('hrContractRenewalDecision','terminate','终止',4,'danger'),
  ('hrContractRenewalDecision','completed','已完成',5,'success'),
  ('hrQualificationVerificationStatus','pending','待核验',1,'warning'),
  ('hrQualificationVerificationStatus','verified','已核验',2,'success'),
  ('hrQualificationVerificationStatus','rejected','核验驳回',3,'danger'),
  ('hrComplianceRiskStatus','overdue','已逾期',1,'danger'),
  ('hrComplianceRiskStatus','critical','7 天内到期',2,'danger'),
  ('hrComplianceRiskStatus','due_soon','30 天内到期',3,'warning'),
  ('hrComplianceRiskStatus','watch','提醒期内',4,'primary'),
  ('hrComplianceRiskStatus','clear','正常',5,'success'),
  ('hrComplianceEventType','created','创建记录',1,'info'),
  ('hrComplianceEventType','updated','更新资料',2,'primary'),
  ('hrComplianceEventType','activated','合同生效',3,'success'),
  ('hrComplianceEventType','renewal_started','启动续签',4,'warning'),
  ('hrComplianceEventType','renewed','完成续签',5,'success'),
  ('hrComplianceEventType','terminated','终止合同',6,'danger'),
  ('hrComplianceEventType','verified','核验通过',7,'success'),
  ('hrComplianceEventType','verification_rejected','核验驳回',8,'danger'),
  ('hrComplianceEventType','revoked','撤销资质',9,'danger'),
  ('hrComplianceEventType','commented','补充说明',10,'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 用工合规字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

update public.sys_menu
set meta = jsonb_set(meta, '{title}', '"用工合规中心"'::jsonb, true),
    update_by = '624944977@qq.com', update_time = now()
where id = 'c0de0000-0000-4000-8000-000000000103'::uuid;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000103'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8103-000000000005'::uuid, 'Hr:Compliance:Contract:Renew', '续签劳动合同', 5),
  ('c0de0000-0000-4000-8103-000000000006'::uuid, 'Hr:Compliance:Contract:Terminate', '终止劳动合同', 6),
  ('c0de0000-0000-4000-8103-000000000007'::uuid, 'Hr:Compliance:Qualification:Verify', '核验员工资质', 7),
  ('c0de0000-0000-4000-8103-000000000008'::uuid, 'Hr:Compliance:Qualification:Revoke', '撤销员工资质', 8)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select edit_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu edit_grant
join public.sys_role role on role.id = edit_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8103-000000000005'::uuid),
  ('c0de0000-0000-4000-8103-000000000006'::uuid),
  ('c0de0000-0000-4000-8103-000000000007'::uuid),
  ('c0de0000-0000-4000-8103-000000000008'::uuid)
) button(id)
where edit_grant.menu_id = 'c0de0000-0000-4000-8103-000000000003'::uuid
on conflict (role_id, menu_id) do nothing;

;
