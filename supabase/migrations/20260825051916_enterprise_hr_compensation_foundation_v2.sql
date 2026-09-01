-- Enterprise HR compensation foundation.
-- HR owns compensation policy, effective-dated employee packages and payroll inputs.
-- FMS remains the owner of payroll calculation, accounting and payment.

create table public.hr_pay_component (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  component_code text not null,
  component_name text not null,
  category text not null,
  amount_type text not null default 'fixed',
  taxable boolean not null default true,
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_pay_component_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_pay_component_id_tenant_unique unique (id, tenant_id),
  constraint hr_pay_component_code_not_blank check (btrim(component_code) <> ''),
  constraint hr_pay_component_name_not_blank check (btrim(component_name) <> ''),
  constraint hr_pay_component_category_check
    check (category in ('earning', 'deduction', 'employer_cost')),
  constraint hr_pay_component_amount_type_check
    check (amount_type in ('fixed', 'rate', 'variable'))
);
create unique index hr_pay_component_tenant_code_unique
  on public.hr_pay_component(tenant_id, lower(component_code));
create index hr_pay_component_tenant_enabled_sort_idx
  on public.hr_pay_component(tenant_id, enabled, category, sort, component_name);
create table public.hr_compensation_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_code text not null,
  plan_name text not null,
  currency_code text not null default 'CNY',
  pay_frequency text not null default 'monthly',
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_compensation_plan_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compensation_plan_id_tenant_unique unique (id, tenant_id),
  constraint hr_compensation_plan_code_not_blank check (btrim(plan_code) <> ''),
  constraint hr_compensation_plan_name_not_blank check (btrim(plan_name) <> ''),
  constraint hr_compensation_plan_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_compensation_plan_frequency_check
    check (pay_frequency in ('monthly', 'annual', 'hourly'))
);
create unique index hr_compensation_plan_tenant_code_unique
  on public.hr_compensation_plan(tenant_id, lower(plan_code));
create index hr_compensation_plan_tenant_enabled_sort_idx
  on public.hr_compensation_plan(tenant_id, enabled, sort, plan_name);
create table public.hr_compensation_plan_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_id uuid not null,
  component_id uuid not null,
  default_amount numeric(18, 2),
  default_rate numeric(12, 6),
  required boolean not null default false,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_compensation_plan_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_compensation_plan_item_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_compensation_plan(id, tenant_id) on delete cascade,
  constraint hr_compensation_plan_item_component_fkey foreign key (component_id, tenant_id)
    references public.hr_pay_component(id, tenant_id) on delete restrict,
  constraint hr_compensation_plan_item_id_tenant_unique unique (id, tenant_id),
  constraint hr_compensation_plan_item_unique unique (plan_id, component_id),
  constraint hr_compensation_plan_item_amount_nonnegative
    check (default_amount is null or default_amount >= 0),
  constraint hr_compensation_plan_item_rate_nonnegative
    check (default_rate is null or default_rate >= 0)
);
create index hr_compensation_plan_item_plan_idx
  on public.hr_compensation_plan_item(plan_id, tenant_id, sort);
create index hr_compensation_plan_item_component_idx
  on public.hr_compensation_plan_item(component_id, tenant_id);
create table public.hr_salary_band (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  grade_id uuid not null,
  currency_code text not null default 'CNY',
  minimum_amount numeric(18, 2) not null,
  midpoint_amount numeric(18, 2) not null,
  maximum_amount numeric(18, 2) not null,
  effective_from date not null,
  effective_to date,
  status text not null default 'draft',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_salary_band_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_salary_band_grade_fkey foreign key (grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_salary_band_id_tenant_unique unique (id, tenant_id),
  constraint hr_salary_band_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_salary_band_amounts_check check (
    minimum_amount >= 0
    and midpoint_amount >= minimum_amount
    and maximum_amount >= midpoint_amount
  ),
  constraint hr_salary_band_dates_check
    check (effective_to is null or effective_to >= effective_from),
  constraint hr_salary_band_status_check
    check (status in ('draft', 'approved', 'cancelled'))
);
create index hr_salary_band_grade_effective_idx
  on public.hr_salary_band(tenant_id, grade_id, currency_code, effective_from desc);
create index hr_salary_band_approved_effective_idx
  on public.hr_salary_band(tenant_id, effective_from, effective_to)
  where status = 'approved';
create table public.hr_employee_compensation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  employee_id uuid not null,
  plan_id uuid not null,
  grade_id uuid,
  base_amount numeric(18, 2) not null,
  currency_code text not null default 'CNY',
  pay_frequency text not null default 'monthly',
  effective_from date not null,
  effective_to date,
  status text not null default 'draft',
  change_reason text not null,
  source_change_id uuid,
  approved_by text,
  approved_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_compensation_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_compensation_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_compensation_plan_fkey foreign key (plan_id, tenant_id)
    references public.hr_compensation_plan(id, tenant_id) on delete restrict,
  constraint hr_employee_compensation_grade_fkey foreign key (grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_employee_compensation_source_change_fkey foreign key (source_change_id)
    references public.hr_personnel_change(id) on delete restrict,
  constraint hr_employee_compensation_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_compensation_amount_nonnegative check (base_amount >= 0),
  constraint hr_employee_compensation_currency_check check (currency_code ~ '^[A-Z]{3}$'),
  constraint hr_employee_compensation_frequency_check
    check (pay_frequency in ('monthly', 'annual', 'hourly')),
  constraint hr_employee_compensation_dates_check
    check (effective_to is null or effective_to >= effective_from),
  constraint hr_employee_compensation_status_check
    check (status in ('draft', 'approved', 'cancelled')),
  constraint hr_employee_compensation_reason_not_blank check (btrim(change_reason) <> '')
);
create index hr_employee_compensation_employee_effective_idx
  on public.hr_employee_compensation(tenant_id, employee_id, effective_from desc);
create index hr_employee_compensation_plan_idx
  on public.hr_employee_compensation(plan_id, tenant_id);
create index hr_employee_compensation_grade_idx
  on public.hr_employee_compensation(grade_id, tenant_id)
  where grade_id is not null;
create index hr_employee_compensation_approved_effective_idx
  on public.hr_employee_compensation(tenant_id, effective_from, effective_to)
  where status = 'approved';
create table public.hr_employee_compensation_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  compensation_id uuid not null,
  component_id uuid not null,
  amount numeric(18, 2),
  rate numeric(12, 6),
  source text not null default 'plan',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_compensation_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_compensation_item_compensation_fkey
    foreign key (compensation_id, tenant_id)
    references public.hr_employee_compensation(id, tenant_id) on delete cascade,
  constraint hr_employee_compensation_item_component_fkey
    foreign key (component_id, tenant_id)
    references public.hr_pay_component(id, tenant_id) on delete restrict,
  constraint hr_employee_compensation_item_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_compensation_item_unique unique (compensation_id, component_id),
  constraint hr_employee_compensation_item_amount_nonnegative
    check (amount is null or amount >= 0),
  constraint hr_employee_compensation_item_rate_nonnegative
    check (rate is null or rate >= 0),
  constraint hr_employee_compensation_item_source_check
    check (source in ('plan', 'override'))
);
create index hr_employee_compensation_item_compensation_idx
  on public.hr_employee_compensation_item(compensation_id, tenant_id);
