begin;
create table public.fms_account_set (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_code text not null,
  account_set_name text not null,
  legal_entity_name text not null,
  unified_social_credit_code text,
  accounting_standard text not null default 'enterprise_2019',
  vat_taxpayer_type text not null default 'general',
  base_currency_code text not null default 'CNY',
  enabled_on date not null,
  fiscal_year_start_month smallint not null default 1,
  status text not null default 'draft',
  is_default boolean not null default false,
  remark text,
  version bigint not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_account_set_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint fms_account_set_code_not_blank check (btrim(account_set_code) <> ''),
  constraint fms_account_set_name_not_blank check (btrim(account_set_name) <> ''),
  constraint fms_account_set_legal_entity_not_blank check (btrim(legal_entity_name) <> ''),
  constraint fms_account_set_code_format check (account_set_code ~ '^[A-Z0-9_-]{2,30}$'),
  constraint fms_account_set_currency_format check (base_currency_code ~ '^[A-Z]{3}$'),
  constraint fms_account_set_fiscal_month_check check (fiscal_year_start_month between 1 and 12),
  constraint fms_account_set_standard_check check (
    accounting_standard in (
      'enterprise_2007',
      'enterprise_2019',
      'small_enterprise',
      'non_profit',
      'union',
      'farmer_cooperative_2023',
      'rural_collective_2024'
    )
  ),
  constraint fms_account_set_taxpayer_check check (
    vat_taxpayer_type in ('general', 'small_scale', 'other')
  ),
  constraint fms_account_set_status_check check (
    status in ('draft', 'active', 'suspended', 'archived')
  ),
  constraint fms_account_set_version_check check (version > 0),
  constraint fms_account_set_id_tenant_key unique (id, tenant_id),
  constraint fms_account_set_tenant_code_key unique (tenant_id, account_set_code)
);
create unique index fms_account_set_tenant_default_uidx
  on public.fms_account_set (tenant_id)
  where is_default and status <> 'archived';
create index fms_account_set_tenant_status_idx
  on public.fms_account_set (tenant_id, status, create_time desc);
create table public.fms_accounting_period (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  fiscal_year smallint not null,
  period_no smallint not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'open',
  closed_at timestamptz,
  closed_by text,
  reopened_at timestamptz,
  reopened_by text,
  reopen_reason text,
  reopen_count integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_accounting_period_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_accounting_period_number_check check (period_no between 1 and 12),
  constraint fms_accounting_period_year_check check (fiscal_year between 1900 and 2999),
  constraint fms_accounting_period_dates_check check (start_date <= end_date),
  constraint fms_accounting_period_status_check check (
    status in ('not_opened', 'open', 'closing', 'closed')
  ),
  constraint fms_accounting_period_reopen_count_check check (reopen_count >= 0),
  constraint fms_accounting_period_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_accounting_period_scope_key unique (account_set_id, fiscal_year, period_no),
  constraint fms_accounting_period_date_scope_key unique (account_set_id, start_date, end_date)
);
create index fms_accounting_period_tenant_status_idx
  on public.fms_accounting_period (tenant_id, status, start_date);
create table public.fms_currency (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  currency_code text not null,
  currency_name text not null,
  symbol text,
  decimal_places smallint not null default 2,
  is_base boolean not null default false,
  is_enabled boolean not null default true,
  sort integer not null default 100,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_currency_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_currency_code_format check (currency_code ~ '^[A-Z]{3}$'),
  constraint fms_currency_name_not_blank check (btrim(currency_name) <> ''),
  constraint fms_currency_decimal_places_check check (decimal_places between 0 and 8),
  constraint fms_currency_sort_check check (sort between 0 and 9999),
  constraint fms_currency_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_currency_scope_code_key unique (account_set_id, currency_code)
);
create unique index fms_currency_account_set_base_uidx
  on public.fms_currency (account_set_id)
  where is_base;
create index fms_currency_tenant_enabled_idx
  on public.fms_currency (tenant_id, account_set_id, is_enabled, sort);
