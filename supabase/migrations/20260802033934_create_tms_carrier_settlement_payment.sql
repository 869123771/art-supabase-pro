
create sequence if not exists public.tms_carrier_statement_no_seq;

create table if not exists public.tms_carrier_statement (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  statement_no text not null default (
    'PS' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.tms_carrier_statement_no_seq'::regclass)::text, 6, '0')
  ),
  carrier_id uuid not null,
  carrier_name_snapshot text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft',
  settled_amount numeric(14, 2) not null default 0,
  submitted_at timestamptz,
  submitted_by text,
  reviewed_at timestamptz,
  reviewed_by text,
  review_remark text,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_carrier_statement_tenant_no_key unique (tenant_id, statement_no),
  constraint tms_carrier_statement_carrier_id_fkey
    foreign key (carrier_id) references public.tms_carrier(id) on delete restrict,
  constraint tms_carrier_statement_period_check check (period_start <= period_end),
  constraint tms_carrier_statement_status_check check (
    status in ('draft', 'pending_review', 'confirmed', 'partially_settled', 'settled', 'voided')
  ),
  constraint tms_carrier_statement_settled_amount_check check (settled_amount >= 0),
  constraint tms_carrier_statement_carrier_name_not_blank_check
    check (btrim(carrier_name_snapshot) <> '')
);

create table if not exists public.tms_carrier_statement_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  statement_id uuid not null,
  carrier_id uuid not null,
  cost_id uuid not null,
  waybill_id uuid not null,
  waybill_no_snapshot text not null,
  cost_type_snapshot text not null,
  occurred_on_snapshot date not null,
  payee_name_snapshot text,
  cost_amount numeric(14, 2) not null,
  adjustment_amount numeric(14, 2) not null default 0,
  line_amount numeric(14, 2) not null,
  is_active boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_carrier_statement_item_statement_id_fkey
    foreign key (statement_id) references public.tms_carrier_statement(id) on delete cascade,
  constraint tms_carrier_statement_item_carrier_id_fkey
    foreign key (carrier_id) references public.tms_carrier(id) on delete restrict,
  constraint tms_carrier_statement_item_cost_id_fkey
    foreign key (cost_id) references public.tms_waybill_cost(id) on delete restrict,
  constraint tms_carrier_statement_item_waybill_id_fkey
    foreign key (waybill_id) references public.tms_waybill(id) on delete restrict,
  constraint tms_carrier_statement_item_statement_cost_key unique (statement_id, cost_id),
  constraint tms_carrier_statement_item_cost_amount_check check (cost_amount > 0),
  constraint tms_carrier_statement_item_line_amount_check
    check (line_amount = cost_amount + adjustment_amount and line_amount >= 0),
  constraint tms_carrier_statement_item_waybill_no_not_blank_check
    check (btrim(waybill_no_snapshot) <> ''),
  constraint tms_carrier_statement_item_cost_type_not_blank_check
    check (btrim(cost_type_snapshot) <> '')
);

create table if not exists public.tms_carrier_cash_allocation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  transaction_id uuid not null,
  statement_id uuid not null,
  carrier_id uuid not null,
  allocated_amount numeric(14, 2) not null,
  is_active boolean not null default true,
  allocated_at timestamptz not null default now(),
  allocated_by text,
  reversed_at timestamptz,
  reversed_by text,
  reverse_reason text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_carrier_cash_allocation_transaction_id_fkey
    foreign key (transaction_id) references public.tms_cash_transaction(id) on delete restrict,
  constraint tms_carrier_cash_allocation_statement_id_fkey
    foreign key (statement_id) references public.tms_carrier_statement(id) on delete restrict,
  constraint tms_carrier_cash_allocation_carrier_id_fkey
    foreign key (carrier_id) references public.tms_carrier(id) on delete restrict,
  constraint tms_carrier_cash_allocation_amount_check check (allocated_amount > 0)
);

alter table public.tms_cash_transaction
  add column if not exists carrier_id uuid;

alter table public.tms_cash_transaction
  drop constraint if exists tms_cash_transaction_receipt_customer_check;

alter table public.tms_cash_transaction
  drop constraint if exists tms_cash_transaction_counterparty_type_check;

alter table public.tms_cash_transaction
  add constraint tms_cash_transaction_carrier_id_fkey
    foreign key (carrier_id) references public.tms_carrier(id) on delete restrict;

alter table public.tms_cash_transaction
  add constraint tms_cash_transaction_counterparty_type_check check (
    (direction = 'receipt' and customer_id is not null and carrier_id is null)
    or (direction = 'payment' and carrier_id is not null and customer_id is null)
  );

create index if not exists tms_carrier_statement_tenant_status_time_idx
  on public.tms_carrier_statement (tenant_id, status, create_time desc);
create index if not exists tms_carrier_statement_carrier_period_idx
  on public.tms_carrier_statement (tenant_id, carrier_id, period_start, period_end);
create index if not exists tms_carrier_statement_carrier_id_idx
  on public.tms_carrier_statement (carrier_id);
create index if not exists tms_carrier_statement_item_statement_id_idx
  on public.tms_carrier_statement_item (statement_id);