create index hr_employee_compensation_item_component_idx
  on public.hr_employee_compensation_item(component_id, tenant_id);
create trigger hr_pay_component_create_audit before insert on public.hr_pay_component
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_pay_component_update_audit before update on public.hr_pay_component
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_compensation_plan_create_audit before insert on public.hr_compensation_plan
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_compensation_plan_update_audit before update on public.hr_compensation_plan
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_compensation_plan_item_create_audit before insert on public.hr_compensation_plan_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_compensation_plan_item_update_audit before update on public.hr_compensation_plan_item
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_salary_band_create_audit before insert on public.hr_salary_band
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_salary_band_update_audit before update on public.hr_salary_band
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_employee_compensation_create_audit before insert on public.hr_employee_compensation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_compensation_update_audit before update on public.hr_employee_compensation
for each row execute function public.trg_set_update_time_and_by();
create trigger hr_employee_compensation_item_create_audit before insert on public.hr_employee_compensation_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_compensation_item_update_audit before update on public.hr_employee_compensation_item
for each row execute function public.trg_set_update_time_and_by();
alter table public.hr_pay_component enable row level security;
alter table public.hr_compensation_plan enable row level security;
alter table public.hr_compensation_plan_item enable row level security;
alter table public.hr_salary_band enable row level security;
alter table public.hr_employee_compensation enable row level security;
alter table public.hr_employee_compensation_item enable row level security;
revoke all on table public.hr_pay_component from public, anon, authenticated;
revoke all on table public.hr_compensation_plan from public, anon, authenticated;
revoke all on table public.hr_compensation_plan_item from public, anon, authenticated;
revoke all on table public.hr_salary_band from public, anon, authenticated;
revoke all on table public.hr_employee_compensation from public, anon, authenticated;
revoke all on table public.hr_employee_compensation_item from public, anon, authenticated;
grant all on table public.hr_pay_component to service_role;
grant all on table public.hr_compensation_plan to service_role;
grant all on table public.hr_compensation_plan_item to service_role;
grant all on table public.hr_salary_band to service_role;
grant all on table public.hr_employee_compensation to service_role;
grant all on table public.hr_employee_compensation_item to service_role;
create or replace function public.hr_compensation_overview_secure(p_tenant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_employee_count integer := 0;
  v_covered_count integer := 0;
begin
  if not app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:View', null, false
  ) then
    raise exception 'Missing compensation view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  select count(*)::integer into v_employee_count
  from public.hr_employee employee_row
  where (p_tenant_id is null or employee_row.tenant_id = p_tenant_id)
    and employee_row.employment_status in ('probation', 'active', 'leave');

  select count(distinct compensation_row.employee_id)::integer into v_covered_count
  from public.hr_employee_compensation compensation_row
  join public.hr_employee employee_row
    on employee_row.id = compensation_row.employee_id
   and employee_row.tenant_id = compensation_row.tenant_id
  where (p_tenant_id is null or compensation_row.tenant_id = p_tenant_id)
    and employee_row.employment_status in ('probation', 'active', 'leave')
    and compensation_row.status = 'approved'
    and compensation_row.effective_from <= current_date
    and coalesce(compensation_row.effective_to, 'infinity'::date) >= current_date;

  return jsonb_build_object(
    'employee_count', v_employee_count,
    'covered_count', v_covered_count,
    'coverage_rate', case when v_employee_count = 0 then 0
      else round(v_covered_count::numeric * 100 / v_employee_count, 1) end,
    'scheduled_count', (
      select count(*) from public.hr_employee_compensation compensation_row
      where (p_tenant_id is null or compensation_row.tenant_id = p_tenant_id)
        and compensation_row.status = 'approved'
        and compensation_row.effective_from > current_date
    ),
    'enabled_plan_count', (
      select count(*) from public.hr_compensation_plan plan_row
      where (p_tenant_id is null or plan_row.tenant_id = p_tenant_id)
        and plan_row.enabled
    ),
    'enabled_component_count', (
      select count(*) from public.hr_pay_component component_row
      where (p_tenant_id is null or component_row.tenant_id = p_tenant_id)
        and component_row.enabled
    )
  );
end;
$function$;
create or replace function public.hr_list_compensation_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
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
  v_can_view_amount boolean;
  v_result jsonb;
