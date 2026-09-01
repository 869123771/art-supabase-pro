begin;
drop index if exists public.fms_opening_balance_dimension_uidx;
create unique index fms_opening_balance_dimension_uidx
  on public.fms_opening_balance (
    account_set_id,
    fiscal_year,
    subject_id,
    currency_id,
    (md5(auxiliary_values::text))
  ) nulls not distinct;
create table public.fms_opening_balance_control (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  fiscal_year smallint not null,
  status text not null default 'draft',
  confirmed_at timestamptz,
  confirmed_by text,
  reopened_at timestamptz,
  reopened_by text,
  reopen_reason text,
  reopen_count integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_opening_balance_control_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_opening_balance_control_status_check
    check (status in ('draft', 'confirmed')),
  constraint fms_opening_balance_control_year_check
    check (fiscal_year between 1900 and 2999),
  constraint fms_opening_balance_control_reopen_count_check
    check (reopen_count >= 0),
  constraint fms_opening_balance_control_scope_key
    unique (account_set_id, fiscal_year)
);
create index fms_opening_balance_control_tenant_status_idx
  on public.fms_opening_balance_control (tenant_id, status, fiscal_year);
create trigger fms_opening_balance_control_create_audit
before insert on public.fms_opening_balance_control
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger fms_opening_balance_control_update_audit
before update on public.fms_opening_balance_control
for each row execute function public.trg_set_update_time_and_by();
alter table public.fms_opening_balance_control enable row level security;
create policy fms_opening_balance_control_tenant_select
on public.fms_opening_balance_control for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_opening_balance_control_platform_insert
on public.fms_opening_balance_control for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy fms_opening_balance_control_platform_update
on public.fms_opening_balance_control for update to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));
create policy fms_opening_balance_control_platform_delete
on public.fms_opening_balance_control for delete to authenticated
using ((select app_private.is_platform_super()));
grant select, insert, update, delete on public.fms_opening_balance_control to authenticated;
grant all on public.fms_opening_balance_control to service_role;
create or replace function public.save_fms_subject(p_payload jsonb)
returns public.fms_subject
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_subject public.fms_subject%rowtype;
  v_subject_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := (p_payload ->> 'accountSetId')::uuid;
  v_tenant_id uuid := (p_payload ->> 'tenantId')::uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护会计科目';
  end if;

  if v_subject_id is null then
    insert into public.fms_subject (
      tenant_id, account_set_id, parent_id, subject_code, subject_name,
      category, balance_direction, is_enabled, allow_quantity, unit_name,
      allow_foreign_currency, allow_period_end_revaluation, cash_flow_required,
      sort, remark
    ) values (
      v_tenant_id,
      v_account_set_id,
      nullif(p_payload ->> 'parentId', '')::uuid,
      btrim(p_payload ->> 'subjectCode'),
      btrim(p_payload ->> 'subjectName'),
      p_payload ->> 'category',
      p_payload ->> 'balanceDirection',
      coalesce((p_payload ->> 'isEnabled')::boolean, true),
      coalesce((p_payload ->> 'allowQuantity')::boolean, false),
      nullif(btrim(p_payload ->> 'unitName'), ''),
      coalesce((p_payload ->> 'allowForeignCurrency')::boolean, false),
      coalesce((p_payload ->> 'allowPeriodEndRevaluation')::boolean, false),
      coalesce((p_payload ->> 'cashFlowRequired')::boolean, false),
      coalesce((p_payload ->> 'sort')::integer, 100),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_subject;
  else
    update public.fms_subject set
      parent_id = nullif(p_payload ->> 'parentId', '')::uuid,
      subject_code = btrim(p_payload ->> 'subjectCode'),
      subject_name = btrim(p_payload ->> 'subjectName'),
      category = p_payload ->> 'category',
      balance_direction = p_payload ->> 'balanceDirection',
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, is_enabled),
      allow_quantity = coalesce((p_payload ->> 'allowQuantity')::boolean, false),
      unit_name = nullif(btrim(p_payload ->> 'unitName'), ''),
      allow_foreign_currency = coalesce((p_payload ->> 'allowForeignCurrency')::boolean, false),
      allow_period_end_revaluation = coalesce((p_payload ->> 'allowPeriodEndRevaluation')::boolean, false),
      cash_flow_required = coalesce((p_payload ->> 'cashFlowRequired')::boolean, false),
      sort = coalesce((p_payload ->> 'sort')::integer, 100),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = v_subject_id
      and account_set_id = v_account_set_id
      and tenant_id = v_tenant_id
    returning * into v_subject;

    if not found then
      raise exception using errcode = 'P0002', message = '会计科目不存在或不属于当前账套';
    end if;
  end if;

  if p_payload ? 'auxiliaryConfigs' then
    if exists (
      select 1 from public.fms_opening_balance b where b.subject_id = v_subject.id
    ) and (
      exists (
        select current_config.auxiliary_type_id, current_config.is_required
        from public.fms_subject_auxiliary_type current_config
        where current_config.subject_id = v_subject.id
        except
        select desired.auxiliary_type_id, desired.is_required
        from jsonb_to_recordset(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb))
          as desired(auxiliary_type_id uuid, is_required boolean, sort integer)
      )
      or exists (
        select desired.auxiliary_type_id, desired.is_required
        from jsonb_to_recordset(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb))
          as desired(auxiliary_type_id uuid, is_required boolean, sort integer)
        except
        select current_config.auxiliary_type_id, current_config.is_required
        from public.fms_subject_auxiliary_type current_config
        where current_config.subject_id = v_subject.id
      )
    ) then
      raise exception using errcode = '23514', message = '科目已有期初余额，不能变更辅助核算配置';
    end if;

    delete from public.fms_subject_auxiliary_type where subject_id = v_subject.id;

    insert into public.fms_subject_auxiliary_type (
      tenant_id, account_set_id, subject_id, auxiliary_type_id, is_required, sort
    )
    select
      v_subject.tenant_id,
      v_subject.account_set_id,
      v_subject.id,
      config.auxiliary_type_id,
      coalesce(config.is_required, true),
      coalesce(config.sort, 100)
    from jsonb_to_recordset(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb))
      as config(auxiliary_type_id uuid, is_required boolean, sort integer);
  end if;

  return v_subject;
