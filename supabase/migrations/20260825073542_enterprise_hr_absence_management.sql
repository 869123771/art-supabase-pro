-- Enterprise HR absence management.
-- Attendance keeps schedule/clock facts; this domain owns leave policy, entitlement,
-- immutable balance movements, privacy-aware requests, and controlled approval.

create table public.hr_leave_type (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  leave_code text not null,
  leave_name text not null,
  category text not null,
  unit text not null default 'day',
  paid_ratio numeric(5, 4) not null default 1,
  minimum_increment numeric(8, 2) not null default 0.5,
  proof_required_after numeric(8, 2),
  color text not null default '#6366f1',
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_leave_type_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_leave_type_id_tenant_unique unique (id, tenant_id),
  constraint hr_leave_type_code_unique unique (tenant_id, leave_code),
  constraint hr_leave_type_code_not_blank check (btrim(leave_code) <> ''),
  constraint hr_leave_type_name_not_blank check (btrim(leave_name) <> ''),
  constraint hr_leave_type_category_check check (category in (
    'annual', 'sick', 'personal', 'compensatory', 'marriage', 'maternity',
    'paternity', 'bereavement', 'parental', 'unpaid', 'other'
  )),
  constraint hr_leave_type_unit_check check (unit in ('day', 'hour')),
  constraint hr_leave_type_paid_ratio_check check (paid_ratio between 0 and 1),
  constraint hr_leave_type_increment_check check (minimum_increment > 0),
  constraint hr_leave_type_proof_threshold_check
    check (proof_required_after is null or proof_required_after >= 0),
  constraint hr_leave_type_color_check check (color ~ '^#[0-9A-Fa-f]{6}$')
)

create index hr_leave_type_tenant_enabled_idx
  on public.hr_leave_type(tenant_id, enabled, sort, leave_name)

create table public.hr_leave_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  leave_type_id uuid not null,
  policy_code text not null,
  policy_name text not null,
  scope_type text not null default 'all',
  organization_id uuid,
  employee_id uuid,
  grade_id uuid,
  entitlement_method text not null default 'annual',
  annual_quota numeric(10, 2) not null default 0,
  monthly_accrual numeric(10, 4) not null default 0,
  carryover_limit numeric(10, 2) not null default 0,
  carryover_expiry_months integer,
  allow_negative boolean not null default false,
  negative_limit numeric(10, 2) not null default 0,
  probation_eligible boolean not null default false,
  effective_from date not null,
  effective_to date,
  status text not null default 'draft',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_leave_policy_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_leave_policy_type_fkey foreign key (leave_type_id, tenant_id)
    references public.hr_leave_type(id, tenant_id) on delete restrict,
  constraint hr_leave_policy_organization_fkey foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  constraint hr_leave_policy_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_leave_policy_grade_fkey foreign key (grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_leave_policy_id_tenant_unique unique (id, tenant_id),
  constraint hr_leave_policy_code_unique unique (tenant_id, policy_code),
  constraint hr_leave_policy_code_not_blank check (btrim(policy_code) <> ''),
  constraint hr_leave_policy_name_not_blank check (btrim(policy_name) <> ''),
  constraint hr_leave_policy_scope_type_check
    check (scope_type in ('all', 'organization', 'employee', 'grade')),
  constraint hr_leave_policy_scope_target_check check (
    (scope_type = 'all' and organization_id is null and employee_id is null and grade_id is null)
    or (scope_type = 'organization' and organization_id is not null and employee_id is null and grade_id is null)
    or (scope_type = 'employee' and employee_id is not null and organization_id is null and grade_id is null)
    or (scope_type = 'grade' and grade_id is not null and organization_id is null and employee_id is null)
  ),
  constraint hr_leave_policy_method_check
    check (entitlement_method in ('annual', 'monthly_accrual', 'manual', 'none')),
  constraint hr_leave_policy_amounts_check check (
    annual_quota >= 0 and monthly_accrual >= 0 and carryover_limit >= 0
    and negative_limit >= 0
  ),
  constraint hr_leave_policy_carryover_expiry_check
    check (carryover_expiry_months is null or carryover_expiry_months between 1 and 60),
  constraint hr_leave_policy_dates_check
    check (effective_to is null or effective_to >= effective_from),
  constraint hr_leave_policy_status_check check (status in ('draft', 'active', 'inactive'))
)

create index hr_leave_policy_type_effective_idx
  on public.hr_leave_policy(tenant_id, leave_type_id, status, effective_from, effective_to)

create index hr_leave_policy_organization_fk_idx
  on public.hr_leave_policy(organization_id, tenant_id) where organization_id is not null

create index hr_leave_policy_employee_fk_idx
  on public.hr_leave_policy(employee_id, tenant_id) where employee_id is not null

create index hr_leave_policy_grade_fk_idx
  on public.hr_leave_policy(grade_id, tenant_id) where grade_id is not null

alter table public.hr_leave_policy
  add constraint hr_leave_policy_active_no_overlap
  exclude using gist (
    tenant_id with =,
    leave_type_id with =,
    scope_type with =,
    (coalesce(organization_id, employee_id, grade_id,
      '00000000-0000-0000-0000-000000000000'::uuid)) with =,
    (daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]')) with &&
  ) where (status = 'active')

create table public.hr_leave_balance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  leave_type_id uuid not null,
  policy_id uuid,
  balance_year integer not null,
  opening_amount numeric(12, 2) not null default 0,
  accrued_amount numeric(12, 2) not null default 0,
  adjusted_amount numeric(12, 2) not null default 0,
  pending_amount numeric(12, 2) not null default 0,
  used_amount numeric(12, 2) not null default 0,
  expired_amount numeric(12, 2) not null default 0,
  expires_on date,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_leave_balance_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_leave_balance_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_leave_balance_type_fkey foreign key (leave_type_id, tenant_id)
    references public.hr_leave_type(id, tenant_id) on delete restrict,
  constraint hr_leave_balance_policy_fkey foreign key (policy_id, tenant_id)
    references public.hr_leave_policy(id, tenant_id) on delete restrict,
  constraint hr_leave_balance_id_tenant_unique unique (id, tenant_id),
  constraint hr_leave_balance_employee_year_unique
    unique (tenant_id, employee_id, leave_type_id, balance_year),
  constraint hr_leave_balance_year_check check (balance_year between 2000 and 2200),
  constraint hr_leave_balance_nonnegative_facts check (
    opening_amount >= 0 and accrued_amount >= 0 and pending_amount >= 0
    and used_amount >= 0 and expired_amount >= 0
  )
)

create index hr_leave_balance_employee_fk_idx
  on public.hr_leave_balance(employee_id, tenant_id)

create index hr_leave_balance_type_fk_idx
  on public.hr_leave_balance(leave_type_id, tenant_id)

create index hr_leave_balance_policy_fk_idx
  on public.hr_leave_balance(policy_id, tenant_id) where policy_id is not null

create index hr_leave_balance_year_idx
  on public.hr_leave_balance(tenant_id, balance_year, employee_id)