begin
  if p_kind not in ('employee', 'plan', 'component', 'band') then
    raise exception '不支持的薪酬记录类型';
  end if;
  if not app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:View', null, false
  ) then
    raise exception 'Missing compensation view permission' using errcode = '42501';
  end if;
  v_can_view_amount := app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:Amount:View', null, false
  );
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'component' then
    with filtered as materialized (
      select component_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        (select count(*) from public.hr_compensation_plan_item item_row
          where item_row.component_id = component_row.id) as plan_count
      from public.hr_pay_component component_row
      join public.sys_tenant tenant_row on tenant_row.id = component_row.tenant_id
      where (p_tenant_id is null or component_row.tenant_id = p_tenant_id)
        and (p_status is null or component_row.enabled = (p_status = 'enabled'))
        and (v_keyword is null
          or component_row.component_code ilike '%' || v_keyword || '%'
          or component_row.component_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, category, sort, component_name
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'tenant_code' - 'tenant_name') ||
        jsonb_build_object('tenant', jsonb_build_object(
          'id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name
        )) order by tenant_name, category, sort, component_name
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'amount_access', v_can_view_amount
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'amount_access', v_can_view_amount));
  end if;

  if p_kind = 'plan' then
    with filtered as materialized (
      select plan_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        (select count(*) from public.hr_compensation_plan_item item_row
          where item_row.plan_id = plan_row.id) as component_count,
        (select count(*) from public.hr_employee_compensation compensation_row
          where compensation_row.plan_id = plan_row.id
            and compensation_row.status <> 'cancelled') as employee_count,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', item_row.id,
            'component_id', item_row.component_id,
            'component_code', component_row.component_code,
            'component_name', component_row.component_name,
            'category', component_row.category,
            'amount_type', component_row.amount_type,
            'default_amount', case when v_can_view_amount then to_jsonb(item_row.default_amount) else 'null'::jsonb end,
            'default_rate', case when v_can_view_amount then to_jsonb(item_row.default_rate) else 'null'::jsonb end,
            'required', item_row.required,
            'sort', item_row.sort
          ) order by item_row.sort, component_row.component_name)
          from public.hr_compensation_plan_item item_row
          join public.hr_pay_component component_row on component_row.id = item_row.component_id
          where item_row.plan_id = plan_row.id
        ), '[]'::jsonb) as items
      from public.hr_compensation_plan plan_row
      join public.sys_tenant tenant_row on tenant_row.id = plan_row.tenant_id
      where (p_tenant_id is null or plan_row.tenant_id = p_tenant_id)
        and (p_status is null or plan_row.enabled = (p_status = 'enabled'))
        and (v_keyword is null
          or plan_row.plan_code ilike '%' || v_keyword || '%'
          or plan_row.plan_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, sort, plan_name
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'tenant_code' - 'tenant_name') ||
        jsonb_build_object('tenant', jsonb_build_object(
          'id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name
        )) order by tenant_name, sort, plan_name
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'amount_access', v_can_view_amount
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'amount_access', v_can_view_amount));
  end if;

  if p_kind = 'band' then
    with filtered as materialized (
      select band_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
        grade_row.grade_code, grade_row.grade_name, grade_row.grade_level,
        case
          when band_row.status = 'cancelled' then 'cancelled'
          when band_row.status = 'draft' then 'draft'
          when band_row.effective_from > current_date then 'scheduled'
          when band_row.effective_to is not null and band_row.effective_to < current_date then 'expired'
          else 'active'
        end as lifecycle_status
      from public.hr_salary_band band_row
      join public.hr_grade grade_row
        on grade_row.id = band_row.grade_id and grade_row.tenant_id = band_row.tenant_id
      join public.sys_tenant tenant_row on tenant_row.id = band_row.tenant_id
      where (p_tenant_id is null or band_row.tenant_id = p_tenant_id)
        and (p_status is null or case
          when band_row.status = 'cancelled' then 'cancelled'
          when band_row.status = 'draft' then 'draft'
          when band_row.effective_from > current_date then 'scheduled'
          when band_row.effective_to is not null and band_row.effective_to < current_date then 'expired'
          else 'active' end = p_status)
        and (v_keyword is null
          or grade_row.grade_code ilike '%' || v_keyword || '%'
          or grade_row.grade_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by tenant_name, grade_level, effective_from desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged)
          - 'tenant_code' - 'tenant_name' - 'grade_code' - 'grade_name' - 'grade_level'
          - case when v_can_view_amount then '__keep_amounts__' else 'minimum_amount' end
          - case when v_can_view_amount then '__keep_midpoint__' else 'midpoint_amount' end
          - case when v_can_view_amount then '__keep_maximum__' else 'maximum_amount' end) ||
        jsonb_build_object(
          'tenant', jsonb_build_object('id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name),
          'grade', jsonb_build_object('id', grade_id, 'grade_code', grade_code, 'grade_name', grade_name, 'grade_level', grade_level),
          'minimum_amount', case when v_can_view_amount then to_jsonb(minimum_amount) else to_jsonb('***'::text) end,
          'midpoint_amount', case when v_can_view_amount then to_jsonb(midpoint_amount) else to_jsonb('***'::text) end,
          'maximum_amount', case when v_can_view_amount then to_jsonb(maximum_amount) else to_jsonb('***'::text) end
        ) order by tenant_name, grade_level, effective_from desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'amount_access', v_can_view_amount
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'amount_access', v_can_view_amount));
  end if;

  with filtered as materialized (
    select compensation_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
      employee_row.employee_no, employee_row.employee_name, employee_row.organization_id,
      organization_row.organization_code, organization_row.organization_name,
      plan_row.plan_code, plan_row.plan_name,
      grade_row.grade_code, grade_row.grade_name, grade_row.grade_level,
      case
        when compensation_row.status = 'cancelled' then 'cancelled'
        when compensation_row.status = 'draft' then 'draft'
        when compensation_row.effective_from > current_date then 'scheduled'
        when compensation_row.effective_to is not null and compensation_row.effective_to < current_date then 'expired'
        else 'active'
      end as lifecycle_status,
      active_band.minimum_amount as band_minimum,
      active_band.maximum_amount as band_maximum,
      case
        when active_band.id is null then 'unconfigured'
        when compensation_row.base_amount < active_band.minimum_amount then 'below'
        when compensation_row.base_amount > active_band.maximum_amount then 'above'
        else 'within'
      end as range_status,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', item_row.id,
          'component_id', item_row.component_id,
          'component_code', component_row.component_code,
          'component_name', component_row.component_name,
          'category', component_row.category,
          'amount_type', component_row.amount_type,
          'amount', case when v_can_view_amount then to_jsonb(item_row.amount) else 'null'::jsonb end,
          'rate', case when v_can_view_amount then to_jsonb(item_row.rate) else 'null'::jsonb end,
          'source', item_row.source
        ) order by component_row.sort, component_row.component_name)
        from public.hr_employee_compensation_item item_row
        join public.hr_pay_component component_row on component_row.id = item_row.component_id
        where item_row.compensation_id = compensation_row.id
      ), '[]'::jsonb) as items
    from public.hr_employee_compensation compensation_row
    join public.hr_employee employee_row
      on employee_row.id = compensation_row.employee_id
     and employee_row.tenant_id = compensation_row.tenant_id
    left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
    join public.hr_compensation_plan plan_row
      on plan_row.id = compensation_row.plan_id
     and plan_row.tenant_id = compensation_row.tenant_id
    left join public.hr_grade grade_row
      on grade_row.id = compensation_row.grade_id
     and grade_row.tenant_id = compensation_row.tenant_id
    join public.sys_tenant tenant_row on tenant_row.id = compensation_row.tenant_id
    left join lateral (
      select band_row.* from public.hr_salary_band band_row
      where band_row.tenant_id = compensation_row.tenant_id
        and band_row.grade_id = compensation_row.grade_id
        and band_row.currency_code = compensation_row.currency_code
        and band_row.status = 'approved'
        and band_row.effective_from <= compensation_row.effective_from
        and coalesce(band_row.effective_to, 'infinity'::date) >= compensation_row.effective_from
      order by band_row.effective_from desc limit 1
    ) active_band on true
    where (p_tenant_id is null or compensation_row.tenant_id = p_tenant_id)
      and (p_status is null or case
        when compensation_row.status = 'cancelled' then 'cancelled'
        when compensation_row.status = 'draft' then 'draft'
        when compensation_row.effective_from > current_date then 'scheduled'
        when compensation_row.effective_to is not null and compensation_row.effective_to < current_date then 'expired'
        else 'active' end = p_status)
      and (v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or plan_row.plan_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by tenant_name, effective_from desc, employee_name
    offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged)
        - 'tenant_code' - 'tenant_name' - 'employee_no' - 'employee_name'
        - 'organization_code' - 'organization_name' - 'plan_code' - 'plan_name'
        - 'grade_code' - 'grade_name' - 'grade_level' - 'band_minimum' - 'band_maximum'
        - 'base_amount') ||
      jsonb_build_object(
        'tenant', jsonb_build_object('id', tenant_id, 'tenant_code', tenant_code, 'tenant_name', tenant_name),
        'employee', jsonb_build_object('id', employee_id, 'employee_no', employee_no, 'employee_name', employee_name),
        'organization', case when organization_id is null then null else jsonb_build_object(
          'id', organization_id, 'organization_code', organization_code, 'organization_name', organization_name
        ) end,
        'plan', jsonb_build_object('id', plan_id, 'plan_code', plan_code, 'plan_name', plan_name),
        'grade', case when grade_id is null then null else jsonb_build_object(
          'id', grade_id, 'grade_code', grade_code, 'grade_name', grade_name, 'grade_level', grade_level
        ) end,
        'base_amount', case when v_can_view_amount then to_jsonb(base_amount) else to_jsonb('***'::text) end,
        'band_minimum', case when not v_can_view_amount or band_minimum is null then null else to_jsonb(band_minimum) end,
        'band_maximum', case when not v_can_view_amount or band_maximum is null then null else to_jsonb(band_maximum) end
      ) order by tenant_name, effective_from desc, employee_name
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'amount_access', v_can_view_amount
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0, 'amount_access', v_can_view_amount));
end;
$function$;
create or replace function public.hr_list_compensation_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:View', null, false
  ) then
    raise exception 'Missing compensation view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then return '[]'::jsonb; end if;

  if p_kind = 'employee' then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', employee_row.id,
        'code', employee_row.employee_no,
        'name', employee_row.employee_name,
        'organization_id', employee_row.organization_id,
        'organization_name', organization_row.organization_name,
        'grade_id', assignment_row.grade_id,
        'grade_name', grade_row.grade_name
      ) order by employee_row.employee_name)
      from public.hr_employee employee_row
      left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
      left join lateral (
        select assignment.grade_id
        from public.hr_employee_assignment assignment
        where assignment.employee_id = employee_row.id
          and assignment.tenant_id = employee_row.tenant_id
          and assignment.is_primary
          and assignment.assignment_status = 'active'
          and assignment.effective_start <= current_date
          and coalesce(assignment.effective_end, 'infinity'::date) >= current_date
        order by assignment.effective_start desc limit 1
      ) assignment_row on true
      left join public.hr_grade grade_row on grade_row.id = assignment_row.grade_id
      where employee_row.tenant_id = p_tenant_id
        and employee_row.employment_status in ('probation', 'active', 'leave')
    ), '[]'::jsonb);
  end if;
  if p_kind = 'plan' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'code', plan_code, 'name', plan_name,
      'currency_code', currency_code, 'pay_frequency', pay_frequency
    ) order by sort, plan_name) from public.hr_compensation_plan
      where tenant_id = p_tenant_id and enabled), '[]'::jsonb);
  end if;
  if p_kind = 'component' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'code', component_code, 'name', component_name,
      'category', category, 'amount_type', amount_type
    ) order by category, sort, component_name) from public.hr_pay_component
      where tenant_id = p_tenant_id and enabled), '[]'::jsonb);
  end if;
  if p_kind = 'grade' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', id, 'code', grade_code, 'name', grade_name, 'level', grade_level
    ) order by grade_level, sort, grade_name) from public.hr_grade
      where tenant_id = p_tenant_id and enabled), '[]'::jsonb);
  end if;
  raise exception '不支持的薪酬选项类型';