create index if not exists tms_carrier_statement_item_carrier_id_idx
  on public.tms_carrier_statement_item (carrier_id);
create index if not exists tms_carrier_statement_item_cost_id_idx
  on public.tms_carrier_statement_item (cost_id);
create index if not exists tms_carrier_statement_item_waybill_id_idx
  on public.tms_carrier_statement_item (waybill_id);
create unique index if not exists tms_carrier_statement_item_active_cost_uk
  on public.tms_carrier_statement_item (tenant_id, cost_id)
  where is_active;
create index if not exists tms_carrier_cash_allocation_transaction_id_idx
  on public.tms_carrier_cash_allocation (transaction_id);
create index if not exists tms_carrier_cash_allocation_statement_id_idx
  on public.tms_carrier_cash_allocation (statement_id);
create index if not exists tms_carrier_cash_allocation_carrier_id_idx
  on public.tms_carrier_cash_allocation (carrier_id);
create index if not exists tms_carrier_cash_allocation_tenant_active_transaction_idx
  on public.tms_carrier_cash_allocation (tenant_id, transaction_id, create_time desc)
  where is_active;
create index if not exists tms_carrier_cash_allocation_tenant_active_statement_idx
  on public.tms_carrier_cash_allocation (tenant_id, statement_id, create_time desc)
  where is_active;
create index if not exists tms_cash_transaction_carrier_id_idx
  on public.tms_cash_transaction (carrier_id)
  where carrier_id is not null;
create index if not exists tms_cash_transaction_tenant_carrier_date_idx
  on public.tms_cash_transaction (tenant_id, carrier_id, transaction_date desc)
  where carrier_id is not null;

comment on table public.tms_carrier_statement is '承运商应付对账单';
comment on table public.tms_carrier_statement_item is '承运商应付对账单费用明细';
comment on table public.tms_carrier_cash_allocation is '承运商付款与应付对账单核销明细';
comment on column public.tms_cash_transaction.carrier_id is '付款方向对应的承运商';

create or replace function public.trg_validate_tms_carrier_statement()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_carrier_tenant_id uuid;
  v_carrier_name text;
  v_actor text;
begin
  select c.tenant_id, c.company_name
    into v_carrier_tenant_id, v_carrier_name
  from public.tms_carrier c
  where c.id = new.carrier_id;

  if not found then
    raise exception '对账承运商不存在';
  end if;
  if new.period_start > new.period_end then
    raise exception '账期开始日期不能晚于结束日期';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_carrier_tenant_id;
    new.carrier_name_snapshot := v_carrier_name;
    new.status := 'draft';
    new.settled_amount := 0;
    new.submitted_at := null;
    new.submitted_by := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_remark := null;
    new.voided_at := null;
    new.voided_by := null;
    new.void_reason := null;
    return new;
  end if;

  if old.status = 'voided' then
    raise exception '已作废承运商对账单不可修改';
  end if;
  if new.tenant_id is distinct from old.tenant_id
     or new.statement_no is distinct from old.statement_no
     or new.carrier_id is distinct from old.carrier_id
     or new.carrier_name_snapshot is distinct from old.carrier_name_snapshot
     or new.period_start is distinct from old.period_start
     or new.period_end is distinct from old.period_end then
    raise exception '对账单承运商、账期和单号不可修改';
  end if;
  if new.settled_amount is distinct from old.settled_amount and pg_trigger_depth() <= 1 then
    raise exception '已结金额只能由付款核销流程更新';
  end if;

  new.submitted_at := old.submitted_at;
  new.submitted_by := old.submitted_by;
  new.reviewed_at := old.reviewed_at;
  new.reviewed_by := old.reviewed_by;
  new.voided_at := old.voided_at;
  new.voided_by := old.voided_by;

  if new.status is distinct from old.status and not (
    (old.status = 'draft' and new.status in ('pending_review', 'voided'))
    or (old.status = 'pending_review' and new.status in ('draft', 'confirmed', 'voided'))
    or (old.status = 'confirmed' and new.status in ('partially_settled', 'settled', 'voided'))
    or (old.status = 'partially_settled' and new.status in ('confirmed', 'settled', 'voided'))
    or (old.status = 'settled' and new.status in ('partially_settled', 'voided'))
  ) then
    raise exception '不允许的承运商对账单状态流转：% -> %', old.status, new.status;
  end if;

  v_actor := coalesce(nullif(public.get_app_user_display_name(), ''), nullif(auth.jwt() ->> 'email', ''), 'unknown');
  if new.status = 'pending_review' and old.status <> 'pending_review' then
    new.submitted_at := now();
    new.submitted_by := v_actor;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_remark := null;
  elsif old.status = 'pending_review' and new.status = 'confirmed' then
    new.reviewed_at := now();
    new.reviewed_by := v_actor;
  elsif old.status = 'pending_review' and new.status = 'draft' then
    if btrim(coalesce(new.review_remark, '')) = '' then
      raise exception '驳回原因不能为空';
    end if;
    new.reviewed_at := now();
    new.reviewed_by := v_actor;
  elsif new.status = 'voided' then
    if btrim(coalesce(new.void_reason, '')) = '' then
      raise exception '作废原因不能为空';
    end if;
    new.voided_at := now();
    new.voided_by := v_actor;
  end if;
  return new;