create table public.hr_leave_request (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  request_no text not null,
  employee_id uuid not null,
  leave_type_id uuid not null,
  policy_id uuid,
  balance_id uuid,
  start_date date not null,
  end_date date not null,
  start_session text not null default 'full',
  end_session text not null default 'full',
  requested_amount numeric(10, 2) not null,
  unit_snapshot text not null,
  reason text not null,
  proof_urls jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  workflow_instance_id uuid,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by text,
  review_comment text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_leave_request_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_leave_request_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_leave_request_type_fkey foreign key (leave_type_id, tenant_id)
    references public.hr_leave_type(id, tenant_id) on delete restrict,
  constraint hr_leave_request_policy_fkey foreign key (policy_id, tenant_id)
    references public.hr_leave_policy(id, tenant_id) on delete restrict,
  constraint hr_leave_request_balance_fkey foreign key (balance_id, tenant_id)
    references public.hr_leave_balance(id, tenant_id) on delete restrict,
  constraint hr_leave_request_id_tenant_unique unique (id, tenant_id),
  constraint hr_leave_request_no_unique unique (tenant_id, request_no),
  constraint hr_leave_request_dates_check check (end_date >= start_date),
  constraint hr_leave_request_single_year_check
    check (extract(year from start_date) = extract(year from end_date)),
  constraint hr_leave_request_amount_check check (requested_amount > 0),
  constraint hr_leave_request_unit_check check (unit_snapshot in ('day', 'hour')),
  constraint hr_leave_request_session_check
    check (start_session in ('full', 'morning', 'afternoon') and end_session in ('full', 'morning', 'afternoon')),
  constraint hr_leave_request_reason_not_blank check (btrim(reason) <> ''),
  constraint hr_leave_request_proof_urls_array check (jsonb_typeof(proof_urls) = 'array'),
  constraint hr_leave_request_status_check
    check (status in ('draft', 'pending', 'approved', 'rejected', 'cancelled'))
)

create index hr_leave_request_employee_fk_idx
  on public.hr_leave_request(employee_id, tenant_id)

create index hr_leave_request_type_fk_idx
  on public.hr_leave_request(leave_type_id, tenant_id)

create index hr_leave_request_policy_fk_idx
  on public.hr_leave_request(policy_id, tenant_id) where policy_id is not null

create index hr_leave_request_balance_fk_idx
  on public.hr_leave_request(balance_id, tenant_id) where balance_id is not null

create index hr_leave_request_workflow_fk_idx
  on public.hr_leave_request(workflow_instance_id) where workflow_instance_id is not null

create index hr_leave_request_status_dates_idx
  on public.hr_leave_request(tenant_id, status, start_date, end_date)

alter table public.hr_leave_request
  add constraint hr_leave_request_active_no_overlap
  exclude using gist (
    tenant_id with =,
    employee_id with =,
    (daterange(start_date, end_date, '[]')) with &&
  ) where (status in ('pending', 'approved'))

create table public.hr_leave_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  balance_id uuid not null,
  employee_id uuid not null,
  leave_type_id uuid not null,
  request_id uuid,
  transaction_type text not null,
  delta_opening numeric(12, 2) not null default 0,
  delta_accrued numeric(12, 2) not null default 0,
  delta_adjusted numeric(12, 2) not null default 0,
  delta_pending numeric(12, 2) not null default 0,
  delta_used numeric(12, 2) not null default 0,
  delta_expired numeric(12, 2) not null default 0,
  occurred_on date not null default current_date,
  reason text not null,
  idempotency_key text not null,
  create_by text,
  create_time timestamptz not null default now(),
  constraint hr_leave_ledger_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_leave_ledger_balance_fkey foreign key (balance_id, tenant_id)
    references public.hr_leave_balance(id, tenant_id) on delete restrict,
  constraint hr_leave_ledger_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_leave_ledger_type_fkey foreign key (leave_type_id, tenant_id)
    references public.hr_leave_type(id, tenant_id) on delete restrict,
  constraint hr_leave_ledger_request_fkey foreign key (request_id, tenant_id)
    references public.hr_leave_request(id, tenant_id) on delete restrict,
  constraint hr_leave_ledger_idempotency_unique unique (tenant_id, idempotency_key),
  constraint hr_leave_ledger_type_check check (transaction_type in (
    'opening', 'accrual', 'adjustment', 'reservation', 'release',
    'usage', 'reversal', 'expiry', 'carryover'
  )),
  constraint hr_leave_ledger_reason_not_blank check (btrim(reason) <> '')
)

create index hr_leave_ledger_balance_fk_idx
  on public.hr_leave_ledger(balance_id, tenant_id)

create index hr_leave_ledger_employee_fk_idx
  on public.hr_leave_ledger(employee_id, tenant_id)

create index hr_leave_ledger_type_fk_idx
  on public.hr_leave_ledger(leave_type_id, tenant_id)

create index hr_leave_ledger_request_fk_idx
  on public.hr_leave_ledger(request_id, tenant_id) where request_id is not null

create index hr_leave_ledger_occurred_idx
  on public.hr_leave_ledger(tenant_id, occurred_on desc, create_time desc)

create trigger hr_leave_type_create_audit before insert on public.hr_leave_type
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_leave_type_update_audit before update on public.hr_leave_type
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_leave_policy_create_audit before insert on public.hr_leave_policy
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_leave_policy_update_audit before update on public.hr_leave_policy
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_leave_balance_create_audit before insert on public.hr_leave_balance
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_leave_balance_update_audit before update on public.hr_leave_balance
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_leave_request_create_audit before insert on public.hr_leave_request
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_leave_request_update_audit before update on public.hr_leave_request
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_leave_ledger_create_audit before insert on public.hr_leave_ledger
for each row execute function public.trg_set_create_time_and_by('true', 'true')

alter table public.hr_leave_type enable row level security

alter table public.hr_leave_policy enable row level security

alter table public.hr_leave_balance enable row level security

alter table public.hr_leave_request enable row level security

alter table public.hr_leave_ledger enable row level security

create policy hr_leave_type_deny_direct_access on public.hr_leave_type
  for all to authenticated using (false) with check (false)

create policy hr_leave_policy_deny_direct_access on public.hr_leave_policy
  for all to authenticated using (false) with check (false)

create policy hr_leave_balance_deny_direct_access on public.hr_leave_balance
  for all to authenticated using (false) with check (false)

create policy hr_leave_request_deny_direct_access on public.hr_leave_request
  for all to authenticated using (false) with check (false)

create policy hr_leave_ledger_deny_direct_access on public.hr_leave_ledger
  for all to authenticated using (false) with check (false)

revoke all on table public.hr_leave_type from public, anon, authenticated

revoke all on table public.hr_leave_policy from public, anon, authenticated

revoke all on table public.hr_leave_balance from public, anon, authenticated

revoke all on table public.hr_leave_request from public, anon, authenticated

revoke all on table public.hr_leave_ledger from public, anon, authenticated

grant all on table public.hr_leave_type to service_role

grant all on table public.hr_leave_policy to service_role

grant all on table public.hr_leave_balance to service_role

grant all on table public.hr_leave_request to service_role

grant all on table public.hr_leave_ledger to service_role