end;
$function$;
create or replace function public.hr_save_compensation_master_secure(
  p_kind text,
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_tenant_id uuid;
  v_permission text := case when p_id is null
    then 'Hr:Compensation:Policy:Add' else 'Hr:Compensation:Policy:Edit' end;
  v_grade_id uuid;
begin
  if p_kind not in ('component', 'plan', 'band') then
    raise exception '不支持的薪酬主数据类型';
  end if;
  if not app_private.can_execute_business_action('HrCompensation', v_permission, null, false) then
    raise exception 'Missing compensation policy write permission' using errcode = '42501';
  end if;
  v_tenant_id := case when app_private.is_platform_super()
    then coalesce(
      nullif(p_payload->>'tenant_id', '')::uuid,
      case p_kind
        when 'component' then (select tenant_id from public.hr_pay_component where id = p_id)
        when 'plan' then (select tenant_id from public.hr_compensation_plan where id = p_id)
        else (select tenant_id from public.hr_salary_band where id = p_id)
      end
    )
    else app_private.current_user_tenant_id()
  end;
  if v_tenant_id is null then raise exception '请选择所属租户'; end if;

  if p_kind = 'component' then
    insert into public.hr_pay_component(
      id, tenant_id, component_code, component_name, category, amount_type,
      taxable, enabled, sort, description
    ) values (
      v_id, v_tenant_id,
      upper(btrim(p_payload->>'component_code')),
      btrim(p_payload->>'component_name'),
      p_payload->>'category', coalesce(nullif(p_payload->>'amount_type', ''), 'fixed'),
      coalesce((p_payload->>'taxable')::boolean, true),
      coalesce((p_payload->>'enabled')::boolean, true),
      coalesce((p_payload->>'sort')::integer, 0),
      nullif(btrim(p_payload->>'description'), '')
    )
    on conflict (id) do update set
      component_code = excluded.component_code,
      component_name = excluded.component_name,
      category = excluded.category,
      amount_type = excluded.amount_type,
      taxable = excluded.taxable,
      enabled = excluded.enabled,
      sort = excluded.sort,
      description = excluded.description
    where hr_pay_component.tenant_id = v_tenant_id;
    if not found then raise exception '薪酬项目不存在或无权编辑'; end if;
    return v_id;
  end if;

  if p_kind = 'plan' then
    if p_id is not null and exists (
      select 1 from public.hr_employee_compensation
      where plan_id = p_id and status = 'approved'
    ) then
      raise exception '该薪酬方案已有已批准员工薪酬，须复制为新方案后调整';
    end if;
    insert into public.hr_compensation_plan(
      id, tenant_id, plan_code, plan_name, currency_code, pay_frequency,
      enabled, sort, description
    ) values (
      v_id, v_tenant_id,
      upper(btrim(p_payload->>'plan_code')),
      btrim(p_payload->>'plan_name'),
      upper(coalesce(nullif(btrim(p_payload->>'currency_code'), ''), 'CNY')),
      coalesce(nullif(p_payload->>'pay_frequency', ''), 'monthly'),
      coalesce((p_payload->>'enabled')::boolean, true),
      coalesce((p_payload->>'sort')::integer, 0),
      nullif(btrim(p_payload->>'description'), '')
    )
    on conflict (id) do update set
      plan_code = excluded.plan_code,
      plan_name = excluded.plan_name,
      currency_code = excluded.currency_code,
      pay_frequency = excluded.pay_frequency,
      enabled = excluded.enabled,
      sort = excluded.sort,
      description = excluded.description
    where hr_compensation_plan.tenant_id = v_tenant_id;
    if not found then raise exception '薪酬方案不存在或无权编辑'; end if;

    delete from public.hr_compensation_plan_item where plan_id = v_id;
    insert into public.hr_compensation_plan_item(
      tenant_id, plan_id, component_id, default_amount, default_rate, required, sort
    )
    select
      v_tenant_id, v_id, component_row.id,
      nullif(item->>'default_amount', '')::numeric,
      nullif(item->>'default_rate', '')::numeric,
      coalesce((item->>'required')::boolean, false),
      coalesce((item->>'sort')::integer, component_row.sort)
    from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) item
    join public.hr_pay_component component_row
      on component_row.id = nullif(item->>'component_id', '')::uuid
     and component_row.tenant_id = v_tenant_id
     and component_row.enabled;
    if jsonb_array_length(coalesce(p_payload->'items', '[]'::jsonb)) <> (
      select count(*) from public.hr_compensation_plan_item where plan_id = v_id
    ) then
      raise exception '薪酬方案包含无效或重复的薪酬项目';
    end if;
    return v_id;
  end if;

  if not app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:Amount:Edit', null, false
  ) then
    raise exception 'Missing compensation amount edit permission' using errcode = '42501';
  end if;
  v_grade_id := nullif(p_payload->>'grade_id', '')::uuid;
  if not exists (
    select 1 from public.hr_grade
    where id = v_grade_id and tenant_id = v_tenant_id and enabled
  ) then raise exception '所选职级不可用'; end if;
  if p_id is not null and not exists (
    select 1 from public.hr_salary_band
    where id = p_id and tenant_id = v_tenant_id and status = 'draft'
  ) then raise exception '只有草稿薪级范围可以编辑'; end if;

  insert into public.hr_salary_band(
    id, tenant_id, grade_id, currency_code,
    minimum_amount, midpoint_amount, maximum_amount,
    effective_from, effective_to, status, description
  ) values (
    v_id, v_tenant_id, v_grade_id,
    upper(coalesce(nullif(btrim(p_payload->>'currency_code'), ''), 'CNY')),
    (p_payload->>'minimum_amount')::numeric,
    (p_payload->>'midpoint_amount')::numeric,
    (p_payload->>'maximum_amount')::numeric,
    (p_payload->>'effective_from')::date,
    nullif(p_payload->>'effective_to', '')::date,
    'draft', nullif(btrim(p_payload->>'description'), '')
  )
  on conflict (id) do update set
    grade_id = excluded.grade_id,
    currency_code = excluded.currency_code,
    minimum_amount = excluded.minimum_amount,
    midpoint_amount = excluded.midpoint_amount,
    maximum_amount = excluded.maximum_amount,
    effective_from = excluded.effective_from,
    effective_to = excluded.effective_to,
    description = excluded.description
  where hr_salary_band.tenant_id = v_tenant_id
    and hr_salary_band.status = 'draft';
  if not found then raise exception '薪级范围不存在或无权编辑'; end if;
  return v_id;