end;
$$;

create or replace function app_private.trg_require_carrier_statement_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'draft' and new.status = 'pending_review' and not exists (
    select 1 from public.tms_carrier_statement_item i
    where i.statement_id = new.id and i.is_active
  ) then
    raise exception '承运商对账单没有有效费用明细，不能提交审核';
  end if;
  return new;
end;
$$;

create or replace function app_private.trg_release_carrier_statement_costs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'voided' and old.status <> 'voided' then
    update public.tms_carrier_statement_item
    set is_active = false
    where statement_id = new.id and is_active;
  end if;
  return new;
end;
$$;

create or replace function public.trg_validate_tms_carrier_cash_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_transaction record;
  v_statement record;
  v_statement_amount numeric(14, 2);
  v_statement_settled numeric(14, 2);
  v_actor text;
begin
  select t.id, t.tenant_id, t.direction, t.carrier_id, t.amount,
         t.allocated_amount, t.status
    into v_transaction
  from public.tms_cash_transaction t
  where t.id = new.transaction_id
  for update;
  if not found then raise exception '付款记录不存在'; end if;

  select s.id, s.tenant_id, s.carrier_id, s.status
    into v_statement
  from public.tms_carrier_statement s
  where s.id = new.statement_id
  for update;
  if not found then raise exception '承运商对账单不存在'; end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.transaction_id is distinct from old.transaction_id
       or new.statement_id is distinct from old.statement_id
       or new.carrier_id is distinct from old.carrier_id
       or new.allocated_amount is distinct from old.allocated_amount
       or new.allocated_at is distinct from old.allocated_at
       or new.allocated_by is distinct from old.allocated_by
       or new.remark is distinct from old.remark then
      raise exception '付款核销明细业务字段不可修改';
    end if;
    if not old.is_active or new.is_active then
      raise exception '付款核销明细只能由有效状态撤销一次';
    end if;
    if btrim(coalesce(new.reverse_reason, '')) = '' then
      raise exception '撤销核销原因不能为空';
    end if;
    v_actor := coalesce(nullif(public.get_app_user_display_name(), ''), nullif(auth.jwt() ->> 'email', ''), 'unknown');
    new.reversed_at := now();
    new.reversed_by := v_actor;
    new.reverse_reason := btrim(new.reverse_reason);
    return new;
  end if;

  if v_transaction.direction <> 'payment' or v_transaction.status = 'voided' then
    raise exception '只有未作废的承运商付款可以核销';
  end if;
  if v_statement.status not in ('confirmed', 'partially_settled') then
    raise exception '只有已确认或部分结算的承运商对账单可以核销';
  end if;
  if v_transaction.tenant_id is distinct from v_statement.tenant_id
     or v_transaction.carrier_id is distinct from v_statement.carrier_id then
    raise exception '付款记录与对账单必须属于同一租户和承运商';
  end if;

  select coalesce(sum(i.line_amount), 0)::numeric(14, 2)
    into v_statement_amount
  from public.tms_carrier_statement_item i
  where i.statement_id = v_statement.id;
  select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
    into v_statement_settled
  from public.tms_carrier_cash_allocation a
  where a.statement_id = v_statement.id;

  if new.allocated_amount <= 0 then raise exception '核销金额必须大于 0'; end if;
  if new.allocated_amount > v_transaction.amount - v_transaction.allocated_amount then
    raise exception '核销金额超过本笔付款未核销余额';
  end if;
  if new.allocated_amount > v_statement_amount - v_statement_settled then
    raise exception '核销金额超过承运商对账单未结金额';
  end if;

  v_actor := coalesce(nullif(public.get_app_user_display_name(), ''), nullif(auth.jwt() ->> 'email', ''), 'unknown');
  new.tenant_id := v_transaction.tenant_id;
  new.carrier_id := v_transaction.carrier_id;
  new.is_active := true;
  new.allocated_at := now();
  new.allocated_by := v_actor;
  new.reversed_at := null;
  new.reversed_by := null;
  new.reverse_reason := null;
  new.remark := nullif(btrim(new.remark), '');
  return new;
end;
$$;

create or replace function app_private.trg_sync_tms_carrier_cash_allocation_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction_amount numeric(14, 2);
  v_transaction_allocated numeric(14, 2);
  v_statement_amount numeric(14, 2);
  v_statement_settled numeric(14, 2);
begin
  select amount into v_transaction_amount
  from public.tms_cash_transaction where id = new.transaction_id;
  select coalesce(sum(allocated_amount) filter (where is_active), 0)::numeric(14, 2)
    into v_transaction_allocated
  from public.tms_carrier_cash_allocation where transaction_id = new.transaction_id;
  select coalesce(sum(line_amount), 0)::numeric(14, 2)
    into v_statement_amount
  from public.tms_carrier_statement_item where statement_id = new.statement_id;
  select coalesce(sum(allocated_amount) filter (where is_active), 0)::numeric(14, 2)
    into v_statement_settled
  from public.tms_carrier_cash_allocation where statement_id = new.statement_id;

  update public.tms_carrier_statement
  set settled_amount = v_statement_settled,
      status = case
        when v_statement_settled = 0 then 'confirmed'
        when v_statement_settled < v_statement_amount then 'partially_settled'
        else 'settled'
      end
  where id = new.statement_id;

  update public.tms_cash_transaction
  set allocated_amount = v_transaction_allocated,
      status = case
        when v_transaction_allocated = 0 then 'pending_allocation'
        when v_transaction_allocated < v_transaction_amount then 'partially_allocated'
        else 'allocated'
      end
  where id = new.transaction_id;
  return new;
