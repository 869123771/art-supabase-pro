begin;

create or replace function app_private.mask_fms_fund_account_no(p_account_no text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when nullif(regexp_replace(coalesce(p_account_no, ''), '[^0-9A-Za-z]', '', 'g'), '') is null
      then null
    when length(regexp_replace(p_account_no, '[^0-9A-Za-z]', '', 'g')) <= 4
      then repeat('*', length(regexp_replace(p_account_no, '[^0-9A-Za-z]', '', 'g')))
    else repeat('*', greatest(length(regexp_replace(p_account_no, '[^0-9A-Za-z]', '', 'g')) - 4, 4))
      || right(regexp_replace(p_account_no, '[^0-9A-Za-z]', '', 'g'), 4)
  end
$$;

create table public.fms_fund_account (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  currency_id uuid not null,
  account_code text not null,
  account_name text not null,
  account_type text not null,
  bank_name text,
  bank_branch text,
  account_no_masked text not null,
  account_no_fingerprint text not null,
  opening_balance numeric(18, 2) not null default 0,
  frozen_balance numeric(18, 2) not null default 0,
  status text not null default 'active',
  is_default boolean not null default false,
  online_banking_enabled boolean not null default false,
  reconciliation_enabled boolean not null default true,
  balance_as_of date,
  remark text,
  version integer not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_fund_account_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set (id, tenant_id) on delete restrict,
  constraint fms_fund_account_currency_fkey
    foreign key (currency_id, account_set_id, tenant_id)
    references public.fms_currency (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_fund_account_scope_code_key unique (account_set_id, account_code),
  constraint fms_fund_account_scope_number_key unique (account_set_id, account_no_fingerprint),
  constraint fms_fund_account_id_scope_key unique (id, tenant_id),
  constraint fms_fund_account_id_full_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_fund_account_code_check check (account_code ~ '^[A-Z0-9_-]{2,30}$'),
  constraint fms_fund_account_name_check check (btrim(account_name) <> ''),
  constraint fms_fund_account_type_check check (account_type in ('bank', 'cash', 'digital_wallet')),
  constraint fms_fund_account_status_check check (status in ('active', 'frozen', 'closed')),
  constraint fms_fund_account_frozen_balance_check check (frozen_balance >= 0),
  constraint fms_fund_account_version_check check (version > 0),
  constraint fms_fund_account_bank_fields_check check (
    account_type <> 'bank' or nullif(btrim(bank_name), '') is not null
  )
);

create unique index fms_fund_account_default_idx
  on public.fms_fund_account (account_set_id, account_type)
  where is_default and status <> 'closed';
create index fms_fund_account_tenant_status_idx
  on public.fms_fund_account (tenant_id, account_set_id, status, account_type);
create index fms_fund_account_currency_fk_idx
  on public.fms_fund_account (currency_id, account_set_id, tenant_id);

create table public.fms_fund_ledger_entry (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_set_id uuid not null,
  fund_account_id uuid not null,
  entry_no text not null,
  entry_date date not null,
  direction text not null,
  amount numeric(18, 2) not null,
  source_type text not null,
  source_id uuid,
  source_no text,
  summary text not null,
  counterparty_name text,
  bank_reference text,
  status text not null default 'posted',
  reversal_of_id uuid unique references public.fms_fund_ledger_entry (id) on delete restrict,
  posted_at timestamptz not null default now(),
  posted_by text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_fund_ledger_account_fkey
    foreign key (fund_account_id, account_set_id, tenant_id)
    references public.fms_fund_account (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_fund_ledger_entry_no_key unique (account_set_id, entry_no),
  constraint fms_fund_ledger_direction_check check (direction in ('inflow', 'outflow')),
  constraint fms_fund_ledger_amount_check check (amount > 0),
  constraint fms_fund_ledger_source_check check (
    source_type in (
      'customer_receipt', 'carrier_payment', 'expense_payment', 'fund_transfer',
      'manual_adjustment', 'opening'
    )
  ),
  constraint fms_fund_ledger_status_check check (status in ('posted', 'reversed')),
  constraint fms_fund_ledger_summary_check check (btrim(summary) <> '')
);

create unique index fms_fund_ledger_source_key
  on public.fms_fund_ledger_entry (fund_account_id, source_type, source_id, direction)
  where source_id is not null;
create index fms_fund_ledger_list_idx
  on public.fms_fund_ledger_entry (
    tenant_id, account_set_id, fund_account_id, entry_date desc, create_time desc
  );
create index fms_fund_ledger_status_idx
  on public.fms_fund_ledger_entry (fund_account_id, status, entry_date desc);
create index fms_fund_ledger_account_fk_idx
  on public.fms_fund_ledger_entry (fund_account_id, account_set_id, tenant_id);

alter table public.tms_cash_transaction
  add column if not exists fund_account_id uuid;
alter table public.tms_cash_transaction
  drop constraint if exists tms_cash_transaction_fund_account_fkey;
alter table public.tms_cash_transaction
  add constraint tms_cash_transaction_fund_account_fkey
  foreign key (fund_account_id, tenant_id)
  references public.fms_fund_account (id, tenant_id) on delete restrict;
create index if not exists tms_cash_transaction_fund_account_fk_idx
  on public.tms_cash_transaction (fund_account_id, tenant_id);

alter table public.tms_expense_payment
  add column if not exists fund_account_id uuid;
alter table public.tms_expense_payment
  drop constraint if exists tms_expense_payment_fund_account_fkey;
alter table public.tms_expense_payment
  add constraint tms_expense_payment_fund_account_fkey
  foreign key (fund_account_id, tenant_id)
  references public.fms_fund_account (id, tenant_id) on delete restrict;
create index if not exists tms_expense_payment_fund_account_fk_idx
  on public.tms_expense_payment (fund_account_id, tenant_id);

create or replace view public.tms_cash_transaction_summary
with (security_invoker = true)
as
select
  t.id,
  t.tenant_id,
  t.transaction_no,
  t.direction,
  t.customer_id,
  t.carrier_id,
  t.counterparty_name_snapshot as counterparty_name,
  t.transaction_date,
  t.amount,
  t.allocated_amount,
  greatest(t.amount - t.allocated_amount, 0::numeric)::numeric(14, 2) as unallocated_amount,
  case
    when t.direction = 'receipt' then (
      select count(*)::integer
      from public.tms_cash_allocation a
      where a.transaction_id = t.id and a.is_active
    )
    else (
      select count(*)::integer
      from public.tms_carrier_cash_allocation a
      where a.transaction_id = t.id and a.is_active
    )
  end as allocation_count,
  t.payment_method,
  t.bank_reference,
  t.voucher_urls,
  t.status,
  t.voided_at,
  t.voided_by,
  t.void_reason,
  t.remark,
  t.create_by,
  t.create_time,
  t.update_by,
  t.update_time,
  t.payment_application_id,
  t.fund_account_id
from public.tms_cash_transaction t;

drop trigger if exists fms_fund_account_create_audit on public.fms_fund_account;
create trigger fms_fund_account_create_audit
before insert on public.fms_fund_account
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists fms_fund_account_update_audit on public.fms_fund_account;
create trigger fms_fund_account_update_audit
before update on public.fms_fund_account
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists fms_fund_ledger_create_audit on public.fms_fund_ledger_entry;
create trigger fms_fund_ledger_create_audit
before insert on public.fms_fund_ledger_entry
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists fms_fund_ledger_update_audit on public.fms_fund_ledger_entry;
create trigger fms_fund_ledger_update_audit
before update on public.fms_fund_ledger_entry
for each row execute function public.trg_set_update_time_and_by();

alter table public.fms_fund_account enable row level security;
alter table public.fms_fund_ledger_entry enable row level security;

create policy fms_fund_account_tenant_select on public.fms_fund_account
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_fund_account_super_insert on public.fms_fund_account
for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy fms_fund_account_super_update on public.fms_fund_account
for update to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));
create policy fms_fund_account_super_delete on public.fms_fund_account
for delete to authenticated
using ((select app_private.is_platform_super()));

create policy fms_fund_ledger_tenant_select on public.fms_fund_ledger_entry
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

grant select, insert, update, delete on public.fms_fund_account to authenticated;
grant all on public.fms_fund_account to service_role;
grant select on public.fms_fund_ledger_entry to authenticated;
grant all on public.fms_fund_ledger_entry to service_role;

create or replace view public.fms_fund_account_summary
with (security_invoker = true)
as
select
  a.*,
  coalesce(l.inflow_amount, 0)::numeric(18, 2) as inflow_amount,
  coalesce(l.outflow_amount, 0)::numeric(18, 2) as outflow_amount,
  (a.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0))::numeric(18, 2)
    as current_balance,
  (a.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0)
    - a.frozen_balance)::numeric(18, 2) as available_balance,
  coalesce(l.entry_count, 0)::integer as ledger_entry_count,
  greatest(a.balance_as_of, l.last_entry_date) as latest_balance_date