end;
$$;
create or replace function public.sync_fms_auxiliary_items(
  p_account_set_id uuid,
  p_auxiliary_type_id uuid
)
returns table (inserted_count integer, updated_count integer, total_count integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_account_set public.fms_account_set%rowtype;
  v_type public.fms_auxiliary_type%rowtype;
  v_before integer;
  v_source_count integer := 0;
  v_after integer;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可同步辅助核算项目';
  end if;

  select * into v_account_set from public.fms_account_set where id = p_account_set_id;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在';
  end if;

  select * into v_type
  from public.fms_auxiliary_type
  where id = p_auxiliary_type_id and account_set_id = p_account_set_id;
  if not found then
    raise exception using errcode = 'P0002', message = '辅助核算类型不存在';
  end if;

  if v_type.source_type in ('manual', 'project') then
    raise exception using errcode = '23514', message = '当前辅助核算类型使用手工维护，无需同步';
  end if;

  select count(*) into v_before
  from public.fms_auxiliary_item
  where auxiliary_type_id = v_type.id and external_entity_id is not null;

  if v_type.source_type = 'customer' then
    select count(*) into v_source_count from public.tms_customer where tenant_id = v_account_set.tenant_id;
    insert into public.fms_auxiliary_item (
      tenant_id, account_set_id, auxiliary_type_id, item_code, item_name,
      external_entity_type, external_entity_id, is_enabled
    )
    select v_account_set.tenant_id, v_account_set.id, v_type.id,
      coalesce(nullif(btrim(c.customer_code), ''), left(c.id::text, 12)),
      c.customer_name, 'tms_customer', c.id, c.enabled
    from public.tms_customer c
    where c.tenant_id = v_account_set.tenant_id
    on conflict (auxiliary_type_id, external_entity_type, external_entity_id)
      where external_entity_id is not null
    do update set item_code = excluded.item_code, item_name = excluded.item_name,
      is_enabled = excluded.is_enabled, update_time = now();
  elsif v_type.source_type = 'carrier' then
    select count(*) into v_source_count from public.tms_carrier where tenant_id = v_account_set.tenant_id;
    insert into public.fms_auxiliary_item (
      tenant_id, account_set_id, auxiliary_type_id, item_code, item_name,
      external_entity_type, external_entity_id, is_enabled
    )
    select v_account_set.tenant_id, v_account_set.id, v_type.id,
      coalesce(nullif(btrim(c.carrier_code), ''), left(c.id::text, 12)),
      c.company_name, 'tms_carrier', c.id, c.enabled
    from public.tms_carrier c
    where c.tenant_id = v_account_set.tenant_id
    on conflict (auxiliary_type_id, external_entity_type, external_entity_id)
      where external_entity_id is not null
    do update set item_code = excluded.item_code, item_name = excluded.item_name,
      is_enabled = excluded.is_enabled, update_time = now();
  elsif v_type.source_type = 'department' then
    select count(*) into v_source_count from public.sys_organization where tenant_id = v_account_set.tenant_id;
    insert into public.fms_auxiliary_item (
      tenant_id, account_set_id, auxiliary_type_id, item_code, item_name,
      external_entity_type, external_entity_id, is_enabled
    )
    select v_account_set.tenant_id, v_account_set.id, v_type.id,
      coalesce(nullif(btrim(o.organization_code), ''), left(o.id::text, 12)),
      o.organization_name, 'sys_organization', o.id, o.status = '1'
    from public.sys_organization o
    where o.tenant_id = v_account_set.tenant_id
    on conflict (auxiliary_type_id, external_entity_type, external_entity_id)
      where external_entity_id is not null
    do update set item_code = excluded.item_code, item_name = excluded.item_name,
      is_enabled = excluded.is_enabled, update_time = now();
  elsif v_type.source_type = 'employee' then
    select count(*) into v_source_count from public.hr_employee where tenant_id = v_account_set.tenant_id;
    insert into public.fms_auxiliary_item (
      tenant_id, account_set_id, auxiliary_type_id, item_code, item_name,
      external_entity_type, external_entity_id, is_enabled
    )
    select v_account_set.tenant_id, v_account_set.id, v_type.id,
      coalesce(nullif(btrim(e.employee_no), ''), left(e.id::text, 12)),
      e.employee_name, 'hr_employee', e.id, e.employment_status in ('active', 'probation')
    from public.hr_employee e
    where e.tenant_id = v_account_set.tenant_id
    on conflict (auxiliary_type_id, external_entity_type, external_entity_id)
      where external_entity_id is not null
    do update set item_code = excluded.item_code, item_name = excluded.item_name,
      is_enabled = excluded.is_enabled, update_time = now();
  end if;

  select count(*) into v_after
  from public.fms_auxiliary_item
  where auxiliary_type_id = v_type.id and external_entity_id is not null;

  return query select greatest(v_after - v_before, 0),
    greatest(v_source_count - greatest(v_after - v_before, 0), 0), v_after;
end;
$$;
create or replace function public.save_fms_opening_balance(p_payload jsonb)
returns public.fms_opening_balance
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_balance public.fms_opening_balance%rowtype;
  v_subject public.fms_subject%rowtype;
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := (p_payload ->> 'accountSetId')::uuid;
  v_subject_id uuid := (p_payload ->> 'subjectId')::uuid;
  v_currency_id uuid := nullif(p_payload ->> 'currencyId', '')::uuid;
  v_year smallint := (p_payload ->> 'fiscalYear')::smallint;
  v_auxiliary_values jsonb := coalesce(p_payload -> 'auxiliaryValues', '{}'::jsonb);
  v_opening_debit numeric(20, 2) := coalesce((p_payload ->> 'openingDebit')::numeric, 0);
  v_opening_credit numeric(20, 2) := coalesce((p_payload ->> 'openingCredit')::numeric, 0);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护期初余额';
  end if;

  if exists (
    select 1 from public.fms_opening_balance_control c
    where c.account_set_id = v_account_set_id and c.fiscal_year = v_year and c.status = 'confirmed'
  ) then
    raise exception using errcode = '23514', message = '期初余额已确认，请先反确认后再修改';
  end if;

  if exists (
    select 1 from public.fms_accounting_period p
    where p.account_set_id = v_account_set_id and p.fiscal_year = v_year
      and p.status in ('closing', 'closed')
  ) then
    raise exception using errcode = '23514', message = '会计期间已进入结账流程，不能修改期初余额';
  end if;

  select * into v_subject
  from public.fms_subject
  where id = v_subject_id and account_set_id = v_account_set_id and is_enabled;
  if not found then
    raise exception using errcode = 'P0002', message = '会计科目不存在、已停用或不属于当前账套';
  end if;

  if exists (select 1 from public.fms_subject child where child.parent_id = v_subject.id) then
    raise exception using errcode = '23514', message = '期初余额只能录入末级科目';
  end if;

  if (v_subject.balance_direction = 'debit' and v_opening_credit <> 0)
     or (v_subject.balance_direction = 'credit' and v_opening_debit <> 0) then
    raise exception using errcode = '23514', message = '期初余额必须录入科目规定的余额方向';
  end if;

  if v_currency_id is not null and not v_subject.allow_foreign_currency then
    raise exception using errcode = '23514', message = '当前科目未启用外币核算';
  end if;

  if not v_subject.allow_quantity and coalesce((p_payload ->> 'openingQuantity')::numeric, 0) <> 0 then
    raise exception using errcode = '23514', message = '当前科目未启用数量核算';
  end if;

  if exists (
    select 1
    from public.fms_subject_auxiliary_type config
    where config.subject_id = v_subject.id and config.is_required
      and nullif(v_auxiliary_values ->> config.auxiliary_type_id::text, '') is null
  ) then
    raise exception using errcode = '23502', message = '请完整填写科目要求的辅助核算项目';
  end if;

  if exists (
    select 1
    from jsonb_each_text(v_auxiliary_values) provided(type_id, item_id)
    left join public.fms_auxiliary_item item
      on item.id = provided.item_id::uuid
      and item.auxiliary_type_id = provided.type_id::uuid
      and item.account_set_id = v_account_set_id
      and item.is_enabled
    where item.id is null
  ) then
    raise exception using errcode = '23503', message = '辅助核算项目不存在、已停用或不属于当前账套';
  end if;

  if v_id is null then
    insert into public.fms_opening_balance (
      tenant_id, account_set_id, fiscal_year, subject_id, currency_id, auxiliary_values,
      opening_debit, opening_credit, year_to_date_debit, year_to_date_credit,
      opening_quantity, original_currency_amount
    ) values (
      (p_payload ->> 'tenantId')::uuid, v_account_set_id, v_year, v_subject_id,
      v_currency_id, v_auxiliary_values, v_opening_debit, v_opening_credit,
      coalesce((p_payload ->> 'yearToDateDebit')::numeric, 0),
      coalesce((p_payload ->> 'yearToDateCredit')::numeric, 0),
      coalesce((p_payload ->> 'openingQuantity')::numeric, 0),
      coalesce((p_payload ->> 'originalCurrencyAmount')::numeric, 0)
    ) returning * into v_balance;
  else
    update public.fms_opening_balance set
      subject_id = v_subject_id,
      currency_id = v_currency_id,
      auxiliary_values = v_auxiliary_values,
      opening_debit = v_opening_debit,
      opening_credit = v_opening_credit,
      year_to_date_debit = coalesce((p_payload ->> 'yearToDateDebit')::numeric, 0),
      year_to_date_credit = coalesce((p_payload ->> 'yearToDateCredit')::numeric, 0),
      opening_quantity = coalesce((p_payload ->> 'openingQuantity')::numeric, 0),
      original_currency_amount = coalesce((p_payload ->> 'originalCurrencyAmount')::numeric, 0)
    where id = v_id and account_set_id = v_account_set_id and fiscal_year = v_year
    returning * into v_balance;

    if not found then
      raise exception using errcode = 'P0002', message = '期初余额不存在或不属于当前账套年度';
    end if;
  end if;

  return v_balance;
end;
$$;
create or replace function public.fms_opening_balance_summary(
  p_account_set_id uuid,
  p_fiscal_year smallint
)
returns table (
  account_set_id uuid,
  fiscal_year smallint,
  status text,
  entry_count bigint,
  opening_debit numeric,
  opening_credit numeric,
  difference numeric,
  is_balanced boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    a.id,
    p_fiscal_year,
    coalesce(c.status, 'draft'),
    count(b.id),
    coalesce(sum(b.opening_debit), 0),
    coalesce(sum(b.opening_credit), 0),
    coalesce(sum(b.opening_debit), 0) - coalesce(sum(b.opening_credit), 0),
    coalesce(sum(b.opening_debit), 0) = coalesce(sum(b.opening_credit), 0)
  from public.fms_account_set a
  left join public.fms_opening_balance_control c
    on c.account_set_id = a.id and c.fiscal_year = p_fiscal_year
  left join public.fms_opening_balance b
    on b.account_set_id = a.id and b.fiscal_year = p_fiscal_year
  where a.id = p_account_set_id
  group by a.id, c.status
$$;
create or replace function public.set_fms_opening_balance_status(
  p_account_set_id uuid,
  p_fiscal_year smallint,
  p_status text,
  p_reason text default null
)
returns public.fms_opening_balance_control
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_account_set public.fms_account_set%rowtype;
  v_control public.fms_opening_balance_control%rowtype;
  v_count bigint;
  v_debit numeric;
  v_credit numeric;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可确认或反确认期初余额';
  end if;

  select * into v_account_set from public.fms_account_set where id = p_account_set_id;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在';
  end if;

  select * into v_control
  from public.fms_opening_balance_control
  where account_set_id = p_account_set_id and fiscal_year = p_fiscal_year
  for update;

  if p_status = 'confirmed' then
    if found and v_control.status = 'confirmed' then
      raise exception using errcode = '23514', message = '期初余额已经确认';
    end if;

    select count(*), coalesce(sum(opening_debit), 0), coalesce(sum(opening_credit), 0)
    into v_count, v_debit, v_credit
    from public.fms_opening_balance
    where account_set_id = p_account_set_id and fiscal_year = p_fiscal_year;

    if v_count = 0 then
      raise exception using errcode = '23514', message = '尚未录入期初余额，不能确认';
    end if;
    if v_debit <> v_credit then
      raise exception using errcode = '23514', message = '期初借贷不平衡，不能确认';
    end if;

    insert into public.fms_opening_balance_control (
      tenant_id, account_set_id, fiscal_year, status, confirmed_at, confirmed_by
    ) values (
      v_account_set.tenant_id, v_account_set.id, p_fiscal_year, 'confirmed', now(),
      coalesce(auth.jwt() ->> 'email', 'unknown')
    )
    on conflict (account_set_id, fiscal_year) do update set
      status = 'confirmed', confirmed_at = now(),
      confirmed_by = coalesce(auth.jwt() ->> 'email', 'unknown')
    returning * into v_control;
  elsif p_status = 'draft' then
    if not found or v_control.status <> 'confirmed' then
      raise exception using errcode = '23514', message = '当前期初余额未确认，无需反确认';
    end if;
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = '23502', message = '反确认必须填写原因';
    end if;
    if exists (
      select 1 from public.fms_accounting_period p
      where p.account_set_id = p_account_set_id and p.fiscal_year = p_fiscal_year
        and p.status in ('closing', 'closed')
    ) then
      raise exception using errcode = '23514', message = '会计期间已进入结账流程，不能反确认期初余额';
    end if;

    update public.fms_opening_balance_control set
      status = 'draft', reopened_at = now(),
      reopened_by = coalesce(auth.jwt() ->> 'email', 'unknown'),
      reopen_reason = btrim(p_reason), reopen_count = reopen_count + 1
    where id = v_control.id
    returning * into v_control;
  else
    raise exception using errcode = '23514', message = '不支持的期初余额状态';
  end if;

  return v_control;
end;
$$;
revoke execute on function public.save_fms_subject(jsonb) from public, anon;
revoke execute on function public.sync_fms_auxiliary_items(uuid, uuid) from public, anon;
revoke execute on function public.save_fms_opening_balance(jsonb) from public, anon;
revoke execute on function public.fms_opening_balance_summary(uuid, smallint) from public, anon;
revoke execute on function public.set_fms_opening_balance_status(uuid, smallint, text, text) from public, anon;
grant execute on function public.save_fms_subject(jsonb) to authenticated, service_role;
grant execute on function public.sync_fms_auxiliary_items(uuid, uuid) to authenticated, service_role;
grant execute on function public.save_fms_opening_balance(jsonb) to authenticated, service_role;
grant execute on function public.fms_opening_balance_summary(uuid, smallint) to authenticated, service_role;
grant execute on function public.set_fms_opening_balance_status(uuid, smallint, text, text) to authenticated, service_role;
with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select item.id, item.name, item.code, '1', '624944977@qq.com', '624944977@qq.com',
  platform_tenant.id, 'dictionary', item.sort, item.remark
from platform_tenant
cross join (values
  ('b2000000-0000-4000-8000-000000000005'::uuid, '会计科目类别', 'fmsSubjectCategory', 205, '企业会计科目分类'),
  ('b2000000-0000-4000-8000-000000000006'::uuid, '余额方向', 'fmsBalanceDirection', 206, '会计科目余额方向'),
  ('b2000000-0000-4000-8000-000000000007'::uuid, '辅助核算来源', 'fmsAuxiliarySourceType', 207, '辅助核算项目权威来源'),
  ('b2000000-0000-4000-8000-000000000008'::uuid, '汇率类型', 'fmsExchangeRateType', 208, '外币汇率业务口径'),
  ('b2000000-0000-4000-8000-000000000009'::uuid, '期初余额状态', 'fmsOpeningBalanceStatus', 209, '期初余额确认状态')
) as item(id, name, code, sort, remark)
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark;
with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000021'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'asset', '资产', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000022'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'liability', '负债', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000023'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'equity', '所有者权益', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000024'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'cost', '成本', 4, 'danger'),
    ('c2000000-0000-4000-8000-000000000025'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'income', '收入', 5, 'success'),
    ('c2000000-0000-4000-8000-000000000026'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'expense', '费用', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000027'::uuid, 'b2000000-0000-4000-8000-000000000005'::uuid, 'memo', '备查', 7, 'info'),
    ('c2000000-0000-4000-8000-000000000031'::uuid, 'b2000000-0000-4000-8000-000000000006'::uuid, 'debit', '借方', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000032'::uuid, 'b2000000-0000-4000-8000-000000000006'::uuid, 'credit', '贷方', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000041'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'manual', '手工维护', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000042'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'customer', '客户主数据', 2, 'primary'),
    ('c2000000-0000-4000-8000-000000000043'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'carrier', '承运商主数据', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000044'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'department', '组织部门', 4, 'warning'),
    ('c2000000-0000-4000-8000-000000000045'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'employee', '员工档案', 5, 'danger'),
    ('c2000000-0000-4000-8000-000000000046'::uuid, 'b2000000-0000-4000-8000-000000000007'::uuid, 'project', '项目档案', 6, 'info'),
    ('c2000000-0000-4000-8000-000000000051'::uuid, 'b2000000-0000-4000-8000-000000000008'::uuid, 'spot', '即期汇率', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000052'::uuid, 'b2000000-0000-4000-8000-000000000008'::uuid, 'average', '期间平均汇率', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000053'::uuid, 'b2000000-0000-4000-8000-000000000008'::uuid, 'closing', '期末汇率', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000061'::uuid, 'b2000000-0000-4000-8000-000000000009'::uuid, 'draft', '草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000062'::uuid, 'b2000000-0000-4000-8000-000000000009'::uuid, 'confirmed', '已确认', 2, 'success')
  ) as values_table(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select item.id, item.type_id, item.value, '1', item.value, item.label,
  item.sort, item.tag_type, '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();
insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values
  (
    'a1000000-0000-4000-8000-000000000014'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceAccountingAuxiliary', 'accounting-auxiliary', '/fms/accounting-auxiliary',
    'menu', 15,
    jsonb_build_object('icon', 'ri:git-branch-line', 'title', '辅助核算', 'is_enable', true, 'keep_alive', true),
    '624944977@qq.com', '624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000015'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceAccountingCurrency', 'accounting-currency', '/fms/accounting-currency',
    'menu', 16,
    jsonb_build_object('icon', 'ri:exchange-dollar-line', 'title', '币种汇率', 'is_enable', true, 'keep_alive', true),
    '624944977@qq.com', '624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000016'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceOpeningBalance', 'opening-balance', '/fms/opening-balance',
    'menu', 17,
    jsonb_build_object('icon', 'ri:scale-line', 'title', '期初余额', 'is_enable', true, 'keep_alive', true),
    '624944977@qq.com', '624944977@qq.com'
  )
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, type = excluded.type, sort = excluded.sort,
  meta = excluded.meta, update_by = excluded.update_by, update_time = now();
insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select rm.role_id, menu.id, rm.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu rm
cross join (values
  ('a1000000-0000-4000-8000-000000000014'::uuid),
  ('a1000000-0000-4000-8000-000000000015'::uuid),
  ('a1000000-0000-4000-8000-000000000016'::uuid)
) as menu(id)
where rm.menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
on conflict (role_id, menu_id) do nothing;
commit;