end;
$$;

create or replace function public.trg_validate_tms_cash_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_counterparty_tenant_id uuid;
  v_counterparty_name text;
  v_expected_allocated numeric(14, 2);
  v_expected_status text;
  v_actor text;
begin
  if new.direction = 'receipt' then
    select c.tenant_id, c.customer_name
      into v_counterparty_tenant_id, v_counterparty_name
    from public.tms_customer c
    where c.id = new.customer_id and c.enabled;
    if not found then raise exception '收款客户不存在或已停用'; end if;
    new.carrier_id := null;
  elsif new.direction = 'payment' then
    select c.tenant_id, c.company_name
      into v_counterparty_tenant_id, v_counterparty_name
    from public.tms_carrier c
    where c.id = new.carrier_id and c.enabled;
    if not found then raise exception '付款承运商不存在或已停用'; end if;
    new.customer_id := null;
  else
    raise exception '收付方向不正确';
  end if;

  if new.amount <= 0 then raise exception '收付金额必须大于 0'; end if;
  if jsonb_typeof(coalesce(new.voucher_urls, '[]'::jsonb)) <> 'array' then
    raise exception '收付款凭证格式不正确';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_counterparty_tenant_id;
    new.counterparty_name_snapshot := v_counterparty_name;
    new.allocated_amount := 0;
    new.status := 'pending_allocation';
    new.voucher_urls := coalesce(new.voucher_urls, '[]'::jsonb);
    new.bank_reference := nullif(btrim(new.bank_reference), '');
    new.remark := nullif(btrim(new.remark), '');
    new.voided_at := null;
    new.voided_by := null;
    new.void_reason := null;
    return new;
  end if;

  if old.status = 'voided' then raise exception '已作废收付款记录不可修改'; end if;
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.transaction_no is distinct from old.transaction_no
     or new.direction is distinct from old.direction
     or new.customer_id is distinct from old.customer_id
     or new.carrier_id is distinct from old.carrier_id
     or new.counterparty_name_snapshot is distinct from old.counterparty_name_snapshot
     or new.transaction_date is distinct from old.transaction_date
     or new.amount is distinct from old.amount
     or new.payment_method is distinct from old.payment_method
     or new.bank_reference is distinct from old.bank_reference
     or new.voucher_urls is distinct from old.voucher_urls then
    raise exception '收付款核心业务字段登记后不可修改';
  end if;

  if new.direction = 'receipt' then
    select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
      into v_expected_allocated
    from public.tms_cash_allocation a where a.transaction_id = new.id;
  else
    select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
      into v_expected_allocated
    from public.tms_carrier_cash_allocation a where a.transaction_id = new.id;
  end if;

  if new.allocated_amount is distinct from v_expected_allocated then
    raise exception '已核销金额必须等于有效核销明细合计';
  end if;
  if new.status = 'voided' then
    if v_expected_allocated <> 0 then raise exception '存在有效核销明细，不能作废；请先撤销核销'; end if;
    if btrim(coalesce(new.void_reason, '')) = '' then raise exception '作废原因不能为空'; end if;
    v_actor := coalesce(nullif(public.get_app_user_display_name(), ''), nullif(auth.jwt() ->> 'email', ''), 'unknown');
    new.voided_at := now();
    new.voided_by := v_actor;
    return new;
  end if;

  v_expected_status := case
    when v_expected_allocated = 0 then 'pending_allocation'
    when v_expected_allocated < new.amount then 'partially_allocated'
    else 'allocated'
  end;
  if new.status is distinct from v_expected_status then
    raise exception '收付款状态与核销金额不一致';
  end if;
  new.voided_at := old.voided_at;
  new.voided_by := old.voided_by;
  new.void_reason := old.void_reason;
  return new;
end;
$$;

-- The item validator must exist before its trigger is created. It is replaced below
-- with the same definition after the views to keep all item-specific logic together.
create or replace function public.trg_validate_tms_carrier_statement_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  return new;
end;
$$;