create table public.fms_exchange_rate (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  currency_id uuid not null,
  rate_date date not null,
  rate_type text not null default 'spot',
  direct_rate numeric(20, 10) not null,
  source text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_exchange_rate_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_exchange_rate_currency_fkey
    foreign key (currency_id, account_set_id, tenant_id)
    references public.fms_currency(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_exchange_rate_type_check check (rate_type in ('spot', 'average', 'closing')),
  constraint fms_exchange_rate_positive_check check (direct_rate > 0),
  constraint fms_exchange_rate_scope_key unique (account_set_id, currency_id, rate_date, rate_type)
);
create index fms_exchange_rate_lookup_idx
  on public.fms_exchange_rate (tenant_id, account_set_id, currency_id, rate_type, rate_date desc);
create table public.fms_auxiliary_type (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  type_code text not null,
  type_name text not null,
  source_type text not null default 'manual',
  is_system boolean not null default false,
  is_enabled boolean not null default true,
  sort integer not null default 100,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_auxiliary_type_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_auxiliary_type_code_format check (type_code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
  constraint fms_auxiliary_type_name_not_blank check (btrim(type_name) <> ''),
  constraint fms_auxiliary_type_source_check check (
    source_type in ('manual', 'customer', 'carrier', 'department', 'employee', 'project')
  ),
  constraint fms_auxiliary_type_sort_check check (sort between 0 and 9999),
  constraint fms_auxiliary_type_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_auxiliary_type_scope_code_key unique (account_set_id, type_code)
);
create index fms_auxiliary_type_tenant_enabled_idx
  on public.fms_auxiliary_type (tenant_id, account_set_id, is_enabled, sort);
create table public.fms_auxiliary_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  auxiliary_type_id uuid not null,
  item_code text not null,
  item_name text not null,
  external_entity_type text,
  external_entity_id uuid,
  is_enabled boolean not null default true,
  sort integer not null default 100,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_auxiliary_item_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_auxiliary_item_type_fkey
    foreign key (auxiliary_type_id, account_set_id, tenant_id)
    references public.fms_auxiliary_type(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_auxiliary_item_code_not_blank check (btrim(item_code) <> ''),
  constraint fms_auxiliary_item_name_not_blank check (btrim(item_name) <> ''),
  constraint fms_auxiliary_item_external_pair_check check (
    (external_entity_type is null and external_entity_id is null)
    or (external_entity_type is not null and external_entity_id is not null)
  ),
  constraint fms_auxiliary_item_sort_check check (sort between 0 and 9999),
  constraint fms_auxiliary_item_scope_code_key unique (auxiliary_type_id, item_code)
);
create unique index fms_auxiliary_item_external_uidx
  on public.fms_auxiliary_item (auxiliary_type_id, external_entity_type, external_entity_id)
  where external_entity_id is not null;
create index fms_auxiliary_item_lookup_idx
  on public.fms_auxiliary_item (tenant_id, account_set_id, auxiliary_type_id, is_enabled, sort);
create table public.fms_subject (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  parent_id uuid,
  subject_code text not null,
  subject_name text not null,
  category text not null,
  balance_direction text not null,
  level smallint not null default 1,
  is_system boolean not null default false,
  is_enabled boolean not null default true,
  allow_quantity boolean not null default false,
  unit_name text,
  allow_foreign_currency boolean not null default false,
  allow_period_end_revaluation boolean not null default false,
  cash_flow_required boolean not null default false,
  sort integer not null default 100,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_subject_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_subject_code_format check (subject_code ~ '^[0-9]{1,40}$'),
  constraint fms_subject_name_not_blank check (btrim(subject_name) <> ''),
  constraint fms_subject_category_check check (
    category in ('asset', 'liability', 'equity', 'cost', 'income', 'expense', 'memo')
  ),
  constraint fms_subject_direction_check check (balance_direction in ('debit', 'credit')),
  constraint fms_subject_level_check check (level between 1 and 10),
  constraint fms_subject_quantity_unit_check check (
    (allow_quantity and nullif(btrim(unit_name), '') is not null) or not allow_quantity
  ),
  constraint fms_subject_revaluation_check check (
    not allow_period_end_revaluation
    or (allow_foreign_currency and category in ('asset', 'liability'))
  ),
  constraint fms_subject_sort_check check (sort between 0 and 9999),
  constraint fms_subject_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_subject_scope_code_key unique (account_set_id, subject_code),
  constraint fms_subject_parent_fkey
    foreign key (parent_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict
);
create index fms_subject_tree_idx
  on public.fms_subject (tenant_id, account_set_id, parent_id, sort, subject_code);
create index fms_subject_enabled_category_idx
  on public.fms_subject (tenant_id, account_set_id, is_enabled, category, subject_code);
create table public.fms_subject_auxiliary_type (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  subject_id uuid not null,
  auxiliary_type_id uuid not null,
  is_required boolean not null default true,
  sort integer not null default 100,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_subject_auxiliary_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_subject_auxiliary_subject_fkey
    foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_subject_auxiliary_type_fkey
    foreign key (auxiliary_type_id, account_set_id, tenant_id)
    references public.fms_auxiliary_type(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_subject_auxiliary_sort_check check (sort between 0 and 9999),
  constraint fms_subject_auxiliary_scope_key unique (subject_id, auxiliary_type_id)
);
create index fms_subject_auxiliary_type_idx
  on public.fms_subject_auxiliary_type (tenant_id, account_set_id, auxiliary_type_id, subject_id);
create table public.fms_opening_balance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  fiscal_year smallint not null,
  subject_id uuid not null,
  currency_id uuid,
  auxiliary_values jsonb not null default '{}'::jsonb,
  opening_debit numeric(20, 2) not null default 0,
  opening_credit numeric(20, 2) not null default 0,
  year_to_date_debit numeric(20, 2) not null default 0,
  year_to_date_credit numeric(20, 2) not null default 0,
  opening_quantity numeric(20, 6) not null default 0,
  original_currency_amount numeric(20, 2) not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_opening_balance_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_opening_balance_subject_fkey
    foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_opening_balance_currency_fkey
    foreign key (currency_id, account_set_id, tenant_id)
    references public.fms_currency(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_opening_balance_year_check check (fiscal_year between 1900 and 2999),
  constraint fms_opening_balance_debit_credit_check check (
    opening_debit >= 0 and opening_credit >= 0
    and year_to_date_debit >= 0 and year_to_date_credit >= 0
  ),
  constraint fms_opening_balance_single_direction_check check (
    opening_debit = 0 or opening_credit = 0
  ),
  constraint fms_opening_balance_auxiliary_object_check check (
    jsonb_typeof(auxiliary_values) = 'object'
  )
);
create unique index fms_opening_balance_dimension_uidx
  on public.fms_opening_balance (
    account_set_id,
    fiscal_year,
    subject_id,
    currency_id,
    auxiliary_values
  ) nulls not distinct;
create index fms_opening_balance_lookup_idx
  on public.fms_opening_balance (tenant_id, account_set_id, fiscal_year, subject_id);
create or replace function public.trg_validate_fms_subject_hierarchy()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_parent public.fms_subject%rowtype;
  v_cycle_found boolean := false;
begin
  new.subject_code := btrim(new.subject_code);
  new.subject_name := btrim(new.subject_name);

  if new.parent_id is null then
    new.level := 1;
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception using errcode = '23514', message = '上级科目不能选择当前科目';
  end if;

  select * into v_parent
  from public.fms_subject
  where id = new.parent_id
    and account_set_id = new.account_set_id
    and tenant_id = new.tenant_id;

  if not found then
    raise exception using errcode = '23503', message = '上级科目不存在或不属于当前账套';
  end if;

  if new.subject_code !~ ('^' || v_parent.subject_code || '[0-9]+$') then
    raise exception using errcode = '23514', message = '下级科目编码必须以上级科目编码开头';
  end if;

  if new.category <> v_parent.category or new.balance_direction <> v_parent.balance_direction then
    raise exception using errcode = '23514', message = '下级科目的类别和余额方向必须与上级一致';
  end if;

  new.level := v_parent.level + 1;
  if new.level > 10 then
    raise exception using errcode = '23514', message = '会计科目最多支持十级';
  end if;

  if tg_op = 'UPDATE'
     and (new.parent_id is distinct from old.parent_id or new.subject_code <> old.subject_code)
     and exists (select 1 from public.fms_subject child where child.parent_id = new.id) then
    raise exception using errcode = '23514', message = '存在下级科目时不能变更上级或科目编码';
  end if;

  if tg_op = 'UPDATE' and new.parent_id is distinct from old.parent_id then
    with recursive descendants as (
      select s.id from public.fms_subject s where s.parent_id = new.id
      union all
      select s.id from public.fms_subject s join descendants d on s.parent_id = d.id
    )
    select exists(select 1 from descendants where id = new.parent_id) into v_cycle_found;
    if v_cycle_found then
      raise exception using errcode = '23514', message = '科目层级不能形成循环';
    end if;
  end if;

  return new;
end;
$$;
create trigger fms_subject_validate_hierarchy
before insert or update of parent_id, subject_code, subject_name, category, balance_direction,
  account_set_id, tenant_id
on public.fms_subject
for each row execute function public.trg_validate_fms_subject_hierarchy();
create or replace function public.save_fms_account_set(p_payload jsonb)
returns public.fms_account_set
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_tenant_id uuid := nullif(p_payload ->> 'tenantId', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_enabled_on date := nullif(p_payload ->> 'enabledOn', '')::date;
  v_fiscal_year_start_month smallint := coalesce(nullif(p_payload ->> 'fiscalYearStartMonth', '')::smallint, 1);
  v_base_currency_code text := upper(coalesce(nullif(btrim(p_payload ->> 'baseCurrencyCode'), ''), 'CNY'));
  v_period_start date;
  v_period_end date;
  v_fiscal_year smallint;
  v_period_no integer;
  v_is_default boolean := coalesce((p_payload ->> 'isDefault')::boolean, false);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护账套';
  end if;

  if v_enabled_on is null then
    raise exception using errcode = '23502', message = '启用日期不能为空';
  end if;

  if v_fiscal_year_start_month not between 1 and 12 then
    raise exception using errcode = '23514', message = '会计年度起始月份必须为 1 到 12';
  end if;

  if v_tenant_id is null then
    raise exception using errcode = '23502', message = '请选择账套所属租户';
  end if;

  if not exists(select 1 from public.sys_tenant where id = v_tenant_id and status = '1') then
    raise exception using errcode = '23503', message = '所选租户不存在或已停用';
  end if;

  if v_id is null then
    if not exists(select 1 from public.fms_account_set where tenant_id = v_tenant_id) then
      v_is_default := true;
    end if;

    if v_is_default then
      update public.fms_account_set
      set is_default = false
      where tenant_id = v_tenant_id and is_default;
    end if;

    insert into public.fms_account_set (
      tenant_id,
      account_set_code,
      account_set_name,
      legal_entity_name,
      unified_social_credit_code,
      accounting_standard,
      vat_taxpayer_type,
      base_currency_code,
      enabled_on,
      fiscal_year_start_month,
      status,
      is_default,
      remark
    ) values (
      v_tenant_id,
      upper(btrim(p_payload ->> 'accountSetCode')),
      btrim(p_payload ->> 'accountSetName'),
      btrim(p_payload ->> 'legalEntityName'),
      nullif(btrim(p_payload ->> 'unifiedSocialCreditCode'), ''),
      coalesce(nullif(p_payload ->> 'accountingStandard', ''), 'enterprise_2019'),
      coalesce(nullif(p_payload ->> 'vatTaxpayerType', ''), 'general'),
      v_base_currency_code,
      v_enabled_on,
      v_fiscal_year_start_month,
      coalesce(nullif(p_payload ->> 'status', ''), 'draft'),
      v_is_default,
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_account_set;

    insert into public.fms_currency (
      tenant_id, account_set_id, currency_code, currency_name, symbol, decimal_places, is_base, sort
    ) values (
      v_tenant_id,
      v_account_set.id,
      v_base_currency_code,
      case v_base_currency_code when 'CNY' then '人民币' else v_base_currency_code end,
      case v_base_currency_code when 'CNY' then '¥' else null end,
      2,
      true,
      1
    );

    insert into public.fms_auxiliary_type (
      tenant_id, account_set_id, type_code, type_name, source_type, is_system, sort
    ) values
      (v_tenant_id, v_account_set.id, 'CUSTOMER', '客户', 'customer', true, 10),
      (v_tenant_id, v_account_set.id, 'CARRIER', '承运商', 'carrier', true, 20),
      (v_tenant_id, v_account_set.id, 'DEPARTMENT', '部门', 'department', true, 30),
      (v_tenant_id, v_account_set.id, 'EMPLOYEE', '员工', 'employee', true, 40),
      (v_tenant_id, v_account_set.id, 'PROJECT', '项目', 'project', true, 50);

    v_fiscal_year := case
      when extract(month from v_enabled_on)::int < v_fiscal_year_start_month
        then extract(year from v_enabled_on)::int - 1
      else extract(year from v_enabled_on)::int
    end;

    for v_period_no in 1..12 loop
      v_period_start := (
        make_date(v_fiscal_year, v_fiscal_year_start_month, 1)
        + make_interval(months => v_period_no - 1)
      )::date;
      v_period_end := (v_period_start + interval '1 month - 1 day')::date;

      insert into public.fms_accounting_period (
        tenant_id,
        account_set_id,
        fiscal_year,
        period_no,
        start_date,
        end_date,
        status
      ) values (
        v_tenant_id,
        v_account_set.id,
        v_fiscal_year,
        v_period_no,
        v_period_start,
        v_period_end,
        case when v_period_end < v_enabled_on then 'not_opened' else 'open' end
      );
    end loop;
  else
    select * into v_account_set from public.fms_account_set where id = v_id for update;
    if not found then
      raise exception using errcode = 'P0002', message = '账套不存在或已被删除';
    end if;
    if v_account_set.tenant_id <> v_tenant_id then
      raise exception using errcode = '23514', message = '账套所属租户不可变更';
    end if;
    if v_account_set.base_currency_code <> v_base_currency_code
       and exists (
         select 1 from public.fms_opening_balance where account_set_id = v_account_set.id
       ) then
      raise exception using errcode = '23514', message = '账套已有期初余额，不能变更本位币';
    end if;

    if v_is_default then
      update public.fms_account_set
      set is_default = false
      where tenant_id = v_tenant_id and id <> v_id and is_default;
    end if;

    update public.fms_account_set set
      account_set_code = upper(btrim(p_payload ->> 'accountSetCode')),
      account_set_name = btrim(p_payload ->> 'accountSetName'),
      legal_entity_name = btrim(p_payload ->> 'legalEntityName'),
      unified_social_credit_code = nullif(btrim(p_payload ->> 'unifiedSocialCreditCode'), ''),
      accounting_standard = coalesce(nullif(p_payload ->> 'accountingStandard', ''), accounting_standard),
      vat_taxpayer_type = coalesce(nullif(p_payload ->> 'vatTaxpayerType', ''), vat_taxpayer_type),
      base_currency_code = v_base_currency_code,
      is_default = v_is_default,
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      version = version + 1
    where id = v_id
    returning * into v_account_set;

    update public.fms_currency set
      currency_code = v_base_currency_code,
      currency_name = case v_base_currency_code when 'CNY' then '人民币' else v_base_currency_code end,
      symbol = case v_base_currency_code when 'CNY' then '¥' else symbol end
    where account_set_id = v_account_set.id and is_base;
  end if;

  if v_account_set.is_default then
    update public.fms_account_set
    set is_default = false
    where tenant_id = v_account_set.tenant_id
      and id <> v_account_set.id
      and is_default;
  end if;

  return v_account_set;
end;
$$;
create or replace function public.set_fms_account_set_status(
  p_account_set_id uuid,
  p_status text,
  p_reason text default null
)
returns public.fms_account_set
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.fms_account_set%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可变更账套状态';
  end if;

  select * into v_row from public.fms_account_set where id = p_account_set_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在或已被删除';
  end if;

  if not (
    (v_row.status = 'draft' and p_status in ('active', 'archived'))
    or (v_row.status = 'active' and p_status in ('suspended', 'archived'))
    or (v_row.status = 'suspended' and p_status in ('active', 'archived'))
  ) then
    raise exception using errcode = '23514', message = '当前账套状态不允许执行该变更';
  end if;

  if p_status in ('suspended', 'archived') and nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '23502', message = '停用或归档账套必须填写原因';
  end if;

  update public.fms_account_set set
    status = p_status,
    remark = case
      when nullif(btrim(p_reason), '') is null then remark
      else concat_ws(E'\n', nullif(remark, ''), concat('[状态变更] ', btrim(p_reason)))
    end,
    is_default = case when p_status = 'archived' then false else is_default end,
    version = version + 1
  where id = p_account_set_id
  returning * into v_row;

  return v_row;
end;
$$;
create or replace function public.set_fms_accounting_period_status(
  p_period_id uuid,
  p_status text,
  p_reason text default null
)
returns public.fms_accounting_period
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_period public.fms_accounting_period%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可变更会计期间';
  end if;

  select * into v_period from public.fms_accounting_period where id = p_period_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = '会计期间不存在';
  end if;

  if p_status = 'open' and v_period.status = 'not_opened' then
    null;
  elsif p_status = 'closing' and v_period.status = 'open' then
    null;
  elsif p_status = 'closed' and v_period.status = 'closing' then
    if exists (
      select 1
      from public.fms_accounting_period earlier
      where earlier.account_set_id = v_period.account_set_id
        and earlier.start_date < v_period.start_date
        and earlier.status not in ('not_opened', 'closed')
    ) then
      raise exception using errcode = '23514', message = '请先关闭当前期间之前的所有会计期间';
    end if;
  elsif p_status = 'open' and v_period.status = 'closing' then
    null;
  elsif p_status = 'open' and v_period.status = 'closed' then
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = '23502', message = '反结账必须填写原因';
    end if;
    if exists (
      select 1
      from public.fms_accounting_period later
      where later.account_set_id = v_period.account_set_id
        and later.start_date > v_period.start_date
        and later.status = 'closed'
    ) then
      raise exception using errcode = '23514', message = '请先反结账后续期间';
    end if;
  else
    raise exception using errcode = '23514', message = '当前期间状态不允许执行该变更';
  end if;

  update public.fms_accounting_period set
    status = p_status,
    closed_at = case when p_status = 'closed' then now() else closed_at end,
    closed_by = case
      when p_status = 'closed' then coalesce(auth.jwt() ->> 'email', 'unknown')
      else closed_by
    end,
    reopened_at = case when v_period.status = 'closed' and p_status = 'open' then now() else reopened_at end,
    reopened_by = case
      when v_period.status = 'closed' and p_status = 'open'
        then coalesce(auth.jwt() ->> 'email', 'unknown')
      else reopened_by
    end,
    reopen_reason = case
      when v_period.status = 'closed' and p_status = 'open' then btrim(p_reason)
      else reopen_reason
    end,
    reopen_count = case
      when v_period.status = 'closed' and p_status = 'open' then reopen_count + 1
      else reopen_count
    end
  where id = p_period_id
  returning * into v_period;

  return v_period;
end;
$$;
create or replace function public.fms_accounting_foundation_summary(p_account_set_id uuid)
returns table (
  account_set_id uuid,
  subject_count bigint,
  enabled_subject_count bigint,
  currency_count bigint,
  auxiliary_type_count bigint,
  open_period_count bigint,
  closed_period_count bigint,
  opening_balance_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    a.id,
    (select count(*) from public.fms_subject s where s.account_set_id = a.id),
    (select count(*) from public.fms_subject s where s.account_set_id = a.id and s.is_enabled),
    (select count(*) from public.fms_currency c where c.account_set_id = a.id and c.is_enabled),
    (select count(*) from public.fms_auxiliary_type t where t.account_set_id = a.id and t.is_enabled),
    (select count(*) from public.fms_accounting_period p where p.account_set_id = a.id and p.status = 'open'),
    (select count(*) from public.fms_accounting_period p where p.account_set_id = a.id and p.status = 'closed'),
    (select count(*) from public.fms_opening_balance b where b.account_set_id = a.id)
  from public.fms_account_set a
  where a.id = p_account_set_id
$$;
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fms_account_set',
    'fms_accounting_period',
    'fms_currency',
    'fms_exchange_rate',
    'fms_auxiliary_type',
    'fms_auxiliary_item',
    'fms_subject',
    'fms_subject_auxiliary_type',
    'fms_opening_balance'
  ] loop
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table || '_create_audit',
      v_table
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.trg_set_update_time_and_by()',
      v_table || '_update_audit',
      v_table
    );
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
      v_table || '_tenant_select',
      v_table
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select app_private.is_platform_super()))',
      v_table || '_platform_insert',
      v_table
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()))',
      v_table || '_platform_update',
      v_table
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select app_private.is_platform_super()))',
      v_table || '_platform_delete',
      v_table
    );
    execute format('grant select, insert, update, delete on public.%I to authenticated', v_table);
    execute format('grant all on public.%I to service_role', v_table);
  end loop;