create or replace function app_private.hr_find_leave_policy(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_effective_date date
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select policy_row.id
  from public.hr_leave_policy policy_row
  join public.hr_employee employee_row
    on employee_row.id = p_employee_id and employee_row.tenant_id = p_tenant_id
  left join lateral (
    select assignment_row.grade_id
    from public.hr_employee_assignment assignment_row
    where assignment_row.employee_id = employee_row.id
      and assignment_row.tenant_id = employee_row.tenant_id
      and assignment_row.assignment_status = 'active'
      and assignment_row.effective_start <= p_effective_date
      and coalesce(assignment_row.effective_end, 'infinity'::date) >= p_effective_date
    order by assignment_row.primary_assignment desc, assignment_row.effective_start desc
    limit 1
  ) assignment_row on true
  where policy_row.tenant_id = p_tenant_id
    and policy_row.leave_type_id = p_leave_type_id
    and policy_row.status = 'active'
    and policy_row.effective_from <= p_effective_date
    and coalesce(policy_row.effective_to, 'infinity'::date) >= p_effective_date
    and (
      policy_row.scope_type = 'all'
      or (policy_row.scope_type = 'organization' and policy_row.organization_id = employee_row.organization_id)
      or (policy_row.scope_type = 'employee' and policy_row.employee_id = employee_row.id)
      or (policy_row.scope_type = 'grade' and policy_row.grade_id = assignment_row.grade_id)
    )
  order by case policy_row.scope_type
    when 'employee' then 40 when 'organization' then 30 when 'grade' then 20 else 10 end desc,
    policy_row.effective_from desc
  limit 1;
$function$

create or replace function app_private.hr_ensure_leave_balance(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_balance_year integer,
  p_effective_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_policy public.hr_leave_policy%rowtype;
  v_balance_id uuid;
  v_initial_accrual numeric(12, 2) := 0;
begin
  select * into v_policy
  from public.hr_leave_policy
  where id = app_private.hr_find_leave_policy(
    p_tenant_id, p_employee_id, p_leave_type_id, p_effective_date
  );
  if v_policy.id is null then
    raise exception '当前员工没有匹配的生效休假政策';
  end if;

  if v_policy.entitlement_method = 'annual' then
    v_initial_accrual := v_policy.annual_quota;
  elsif v_policy.entitlement_method = 'monthly_accrual' then
    v_initial_accrual := round(v_policy.monthly_accrual * extract(month from p_effective_date), 2);
  end if;

  insert into public.hr_leave_balance(
    tenant_id, employee_id, leave_type_id, policy_id, balance_year, accrued_amount
  ) values (
    p_tenant_id, p_employee_id, p_leave_type_id, v_policy.id, p_balance_year, v_initial_accrual
  )
  on conflict (tenant_id, employee_id, leave_type_id, balance_year) do update set
    policy_id = excluded.policy_id,
    update_time = now()
  returning id into v_balance_id;

  insert into public.hr_leave_ledger(
    tenant_id, balance_id, employee_id, leave_type_id, transaction_type,
    delta_accrued, occurred_on, reason, idempotency_key
  )
  select p_tenant_id, v_balance_id, p_employee_id, p_leave_type_id, 'accrual',
    v_initial_accrual, make_date(p_balance_year, 1, 1), '年度休假权益初始化',
    'balance-init:' || v_balance_id::text
  where v_initial_accrual <> 0
  on conflict (tenant_id, idempotency_key) do nothing;

  return v_balance_id;
end;
$function$

create or replace function public.hr_absence_overview_secure(p_tenant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrAbsence', 'Hr:Absence:View', null, false) then
    raise exception 'Missing absence view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'pending_count', (select count(*) from public.hr_leave_request request_row
      where (p_tenant_id is null or request_row.tenant_id = p_tenant_id) and request_row.status = 'pending'),
    'upcoming_count', (select count(*) from public.hr_leave_request request_row
      where (p_tenant_id is null or request_row.tenant_id = p_tenant_id)
        and request_row.status = 'approved' and request_row.start_date between current_date and current_date + 30),
    'covered_employee_count', (select count(distinct balance_row.employee_id)
      from public.hr_leave_balance balance_row
      where (p_tenant_id is null or balance_row.tenant_id = p_tenant_id)
        and balance_row.balance_year = extract(year from current_date)::integer),
    'active_policy_count', (select count(*) from public.hr_leave_policy policy_row
      where (p_tenant_id is null or policy_row.tenant_id = p_tenant_id)
        and policy_row.status = 'active'
        and policy_row.effective_from <= current_date
        and coalesce(policy_row.effective_to, 'infinity'::date) >= current_date),
    'expiring_balance_count', (select count(*) from public.hr_leave_balance balance_row
      where (p_tenant_id is null or balance_row.tenant_id = p_tenant_id)
        and balance_row.expires_on between current_date and current_date + 30
        and balance_row.opening_amount + balance_row.accrued_amount + balance_row.adjusted_amount
          - balance_row.pending_amount - balance_row.used_amount - balance_row.expired_amount > 0)
  );
end;
$function$

create or replace function public.hr_list_absence_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_balance_year integer default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_can_view_reason boolean;
  v_result jsonb;
begin
  if p_kind not in ('request', 'balance', 'policy', 'type', 'ledger') then
    raise exception '不支持的假勤记录类型';
  end if;
  if not app_private.can_execute_business_action('HrAbsence', 'Hr:Absence:View', null, false) then
    raise exception 'Missing absence view permission' using errcode = '42501';
  end if;
  v_can_view_reason := app_private.can_execute_business_action(
    'HrAbsence', 'Hr:Absence:Reason:View', null, false
  );
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'type' then
    with filtered as materialized (
      select type_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        (select count(*) from public.hr_leave_policy policy_row
          where policy_row.leave_type_id = type_row.id) as policy_count
      from public.hr_leave_type type_row
      join public.sys_tenant tenant_row on tenant_row.id = type_row.tenant_id
      where (p_tenant_id is null or type_row.tenant_id = p_tenant_id)
        and (p_status is null or type_row.enabled = (p_status = 'enabled'))
        and (v_keyword is null or type_row.leave_code ilike '%' || v_keyword || '%'
          or type_row.leave_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, sort, leave_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg((to_jsonb(paged) - 'tenant_code' - 'tenant_name') ||
        jsonb_build_object('tenant', jsonb_build_object('id', tenant_id,
          'tenant_code', tenant_code, 'tenant_name', tenant_name))
        order by tenant_name, sort, leave_name), '[]'::jsonb),
      'total', (select count(*) from filtered), 'reason_access', v_can_view_reason
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'reason_access', v_can_view_reason));
  end if;

  if p_kind = 'policy' then
    with filtered as materialized (
      select policy_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        type_row.leave_code, type_row.leave_name, type_row.unit,
        organization_row.organization_code, organization_row.organization_name,
        employee_row.employee_no, employee_row.employee_name,
        grade_row.grade_code, grade_row.grade_name
      from public.hr_leave_policy policy_row
      join public.sys_tenant tenant_row on tenant_row.id = policy_row.tenant_id
      join public.hr_leave_type type_row on type_row.id = policy_row.leave_type_id
      left join public.sys_organization organization_row on organization_row.id = policy_row.organization_id
      left join public.hr_employee employee_row on employee_row.id = policy_row.employee_id
      left join public.hr_grade grade_row on grade_row.id = policy_row.grade_id
      where (p_tenant_id is null or policy_row.tenant_id = p_tenant_id)
        and (p_status is null or policy_row.status = p_status)
        and (v_keyword is null or policy_row.policy_code ilike '%' || v_keyword || '%'
          or policy_row.policy_name ilike '%' || v_keyword || '%'
          or type_row.leave_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, policy_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg((to_jsonb(paged)
        - 'tenant_code' - 'tenant_name' - 'leave_code' - 'leave_name' - 'unit'
        - 'organization_code' - 'organization_name' - 'employee_no' - 'employee_name'
        - 'grade_code' - 'grade_name') || jsonb_build_object(
          'tenant', jsonb_build_object('id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name),
          'leave_type', jsonb_build_object('id', leave_type_id, 'leave_code', leave_code, 'leave_name', leave_name, 'unit', unit),
          'scope', jsonb_strip_nulls(jsonb_build_object(
            'organization_id', organization_id, 'organization_code', organization_code, 'organization_name', organization_name,
            'employee_id', employee_id, 'employee_no', employee_no, 'employee_name', employee_name,
            'grade_id', grade_id, 'grade_code', grade_code, 'grade_name', grade_name
          ))
        ) order by tenant_name, policy_name), '[]'::jsonb),
      'total', (select count(*) from filtered), 'reason_access', v_can_view_reason
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'reason_access', v_can_view_reason));
  end if;

  if p_kind = 'balance' then
    with filtered as materialized (
      select balance_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        employee_row.employee_no, employee_row.employee_name,
        organization_row.organization_name,
        type_row.leave_code, type_row.leave_name, type_row.unit,
        policy_row.policy_code, policy_row.policy_name,
        balance_row.opening_amount + balance_row.accrued_amount + balance_row.adjusted_amount
          - balance_row.pending_amount - balance_row.used_amount - balance_row.expired_amount as available_amount
      from public.hr_leave_balance balance_row
      join public.sys_tenant tenant_row on tenant_row.id = balance_row.tenant_id
      join public.hr_employee employee_row on employee_row.id = balance_row.employee_id
      left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
      join public.hr_leave_type type_row on type_row.id = balance_row.leave_type_id
      left join public.hr_leave_policy policy_row on policy_row.id = balance_row.policy_id
      where (p_tenant_id is null or balance_row.tenant_id = p_tenant_id)
        and (p_balance_year is null or balance_row.balance_year = p_balance_year)
        and (v_keyword is null or employee_row.employee_no ilike '%' || v_keyword || '%'
          or employee_row.employee_name ilike '%' || v_keyword || '%'
          or type_row.leave_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, employee_name, leave_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg((to_jsonb(paged)
        - 'tenant_code' - 'tenant_name' - 'employee_no' - 'employee_name' - 'organization_name'
        - 'leave_code' - 'leave_name' - 'unit' - 'policy_code' - 'policy_name') || jsonb_build_object(
          'tenant', jsonb_build_object('id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name),
          'employee', jsonb_build_object('id', employee_id, 'employee_no', employee_no, 'employee_name', employee_name),
          'organization', jsonb_build_object('organization_name', organization_name),
          'leave_type', jsonb_build_object('id', leave_type_id, 'leave_code', leave_code, 'leave_name', leave_name, 'unit', unit),
          'policy', case when policy_id is null then null else jsonb_build_object('id', policy_id, 'policy_code', policy_code, 'policy_name', policy_name) end
        ) order by tenant_name, employee_name, leave_name), '[]'::jsonb),
      'total', (select count(*) from filtered), 'reason_access', v_can_view_reason
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'reason_access', v_can_view_reason));
  end if;

  if p_kind = 'request' then
    with filtered as materialized (
      select request_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        employee_row.employee_no, employee_row.employee_name,
        organization_row.organization_name,
        type_row.leave_code, type_row.leave_name,
        case when v_can_view_reason then request_row.reason else '***' end as visible_reason
      from public.hr_leave_request request_row
      join public.sys_tenant tenant_row on tenant_row.id = request_row.tenant_id
      join public.hr_employee employee_row on employee_row.id = request_row.employee_id
      left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
      join public.hr_leave_type type_row on type_row.id = request_row.leave_type_id
      where (p_tenant_id is null or request_row.tenant_id = p_tenant_id)
        and (p_status is null or request_row.status = p_status)
        and (v_keyword is null or request_row.request_no ilike '%' || v_keyword || '%'
          or employee_row.employee_no ilike '%' || v_keyword || '%'
          or employee_row.employee_name ilike '%' || v_keyword || '%'
          or type_row.leave_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, create_time desc offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(((to_jsonb(paged)
        - 'tenant_code' - 'tenant_name' - 'employee_no' - 'employee_name' - 'organization_name'
        - 'leave_code' - 'leave_name' - 'visible_reason' - 'reason'
        - case when v_can_view_reason then '__keep_proof__' else 'proof_urls' end) || jsonb_build_object(
          'reason', visible_reason,
          'proof_urls', case when v_can_view_reason then proof_urls else '[]'::jsonb end,
          'tenant', jsonb_build_object('id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name),
          'employee', jsonb_build_object('id', employee_id, 'employee_no', employee_no, 'employee_name', employee_name),
          'organization', jsonb_build_object('organization_name', organization_name),
          'leave_type', jsonb_build_object('id', leave_type_id, 'leave_code', leave_code, 'leave_name', leave_name, 'unit', unit_snapshot)
        )) order by tenant_name, create_time desc), '[]'::jsonb),
      'total', (select count(*) from filtered), 'reason_access', v_can_view_reason
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'reason_access', v_can_view_reason));
  end if;

  with filtered as materialized (
    select ledger_row.*, employee_row.employee_no, employee_row.employee_name,
      type_row.leave_code, type_row.leave_name, type_row.unit,
      request_row.request_no
    from public.hr_leave_ledger ledger_row
    join public.hr_employee employee_row on employee_row.id = ledger_row.employee_id
    join public.hr_leave_type type_row on type_row.id = ledger_row.leave_type_id
    left join public.hr_leave_request request_row on request_row.id = ledger_row.request_id
    where (p_tenant_id is null or ledger_row.tenant_id = p_tenant_id)
      and (p_balance_year is null or extract(year from ledger_row.occurred_on)::integer = p_balance_year)
      and (p_status is null or ledger_row.transaction_type = p_status)
      and (v_keyword is null or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or type_row.leave_name ilike '%' || v_keyword || '%'
        or request_row.request_no ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by occurred_on desc, create_time desc offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg((to_jsonb(paged)
      - 'employee_no' - 'employee_name' - 'leave_code' - 'leave_name' - 'unit' - 'request_no') || jsonb_build_object(
        'employee', jsonb_build_object('id', employee_id, 'employee_no', employee_no, 'employee_name', employee_name),
        'leave_type', jsonb_build_object('id', leave_type_id, 'leave_code', leave_code, 'leave_name', leave_name, 'unit', unit),
        'request', case when request_id is null then null else jsonb_build_object('id', request_id, 'request_no', request_no) end
      ) order by occurred_on desc, create_time desc), '[]'::jsonb),
    'total', (select count(*) from filtered), 'reason_access', v_can_view_reason
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'reason_access', v_can_view_reason));
end;
$function$