drop trigger if exists tms_carrier_statement_validate on public.tms_carrier_statement;
create trigger tms_carrier_statement_validate
before insert or update on public.tms_carrier_statement
for each row execute function public.trg_validate_tms_carrier_statement();
drop trigger if exists tms_carrier_statement_require_items on public.tms_carrier_statement;
create trigger tms_carrier_statement_require_items
before update on public.tms_carrier_statement
for each row execute function app_private.trg_require_carrier_statement_items();
drop trigger if exists tms_carrier_statement_release_costs on public.tms_carrier_statement;
create trigger tms_carrier_statement_release_costs
after update on public.tms_carrier_statement
for each row execute function app_private.trg_release_carrier_statement_costs();
drop trigger if exists tms_carrier_statement_create_audit on public.tms_carrier_statement;
create trigger tms_carrier_statement_create_audit
before insert on public.tms_carrier_statement
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists tms_carrier_statement_update_audit on public.tms_carrier_statement;
create trigger tms_carrier_statement_update_audit
before update on public.tms_carrier_statement
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_carrier_statement_item_validate on public.tms_carrier_statement_item;
create trigger tms_carrier_statement_item_validate
before insert or update on public.tms_carrier_statement_item
for each row execute function public.trg_validate_tms_carrier_statement_item();
drop trigger if exists tms_carrier_statement_item_create_audit on public.tms_carrier_statement_item;
create trigger tms_carrier_statement_item_create_audit
before insert on public.tms_carrier_statement_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists tms_carrier_statement_item_update_audit on public.tms_carrier_statement_item;
create trigger tms_carrier_statement_item_update_audit
before update on public.tms_carrier_statement_item
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_carrier_cash_allocation_validate on public.tms_carrier_cash_allocation;
create trigger tms_carrier_cash_allocation_validate
before insert or update on public.tms_carrier_cash_allocation
for each row execute function public.trg_validate_tms_carrier_cash_allocation();
drop trigger if exists tms_carrier_cash_allocation_sync_totals on public.tms_carrier_cash_allocation;
create trigger tms_carrier_cash_allocation_sync_totals
after insert or update on public.tms_carrier_cash_allocation
for each row execute function app_private.trg_sync_tms_carrier_cash_allocation_totals();
drop trigger if exists tms_carrier_cash_allocation_create_audit on public.tms_carrier_cash_allocation;
create trigger tms_carrier_cash_allocation_create_audit
before insert on public.tms_carrier_cash_allocation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists tms_carrier_cash_allocation_update_audit on public.tms_carrier_cash_allocation;
create trigger tms_carrier_cash_allocation_update_audit
before update on public.tms_carrier_cash_allocation
for each row execute function public.trg_set_update_time_and_by();

create or replace view public.tms_carrier_statement_summary


with (security_invoker = true)
as
select
  s.id, s.tenant_id, s.statement_no, s.carrier_id,
  s.carrier_name_snapshot as carrier_name,
  s.period_start, s.period_end,
  count(i.id)::integer as cost_count,
  count(distinct i.waybill_id)::integer as waybill_count,
  coalesce(sum(i.line_amount), 0)::numeric(14, 2) as statement_amount,
  s.settled_amount,
  greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0)::numeric(14, 2) as outstanding_amount,
  s.status, s.submitted_at, s.submitted_by, s.reviewed_at, s.reviewed_by,
  s.review_remark, s.voided_at, s.voided_by, s.void_reason, s.remark,
  s.create_by, s.create_time, s.update_by, s.update_time
from public.tms_carrier_statement s
left join public.tms_carrier_statement_item i on i.statement_id = s.id
group by s.id;

create or replace view public.tms_carrier_statement_eligible_cost
with (security_invoker = true)
as
select
  wc.id, wc.tenant_id, wc.carrier_id, c.company_name as carrier_name,
  wc.waybill_id, w.waybill_no, w.status as waybill_status,
  wc.cost_type, wc.amount as cost_amount, wc.occurred_on,
  wc.payee_name, wc.remark, w.origin_city, w.destination_city
from public.tms_waybill_cost wc
join public.tms_carrier c on c.id = wc.carrier_id
join public.tms_waybill w on w.id = wc.waybill_id
where wc.audit_status = 'approved'
  and wc.carrier_id is not null
  and not exists (
    select 1 from public.tms_carrier_statement_item i
    where i.tenant_id = wc.tenant_id and i.cost_id = wc.id and i.is_active
  );

create or replace view public.tms_carrier_statement_allocatable
with (security_invoker = true)
as
select
  s.id, s.tenant_id, s.statement_no, s.carrier_id,
  s.carrier_name_snapshot as carrier_name,
  s.period_start, s.period_end,
  count(i.id)::integer as cost_count,
  count(distinct i.waybill_id)::integer as waybill_count,
  coalesce(sum(i.line_amount), 0)::numeric(14, 2) as statement_amount,
  s.settled_amount,
  greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0)::numeric(14, 2) as outstanding_amount,
  s.status, s.create_time
from public.tms_carrier_statement s
left join public.tms_carrier_statement_item i on i.statement_id = s.id
where s.status in ('confirmed', 'partially_settled')
group by s.id
having greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0) > 0;

drop view if exists public.tms_cash_transaction_summary;
create view public.tms_cash_transaction_summary
with (security_invoker = true)
as
select
  t.id, t.tenant_id, t.transaction_no, t.direction, t.customer_id, t.carrier_id,
  t.counterparty_name_snapshot as counterparty_name,
  t.transaction_date, t.amount, t.allocated_amount,
  greatest(t.amount - t.allocated_amount, 0)::numeric(14, 2) as unallocated_amount,
  case when t.direction = 'receipt'
    then (select count(*)::integer from public.tms_cash_allocation a where a.transaction_id = t.id and a.is_active)
    else (select count(*)::integer from public.tms_carrier_cash_allocation a where a.transaction_id = t.id and a.is_active)
  end as allocation_count,
  t.payment_method, t.bank_reference, t.voucher_urls, t.status,
  t.voided_at, t.voided_by, t.void_reason, t.remark,
  t.create_by, t.create_time, t.update_by, t.update_time