end;
$function$;
create or replace function public.hr_save_employee_compensation_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_tenant_id uuid;
  v_employee_id uuid := nullif(p_payload->>'employee_id', '')::uuid;
  v_plan_id uuid := nullif(p_payload->>'plan_id', '')::uuid;
  v_grade_id uuid := nullif(p_payload->>'grade_id', '')::uuid;
  v_plan public.hr_compensation_plan%rowtype;
  v_permission text := case when p_id is null
    then 'Hr:Compensation:Record:Add' else 'Hr:Compensation:Record:Edit' end;
begin
  if not app_private.can_execute_business_action('HrCompensation', v_permission, null, false)
    or not app_private.can_execute_business_action(
      'HrCompensation', 'Hr:Compensation:Amount:Edit', null, false
    ) then
    raise exception 'Missing employee compensation edit permission' using errcode = '42501';
  end if;
  v_tenant_id := case when app_private.is_platform_super()
    then coalesce(
      nullif(p_payload->>'tenant_id', '')::uuid,
      (select tenant_id from public.hr_employee_compensation where id = p_id)
    )
    else app_private.current_user_tenant_id()
  end;
  if v_tenant_id is null then raise exception '请选择所属租户'; end if;
  if not exists (
    select 1 from public.hr_employee
    where id = v_employee_id and tenant_id = v_tenant_id
      and employment_status in ('probation', 'active', 'leave')
  ) then raise exception '所选员工不可用'; end if;
  select * into v_plan from public.hr_compensation_plan
  where id = v_plan_id and tenant_id = v_tenant_id and enabled;
  if not found then raise exception '所选薪酬方案不可用'; end if;
  if v_grade_id is null then
    select assignment.grade_id into v_grade_id
    from public.hr_employee_assignment assignment
    where assignment.employee_id = v_employee_id
      and assignment.tenant_id = v_tenant_id
      and assignment.is_primary and assignment.assignment_status = 'active'
      and assignment.effective_start <= (p_payload->>'effective_from')::date
      and coalesce(assignment.effective_end, 'infinity'::date) >= (p_payload->>'effective_from')::date
    order by assignment.effective_start desc limit 1;
  end if;
  if v_grade_id is not null and not exists (
    select 1 from public.hr_grade where id = v_grade_id and tenant_id = v_tenant_id
  ) then raise exception '所选职级无效'; end if;
  if nullif(p_payload->>'source_change_id', '') is not null and not exists (
    select 1 from public.hr_personnel_change
    where id = nullif(p_payload->>'source_change_id', '')::uuid
      and tenant_id = v_tenant_id
  ) then raise exception '关联人事异动无效'; end if;
  if p_id is not null and not exists (
    select 1 from public.hr_employee_compensation
    where id = p_id and tenant_id = v_tenant_id and status = 'draft'
  ) then raise exception '只有草稿员工薪酬可以编辑'; end if;

  insert into public.hr_employee_compensation(
    id, tenant_id, employee_id, plan_id, grade_id, base_amount,
    currency_code, pay_frequency, effective_from, effective_to,
    status, change_reason, source_change_id
  ) values (
    v_id, v_tenant_id, v_employee_id, v_plan_id, v_grade_id,
    (p_payload->>'base_amount')::numeric,
    v_plan.currency_code, v_plan.pay_frequency,
    (p_payload->>'effective_from')::date,
    nullif(p_payload->>'effective_to', '')::date,
    'draft', btrim(p_payload->>'change_reason'),
    nullif(p_payload->>'source_change_id', '')::uuid
  )
  on conflict (id) do update set
    employee_id = excluded.employee_id,
    plan_id = excluded.plan_id,
    grade_id = excluded.grade_id,
    base_amount = excluded.base_amount,
    currency_code = excluded.currency_code,
    pay_frequency = excluded.pay_frequency,
    effective_from = excluded.effective_from,
    effective_to = excluded.effective_to,
    change_reason = excluded.change_reason,
    source_change_id = excluded.source_change_id
  where hr_employee_compensation.tenant_id = v_tenant_id
    and hr_employee_compensation.status = 'draft';
  if not found then raise exception '员工薪酬不存在或无权编辑'; end if;

  delete from public.hr_employee_compensation_item where compensation_id = v_id;
  insert into public.hr_employee_compensation_item(
    tenant_id, compensation_id, component_id, amount, rate, source
  )
  select
    v_tenant_id, v_id, plan_item.component_id,
    coalesce(nullif(payload_item.item->>'amount', '')::numeric, plan_item.default_amount),
    coalesce(nullif(payload_item.item->>'rate', '')::numeric, plan_item.default_rate),
    case when payload_item.item is null then 'plan' else 'override' end
  from public.hr_compensation_plan_item plan_item
  left join lateral (
    select item
    from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) item
    where nullif(item->>'component_id', '')::uuid = plan_item.component_id
    limit 1
  ) payload_item on true
  where plan_item.plan_id = v_plan_id
    and plan_item.tenant_id = v_tenant_id;

  if exists (
    select 1 from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) item
    where not exists (
      select 1 from public.hr_compensation_plan_item plan_item
      where plan_item.plan_id = v_plan_id
        and plan_item.component_id = nullif(item->>'component_id', '')::uuid
    )
  ) then raise exception '员工薪酬包含方案之外的薪酬项目'; end if;
  return v_id;
