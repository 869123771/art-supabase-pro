-- Enterprise workforce planning foundation.
-- Planning cycles and lines are proposals. Effective headcount and the position
-- capacity guard are only synchronized when an approved plan is activated.

create table public.hr_workforce_plan_cycle (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_no text not null,
  plan_name text not null,
  scenario text not null default 'baseline',
  period_start date not null,
  period_end date not null,
  baseline_date date not null default current_date,
  owner_employee_id uuid,
  status text not null default 'draft',
  budget_amount numeric(18,2),
  currency_code text not null default 'CNY',
  objective text,
  assumptions text,
  approved_by text,
  approved_at timestamptz,
  activated_at timestamptz,
  closed_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_workforce_plan_cycle_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_workforce_plan_cycle_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_workforce_plan_cycle_id_tenant_unique unique (id, tenant_id),
  constraint hr_workforce_plan_cycle_no_unique unique (tenant_id, plan_no),
  constraint hr_workforce_plan_cycle_no_not_blank check (btrim(plan_no) <> ''),
  constraint hr_workforce_plan_cycle_name_not_blank check (btrim(plan_name) <> ''),
  constraint hr_workforce_plan_cycle_scenario_check check (
    scenario in ('baseline', 'growth', 'efficiency', 'restructure')
  ),
  constraint hr_workforce_plan_cycle_period_check check (period_end >= period_start),
  constraint hr_workforce_plan_cycle_baseline_check check (baseline_date <= period_end),
  constraint hr_workforce_plan_cycle_status_check check (
    status in ('draft', 'submitted', 'approved', 'active', 'closed', 'cancelled')
  ),
  constraint hr_workforce_plan_cycle_budget_check check (budget_amount is null or budget_amount >= 0),
  constraint hr_workforce_plan_cycle_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_workforce_plan_cycle_approval_check check (
    (status in ('approved', 'active', 'closed') and approved_by is not null and approved_at is not null)
    or (status in ('draft', 'submitted', 'cancelled') and approved_by is null and approved_at is null)
  ),
  constraint hr_workforce_plan_cycle_activation_check check (
    (status in ('active', 'closed') and activated_at is not null)
    or (status not in ('active', 'closed') and activated_at is null)
  ),
  constraint hr_workforce_plan_cycle_close_check check (
    (status = 'closed' and closed_at is not null)
    or (status <> 'closed' and closed_at is null)
  )
);

create index hr_workforce_plan_cycle_owner_fk_idx
  on public.hr_workforce_plan_cycle(owner_employee_id, tenant_id)
  where owner_employee_id is not null;
create index hr_workforce_plan_cycle_status_period_idx
  on public.hr_workforce_plan_cycle(tenant_id, status, period_start desc, period_end);

create table public.hr_workforce_plan_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  baseline_count integer not null default 0,
  planned_hires integer not null default 0,
  planned_exits integer not null default 0,
  target_count integer generated always as (baseline_count + planned_hires - planned_exits) stored,
  annual_cost_per_head numeric(18,2),
  planned_payroll numeric(20,2) generated always as (
    case when annual_cost_per_head is null then null
      else (baseline_count + planned_hires - planned_exits) * annual_cost_per_head end
  ) stored,
  demand_date date,
  priority text not null default 'normal',
  rationale text not null,
  assumptions text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_workforce_plan_line_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_workforce_plan_line_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_workforce_plan_cycle(id, tenant_id) on delete cascade,
  constraint hr_workforce_plan_line_organization_fkey foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_workforce_plan_line_position_fkey foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint hr_workforce_plan_line_id_tenant_unique unique (id, tenant_id),
  constraint hr_workforce_plan_line_scope_unique unique (tenant_id, plan_id, position_id),
  constraint hr_workforce_plan_line_counts_check check (
    baseline_count >= 0 and planned_hires >= 0 and planned_exits >= 0
    and baseline_count + planned_hires - planned_exits >= 0
  ),
  constraint hr_workforce_plan_line_cost_check check (
    annual_cost_per_head is null or annual_cost_per_head >= 0
  ),
  constraint hr_workforce_plan_line_priority_check check (
    priority in ('critical', 'high', 'normal', 'low')
  ),
  constraint hr_workforce_plan_line_rationale_not_blank check (btrim(rationale) <> '')
);

create index hr_workforce_plan_line_plan_fk_idx
  on public.hr_workforce_plan_line(plan_id, tenant_id);
create index hr_workforce_plan_line_organization_fk_idx
  on public.hr_workforce_plan_line(organization_id, tenant_id);
create index hr_workforce_plan_line_position_fk_idx
  on public.hr_workforce_plan_line(position_id, tenant_id);
create index hr_workforce_plan_line_priority_demand_idx
  on public.hr_workforce_plan_line(tenant_id, priority, demand_date)
  where planned_hires > 0;