from public.fms_fund_account a
left join lateral (
  select
    sum(case when e.status = 'posted' and e.direction = 'inflow' then e.amount else 0 end) as inflow_amount,
    sum(case when e.status = 'posted' and e.direction = 'outflow' then e.amount else 0 end) as outflow_amount,
    count(*) filter (where e.status = 'posted') as entry_count,
    max(e.entry_date) filter (where e.status = 'posted') as last_entry_date
  from public.fms_fund_ledger_entry e
  where e.fund_account_id = a.id
) l on true;

grant select on public.fms_fund_account_summary to authenticated, service_role;

create or replace function public.save_fms_fund_account(p_payload jsonb)
returns public.fms_fund_account
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_currency public.fms_currency%rowtype;
  v_record public.fms_fund_account%rowtype;
  v_account_no text := regexp_replace(coalesce(p_payload ->> 'accountNo', ''), '[^0-9A-Za-z]', '', 'g');
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'active');
  v_current_balance numeric(18, 2);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护资金账户';
  end if;
  select * into v_account_set
  from public.fms_account_set
  where id = (p_payload ->> 'accountSetId')::uuid and status = 'active';
  if not found then
    raise exception using errcode = '23503', message = '账套不存在或未启用';
  end if;
  select * into v_currency
  from public.fms_currency
  where id = (p_payload ->> 'currencyId')::uuid
    and account_set_id = v_account_set.id and is_enabled;
  if not found then
    raise exception using errcode = '23503', message = '币种不存在或未启用';
  end if;
  if v_id is null and v_account_no = '' then
    raise exception using errcode = '23514', message = '请输入资金账号';
  end if;
  if coalesce(nullif(p_payload ->> 'openingBalance', '')::numeric, 0) <> 0
    and nullif(p_payload ->> 'balanceAsOf', '') is null then
    raise exception using errcode = '23514', message = '存在期初余额时必须填写余额日期';
  end if;
  if coalesce((p_payload ->> 'isDefault')::boolean, false) then
    update public.fms_fund_account
    set is_default = false
    where account_set_id = v_account_set.id
      and account_type = p_payload ->> 'accountType'
      and id is distinct from v_id;
  end if;

  if v_id is null then
    insert into public.fms_fund_account (
      tenant_id, account_set_id, currency_id, account_code, account_name, account_type,
      bank_name, bank_branch, account_no_masked, account_no_fingerprint,
      opening_balance, frozen_balance, status, is_default, online_banking_enabled,
      reconciliation_enabled, balance_as_of, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id, v_currency.id,
      upper(btrim(p_payload ->> 'accountCode')), btrim(p_payload ->> 'accountName'),
      p_payload ->> 'accountType', nullif(btrim(p_payload ->> 'bankName'), ''),
      nullif(btrim(p_payload ->> 'bankBranch'), ''),
      app_private.mask_fms_fund_account_no(v_account_no),
      encode(extensions.digest(v_account_set.tenant_id::text || ':' || v_account_no, 'sha256'), 'hex'),
      coalesce(nullif(p_payload ->> 'openingBalance', '')::numeric, 0),
      coalesce(nullif(p_payload ->> 'frozenBalance', '')::numeric, 0),
      v_status, coalesce((p_payload ->> 'isDefault')::boolean, false),
      coalesce((p_payload ->> 'onlineBankingEnabled')::boolean, false),
      coalesce((p_payload ->> 'reconciliationEnabled')::boolean, true),
      nullif(p_payload ->> 'balanceAsOf', '')::date,
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_record;
  else
    select * into v_record from public.fms_fund_account where id = v_id for update;
    if not found or v_record.account_set_id <> v_account_set.id then
      raise exception using errcode = 'P0002', message = '资金账户不存在';
    end if;
    if exists (select 1 from public.fms_fund_ledger_entry where fund_account_id = v_id)
      and (
        v_record.currency_id <> v_currency.id
        or v_record.opening_balance <> coalesce(nullif(p_payload ->> 'openingBalance', '')::numeric, 0)
      ) then
      raise exception using errcode = '23514', message = '账户已产生资金流水，不能修改币种或期初余额';
    end if;
    if v_status = 'closed' then
      select current_balance into v_current_balance
      from public.fms_fund_account_summary where id = v_id;
      if coalesce(v_current_balance, 0) <> 0 then
        raise exception using errcode = '23514', message = '账户余额不为零，不能关闭';
      end if;
    end if;
    update public.fms_fund_account set
      currency_id = v_currency.id,
      account_code = upper(btrim(p_payload ->> 'accountCode')),
      account_name = btrim(p_payload ->> 'accountName'),
      account_type = p_payload ->> 'accountType',
      bank_name = nullif(btrim(p_payload ->> 'bankName'), ''),
      bank_branch = nullif(btrim(p_payload ->> 'bankBranch'), ''),
      account_no_masked = case when v_account_no = '' then account_no_masked
        else app_private.mask_fms_fund_account_no(v_account_no) end,
      account_no_fingerprint = case when v_account_no = '' then account_no_fingerprint
        else encode(extensions.digest(v_account_set.tenant_id::text || ':' || v_account_no, 'sha256'), 'hex') end,
      opening_balance = coalesce(nullif(p_payload ->> 'openingBalance', '')::numeric, 0),
      frozen_balance = coalesce(nullif(p_payload ->> 'frozenBalance', '')::numeric, 0),
      status = v_status,
      is_default = coalesce((p_payload ->> 'isDefault')::boolean, false),
      online_banking_enabled = coalesce((p_payload ->> 'onlineBankingEnabled')::boolean, false),
      reconciliation_enabled = coalesce((p_payload ->> 'reconciliationEnabled')::boolean, true),
      balance_as_of = nullif(p_payload ->> 'balanceAsOf', '')::date,
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      version = version + 1
    where id = v_id returning * into v_record;
  end if;
  return v_record;
end;
$$;

create or replace function public.delete_fms_fund_account(p_account_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除资金账户';
  end if;
  if exists (select 1 from public.fms_fund_ledger_entry where fund_account_id = p_account_id)
    or exists (select 1 from public.tms_cash_transaction where fund_account_id = p_account_id)
    or exists (select 1 from public.tms_expense_payment where fund_account_id = p_account_id) then
    raise exception using errcode = '23514', message = '账户已有业务或资金流水，请关闭而不要删除';
  end if;
  delete from public.fms_fund_account where id = p_account_id;
  if not found then raise exception using errcode = 'P0002', message = '资金账户不存在'; end if;
  return p_account_id;
end;
$$;

create or replace function app_private.post_fms_fund_ledger_entry(
  p_fund_account_id uuid,
  p_entry_date date,
  p_direction text,
  p_amount numeric,
  p_source_type text,
  p_source_id uuid,
  p_source_no text,
  p_summary text,
  p_counterparty_name text default null,
  p_bank_reference text default null,
  p_reversal_of_id uuid default null
)
returns public.fms_fund_ledger_entry
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.fms_fund_account%rowtype;
  v_existing public.fms_fund_ledger_entry%rowtype;
  v_record public.fms_fund_ledger_entry%rowtype;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system');
begin
  if p_direction not in ('inflow', 'outflow') or coalesce(p_amount, 0) <= 0 then
    raise exception using errcode = '23514', message = '资金流水方向或金额不正确';
  end if;
  select * into v_account from public.fms_fund_account where id = p_fund_account_id for update;
  if not found or (v_account.status <> 'active' and p_reversal_of_id is null) then
    raise exception using errcode = '23503', message = '资金账户不存在或不可用';
  end if;
  if p_source_id is not null then
    select * into v_existing from public.fms_fund_ledger_entry
    where fund_account_id = p_fund_account_id
      and source_type = p_source_type and source_id = p_source_id and direction = p_direction;
    if found then return v_existing; end if;
  end if;
  insert into public.fms_fund_ledger_entry (
    tenant_id, account_set_id, fund_account_id, entry_no, entry_date, direction, amount,
    source_type, source_id, source_no, summary, counterparty_name, bank_reference,
    status, reversal_of_id, posted_by
  ) values (
    v_account.tenant_id, v_account.account_set_id, v_account.id,
    'FL' || to_char(clock_timestamp(), 'YYYYMMDD') || '-'
      || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    coalesce(p_entry_date, current_date), p_direction, round(p_amount, 2), p_source_type,
    p_source_id, nullif(btrim(p_source_no), ''), btrim(p_summary),
    nullif(btrim(p_counterparty_name), ''), nullif(btrim(p_bank_reference), ''),
    'posted', p_reversal_of_id, v_actor
  ) returning * into v_record;
  if p_reversal_of_id is not null then
    update public.fms_fund_ledger_entry set status = 'reversed'
    where id = p_reversal_of_id and status = 'posted';
  end if;
  return v_record;
end;
$$;

create or replace function app_private.validate_fms_fund_account_assignment(
  p_fund_account_id uuid,
  p_tenant_id uuid,
  p_require_base_currency boolean default true
)
returns public.fms_fund_account
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account public.fms_fund_account%rowtype;
begin
  select a.* into v_account
  from public.fms_fund_account a
  join public.fms_account_set s on s.id = a.account_set_id
  join public.fms_currency c on c.id = a.currency_id
  where a.id = p_fund_account_id and a.tenant_id = p_tenant_id and a.status = 'active'
    and (not p_require_base_currency or c.currency_code = s.base_currency_code);
  if not found then
    raise exception using errcode = '23503', message = '资金账户不存在、已停用或币种不符合业务要求';
  end if;
  return v_account;
end;
$$;

create or replace function app_private.capture_fms_cash_fund_ledger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_original public.fms_fund_ledger_entry%rowtype;
  v_direction text := case when new.direction = 'receipt' then 'inflow' else 'outflow' end;
  v_source_type text := case when new.direction = 'receipt' then 'customer_receipt' else 'carrier_payment' end;
begin
  if new.fund_account_id is null then return new; end if;
  if new.status = 'voided' then
    select * into v_original from public.fms_fund_ledger_entry
    where fund_account_id = new.fund_account_id and source_type = v_source_type
      and source_id = new.id and direction = v_direction;
    if found and v_original.status = 'posted' then
      perform app_private.post_fms_fund_ledger_entry(
        new.fund_account_id, current_date,
        case when v_direction = 'inflow' then 'outflow' else 'inflow' end,
        new.amount, v_source_type, new.id, new.transaction_no,
        '冲销 · ' || new.transaction_no || ' · ' || coalesce(new.void_reason, '业务作废'),
        new.counterparty_name_snapshot, new.bank_reference, v_original.id
      );
    end if;
  else
    perform app_private.validate_fms_fund_account_assignment(new.fund_account_id, new.tenant_id, true);
    perform app_private.post_fms_fund_ledger_entry(
      new.fund_account_id, new.transaction_date, v_direction, new.amount, v_source_type,
      new.id, new.transaction_no,
      case when new.direction = 'receipt' then '客户收款' else '承运商付款' end
        || ' · ' || new.transaction_no,
      new.counterparty_name_snapshot, new.bank_reference
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.guard_fms_cash_fund_account_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.fund_account_id is not null and new.fund_account_id is distinct from old.fund_account_id then
    raise exception using errcode = '23514', message = '已登记资金账户的收付款单不能更换账户';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_fms_cash_fund_account on public.tms_cash_transaction;
create trigger trg_guard_fms_cash_fund_account
before update of fund_account_id on public.tms_cash_transaction
for each row execute function app_private.guard_fms_cash_fund_account_change();

drop trigger if exists trg_capture_fms_cash_fund_ledger on public.tms_cash_transaction;
create trigger trg_capture_fms_cash_fund_ledger
after insert or update of fund_account_id, status on public.tms_cash_transaction
for each row
when (new.fund_account_id is not null)
execute function app_private.capture_fms_cash_fund_ledger();

create or replace function app_private.capture_fms_expense_payment_fund_ledger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.fund_account_id is null then return new; end if;
  perform app_private.validate_fms_fund_account_assignment(new.fund_account_id, new.tenant_id, true);
  perform app_private.post_fms_fund_ledger_entry(
    new.fund_account_id, new.payment_date, 'outflow', new.amount, 'expense_payment',
    new.id, new.payment_no, '费用报销付款 · ' || new.payment_no,
    new.payee_name_snapshot, new.bank_reference
  );
  return new;
end;
$$;

drop trigger if exists trg_capture_fms_expense_payment_fund_ledger on public.tms_expense_payment;
create trigger trg_capture_fms_expense_payment_fund_ledger
after insert or update of fund_account_id on public.tms_expense_payment
for each row
when (new.fund_account_id is not null)
execute function app_private.capture_fms_expense_payment_fund_ledger();

create or replace function public.create_fms_customer_receipt(
  p_customer_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_amount numeric,
  p_payment_method text,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.tms_customer where id = p_customer_id;
  perform app_private.validate_fms_fund_account_assignment(p_fund_account_id, v_tenant_id, true);
  v_id := public.create_tms_customer_receipt(
    p_customer_id, p_transaction_date, p_amount, p_payment_method, p_bank_reference,
    p_voucher_urls, p_remark, p_allocations, p_transaction_no
  );
  update public.tms_cash_transaction set fund_account_id = p_fund_account_id where id = v_id;
  return v_id;
end;
$$;

create or replace function public.create_fms_carrier_payment(
  p_carrier_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_amount numeric,
  p_payment_method text,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.tms_carrier where id = p_carrier_id;
  perform app_private.validate_fms_fund_account_assignment(p_fund_account_id, v_tenant_id, true);
  v_id := public.create_tms_carrier_payment(
    p_carrier_id, p_transaction_date, p_amount, p_payment_method, p_bank_reference,
    p_voucher_urls, p_remark, p_allocations, p_transaction_no
  );
  update public.tms_cash_transaction set fund_account_id = p_fund_account_id where id = v_id;
  return v_id;
end;
$$;

create or replace function public.execute_fms_carrier_payment_application(
  p_application_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.tms_carrier_payment_application where id = p_application_id;
  perform app_private.validate_fms_fund_account_assignment(p_fund_account_id, v_tenant_id, true);
  v_id := public.execute_tms_carrier_payment_application(
    p_application_id, p_transaction_date, p_bank_reference, p_voucher_urls, p_transaction_no
  );
  update public.tms_cash_transaction set fund_account_id = p_fund_account_id where id = v_id;
  return v_id;
end;
$$;

create or replace function public.execute_fms_expense_reimbursement(
  p_reimbursement_id uuid,
  p_fund_account_id uuid,
  p_payment_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_payment_no text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.tms_expense_reimbursement where id = p_reimbursement_id;
  perform app_private.validate_fms_fund_account_assignment(p_fund_account_id, v_tenant_id, true);
  v_id := public.execute_tms_expense_reimbursement(
    p_reimbursement_id, p_payment_date, p_bank_reference, p_voucher_urls, p_remark, p_payment_no
  );
  update public.tms_expense_payment set fund_account_id = p_fund_account_id where id = v_id;
  return v_id;
end;
$$;

create or replace function public.fms_fund_account_overview(p_account_set_id uuid default null)
returns table (
  account_count bigint,
  active_account_count bigint,
  base_currency_current_balance numeric,
  base_currency_available_balance numeric,
  base_currency_frozen_balance numeric,
  foreign_currency_account_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    count(*),
    count(*) filter (where a.status = 'active'),
    coalesce(sum(a.current_balance) filter (where c.currency_code = s.base_currency_code), 0),
    coalesce(sum(a.available_balance) filter (where c.currency_code = s.base_currency_code), 0),
    coalesce(sum(a.frozen_balance) filter (where c.currency_code = s.base_currency_code), 0),
    count(*) filter (where c.currency_code <> s.base_currency_code)
  from public.fms_fund_account_summary a
  join public.fms_account_set s on s.id = a.account_set_id
  join public.fms_currency c on c.id = a.currency_id
  where p_account_set_id is null or a.account_set_id = p_account_set_id
$$;

revoke all on function app_private.mask_fms_fund_account_no(text) from public, anon, authenticated;
revoke all on function app_private.post_fms_fund_ledger_entry(
  uuid, date, text, numeric, text, uuid, text, text, text, text, uuid
) from public, anon, authenticated;
revoke all on function app_private.validate_fms_fund_account_assignment(uuid, uuid, boolean)
  from public, anon, authenticated;
revoke all on function app_private.capture_fms_cash_fund_ledger() from public, anon, authenticated;
revoke all on function app_private.guard_fms_cash_fund_account_change() from public, anon, authenticated;
revoke all on function app_private.capture_fms_expense_payment_fund_ledger() from public, anon, authenticated;

revoke execute on function public.save_fms_fund_account(jsonb) from public, anon;
revoke execute on function public.delete_fms_fund_account(uuid) from public, anon;
revoke execute on function public.create_fms_customer_receipt(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.create_fms_carrier_payment(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.execute_fms_carrier_payment_application(
  uuid, uuid, date, text, jsonb, text
) from public, anon;
revoke execute on function public.execute_fms_expense_reimbursement(
  uuid, uuid, date, text, jsonb, text, text
) from public, anon;
revoke execute on function public.fms_fund_account_overview(uuid) from public, anon;

grant execute on function public.save_fms_fund_account(jsonb) to authenticated, service_role;
grant execute on function public.delete_fms_fund_account(uuid) to authenticated, service_role;
grant execute on function public.create_fms_customer_receipt(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.create_fms_carrier_payment(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.execute_fms_carrier_payment_application(
  uuid, uuid, date, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.execute_fms_expense_reimbursement(
  uuid, uuid, date, text, jsonb, text, text
) to authenticated, service_role;
grant execute on function public.fms_fund_account_overview(uuid) to authenticated, service_role;

commit;

;