end;
$function$;
create or replace function public.hr_delete_compensation_record_secure(
  p_kind text,
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'HrCompensation',
    case when p_kind = 'employee' then 'Hr:Compensation:Record:Delete'
      else 'Hr:Compensation:Policy:Delete' end,
    null, false
  ) then raise exception 'Missing compensation delete permission' using errcode = '42501'; end if;

  if p_kind = 'employee' then
    delete from public.hr_employee_compensation
    where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'band' then
    delete from public.hr_salary_band
    where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'plan' then
    if exists (select 1 from public.hr_employee_compensation where plan_id = p_id) then
      raise exception '该薪酬方案已有员工薪酬记录，不能删除';
    end if;
    delete from public.hr_compensation_plan
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'component' then
    if exists (select 1 from public.hr_compensation_plan_item where component_id = p_id) then
      raise exception '该薪酬项目已被方案使用，不能删除';
    end if;
    delete from public.hr_pay_component
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  else
    raise exception '不支持的薪酬记录类型';
  end if;
  if not found then raise exception '仅草稿记录可删除，或记录不存在'; end if;
  return true;
end;
$function$;
create or replace function public.hr_act_compensation_record_secure(
  p_kind text,
  p_id uuid,
  p_action text,
  p_effective_to date default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_band public.hr_salary_band%rowtype;
  v_compensation public.hr_employee_compensation%rowtype;
begin
  if not app_private.can_execute_business_action(
    'HrCompensation', 'Hr:Compensation:Approve', null, false
  ) then raise exception 'Missing compensation approve permission' using errcode = '42501'; end if;

  if p_kind = 'band' then
    select * into v_band from public.hr_salary_band
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    for update;
    if not found then raise exception '薪级范围不存在或无权操作'; end if;
    if p_action = 'approve' then
      if v_band.status <> 'draft' then raise exception '只有草稿薪级范围可以批准'; end if;
      if exists (
        select 1 from public.hr_salary_band band_row
        where band_row.tenant_id = v_band.tenant_id
          and band_row.grade_id = v_band.grade_id
          and band_row.currency_code = v_band.currency_code
          and band_row.status = 'approved'
          and band_row.effective_from >= v_band.effective_from
          and band_row.effective_from <= coalesce(v_band.effective_to, 'infinity'::date)
      ) then raise exception '该职级在生效区间内已有已批准薪级范围'; end if;
      update public.hr_salary_band band_row
      set effective_to = v_band.effective_from - 1
      where band_row.tenant_id = v_band.tenant_id
        and band_row.grade_id = v_band.grade_id
        and band_row.currency_code = v_band.currency_code
        and band_row.status = 'approved'
        and band_row.effective_from < v_band.effective_from
        and coalesce(band_row.effective_to, 'infinity'::date) >= v_band.effective_from;
      update public.hr_salary_band set status = 'approved' where id = p_id;
    elsif p_action = 'cancel' then
      if v_band.status = 'approved' and v_band.effective_from <= current_date then
        raise exception '已生效薪级范围不能取消，请新建后续版本';
      end if;
      if v_band.status = 'cancelled' then raise exception '薪级范围已取消'; end if;
      update public.hr_salary_band set status = 'cancelled' where id = p_id;
    else raise exception '不支持的薪级范围操作'; end if;
    return true;
  end if;

  if p_kind <> 'employee' then raise exception '不支持的薪酬操作类型'; end if;
  select * into v_compensation from public.hr_employee_compensation
  where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '员工薪酬不存在或无权操作'; end if;

  if p_action = 'approve' then
    if v_compensation.status <> 'draft' then raise exception '只有草稿员工薪酬可以批准'; end if;
    if exists (
      select 1 from public.hr_employee_compensation compensation_row
      where compensation_row.tenant_id = v_compensation.tenant_id
        and compensation_row.employee_id = v_compensation.employee_id
        and compensation_row.status = 'approved'
        and compensation_row.effective_from >= v_compensation.effective_from
        and compensation_row.effective_from <= coalesce(v_compensation.effective_to, 'infinity'::date)
    ) then raise exception '该员工在生效区间内已有已批准薪酬'; end if;
    update public.hr_employee_compensation compensation_row
    set effective_to = v_compensation.effective_from - 1
    where compensation_row.tenant_id = v_compensation.tenant_id
      and compensation_row.employee_id = v_compensation.employee_id
      and compensation_row.status = 'approved'
      and compensation_row.effective_from < v_compensation.effective_from
      and coalesce(compensation_row.effective_to, 'infinity'::date) >= v_compensation.effective_from;
    update public.hr_employee_compensation set
      status = 'approved', approved_by = coalesce(auth.uid()::text, 'system'), approved_at = now()
    where id = p_id;
  elsif p_action = 'cancel' then
    if v_compensation.status = 'approved' and v_compensation.effective_from <= current_date then
      raise exception '已生效员工薪酬不能取消，请使用终止或新建调薪记录';
    end if;
    if v_compensation.status = 'cancelled' then raise exception '员工薪酬已取消'; end if;
    update public.hr_employee_compensation set status = 'cancelled' where id = p_id;
  elsif p_action = 'end' then
    if v_compensation.status <> 'approved'
      or v_compensation.effective_from > current_date then
      raise exception '只有已生效员工薪酬可以终止';
    end if;
    if p_effective_to is null or p_effective_to < v_compensation.effective_from then
      raise exception '请选择有效的终止日期';
    end if;
    update public.hr_employee_compensation set effective_to = p_effective_to where id = p_id;
  else raise exception '不支持的员工薪酬操作'; end if;
  return true;
end;
$function$;
create or replace function public.hr_compensation_payroll_inputs_secure(
  p_payroll_month date,
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
  v_month_start date := date_trunc('month', p_payroll_month)::date;
  v_month_end date := (date_trunc('month', p_payroll_month) + interval '1 month - 1 day')::date;
begin
  if not (
    app_private.can_execute_business_action(
      'HrCompensation', 'Hr:Compensation:Amount:View', null, false
    )
    or app_private.can_execute_business_action(
      'FinancePayroll', 'FinancePayroll:Edit', null, false
    )
    or app_private.can_execute_business_action(
      'FinancePayroll', 'FinancePayroll:Calculate', null, false
    )
  ) then raise exception 'Missing payroll input permission' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then raise exception '请选择所属租户'; end if;

  return coalesce((
    with effective_compensation as (
      select distinct on (compensation_row.employee_id)
        compensation_row.*, employee_row.employee_no, employee_row.employee_name,
        organization_row.organization_name, plan_row.plan_code, plan_row.plan_name
      from public.hr_employee_compensation compensation_row
      join public.hr_employee employee_row
        on employee_row.id = compensation_row.employee_id
       and employee_row.tenant_id = compensation_row.tenant_id
      left join public.sys_organization organization_row on organization_row.id = employee_row.organization_id
      join public.hr_compensation_plan plan_row
        on plan_row.id = compensation_row.plan_id
       and plan_row.tenant_id = compensation_row.tenant_id
      where compensation_row.tenant_id = p_tenant_id
        and compensation_row.status = 'approved'
        and compensation_row.effective_from <= v_month_end
        and coalesce(compensation_row.effective_to, 'infinity'::date) >= v_month_start
      order by compensation_row.employee_id, compensation_row.effective_from desc
    )
    select jsonb_agg(jsonb_build_object(
      'compensation_id', compensation_row.id,
      'employee_id', compensation_row.employee_id,
      'employee_no', compensation_row.employee_no,
      'employee_name', compensation_row.employee_name,
      'organization_name', compensation_row.organization_name,
      'plan_code', compensation_row.plan_code,
      'plan_name', compensation_row.plan_name,
      'currency_code', compensation_row.currency_code,
      'pay_frequency', compensation_row.pay_frequency,
      'effective_from', compensation_row.effective_from,
      'effective_to', compensation_row.effective_to,
      'base_amount', compensation_row.base_amount,
      'earning_items', jsonb_build_array(jsonb_build_object(
        'code', 'BASE_SALARY',
        'name', case compensation_row.pay_frequency
          when 'annual' then '月度基本工资'
          when 'hourly' then '基础时薪'
          else '基本工资' end,
        'amount', case compensation_row.pay_frequency
          when 'annual' then round(compensation_row.base_amount / 12, 2)
          else compensation_row.base_amount end,
        'source', 'hr_compensation'
      )) || coalesce((
        select jsonb_agg(jsonb_build_object(
          'code', component_row.component_code,
          'name', component_row.component_name,
          'amount', coalesce(
            item_row.amount,
            round((case compensation_row.pay_frequency
              when 'annual' then compensation_row.base_amount / 12
              else compensation_row.base_amount end) * item_row.rate, 2),
            0
          ),
          'rate', item_row.rate,
          'source', 'hr_compensation'
        ) order by component_row.sort, component_row.component_name)
        from public.hr_employee_compensation_item item_row
        join public.hr_pay_component component_row on component_row.id = item_row.component_id
        where item_row.compensation_id = compensation_row.id
          and component_row.category = 'earning'
      ), '[]'::jsonb),
      'deduction_items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'code', component_row.component_code,
          'name', component_row.component_name,
          'amount', coalesce(
            item_row.amount,
            round((case compensation_row.pay_frequency
              when 'annual' then compensation_row.base_amount / 12
              else compensation_row.base_amount end) * item_row.rate, 2),
            0
          ),
          'rate', item_row.rate,
          'source', 'hr_compensation'
        ) order by component_row.sort, component_row.component_name)
        from public.hr_employee_compensation_item item_row
        join public.hr_pay_component component_row on component_row.id = item_row.component_id
        where item_row.compensation_id = compensation_row.id
          and component_row.category = 'deduction'
      ), '[]'::jsonb),
      'employer_cost_items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'code', component_row.component_code,
          'name', component_row.component_name,
          'amount', coalesce(
            item_row.amount,
            round((case compensation_row.pay_frequency
              when 'annual' then compensation_row.base_amount / 12
              else compensation_row.base_amount end) * item_row.rate, 2),
            0
          ),
          'rate', item_row.rate,
          'source', 'hr_compensation'
        ) order by component_row.sort, component_row.component_name)
        from public.hr_employee_compensation_item item_row
        join public.hr_pay_component component_row on component_row.id = item_row.component_id
        where item_row.compensation_id = compensation_row.id
          and component_row.category = 'employer_cost'
      ), '[]'::jsonb)
    ) order by compensation_row.employee_name)
    from effective_compensation compensation_row
  ), '[]'::jsonb);