from public.tms_cash_transaction t;

create or replace function public.trg_validate_tms_carrier_statement_item()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_statement record;
  v_source record;
begin
  select s.tenant_id, s.carrier_id, s.status, s.period_start, s.period_end
    into v_statement
  from public.tms_carrier_statement s
  where s.id = new.statement_id;
  if not found then raise exception '所属承运商对账单不存在'; end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.statement_id is distinct from old.statement_id
       or new.carrier_id is distinct from old.carrier_id
       or new.cost_id is distinct from old.cost_id
       or new.waybill_id is distinct from old.waybill_id
       or new.waybill_no_snapshot is distinct from old.waybill_no_snapshot
       or new.cost_type_snapshot is distinct from old.cost_type_snapshot
       or new.occurred_on_snapshot is distinct from old.occurred_on_snapshot
       or new.payee_name_snapshot is distinct from old.payee_name_snapshot
       or new.cost_amount is distinct from old.cost_amount
       or new.adjustment_amount is distinct from old.adjustment_amount
       or new.line_amount is distinct from old.line_amount
       or new.remark is distinct from old.remark then
      raise exception '承运商对账单明细业务字段不可直接修改';
    end if;
    if new.is_active is distinct from old.is_active
       and not (old.is_active and not new.is_active and v_statement.status = 'voided') then
      raise exception '费用占用状态只能在对账单作废时释放';
    end if;
    return new;
  end if;

  if v_statement.status <> 'draft' then
    raise exception '只有草稿承运商对账单可以新增明细';
  end if;

  select wc.tenant_id, wc.carrier_id, wc.waybill_id, wc.cost_type, wc.amount,
         wc.occurred_on, wc.payee_name, wc.audit_status, w.waybill_no
    into v_source
  from public.tms_waybill_cost wc
  join public.tms_waybill w on w.id = wc.waybill_id
  where wc.id = new.cost_id;

  if not found or v_source.audit_status <> 'approved' then
    raise exception '费用不存在或尚未审核通过';
  end if;
  if v_source.carrier_id is null then
    raise exception '费用未关联承运商，不能生成承运商对账单';
  end if;
  if v_source.tenant_id is distinct from v_statement.tenant_id
     or v_source.carrier_id is distinct from v_statement.carrier_id then
    raise exception '费用、承运商与对账单必须属于同一租户和承运商';
  end if;
  if v_source.occurred_on not between v_statement.period_start and v_statement.period_end then
    raise exception '费用发生日期不在对账账期内';
  end if;

  new.tenant_id := v_statement.tenant_id;
  new.carrier_id := v_statement.carrier_id;
  new.waybill_id := v_source.waybill_id;
  new.waybill_no_snapshot := v_source.waybill_no;
  new.cost_type_snapshot := v_source.cost_type;
  new.occurred_on_snapshot := v_source.occurred_on;
  new.payee_name_snapshot := v_source.payee_name;
  new.cost_amount := v_source.amount;
  new.adjustment_amount := coalesce(new.adjustment_amount, 0);
  new.line_amount := v_source.amount + new.adjustment_amount;
  new.is_active := true;
  return new;
end;
$$;