alter table public.hr_position_headcount
  add column if not exists source_plan_line_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_position_headcount_source_plan_line_fkey'
      and conrelid = 'public.hr_position_headcount'::regclass
  ) then
    alter table public.hr_position_headcount
      add constraint hr_position_headcount_source_plan_line_fkey
      foreign key (source_plan_line_id)
      references public.hr_workforce_plan_line(id) on delete set null;
  end if;
end
$$;

create index if not exists hr_position_headcount_source_plan_line_fk_idx
  on public.hr_position_headcount(source_plan_line_id, tenant_id)
  where source_plan_line_id is not null;

create trigger hr_workforce_plan_cycle_create_audit
before insert on public.hr_workforce_plan_cycle
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_workforce_plan_cycle_update_audit
before update on public.hr_workforce_plan_cycle
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_workforce_plan_line_create_audit
before insert on public.hr_workforce_plan_line
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_workforce_plan_line_update_audit
before update on public.hr_workforce_plan_line
for each row execute function public.trg_set_update_time_and_by();

alter table public.hr_workforce_plan_cycle enable row level security;
alter table public.hr_workforce_plan_line enable row level security;

create policy hr_workforce_plan_cycle_deny_direct_access on public.hr_workforce_plan_cycle
  for all to authenticated using (false) with check (false);
create policy hr_workforce_plan_line_deny_direct_access on public.hr_workforce_plan_line
  for all to authenticated using (false) with check (false);

revoke all on table public.hr_workforce_plan_cycle from public, anon, authenticated;
revoke all on table public.hr_workforce_plan_line from public, anon, authenticated;
grant all on table public.hr_workforce_plan_cycle to service_role;
grant all on table public.hr_workforce_plan_line to service_role;

-- Existing workforce-risk reads still use the effective-headcount table directly.
-- Keep tenant-scoped SELECT for authenticated users, but route all writes through RPCs.
revoke all on table public.hr_position_headcount from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.hr_position_headcount from authenticated;
grant select on table public.hr_position_headcount to authenticated;
grant all on table public.hr_position_headcount to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('人力规划场景', 'hrWorkforcePlanScenario', 97),
  ('人力规划状态', 'hrWorkforcePlanStatus', 98),
  ('人力需求优先级', 'hrWorkforcePlanPriority', 99)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 人力规划字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set
  name = excluded.name, status = excluded.status, update_by = excluded.update_by,
  update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrWorkforcePlanScenario', 'baseline', '基准延续', 1, 'info'),
  ('hrWorkforcePlanScenario', 'growth', '业务增长', 2, 'success'),
  ('hrWorkforcePlanScenario', 'efficiency', '效率优化', 3, 'warning'),
  ('hrWorkforcePlanScenario', 'restructure', '组织重构', 4, 'danger'),
  ('hrWorkforcePlanStatus', 'draft', '草稿', 1, 'info'),
  ('hrWorkforcePlanStatus', 'submitted', '待审批', 2, 'warning'),
  ('hrWorkforcePlanStatus', 'approved', '已批准', 3, 'success'),
  ('hrWorkforcePlanStatus', 'active', '执行中', 4, 'primary'),
  ('hrWorkforcePlanStatus', 'closed', '已关闭', 5, 'info'),
  ('hrWorkforcePlanStatus', 'cancelled', '已取消', 6, 'danger'),
  ('hrWorkforcePlanPriority', 'critical', '关键', 1, 'danger'),
  ('hrWorkforcePlanPriority', 'high', '高', 2, 'warning'),
  ('hrWorkforcePlanPriority', 'normal', '常规', 3, 'primary'),
  ('hrWorkforcePlanPriority', 'low', '低', 4, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 人力规划字典项',
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
select seed.id, 'c0de0000-0000-4000-8000-000000000201'::uuid, seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8201-000000000005'::uuid, 'Hr:Headcount:Submit', '提交人力规划', 5),
  ('c0de0000-0000-4000-8201-000000000006'::uuid, 'Hr:Headcount:Approve', '审批人力规划', 6),
  ('c0de0000-0000-4000-8201-000000000007'::uuid, 'Hr:Headcount:Activate', '启用人力规划', 7),
  ('c0de0000-0000-4000-8201-000000000008'::uuid, 'Hr:Headcount:Close', '关闭人力规划', 8)
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
  ('c0de0000-0000-4000-8201-000000000005'::uuid),
  ('c0de0000-0000-4000-8201-000000000006'::uuid),
  ('c0de0000-0000-4000-8201-000000000007'::uuid),
  ('c0de0000-0000-4000-8201-000000000008'::uuid)
) button(id)
where page_grant.menu_id = 'c0de0000-0000-4000-8000-000000000201'::uuid
on conflict (role_id, menu_id) do nothing;