end;
$function$;
revoke all on function public.hr_compensation_overview_secure(uuid) from public, anon;
revoke all on function public.hr_list_compensation_records_secure(text, integer, integer, text, text, uuid) from public, anon;
revoke all on function public.hr_list_compensation_options_secure(text, uuid) from public, anon;
revoke all on function public.hr_save_compensation_master_secure(text, uuid, jsonb) from public, anon;
revoke all on function public.hr_save_employee_compensation_secure(uuid, jsonb) from public, anon;
revoke all on function public.hr_delete_compensation_record_secure(text, uuid) from public, anon;
revoke all on function public.hr_act_compensation_record_secure(text, uuid, text, date) from public, anon;
revoke all on function public.hr_compensation_payroll_inputs_secure(date, uuid) from public, anon;
grant execute on function public.hr_compensation_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_compensation_records_secure(text, integer, integer, text, text, uuid) to authenticated, service_role;
grant execute on function public.hr_list_compensation_options_secure(text, uuid) to authenticated, service_role;
grant execute on function public.hr_save_compensation_master_secure(text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.hr_save_employee_compensation_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.hr_delete_compensation_record_secure(text, uuid) to authenticated, service_role;
grant execute on function public.hr_act_compensation_record_secure(text, uuid, text, date) to authenticated, service_role;
grant execute on function public.hr_compensation_payroll_inputs_secure(date, uuid) to authenticated, service_role;
with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_types(name, code, sort) as (
  values
    ('薪酬项目类别', 'hrCompensationComponentCategory', 60),
    ('薪酬计值方式', 'hrCompensationAmountType', 61),
    ('发薪频率', 'hrPayFrequency', 62),
    ('薪酬记录状态', 'hrCompensationLifecycleStatus', 63),
    ('薪档范围状态', 'hrCompensationRangeStatus', 64)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(), seed.name, seed.code, '1',
  '624944977@qq.com', '624944977@qq.com', '企业 HR 薪酬字典',
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', seed.sort
from dictionary_types seed
cross join platform_tenant
on conflict (code) do update set
  name = excluded.name, status = excluded.status, update_by = excluded.update_by,
  update_time = now(), remark = excluded.remark, sort = excluded.sort;
with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_items(type_code, value, label, sort, tag_type) as (
  values
    ('hrCompensationComponentCategory', 'earning', '收入项', 1, 'success'),
    ('hrCompensationComponentCategory', 'deduction', '扣减项', 2, 'danger'),
    ('hrCompensationComponentCategory', 'employer_cost', '企业成本', 3, 'warning'),
    ('hrCompensationAmountType', 'fixed', '固定金额', 1, 'primary'),
    ('hrCompensationAmountType', 'rate', '比例计算', 2, 'warning'),
    ('hrCompensationAmountType', 'variable', '核算期录入', 3, 'info'),
    ('hrPayFrequency', 'monthly', '月薪', 1, 'primary'),
    ('hrPayFrequency', 'annual', '年薪', 2, 'success'),
    ('hrPayFrequency', 'hourly', '时薪', 3, 'warning'),
    ('hrCompensationLifecycleStatus', 'draft', '草稿', 1, 'info'),
    ('hrCompensationLifecycleStatus', 'scheduled', '待生效', 2, 'warning'),
    ('hrCompensationLifecycleStatus', 'active', '生效中', 3, 'success'),
    ('hrCompensationLifecycleStatus', 'expired', '已失效', 4, 'info'),
    ('hrCompensationLifecycleStatus', 'cancelled', '已取消', 5, 'danger'),
    ('hrCompensationRangeStatus', 'within', '档内', 1, 'success'),
    ('hrCompensationRangeStatus', 'below', '低于下限', 2, 'warning'),
    ('hrCompensationRangeStatus', 'above', '高于上限', 3, 'danger'),
    ('hrCompensationRangeStatus', 'unconfigured', '未配置薪档', 4, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select
  gen_random_uuid(), dictionary_type.id,
  seed.type_code || '_' || seed.value, '1',
  '624944977@qq.com', '624944977@qq.com', '企业 HR 薪酬字典项',
  seed.value, seed.label, platform_tenant.id, seed.tag_type, seed.sort
from dictionary_items seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing_item
  where existing_item.type_id = dictionary_type.id and existing_item.value = seed.value
);
do $$ begin
  if not exists (
    select 1 from public.sys_menu where id = 'c0de0000-0000-4000-8000-000000000205'::uuid
  ) then
    update public.sys_menu set sort = sort + 1, update_by = '624944977@qq.com', update_time = now()
    where parent_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
      and type = 'menu' and sort >= 3;
  end if;
end $$;
insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
values (
  'c0de0000-0000-4000-8000-000000000205',
  'c0de0000-0000-4000-8000-000000000200',
  'HrCompensation', 'compensation', '/hr/operations/compensation',
  jsonb_build_object(
    'title', '薪酬管理', 'icon', 'ri:money-cny-circle-line',
    'is_hide', false, 'is_enable', true, 'keep_alive', true,
    'is_iframe', false, 'fixed_tab', false, 'show_badge', false,
    'show_text_badge', '', 'is_hide_tab', false, 'is_full_page', false,
    'active_path', '', 'link', '', 'roles', jsonb_build_array('R_SUPER', 'R_ADMIN')
  ),
  3, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, meta = excluded.meta, sort = excluded.sort,
  type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();
insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select
  seed.id, 'c0de0000-0000-4000-8000-000000000205'::uuid,
  seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()
  ),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8205-000000000001'::uuid, 'Hr:Compensation:View', '查看薪酬管理', 1),
  ('c0de0000-0000-4000-8205-000000000002'::uuid, 'Hr:Compensation:Policy:Add', '新增薪酬政策', 2),
  ('c0de0000-0000-4000-8205-000000000003'::uuid, 'Hr:Compensation:Policy:Edit', '编辑薪酬政策', 3),
  ('c0de0000-0000-4000-8205-000000000004'::uuid, 'Hr:Compensation:Policy:Delete', '删除薪酬政策', 4),
  ('c0de0000-0000-4000-8205-000000000005'::uuid, 'Hr:Compensation:Record:Add', '新增员工薪酬', 5),
  ('c0de0000-0000-4000-8205-000000000006'::uuid, 'Hr:Compensation:Record:Edit', '编辑员工薪酬', 6),
  ('c0de0000-0000-4000-8205-000000000007'::uuid, 'Hr:Compensation:Record:Delete', '删除员工薪酬', 7),
  ('c0de0000-0000-4000-8205-000000000008'::uuid, 'Hr:Compensation:Amount:View', '查看薪酬金额', 8),
  ('c0de0000-0000-4000-8205-000000000009'::uuid, 'Hr:Compensation:Amount:Edit', '编辑薪酬金额', 9),
  ('c0de0000-0000-4000-8205-000000000010'::uuid, 'Hr:Compensation:Approve', '批准与终止薪酬', 10)
) as seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();
insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select
  existing.role_id, new_menu.menu_id, existing.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('c0de0000-0000-4000-8000-000000000205'::uuid),
  ('c0de0000-0000-4000-8205-000000000001'::uuid),
  ('c0de0000-0000-4000-8205-000000000002'::uuid),
  ('c0de0000-0000-4000-8205-000000000003'::uuid),
  ('c0de0000-0000-4000-8205-000000000004'::uuid),
  ('c0de0000-0000-4000-8205-000000000005'::uuid),
  ('c0de0000-0000-4000-8205-000000000006'::uuid),
  ('c0de0000-0000-4000-8205-000000000007'::uuid),
  ('c0de0000-0000-4000-8205-000000000008'::uuid),
  ('c0de0000-0000-4000-8205-000000000009'::uuid),
  ('c0de0000-0000-4000-8205-000000000010'::uuid)
) as new_menu(menu_id)
where existing.menu_id = 'c0de0000-0000-4000-8000-000000000201'::uuid
on conflict (role_id, menu_id) do nothing;
