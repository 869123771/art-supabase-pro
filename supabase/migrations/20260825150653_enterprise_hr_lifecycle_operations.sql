create table public.hr_lifecycle_template (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  template_code text not null,
  template_name text not null,
  case_type text not null,
  status text not null default 'draft',
  is_default boolean not null default false,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_lifecycle_template_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_lifecycle_template_id_tenant_unique unique (id, tenant_id),
  constraint hr_lifecycle_template_code_unique unique (tenant_id, template_code),
  constraint hr_lifecycle_template_code_not_blank check (btrim(template_code) <> ''),
  constraint hr_lifecycle_template_name_not_blank check (btrim(template_name) <> ''),
  constraint hr_lifecycle_template_case_type_check check (
    case_type in ('onboarding', 'regularization', 'transfer', 'offboarding')
  ),
  constraint hr_lifecycle_template_status_check check (
    status in ('draft', 'active', 'inactive')
  )
);

create unique index hr_lifecycle_template_default_unique
  on public.hr_lifecycle_template(tenant_id, case_type)
  where is_default and status = 'active';
create index hr_lifecycle_template_case_status_idx
  on public.hr_lifecycle_template(tenant_id, case_type, status, template_name);

create table public.hr_lifecycle_template_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  template_id uuid not null,
  task_type text not null,
  task_name text not null,
  description text,
  owner_role text not null default 'hr',
  due_offset_days integer not null default 0,
  required boolean not null default true,
  blocking boolean not null default true,
  evidence_required boolean not null default false,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_lifecycle_template_task_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_lifecycle_template_task_template_fkey foreign key (template_id, tenant_id)
    references public.hr_lifecycle_template(id, tenant_id) on delete cascade,
  constraint hr_lifecycle_template_task_id_tenant_unique unique (id, tenant_id),
  constraint hr_lifecycle_template_task_name_not_blank check (btrim(task_name) <> ''),
  constraint hr_lifecycle_template_task_owner_role_check check (
    owner_role in ('hr', 'manager', 'employee', 'it', 'finance', 'administration', 'asset', 'other')
  ),
  constraint hr_lifecycle_template_task_offset_check check (due_offset_days between -365 and 365),
  constraint hr_lifecycle_template_task_blocking_check check (not blocking or required)
);

create index hr_lifecycle_template_task_template_idx
  on public.hr_lifecycle_template_task(tenant_id, template_id, sort, task_name);

alter table public.hr_lifecycle_case
  add column if not exists template_id uuid,
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists organization_id uuid,
  add column if not exists position_id uuid,
  add column if not exists owner_employee_id uuid,
  add column if not exists buddy_employee_id uuid,
  add column if not exists priority text not null default 'normal',
  add column if not exists execution_status text not null default 'planning',
  add column if not exists actual_effective_date date,
  add column if not exists started_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