create or replace function public.create_tms_carrier_statement(
  p_carrier_id uuid,
  p_period_start date,
  p_period_end date,
  p_cost_ids uuid[],
  p_remark text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_statement_id uuid;
  v_carrier_tenant_id uuid;
  v_cost_id uuid;
  v_expected_count integer;
  v_inserted_count integer;
begin
  if p_period_start is null or p_period_end is null then raise exception '请选择完整对账账期'; end if;
  if p_period_start > p_period_end then raise exception '账期开始日期不能晚于结束日期'; end if;
  if coalesce(cardinality(p_cost_ids), 0) = 0 then raise exception '请至少选择一条承运商费用'; end if;

  select c.tenant_id into v_carrier_tenant_id
  from public.tms_carrier c where c.id = p_carrier_id and c.enabled;
  if not found then raise exception '对账承运商不存在或已停用'; end if;
  if not app_private.is_platform_super()
     and v_carrier_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户生成承运商对账单';
  end if;

  for v_cost_id in select distinct unnest(p_cost_ids) order by 1 loop
    perform pg_advisory_xact_lock(hashtextextended(v_cost_id::text, 841328));
  end loop;

  insert into public.tms_carrier_statement (carrier_id, period_start, period_end, remark)
  values (p_carrier_id, p_period_start, p_period_end, nullif(btrim(p_remark), ''))
  returning id into v_statement_id;

  select count(*) into v_expected_count from (select distinct unnest(p_cost_ids)) x;

  insert into public.tms_carrier_statement_item (
    statement_id, carrier_id, cost_id, waybill_id, waybill_no_snapshot,
    cost_type_snapshot, occurred_on_snapshot, payee_name_snapshot,
    cost_amount, adjustment_amount, line_amount
  )
  select
    v_statement_id, p_carrier_id, wc.id, wc.waybill_id, w.waybill_no,
    wc.cost_type, wc.occurred_on, wc.payee_name, wc.amount, 0, wc.amount
  from public.tms_waybill_cost wc
  join public.tms_waybill w on w.id = wc.waybill_id
  where wc.id = any(p_cost_ids)
    and wc.carrier_id = p_carrier_id
    and wc.tenant_id = v_carrier_tenant_id
    and wc.audit_status = 'approved'
    and wc.occurred_on between p_period_start and p_period_end;

  get diagnostics v_inserted_count = row_count;
  if v_inserted_count <> v_expected_count then
    raise exception '部分费用不存在、不属于该承运商、未审核或不在账期内';
  end if;
  return v_statement_id;
end;
$$;

create or replace function public.create_tms_carrier_payment(
  p_carrier_id uuid,
  p_transaction_date date,
  p_amount numeric,
  p_payment_method text,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_transaction_id uuid;
  v_carrier_tenant_id uuid;
  v_allocation_total numeric(14, 2);
  v_statement_id uuid;
begin
  if p_transaction_date is null then raise exception '请选择付款日期'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception '付款金额必须大于 0'; end if;
  if p_payment_method not in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other') then
    raise exception '请选择正确的付款方式';
  end if;
  if jsonb_typeof(coalesce(p_voucher_urls, '[]'::jsonb)) <> 'array' then raise exception '付款凭证格式不正确'; end if;
  if jsonb_typeof(coalesce(p_allocations, '[]'::jsonb)) <> 'array' then raise exception '核销明细格式不正确'; end if;

  select c.tenant_id into v_carrier_tenant_id
  from public.tms_carrier c where c.id = p_carrier_id and c.enabled;
  if not found then raise exception '付款承运商不存在或已停用'; end if;
  if not app_private.is_platform_super()
     and v_carrier_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户登记付款';
  end if;

  select coalesce(sum(item.amount), 0)::numeric(14, 2)
    into v_allocation_total
  from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb)) as item(statement_id uuid, amount numeric);
  if v_allocation_total > p_amount then raise exception '核销合计不能超过付款金额'; end if;

  for v_statement_id in
    select distinct item.statement_id
    from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb)) as item(statement_id uuid, amount numeric)
    where item.statement_id is not null order by item.statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_statement_id::text, 841329));
  end loop;

  insert into public.tms_cash_transaction (
    tenant_id, transaction_no, direction, carrier_id, counterparty_name_snapshot,
    transaction_date, amount, payment_method, bank_reference, voucher_urls, remark
  )
  select
    c.tenant_id,
    'CP' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
      lpad(nextval('public.tms_cash_transaction_no_seq'::regclass)::text, 6, '0'),
    'payment', c.id, c.company_name, p_transaction_date, round(p_amount, 2),
    p_payment_method, nullif(btrim(p_bank_reference), ''),
    coalesce(p_voucher_urls, '[]'::jsonb), nullif(btrim(p_remark), '')
  from public.tms_carrier c where c.id = p_carrier_id
  returning id into v_transaction_id;

  insert into public.tms_carrier_cash_allocation (
    tenant_id, transaction_id, statement_id, carrier_id, allocated_amount, remark
  )
  select v_carrier_tenant_id, v_transaction_id, item.statement_id, p_carrier_id,
         round(sum(item.amount), 2), '登记付款时核销'
  from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb)) as item(statement_id uuid, amount numeric)
  where item.statement_id is not null
  group by item.statement_id;
  return v_transaction_id;
end;
$$;

create or replace function public.allocate_tms_carrier_payment(
  p_transaction_id uuid,
  p_allocations jsonb
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_transaction record;
  v_allocation_total numeric(14, 2);
  v_statement_id uuid;
  v_inserted_count integer;
begin
  if jsonb_typeof(coalesce(p_allocations, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_allocations, '[]'::jsonb)) = 0 then
    raise exception '请至少填写一条核销明细';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_transaction_id::text, 841326));
  select t.* into v_transaction from public.tms_cash_transaction t
  where t.id = p_transaction_id for update;
  if not found or v_transaction.direction <> 'payment' then raise exception '承运商付款记录不存在'; end if;
  if v_transaction.status = 'voided' then raise exception '已作废付款不能核销'; end if;

  select coalesce(sum(item.amount), 0)::numeric(14, 2) into v_allocation_total
  from jsonb_to_recordset(p_allocations) as item(statement_id uuid, amount numeric);
  if v_allocation_total <= 0 then raise exception '核销金额必须大于 0'; end if;
  if v_allocation_total > v_transaction.amount - v_transaction.allocated_amount then
    raise exception '核销合计超过本笔付款未核销余额';
  end if;

  for v_statement_id in
    select distinct item.statement_id from jsonb_to_recordset(p_allocations) as item(statement_id uuid, amount numeric)
    where item.statement_id is not null order by item.statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_statement_id::text, 841329));
  end loop;

  insert into public.tms_carrier_cash_allocation (
    tenant_id, transaction_id, statement_id, carrier_id, allocated_amount, remark
  )
  select v_transaction.tenant_id, v_transaction.id, item.statement_id,
         v_transaction.carrier_id, round(sum(item.amount), 2), '追加核销'
  from jsonb_to_recordset(p_allocations) as item(statement_id uuid, amount numeric)
  where item.statement_id is not null group by item.statement_id;
  get diagnostics v_inserted_count = row_count;
  if v_inserted_count = 0 then raise exception '没有可保存的核销明细'; end if;
  return v_inserted_count;