end;
$$;
revoke execute on function public.save_fms_account_set(jsonb) from public, anon;
revoke execute on function public.set_fms_account_set_status(uuid, text, text) from public, anon;
revoke execute on function public.set_fms_accounting_period_status(uuid, text, text) from public, anon;
revoke execute on function public.fms_accounting_foundation_summary(uuid) from public, anon;
grant execute on function public.save_fms_account_set(jsonb) to authenticated, service_role;
grant execute on function public.set_fms_account_set_status(uuid, text, text) to authenticated, service_role;
grant execute on function public.set_fms_accounting_period_status(uuid, text, text) to authenticated, service_role;
grant execute on function public.fms_accounting_foundation_summary(uuid) to authenticated, service_role;
with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select values_row.id, values_row.name, values_row.code, '1', '624944977@qq.com',
  '624944977@qq.com', platform_tenant.id, 'dictionary', values_row.sort, values_row.remark
from platform_tenant
cross join (values
  ('b2000000-0000-4000-8000-000000000001'::uuid, '账套状态', 'fmsAccountSetStatus', 201, '企业财务账套生命周期'),
  ('b2000000-0000-4000-8000-000000000002'::uuid, '会计准则', 'fmsAccountingStandard', 202, '账套采用的会计准则'),
  ('b2000000-0000-4000-8000-000000000003'::uuid, '纳税人类型', 'fmsVatTaxpayerType', 203, '增值税纳税人分类'),
  ('b2000000-0000-4000-8000-000000000004'::uuid, '会计期间状态', 'fmsAccountingPeriodStatus', 204, '会计期间生命周期')
) as values_row(id, name, code, sort, remark)
on conflict (id) do update set
  name = excluded.name,
  code = excluded.code,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark;