update public.hr_lifecycle_case
set execution_status = case
      when status = 'effective' then 'completed'
      when status = 'cancelled' then 'cancelled'
      else 'planning'
    end,
    actual_effective_date = case when status = 'effective'
      then coalesce(actual_effective_date, planned_effective_date) else actual_effective_date end,
    completed_at = case when status = 'effective'
      then coalesce(completed_at, update_time) else completed_at end,
    cancelled_at = case when status = 'cancelled'
      then coalesce(cancelled_at, update_time) else cancelled_at end,
    cancellation_reason = case when status = 'cancelled'
      then coalesce(nullif(btrim(cancellation_reason), ''), nullif(btrim(remark), ''), '历史事项已取消')
      else cancellation_reason end;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_case_template_fkey') then
    alter table public.hr_lifecycle_case add constraint hr_lifecycle_case_template_fkey
      foreign key (template_id, tenant_id)
      references public.hr_lifecycle_template(id, tenant_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_case_organization_fkey') then
    alter table public.hr_lifecycle_case add constraint hr_lifecycle_case_organization_fkey
      foreign key (organization_id, tenant_id)
      references public.sys_organization(id, tenant_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_case_position_fkey') then
    alter table public.hr_lifecycle_case add constraint hr_lifecycle_case_position_fkey
      foreign key (position_id, tenant_id)
      references public.hr_position(id, tenant_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_case_owner_employee_fkey') then
    alter table public.hr_lifecycle_case add constraint hr_lifecycle_case_owner_employee_fkey
      foreign key (owner_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_case_buddy_employee_fkey') then
    alter table public.hr_lifecycle_case add constraint hr_lifecycle_case_buddy_employee_fkey
      foreign key (buddy_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
end
$$;

alter table public.hr_lifecycle_case
  drop constraint if exists hr_lifecycle_case_priority_check,
  drop constraint if exists hr_lifecycle_case_execution_status_check,
  drop constraint if exists hr_lifecycle_case_source_check,
  drop constraint if exists hr_lifecycle_case_execution_completion_check;
alter table public.hr_lifecycle_case
  add constraint hr_lifecycle_case_priority_check check (priority in ('low', 'normal', 'high', 'critical')),
  add constraint hr_lifecycle_case_execution_status_check check (
    execution_status in ('planning', 'in_progress', 'ready', 'completed', 'cancelled')
  ),
  add constraint hr_lifecycle_case_source_check check (
    (source_type is null and source_id is null)
    or (source_type = 'recruitment_handoff' and source_id is not null)
  ),
  add constraint hr_lifecycle_case_execution_completion_check check (
    (execution_status = 'completed' and actual_effective_date is not null and completed_at is not null)
    or (execution_status = 'cancelled' and cancelled_at is not null
      and nullif(btrim(cancellation_reason), '') is not null)
    or (execution_status in ('planning', 'in_progress', 'ready') and completed_at is null and cancelled_at is null)
  );

create unique index if not exists hr_lifecycle_case_source_unique
  on public.hr_lifecycle_case(tenant_id, source_type, source_id)
  where source_id is not null;
create index if not exists hr_lifecycle_case_template_fk_idx
  on public.hr_lifecycle_case(template_id, tenant_id) where template_id is not null;
create index if not exists hr_lifecycle_case_organization_fk_idx
  on public.hr_lifecycle_case(organization_id, tenant_id) where organization_id is not null;
create index if not exists hr_lifecycle_case_position_fk_idx
  on public.hr_lifecycle_case(position_id, tenant_id) where position_id is not null;
create index if not exists hr_lifecycle_case_owner_employee_fk_idx
  on public.hr_lifecycle_case(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index if not exists hr_lifecycle_case_buddy_employee_fk_idx
  on public.hr_lifecycle_case(buddy_employee_id, tenant_id) where buddy_employee_id is not null;
create index if not exists hr_lifecycle_case_execution_due_idx
  on public.hr_lifecycle_case(tenant_id, execution_status, planned_effective_date, priority)
  where execution_status in ('planning', 'in_progress', 'ready');

alter table public.hr_lifecycle_task
  add column if not exists template_task_id uuid,
  add column if not exists owner_employee_id uuid,
  add column if not exists owner_role text not null default 'hr',
  add column if not exists description text,
  add column if not exists required boolean not null default true,
  add column if not exists blocking boolean not null default true,
  add column if not exists evidence_required boolean not null default false,
  add column if not exists evidence_note text,
  add column if not exists evidence_url text,
  add column if not exists started_at timestamptz,
  add column if not exists waived_at timestamptz,
  add column if not exists waived_by text,
  add column if not exists waiver_reason text,
  add column if not exists dependency_task_id uuid;

alter table public.hr_lifecycle_task
  add constraint hr_lifecycle_task_id_tenant_unique unique (id, tenant_id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_task_template_task_fkey') then
    alter table public.hr_lifecycle_task add constraint hr_lifecycle_task_template_task_fkey
      foreign key (template_task_id, tenant_id)
      references public.hr_lifecycle_template_task(id, tenant_id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_task_owner_employee_fkey') then
    alter table public.hr_lifecycle_task add constraint hr_lifecycle_task_owner_employee_fkey
      foreign key (owner_employee_id, tenant_id)
      references public.hr_employee(id, tenant_id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'hr_lifecycle_task_dependency_fkey') then
    alter table public.hr_lifecycle_task add constraint hr_lifecycle_task_dependency_fkey
      foreign key (dependency_task_id, tenant_id)
      references public.hr_lifecycle_task(id, tenant_id) on delete restrict;
  end if;
end
$$;

alter table public.hr_lifecycle_task
  drop constraint if exists hr_lifecycle_task_owner_role_check,
  drop constraint if exists hr_lifecycle_task_blocking_check,
  drop constraint if exists hr_lifecycle_task_evidence_check,
  drop constraint if exists hr_lifecycle_task_waiver_check,
  drop constraint if exists hr_lifecycle_task_dependency_self_check;
alter table public.hr_lifecycle_task
  add constraint hr_lifecycle_task_owner_role_check check (
    owner_role in ('hr', 'manager', 'employee', 'it', 'finance', 'administration', 'asset', 'other')
  ),
  add constraint hr_lifecycle_task_blocking_check check (not blocking or required),
  add constraint hr_lifecycle_task_evidence_check check (
    not (status = 'completed' and evidence_required)
    or nullif(btrim(evidence_note), '') is not null
    or nullif(btrim(evidence_url), '') is not null
  ),
  add constraint hr_lifecycle_task_waiver_check check (
    status <> 'skipped'
    or (waived_at is not null and nullif(btrim(waiver_reason), '') is not null)
  ),
  add constraint hr_lifecycle_task_dependency_self_check check (dependency_task_id is distinct from id);

create index if not exists hr_lifecycle_task_template_task_fk_idx
  on public.hr_lifecycle_task(template_task_id, tenant_id) where template_task_id is not null;
create index if not exists hr_lifecycle_task_owner_employee_fk_idx
  on public.hr_lifecycle_task(owner_employee_id, tenant_id) where owner_employee_id is not null;
create index if not exists hr_lifecycle_task_dependency_fk_idx
  on public.hr_lifecycle_task(dependency_task_id, tenant_id) where dependency_task_id is not null;
create index if not exists hr_lifecycle_task_due_status_idx
  on public.hr_lifecycle_task(tenant_id, status, due_date, blocking)
  where status in ('pending', 'processing');

create trigger hr_lifecycle_template_create_audit before insert on public.hr_lifecycle_template
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_lifecycle_template_update_audit before update on public.hr_lifecycle_template
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_lifecycle_template_task_create_audit before insert on public.hr_lifecycle_template_task
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_lifecycle_template_task_update_audit before update on public.hr_lifecycle_template_task
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_lifecycle_template enable row level security;
alter table public.hr_lifecycle_template_task enable row level security;
create policy hr_lifecycle_template_deny_direct_access on public.hr_lifecycle_template
  for all to authenticated using (false) with check (false);
create policy hr_lifecycle_template_task_deny_direct_access on public.hr_lifecycle_template_task
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_lifecycle_case from public, anon, authenticated;
revoke all on table public.hr_lifecycle_task from public, anon, authenticated;
revoke all on table public.hr_lifecycle_template from public, anon, authenticated;
revoke all on table public.hr_lifecycle_template_task from public, anon, authenticated;
grant all on table public.hr_lifecycle_case to service_role;
grant all on table public.hr_lifecycle_task to service_role;
grant all on table public.hr_lifecycle_template to service_role;
grant all on table public.hr_lifecycle_template_task to service_role;

insert into public.hr_lifecycle_template(
  tenant_id, template_code, template_name, case_type, status, is_default, description,
  create_by, update_by
)
select tenant.id, seed.code, seed.name, seed.case_type, 'active', true, seed.description,
  'system', 'system'
from public.sys_tenant tenant
cross join (values
  ('ONBOARDING_STANDARD', '标准入职任务包', 'onboarding', '覆盖报到资料、账号设备、首日引导与试用期目标。'),
  ('REGULARIZATION_STANDARD', '标准转正任务包', 'regularization', '覆盖试用期复盘、转正评估、合同与任职信息确认。'),
  ('TRANSFER_STANDARD', '标准调动任务包', 'transfer', '覆盖原团队交接、新岗位权限、目标对齐与资料更新。'),
  ('OFFBOARDING_STANDARD', '标准离职任务包', 'offboarding', '覆盖知识交接、资产回收、账号停用、薪资结算与离职资料。')
) seed(code, name, case_type, description)
where not exists (
  select 1 from public.hr_lifecycle_template existing
  where existing.tenant_id = tenant.id and existing.template_code = seed.code
);

with task_seed(case_type, task_type, task_name, description, owner_role, due_offset_days, required, blocking, evidence_required, sort) as (values
  ('onboarding','document','核验入职资料','核验身份、合同、资质与报到资料完整性。','hr',-3,true,true,true,10),
  ('onboarding','account','开通账号与岗位权限','按岗位最小权限原则完成账号、组织和业务角色开通。','it',-1,true,true,true,20),
  ('onboarding','asset','准备设备与工位','确认电脑、门禁、工位及岗位必要设备。','administration',-1,true,true,false,30),
  ('onboarding','organization','完成首日引导与目标对齐','安排直属主管、伙伴与首日工作目标沟通。','manager',0,true,true,false,40),
  ('regularization','organization','完成试用期绩效复盘','直属主管确认目标完成、能力表现与转正建议。','manager',-7,true,true,true,10),
  ('regularization','document','确认转正资料与合同信息','核验转正审批、任职信息及需更新的合同资料。','hr',-2,true,true,true,20),
  ('regularization','other','完成转正沟通','向员工反馈转正结论与下一阶段发展要求。','manager',0,true,false,false,30),
  ('transfer','knowledge_transfer','完成原团队知识交接','清点在办事项、关键联系人、资料与风险。','manager',-3,true,true,true,10),
  ('transfer','account','调整账号与岗位权限','回收原岗位权限并按新岗位最小权限开通。','it',-1,true,true,true,20),
  ('transfer','organization','完成新岗位目标对齐','新直属主管明确岗位职责、目标与协作关系。','manager',0,true,true,false,30),
  ('transfer','document','更新组织岗位资料','同步任职、档案与需留存的人事资料。','hr',0,true,true,true,40),
  ('offboarding','knowledge_transfer','完成知识与工作交接','确认在办事项、客户联系人、资料位置和接任人。','manager',-3,true,true,true,10),
  ('offboarding','asset','完成公司资产回收','清点设备、证件、钥匙、车辆及其他公司资产。','asset',-1,true,true,true,20),
  ('offboarding','account','停用账号与业务权限','按离职生效时间停用系统账号、门禁及业务权限。','it',0,true,true,true,30),
  ('offboarding','payroll','完成薪资福利结算确认','核验考勤、薪资、福利、报销与应收应付款项。','finance',0,true,true,true,40),
  ('offboarding','document','归档离职资料','归档审批、交接、证明与离职面谈资料。','hr',1,true,true,true,50)
)
insert into public.hr_lifecycle_template_task(
  tenant_id, template_id, task_type, task_name, description, owner_role,
  due_offset_days, required, blocking, evidence_required, sort, create_by, update_by
)
select template.tenant_id, template.id, seed.task_type, seed.task_name, seed.description,
  seed.owner_role, seed.due_offset_days, seed.required, seed.blocking,
  seed.evidence_required, seed.sort, 'system', 'system'
from task_seed seed
join public.hr_lifecycle_template template
  on template.case_type = seed.case_type and template.is_default and template.status = 'active'
where not exists (
  select 1 from public.hr_lifecycle_template_task existing
  where existing.template_id = template.id and existing.task_name = seed.task_name
);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('生命周期执行状态', 'hrLifecycleExecutionStatus', 105),
  ('生命周期任务包状态', 'hrLifecycleTemplateStatus', 106),
  ('生命周期责任泳道', 'hrLifecycleOwnerRole', 107),
  ('生命周期事项优先级', 'hrLifecyclePriority', 108)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 员工生命周期运营字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrLifecycleExecutionStatus','planning','待规划',1,'info'),
  ('hrLifecycleExecutionStatus','in_progress','执行中',2,'primary'),
  ('hrLifecycleExecutionStatus','ready','已就绪',3,'warning'),
  ('hrLifecycleExecutionStatus','completed','已完成',4,'success'),
  ('hrLifecycleExecutionStatus','cancelled','已取消',5,'danger'),
  ('hrLifecycleTemplateStatus','draft','草稿',1,'info'),
  ('hrLifecycleTemplateStatus','active','启用',2,'success'),
  ('hrLifecycleTemplateStatus','inactive','停用',3,'info'),
  ('hrLifecycleOwnerRole','hr','HR',1,'primary'),
  ('hrLifecycleOwnerRole','manager','直属主管',2,'success'),
  ('hrLifecycleOwnerRole','employee','员工本人',3,'info'),
  ('hrLifecycleOwnerRole','it','信息技术',4,'primary'),
  ('hrLifecycleOwnerRole','finance','财务',5,'warning'),
  ('hrLifecycleOwnerRole','administration','行政',6,'info'),
  ('hrLifecycleOwnerRole','asset','资产管理',7,'warning'),
  ('hrLifecycleOwnerRole','other','其他',8,'info'),
  ('hrLifecyclePriority','low','低',1,'info'),
  ('hrLifecyclePriority','normal','普通',2,'primary'),
  ('hrLifecyclePriority','high','高',3,'warning'),
  ('hrLifecyclePriority','critical','紧急',4,'danger')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 员工生命周期运营字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

with task_types(value, label, sort, tag_type) as (values
  ('knowledge_transfer','知识交接',7,'primary'),
  ('payroll','薪资结算',8,'warning'),
  ('compliance','合规核验',9,'danger')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, 'hrLifecycleTaskType_' || task_types.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 生命周期任务类型',
  task_types.value, task_types.label, platform_tenant.id, task_types.tag_type, task_types.sort
from task_types
join public.sys_dict_type dictionary_type on dictionary_type.code = 'hrLifecycleTaskType'
join public.sys_tenant platform_tenant on platform_tenant.tenant_code = 'platform'
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = task_types.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000102'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8102-000000000007'::uuid, 'Hr:Lifecycle:Start', '启动或推进事项', 7),
  ('c0de0000-0000-4000-8102-000000000008'::uuid, 'Hr:Lifecycle:CompleteCase', '办结生命周期事项', 8),
  ('c0de0000-0000-4000-8102-000000000009'::uuid, 'Hr:Lifecycle:WaiveTask', '豁免生命周期任务', 9),
  ('c0de0000-0000-4000-8102-000000000010'::uuid, 'Hr:Lifecycle:ManageTemplate', '管理标准任务包', 10)
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
  ('c0de0000-0000-4000-8102-000000000007'::uuid),
  ('c0de0000-0000-4000-8102-000000000008'::uuid),
  ('c0de0000-0000-4000-8102-000000000009'::uuid),
  ('c0de0000-0000-4000-8102-000000000010'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000102'::uuid
on conflict (role_id, menu_id) do nothing;