end;
$$;

create or replace function public.reverse_tms_carrier_cash_allocation(
  p_allocation_id uuid,
  p_reason text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_allocation record;
begin
  if btrim(coalesce(p_reason, '')) = '' then raise exception '撤销核销原因不能为空'; end if;
  select a.* into v_allocation from public.tms_carrier_cash_allocation a
  where a.id = p_allocation_id for update;
  if not found or not v_allocation.is_active then raise exception '有效付款核销记录不存在或已撤销'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_allocation.transaction_id::text, 841326));
  perform pg_advisory_xact_lock(hashtextextended(v_allocation.statement_id::text, 841329));
  update public.tms_carrier_cash_allocation
  set is_active = false, reverse_reason = btrim(p_reason)
  where id = p_allocation_id and is_active;
  return p_allocation_id;
end;
$$;

create or replace function public.void_tms_cash_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns uuid
language plpgsql
set search_path = ''
as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then raise exception '作废原因不能为空'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_transaction_id::text, 841326));
  if exists (select 1 from public.tms_cash_allocation where transaction_id = p_transaction_id and is_active)
     or exists (select 1 from public.tms_carrier_cash_allocation where transaction_id = p_transaction_id and is_active) then
    raise exception '存在有效核销明细，不能作废；请先撤销核销';
  end if;
  update public.tms_cash_transaction
  set status = 'voided', void_reason = btrim(p_reason)
  where id = p_transaction_id and status <> 'voided';
  if not found then raise exception '收付款记录不存在或已作废'; end if;
  return p_transaction_id;
end;
$$;

alter table public.tms_carrier_statement enable row level security;
alter table public.tms_carrier_statement_item enable row level security;
alter table public.tms_carrier_cash_allocation enable row level security;

create policy tms_carrier_statement_tenant_select on public.tms_carrier_statement
for select to authenticated using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
create policy tms_carrier_statement_tenant_insert on public.tms_carrier_statement
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and status = 'draft'
  and exists (select 1 from public.tms_carrier c where c.id = carrier_id and c.tenant_id = tms_carrier_statement.tenant_id)
);
create policy tms_carrier_statement_tenant_update on public.tms_carrier_statement
for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and status <> 'voided')
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
create policy tms_carrier_statement_tenant_delete on public.tms_carrier_statement
for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and status = 'draft');

create policy tms_carrier_statement_item_tenant_select on public.tms_carrier_statement_item
for select to authenticated using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
create policy tms_carrier_statement_item_tenant_insert on public.tms_carrier_statement_item
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and is_active
  and exists (
    select 1 from public.tms_carrier_statement s
    where s.id = statement_id and s.tenant_id = tms_carrier_statement_item.tenant_id
      and s.carrier_id = tms_carrier_statement_item.carrier_id and s.status = 'draft'
  )
);

create policy tms_carrier_cash_allocation_tenant_select on public.tms_carrier_cash_allocation
for select to authenticated using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
create policy tms_carrier_cash_allocation_tenant_insert on public.tms_carrier_cash_allocation
for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and is_active
);
create policy tms_carrier_cash_allocation_tenant_update on public.tms_carrier_cash_allocation
for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and is_active)
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and not is_active);

grant usage, select on sequence public.tms_carrier_statement_no_seq to authenticated, service_role;
grant select, insert, update, delete on table public.tms_carrier_statement to authenticated, service_role;
grant select, insert on table public.tms_carrier_statement_item to authenticated, service_role;
grant select, insert, update on table public.tms_carrier_cash_allocation to authenticated, service_role;
grant select on table public.tms_carrier_statement_summary to authenticated, service_role;
grant select on table public.tms_carrier_statement_eligible_cost to authenticated, service_role;
grant select on table public.tms_carrier_statement_allocatable to authenticated, service_role;
grant select on table public.tms_cash_transaction_summary to authenticated, service_role;
grant update (carrier_id) on table public.tms_cash_transaction to service_role;

revoke all on function public.create_tms_carrier_statement(uuid, date, date, uuid[], text) from public;
revoke all on function public.create_tms_carrier_payment(uuid, date, numeric, text, text, jsonb, text, jsonb) from public;
revoke all on function public.allocate_tms_carrier_payment(uuid, jsonb) from public;
revoke all on function public.reverse_tms_carrier_cash_allocation(uuid, text) from public;
grant execute on function public.create_tms_carrier_statement(uuid, date, date, uuid[], text) to authenticated, service_role;
grant execute on function public.create_tms_carrier_payment(uuid, date, numeric, text, text, jsonb, text, jsonb) to authenticated, service_role;
grant execute on function public.allocate_tms_carrier_payment(uuid, jsonb) to authenticated, service_role;
grant execute on function public.reverse_tms_carrier_cash_allocation(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
;