create or replace function public.hr_list_absence_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrAbsence', 'Hr:Absence:View', null, false) then
    raise exception 'Missing absence view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'employee' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', employee_row.id, 'tenant_id', employee_row.tenant_id,
      'code', employee_row.employee_no, 'name', employee_row.employee_name,
      'organization_id', employee_row.organization_id,
      'organization_name', organization_row.organization_name
    ) order by employee_row.employee_name), '[]'::jsonb) into v_result
    from public.hr_employee employee_row
    left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
    where (p_tenant_id is null or employee_row.tenant_id = p_tenant_id)
      and employee_row.employment_status in ('probation', 'active', 'leave');
  elsif p_kind = 'leave_type' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', type_row.id, 'tenant_id', type_row.tenant_id,
      'code', type_row.leave_code, 'name', type_row.leave_name,
      'unit', type_row.unit, 'minimum_increment', type_row.minimum_increment
    ) order by type_row.sort, type_row.leave_name), '[]'::jsonb) into v_result
    from public.hr_leave_type type_row
    where (p_tenant_id is null or type_row.tenant_id = p_tenant_id) and type_row.enabled;
  elsif p_kind = 'organization' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', organization_row.id, 'tenant_id', organization_row.tenant_id,
      'code', organization_row.organization_code, 'name', organization_row.organization_name
    ) order by organization_row.organization_name), '[]'::jsonb) into v_result
    from public.sys_organization organization_row
    where (p_tenant_id is null or organization_row.tenant_id = p_tenant_id);
  elsif p_kind = 'grade' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', grade_row.id, 'tenant_id', grade_row.tenant_id,
      'code', grade_row.grade_code, 'name', grade_row.grade_name
    ) order by grade_row.grade_level, grade_row.grade_name), '[]'::jsonb) into v_result
    from public.hr_grade grade_row
    where (p_tenant_id is null or grade_row.tenant_id = p_tenant_id) and grade_row.enabled;
  elsif p_kind = 'policy' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', policy_row.id, 'tenant_id', policy_row.tenant_id,
      'code', policy_row.policy_code, 'name', policy_row.policy_name,
      'leave_type_id', policy_row.leave_type_id
    ) order by policy_row.policy_name), '[]'::jsonb) into v_result
    from public.hr_leave_policy policy_row
    where (p_tenant_id is null or policy_row.tenant_id = p_tenant_id)
      and policy_row.status = 'active'
      and policy_row.effective_from <= current_date
      and coalesce(policy_row.effective_to, 'infinity'::date) >= current_date;
  else
    raise exception '不支持的假勤选项类型';
  end if;
  return coalesce(v_result, '[]'::jsonb);