with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000001'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'draft', '草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000002'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'active', '启用', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000003'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'suspended', '已停用', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000004'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid, 'archived', '已归档', 4, 'danger'),
    ('c2000000-0000-4000-8000-000000000011'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'enterprise_2007', '企业会计准则（2007）', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000012'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'enterprise_2019', '企业会计准则（2019）', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000013'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'small_enterprise', '小企业会计准则', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000014'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'non_profit', '民间非营利组织会计制度', 4, 'info'),
    ('c2000000-0000-4000-8000-000000000015'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'union', '工会会计制度', 5, 'info'),
    ('c2000000-0000-4000-8000-000000000016'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'farmer_cooperative_2023', '农民专业合作社会计制度（2023）', 6, 'info'),
    ('c2000000-0000-4000-8000-000000000017'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid, 'rural_collective_2024', '农村集体经济组织会计制度', 7, 'info'),
    ('c2000000-0000-4000-8000-000000000021'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid, 'general', '一般纳税人', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000022'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid, 'small_scale', '小规模纳税人', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000023'::uuid, 'b2000000-0000-4000-8000-000000000003'::uuid, 'other', '其他', 3, 'info'),
    ('c2000000-0000-4000-8000-000000000031'::uuid, 'b2000000-0000-4000-8000-000000000004'::uuid, 'not_opened', '未启用', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000032'::uuid, 'b2000000-0000-4000-8000-000000000004'::uuid, 'open', '已开启', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000033'::uuid, 'b2000000-0000-4000-8000-000000000004'::uuid, 'closing', '结账中', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000034'::uuid, 'b2000000-0000-4000-8000-000000000004'::uuid, 'closed', '已结账', 4, 'primary')
  ) as x(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, create_by, update_by, value, label, sort, tag_type, tenant_id
)
select d.id, d.type_id, d.value, '1', '624944977@qq.com', '624944977@qq.com',
  d.value, d.label, d.sort, d.tag_type, platform_tenant.id
from dictionary_items d
cross join platform_tenant
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  value = excluded.value,
  label = excluded.label,
  sort = excluded.sort,
  tag_type = excluded.tag_type;
insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values (
  'a1000000-0000-4000-8000-000000000012'::uuid,
  'a1000000-0000-4000-8000-000000000001'::uuid,
  'FinanceAccountSet',
  'account-set',
  '/fms/account-set',
  'menu',
  13,
  jsonb_build_object(
    'icon', 'ri:book-2-line',
    'title', '账套管理',
    'is_enable', true,
    'keep_alive', true
  ),
  '624944977@qq.com',
  '624944977@qq.com'
)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();
insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select rm.role_id,
  'a1000000-0000-4000-8000-000000000012'::uuid,
  rm.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu rm
where rm.menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
on conflict (role_id, menu_id) do nothing;
commit;