end;
$function$

create or replace function public.hr_save_absence_master_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := coalesce(nullif(p_payload->>'tenant_id', '')::uuid, app_private.current_user_tenant_id());
  v_permission text := case when p_id is null then 'Hr:Absence:Policy:Add' else 'Hr:Absence:Policy:Edit' end;
  v_result_id uuid;
begin
  if p_kind not in ('type', 'policy') then raise exception '不支持的假勤主数据类型'; end if;
  if not app_private.can_execute_business_action('HrAbsence', v_permission, null, false) then
    raise exception 'Missing absence policy permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then v_tenant_id := app_private.current_user_tenant_id(); end if;
  if v_tenant_id is null then raise exception '无法确定租户'; end if;

  if p_kind = 'type' then
    insert into public.hr_leave_type(
      id, tenant_id, leave_code, leave_name, category, unit, paid_ratio,
      minimum_increment, proof_required_after, color, enabled, sort, description
    ) values (
      coalesce(p_id, gen_random_uuid()), v_tenant_id,
      upper(btrim(p_payload->>'leave_code')), btrim(p_payload->>'leave_name'),
      p_payload->>'category', coalesce(p_payload->>'unit', 'day'),
      coalesce((p_payload->>'paid_ratio')::numeric, 1),
      coalesce((p_payload->>'minimum_increment')::numeric, 0.5),
      nullif(p_payload->>'proof_required_after', '')::numeric,
      coalesce(nullif(p_payload->>'color', ''), '#6366f1'),
      coalesce((p_payload->>'enabled')::boolean, true),
      coalesce((p_payload->>'sort')::integer, 0), nullif(btrim(p_payload->>'description'), '')
    )
    on conflict (id) do update set
      leave_code = excluded.leave_code, leave_name = excluded.leave_name,
      category = excluded.category, unit = excluded.unit, paid_ratio = excluded.paid_ratio,
      minimum_increment = excluded.minimum_increment,
      proof_required_after = excluded.proof_required_after, color = excluded.color,
      enabled = excluded.enabled, sort = excluded.sort, description = excluded.description
    where public.hr_leave_type.tenant_id = v_tenant_id
    returning id into v_result_id;
    if v_result_id is null then raise exception '假别不存在或无权修改'; end if;
    return v_result_id;
  end if;

  insert into public.hr_leave_policy(
    id, tenant_id, leave_type_id, policy_code, policy_name, scope_type,
    organization_id, employee_id, grade_id, entitlement_method, annual_quota,
    monthly_accrual, carryover_limit, carryover_expiry_months, allow_negative,
    negative_limit, probation_eligible, effective_from, effective_to, status, description
  ) values (
    coalesce(p_id, gen_random_uuid()), v_tenant_id,
    (p_payload->>'leave_type_id')::uuid, upper(btrim(p_payload->>'policy_code')),
    btrim(p_payload->>'policy_name'), coalesce(p_payload->>'scope_type', 'all'),
    nullif(p_payload->>'organization_id', '')::uuid,
    nullif(p_payload->>'employee_id', '')::uuid,
    nullif(p_payload->>'grade_id', '')::uuid,
    coalesce(p_payload->>'entitlement_method', 'annual'),
    coalesce((p_payload->>'annual_quota')::numeric, 0),
    coalesce((p_payload->>'monthly_accrual')::numeric, 0),
    coalesce((p_payload->>'carryover_limit')::numeric, 0),
    nullif(p_payload->>'carryover_expiry_months', '')::integer,
    coalesce((p_payload->>'allow_negative')::boolean, false),
    coalesce((p_payload->>'negative_limit')::numeric, 0),
    coalesce((p_payload->>'probation_eligible')::boolean, false),
    (p_payload->>'effective_from')::date,
    nullif(p_payload->>'effective_to', '')::date,
    coalesce(p_payload->>'status', 'draft'), nullif(btrim(p_payload->>'description'), '')
  )
  on conflict (id) do update set
    leave_type_id = excluded.leave_type_id, policy_code = excluded.policy_code,
    policy_name = excluded.policy_name, scope_type = excluded.scope_type,
    organization_id = excluded.organization_id, employee_id = excluded.employee_id,
    grade_id = excluded.grade_id, entitlement_method = excluded.entitlement_method,
    annual_quota = excluded.annual_quota, monthly_accrual = excluded.monthly_accrual,
    carryover_limit = excluded.carryover_limit,
    carryover_expiry_months = excluded.carryover_expiry_months,
    allow_negative = excluded.allow_negative, negative_limit = excluded.negative_limit,
    probation_eligible = excluded.probation_eligible,
    effective_from = excluded.effective_from, effective_to = excluded.effective_to,
    status = excluded.status, description = excluded.description
  where public.hr_leave_policy.tenant_id = v_tenant_id
  returning id into v_result_id;
  if v_result_id is null then raise exception '休假政策不存在或无权修改'; end if;
  return v_result_id;
end;
$function$

create or replace function public.hr_save_leave_request_secure(
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := coalesce(nullif(p_payload->>'tenant_id', '')::uuid, app_private.current_user_tenant_id());
  v_permission text := case when p_id is null then 'Hr:Absence:Request:Add' else 'Hr:Absence:Request:Edit' end;
  v_employee_id uuid := (p_payload->>'employee_id')::uuid;
  v_leave_type_id uuid := (p_payload->>'leave_type_id')::uuid;
  v_start_date date := (p_payload->>'start_date')::date;
  v_end_date date := (p_payload->>'end_date')::date;
  v_leave_type public.hr_leave_type%rowtype;
  v_policy_id uuid;
  v_result_id uuid;
begin
  if not app_private.can_execute_business_action('HrAbsence', v_permission, null, false) then
    raise exception 'Missing leave request permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then v_tenant_id := app_private.current_user_tenant_id(); end if;
  if not exists (select 1 from public.hr_employee where id = v_employee_id and tenant_id = v_tenant_id) then
    raise exception '员工不存在或不属于当前租户';
  end if;
  select * into v_leave_type from public.hr_leave_type
  where id = v_leave_type_id and tenant_id = v_tenant_id and enabled;
  if v_leave_type.id is null then raise exception '假别不存在或已停用'; end if;
  if extract(year from v_start_date) <> extract(year from v_end_date) then
    raise exception '跨年度请假请拆分为两张申请';
  end if;
  v_policy_id := app_private.hr_find_leave_policy(v_tenant_id, v_employee_id, v_leave_type_id, v_start_date);
  if v_policy_id is null then raise exception '当前员工没有匹配的生效休假政策'; end if;

  if p_id is not null and not exists (
    select 1 from public.hr_leave_request where id = p_id and tenant_id = v_tenant_id and status = 'draft'
  ) then raise exception '仅草稿申请允许编辑'; end if;

  insert into public.hr_leave_request(
    id, tenant_id, request_no, employee_id, leave_type_id, policy_id,
    start_date, end_date, start_session, end_session, requested_amount,
    unit_snapshot, reason, proof_urls, status
  ) values (
    coalesce(p_id, gen_random_uuid()), v_tenant_id,
    coalesce(nullif(p_payload->>'request_no', ''),
      'LR-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))),
    v_employee_id, v_leave_type_id, v_policy_id, v_start_date, v_end_date,
    coalesce(p_payload->>'start_session', 'full'), coalesce(p_payload->>'end_session', 'full'),
    (p_payload->>'requested_amount')::numeric, v_leave_type.unit,
    btrim(p_payload->>'reason'), coalesce(p_payload->'proof_urls', '[]'::jsonb), 'draft'
  )
  on conflict (id) do update set
    employee_id = excluded.employee_id, leave_type_id = excluded.leave_type_id,
    policy_id = excluded.policy_id, start_date = excluded.start_date, end_date = excluded.end_date,
    start_session = excluded.start_session, end_session = excluded.end_session,
    requested_amount = excluded.requested_amount, unit_snapshot = excluded.unit_snapshot,
    reason = excluded.reason, proof_urls = excluded.proof_urls
  where public.hr_leave_request.tenant_id = v_tenant_id
    and public.hr_leave_request.status = 'draft'
  returning id into v_result_id;
  if v_result_id is null then raise exception '休假申请不存在或不可编辑'; end if;
  return v_result_id;
end;
$function$

create or replace function public.hr_adjust_leave_balance_secure(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_balance_year integer,
  p_delta numeric,
  p_reason text,
  p_tenant_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_balance public.hr_leave_balance%rowtype;
  v_policy public.hr_leave_policy%rowtype;
begin
  if not app_private.can_execute_business_action('HrAbsence', 'Hr:Absence:Balance:Adjust', null, false) then
    raise exception 'Missing leave balance adjustment permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  p_tenant_id := coalesce(p_tenant_id, v_tenant_id);
  if p_delta = 0 then raise exception '调整数量不能为 0'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception '请输入余额调整原因'; end if;

  perform app_private.hr_ensure_leave_balance(
    p_tenant_id, p_employee_id, p_leave_type_id, p_balance_year,
    make_date(p_balance_year, 1, 1)
  );
  select * into v_balance from public.hr_leave_balance
  where tenant_id = p_tenant_id and employee_id = p_employee_id
    and leave_type_id = p_leave_type_id and balance_year = p_balance_year
  for update;
  select * into v_policy from public.hr_leave_policy where id = v_balance.policy_id;

  if not v_policy.allow_negative and
    v_balance.opening_amount + v_balance.accrued_amount + v_balance.adjusted_amount + p_delta
      - v_balance.pending_amount - v_balance.used_amount - v_balance.expired_amount < 0 then
    raise exception '调整后可用余额不能小于 0';
  end if;
  if v_policy.allow_negative and
    v_balance.opening_amount + v_balance.accrued_amount + v_balance.adjusted_amount + p_delta
      - v_balance.pending_amount - v_balance.used_amount - v_balance.expired_amount < -v_policy.negative_limit then
    raise exception '调整后余额超过政策允许的负数额度';
  end if;

  update public.hr_leave_balance set adjusted_amount = adjusted_amount + p_delta
  where id = v_balance.id;
  insert into public.hr_leave_ledger(
    tenant_id, balance_id, employee_id, leave_type_id, transaction_type,
    delta_adjusted, occurred_on, reason, idempotency_key
  ) values (
    p_tenant_id, v_balance.id, p_employee_id, p_leave_type_id, 'adjustment',
    p_delta, current_date, btrim(p_reason), 'adjust:' || gen_random_uuid()::text
  );
  return v_balance.id;
end;
$function$

create or replace function public.hr_act_leave_request_secure(
  p_request_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.hr_leave_request%rowtype;
  v_balance public.hr_leave_balance%rowtype;
  v_policy public.hr_leave_policy%rowtype;
  v_available numeric(12, 2);
  v_permission text;
begin
  if p_action not in ('submit', 'approve', 'reject', 'cancel') then
    raise exception '不支持的休假申请动作';
  end if;
  v_permission := case when p_action in ('approve', 'reject')
    then 'Hr:Absence:Approve' else 'Hr:Absence:Submit' end;
  if not app_private.can_execute_business_action('HrAbsence', v_permission, null, false) then
    raise exception 'Missing leave request action permission' using errcode = '42501';
  end if;

  select * into v_request from public.hr_leave_request where id = p_request_id for update;
  if v_request.id is null then raise exception '休假申请不存在'; end if;
  if not app_private.is_platform_super() and v_request.tenant_id <> app_private.current_user_tenant_id() then
    raise exception '不能处理其他租户的休假申请' using errcode = '42501';
  end if;

  if p_action = 'submit' then
    if v_request.status <> 'draft' then raise exception '仅草稿申请可提交'; end if;
    v_request.balance_id := app_private.hr_ensure_leave_balance(
      v_request.tenant_id, v_request.employee_id, v_request.leave_type_id,
      extract(year from v_request.start_date)::integer, v_request.start_date
    );
    select * into v_balance from public.hr_leave_balance where id = v_request.balance_id for update;
    select * into v_policy from public.hr_leave_policy where id = v_balance.policy_id;
    v_available := v_balance.opening_amount + v_balance.accrued_amount + v_balance.adjusted_amount
      - v_balance.pending_amount - v_balance.used_amount - v_balance.expired_amount;
    if (not v_policy.allow_negative and v_available < v_request.requested_amount)
      or (v_policy.allow_negative and v_available - v_request.requested_amount < -v_policy.negative_limit) then
      raise exception '可用休假余额不足';
    end if;
    update public.hr_leave_balance set pending_amount = pending_amount + v_request.requested_amount
      where id = v_balance.id;
    insert into public.hr_leave_ledger(
      tenant_id, balance_id, employee_id, leave_type_id, request_id,
      transaction_type, delta_pending, occurred_on, reason, idempotency_key
    ) values (
      v_request.tenant_id, v_balance.id, v_request.employee_id, v_request.leave_type_id,
      v_request.id, 'reservation', v_request.requested_amount, current_date,
      '提交休假申请 ' || v_request.request_no, 'request:' || v_request.id::text || ':submit'
    );
    update public.hr_leave_request set status = 'pending', balance_id = v_balance.id,
      policy_id = v_balance.policy_id, submitted_at = now()
    where id = v_request.id;
    return true;
  end if;

  if p_action = 'approve' then
    if v_request.status <> 'pending' then raise exception '仅待审批申请可批准'; end if;
    select * into v_balance from public.hr_leave_balance where id = v_request.balance_id for update;
    if v_balance.pending_amount < v_request.requested_amount then raise exception '待审批余额数据不一致'; end if;
    update public.hr_leave_balance set
      pending_amount = pending_amount - v_request.requested_amount,
      used_amount = used_amount + v_request.requested_amount
    where id = v_balance.id;
    insert into public.hr_leave_ledger(
      tenant_id, balance_id, employee_id, leave_type_id, request_id,
      transaction_type, delta_pending, delta_used, occurred_on, reason, idempotency_key
    ) values (
      v_request.tenant_id, v_balance.id, v_request.employee_id, v_request.leave_type_id,
      v_request.id, 'usage', -v_request.requested_amount, v_request.requested_amount,
      v_request.start_date, '批准休假申请 ' || v_request.request_no,
      'request:' || v_request.id::text || ':approve'
    );
    update public.hr_leave_request set status = 'approved', reviewed_at = now(),
      reviewed_by = coalesce((select user_email from public.sys_user
        where id = app_private.current_app_user_id()), auth.uid()::text, 'system'),
      review_comment = nullif(btrim(p_comment), '')
    where id = v_request.id;
    return true;
  end if;

  if p_action = 'reject' then
    if v_request.status <> 'pending' then raise exception '仅待审批申请可驳回'; end if;
    if nullif(btrim(p_comment), '') is null then raise exception '请输入驳回原因'; end if;
    select * into v_balance from public.hr_leave_balance where id = v_request.balance_id for update;
    update public.hr_leave_balance set pending_amount = pending_amount - v_request.requested_amount
      where id = v_balance.id;
    insert into public.hr_leave_ledger(
      tenant_id, balance_id, employee_id, leave_type_id, request_id,
      transaction_type, delta_pending, occurred_on, reason, idempotency_key
    ) values (
      v_request.tenant_id, v_balance.id, v_request.employee_id, v_request.leave_type_id,
      v_request.id, 'release', -v_request.requested_amount, current_date,
      '驳回休假申请：' || btrim(p_comment), 'request:' || v_request.id::text || ':reject'
    );
    update public.hr_leave_request set status = 'rejected', reviewed_at = now(),
      reviewed_by = coalesce((select user_email from public.sys_user
        where id = app_private.current_app_user_id()), auth.uid()::text, 'system'),
      review_comment = btrim(p_comment)
    where id = v_request.id;
    return true;
  end if;

  if v_request.status = 'draft' then
    update public.hr_leave_request set status = 'cancelled', review_comment = nullif(btrim(p_comment), '')
      where id = v_request.id;
    return true;
  elsif v_request.status = 'pending' then
    select * into v_balance from public.hr_leave_balance where id = v_request.balance_id for update;
    update public.hr_leave_balance set pending_amount = pending_amount - v_request.requested_amount
      where id = v_balance.id;
    insert into public.hr_leave_ledger(
      tenant_id, balance_id, employee_id, leave_type_id, request_id,
      transaction_type, delta_pending, occurred_on, reason, idempotency_key
    ) values (
      v_request.tenant_id, v_balance.id, v_request.employee_id, v_request.leave_type_id,
      v_request.id, 'release', -v_request.requested_amount, current_date,
      '撤销休假申请 ' || v_request.request_no, 'request:' || v_request.id::text || ':cancel'
    );
  elsif v_request.status = 'approved' then
    if v_request.start_date < current_date then raise exception '已开始的休假不能直接撤销，请走考勤冲销流程'; end if;
    select * into v_balance from public.hr_leave_balance where id = v_request.balance_id for update;
    update public.hr_leave_balance set used_amount = used_amount - v_request.requested_amount
      where id = v_balance.id;
    insert into public.hr_leave_ledger(
      tenant_id, balance_id, employee_id, leave_type_id, request_id,
      transaction_type, delta_used, occurred_on, reason, idempotency_key
    ) values (
      v_request.tenant_id, v_balance.id, v_request.employee_id, v_request.leave_type_id,
      v_request.id, 'reversal', -v_request.requested_amount, current_date,
      '撤销已批准休假 ' || v_request.request_no, 'request:' || v_request.id::text || ':cancel-approved'
    );
  else
    raise exception '当前申请状态不能撤销';
  end if;
  update public.hr_leave_request set status = 'cancelled', review_comment = nullif(btrim(p_comment), '')
  where id = v_request.id;
  return true;
end;
$function$

create or replace function public.hr_delete_absence_record_secure(p_kind text, p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_permission text;
  v_count integer;
begin
  if p_kind not in ('type', 'policy', 'request') then raise exception '不支持的删除类型'; end if;
  v_permission := case when p_kind = 'request' then 'Hr:Absence:Request:Delete'
    else 'Hr:Absence:Policy:Delete' end;
  if not app_private.can_execute_business_action('HrAbsence', v_permission, null, false) then
    raise exception 'Missing absence delete permission' using errcode = '42501';
  end if;
  if p_kind = 'request' then
    delete from public.hr_leave_request where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
  elsif p_kind = 'policy' then
    delete from public.hr_leave_policy where id = p_id and status = 'draft'
      and not exists (select 1 from public.hr_leave_balance where policy_id = p_id)
      and (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
  else
    delete from public.hr_leave_type where id = p_id
      and not exists (select 1 from public.hr_leave_policy where leave_type_id = p_id)
      and (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception '记录不存在、状态不可删除或已被业务引用'; end if;
  return true;
end;
$function$

revoke all on function app_private.hr_find_leave_policy(uuid, uuid, uuid, date) from public, anon, authenticated

revoke all on function app_private.hr_ensure_leave_balance(uuid, uuid, uuid, integer, date) from public, anon, authenticated

revoke all on function public.hr_absence_overview_secure(uuid) from public, anon

revoke all on function public.hr_list_absence_records_secure(text, integer, integer, text, text, integer, uuid) from public, anon

revoke all on function public.hr_list_absence_options_secure(text, uuid) from public, anon

revoke all on function public.hr_save_absence_master_secure(text, uuid, jsonb) from public, anon

revoke all on function public.hr_save_leave_request_secure(uuid, jsonb) from public, anon

revoke all on function public.hr_adjust_leave_balance_secure(uuid, uuid, integer, numeric, text, uuid) from public, anon

revoke all on function public.hr_act_leave_request_secure(uuid, text, text) from public, anon

revoke all on function public.hr_delete_absence_record_secure(text, uuid) from public, anon

grant execute on function public.hr_absence_overview_secure(uuid) to authenticated, service_role

grant execute on function public.hr_list_absence_records_secure(text, integer, integer, text, text, integer, uuid) to authenticated, service_role

grant execute on function public.hr_list_absence_options_secure(text, uuid) to authenticated, service_role

grant execute on function public.hr_save_absence_master_secure(text, uuid, jsonb) to authenticated, service_role

grant execute on function public.hr_save_leave_request_secure(uuid, jsonb) to authenticated, service_role

grant execute on function public.hr_adjust_leave_balance_secure(uuid, uuid, integer, numeric, text, uuid) to authenticated, service_role

grant execute on function public.hr_act_leave_request_secure(uuid, text, text) to authenticated, service_role

grant execute on function public.hr_delete_absence_record_secure(text, uuid) to authenticated, service_role

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_types(name, code, sort) as (
  values
    ('休假类别', 'hrLeaveCategory', 65),
    ('休假计量单位', 'hrLeaveUnit', 66),
    ('休假权益方式', 'hrLeaveEntitlementMethod', 67),
    ('休假政策范围', 'hrLeavePolicyScope', 68),
    ('休假政策状态', 'hrLeavePolicyStatus', 69),
    ('休假申请状态', 'hrLeaveRequestStatus', 70),
    ('休假时段', 'hrLeaveSession', 71),
    ('休假台账类型', 'hrLeaveLedgerType', 72)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), seed.name, seed.code, '1',
  '624944977@qq.com', '624944977@qq.com', '企业 HR 假勤字典',
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', seed.sort
from dictionary_types seed cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark, sort = excluded.sort

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_items(type_code, value, label, sort, tag_type) as (
  values
    ('hrLeaveCategory', 'annual', '年休假', 1, 'success'),
    ('hrLeaveCategory', 'sick', '病假', 2, 'warning'),
    ('hrLeaveCategory', 'personal', '事假', 3, 'info'),
    ('hrLeaveCategory', 'compensatory', '调休', 4, 'primary'),
    ('hrLeaveCategory', 'marriage', '婚假', 5, 'danger'),
    ('hrLeaveCategory', 'maternity', '产假', 6, 'danger'),
    ('hrLeaveCategory', 'paternity', '陪产假', 7, 'primary'),
    ('hrLeaveCategory', 'bereavement', '丧假', 8, 'info'),
    ('hrLeaveCategory', 'parental', '育儿假', 9, 'success'),
    ('hrLeaveCategory', 'unpaid', '无薪假', 10, 'warning'),
    ('hrLeaveCategory', 'other', '其他', 11, 'info'),
    ('hrLeaveUnit', 'day', '天', 1, 'primary'),
    ('hrLeaveUnit', 'hour', '小时', 2, 'success'),
    ('hrLeaveEntitlementMethod', 'annual', '年度一次授予', 1, 'primary'),
    ('hrLeaveEntitlementMethod', 'monthly_accrual', '按月累积', 2, 'success'),
    ('hrLeaveEntitlementMethod', 'manual', '人工授予', 3, 'warning'),
    ('hrLeaveEntitlementMethod', 'none', '不管理余额', 4, 'info'),
    ('hrLeavePolicyScope', 'all', '全员', 1, 'primary'),
    ('hrLeavePolicyScope', 'organization', '指定组织', 2, 'success'),
    ('hrLeavePolicyScope', 'grade', '指定职级', 3, 'warning'),
    ('hrLeavePolicyScope', 'employee', '指定员工', 4, 'danger'),
    ('hrLeavePolicyStatus', 'draft', '草稿', 1, 'info'),
    ('hrLeavePolicyStatus', 'active', '生效中', 2, 'success'),
    ('hrLeavePolicyStatus', 'inactive', '已停用', 3, 'danger'),
    ('hrLeaveRequestStatus', 'draft', '草稿', 1, 'info'),
    ('hrLeaveRequestStatus', 'pending', '待审批', 2, 'warning'),
    ('hrLeaveRequestStatus', 'approved', '已批准', 3, 'success'),
    ('hrLeaveRequestStatus', 'rejected', '已驳回', 4, 'danger'),
    ('hrLeaveRequestStatus', 'cancelled', '已撤销', 5, 'info'),
    ('hrLeaveSession', 'full', '全天', 1, 'primary'),
    ('hrLeaveSession', 'morning', '上午', 2, 'warning'),
    ('hrLeaveSession', 'afternoon', '下午', 3, 'success'),
    ('hrLeaveLedgerType', 'opening', '期初', 1, 'info'),
    ('hrLeaveLedgerType', 'accrual', '权益授予', 2, 'success'),
    ('hrLeaveLedgerType', 'adjustment', '人工调整', 3, 'warning'),
    ('hrLeaveLedgerType', 'reservation', '申请占用', 4, 'primary'),
    ('hrLeaveLedgerType', 'release', '占用释放', 5, 'info'),
    ('hrLeaveLedgerType', 'usage', '休假使用', 6, 'danger'),
    ('hrLeaveLedgerType', 'reversal', '使用冲销', 7, 'success'),
    ('hrLeaveLedgerType', 'expiry', '到期失效', 8, 'danger'),
    ('hrLeaveLedgerType', 'carryover', '结转', 9, 'primary')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, seed.type_code || '_' || seed.value, '1',
  '624944977@qq.com', '624944977@qq.com', '企业 HR 假勤字典项',
  seed.value, seed.label, platform_tenant.id, seed.tag_type, seed.sort
from dictionary_items seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing_item
  where existing_item.type_id = dictionary_type.id and existing_item.value = seed.value
)

do $$ begin
  if not exists (select 1 from public.sys_menu where id = 'c0de0000-0000-4000-8000-000000000206'::uuid) then
    update public.sys_menu set sort = sort + 1, update_by = '624944977@qq.com', update_time = now()
    where parent_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
      and type = 'menu' and sort >= 4;
  end if;
end $$

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
values (
  'c0de0000-0000-4000-8000-000000000206',
  'c0de0000-0000-4000-8000-000000000200',
  'HrAbsence', 'absence', '/hr/operations/absence',
  jsonb_build_object(
    'title', '假勤管理', 'icon', 'ri:calendar-schedule-line',
    'is_hide', false, 'is_enable', true, 'keep_alive', true,
    'is_iframe', false, 'fixed_tab', false, 'show_badge', false,
    'show_text_badge', '', 'is_hide_tab', false, 'is_full_page', false,
    'active_path', '', 'link', '', 'roles', jsonb_build_array('R_SUPER', 'R_ADMIN')
  ),
  4, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  path = excluded.path, component = excluded.component, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now()

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000206'::uuid,
  seed.name, '', '', jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8206-000000000001'::uuid, 'Hr:Absence:View', '查看假勤管理', 1),
  ('c0de0000-0000-4000-8206-000000000002'::uuid, 'Hr:Absence:Policy:Add', '新增假别与政策', 2),
  ('c0de0000-0000-4000-8206-000000000003'::uuid, 'Hr:Absence:Policy:Edit', '编辑假别与政策', 3),
  ('c0de0000-0000-4000-8206-000000000004'::uuid, 'Hr:Absence:Policy:Delete', '删除假别与政策', 4),
  ('c0de0000-0000-4000-8206-000000000005'::uuid, 'Hr:Absence:Balance:Adjust', '调整休假余额', 5),
  ('c0de0000-0000-4000-8206-000000000006'::uuid, 'Hr:Absence:Request:Add', '新增休假申请', 6),
  ('c0de0000-0000-4000-8206-000000000007'::uuid, 'Hr:Absence:Request:Edit', '编辑休假申请', 7),
  ('c0de0000-0000-4000-8206-000000000008'::uuid, 'Hr:Absence:Request:Delete', '删除休假申请', 8),
  ('c0de0000-0000-4000-8206-000000000009'::uuid, 'Hr:Absence:Submit', '提交与撤销休假', 9),
  ('c0de0000-0000-4000-8206-000000000010'::uuid, 'Hr:Absence:Approve', '审批休假申请', 10),
  ('c0de0000-0000-4000-8206-000000000011'::uuid, 'Hr:Absence:Reason:View', '查看休假原因与证明', 11)
) as seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now()

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select existing.role_id, menu_seed.menu_id, existing.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('c0de0000-0000-4000-8000-000000000206'::uuid),
  ('c0de0000-0000-4000-8206-000000000001'::uuid)
) as menu_seed(menu_id)
where existing.menu_id = 'c0de0000-0000-4000-8000-000000000201'::uuid
on conflict (role_id, menu_id) do nothing

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select role_row.id, menu_seed.menu_id, role_row.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role role_row
cross join (values
  ('c0de0000-0000-4000-8000-000000000206'::uuid),
  ('c0de0000-0000-4000-8206-000000000001'::uuid),
  ('c0de0000-0000-4000-8206-000000000002'::uuid),
  ('c0de0000-0000-4000-8206-000000000003'::uuid),
  ('c0de0000-0000-4000-8206-000000000004'::uuid),
  ('c0de0000-0000-4000-8206-000000000005'::uuid),
  ('c0de0000-0000-4000-8206-000000000006'::uuid),
  ('c0de0000-0000-4000-8206-000000000007'::uuid),
  ('c0de0000-0000-4000-8206-000000000008'::uuid),
  ('c0de0000-0000-4000-8206-000000000009'::uuid),
  ('c0de0000-0000-4000-8206-000000000010'::uuid),
  ('c0de0000-0000-4000-8206-000000000011'::uuid)
) as menu_seed(menu_id)
where role_row.enabled and (
  role_row.builtin_type = 'platform_super' or role_row.role_code in ('R_SUPER', 'R_ADMIN')
)
on conflict (role_id, menu_id) do nothing
