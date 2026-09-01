create sequence if not exists public.tms_cash_transaction_no_seq;

create table if not exists public.tms_cash_transaction (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  transaction_no text not null default (
    'CR' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.tms_cash_transaction_no_seq'::regclass)::text, 6, '0')
  ),
  direction text not null default 'receipt',
  customer_id uuid,
  counterparty_name_snapshot text not null,
  transaction_date date not null default current_date,
  amount numeric(14, 2) not null,
  allocated_amount numeric(14, 2) not null default 0,
  payment_method text not null default 'bank_transfer',
  bank_reference text,
  voucher_urls jsonb not null default '[]'::jsonb,
  status text not null default 'pending_allocation',
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_cash_transaction_tenant_no_key unique (tenant_id, transaction_no),
  constraint tms_cash_transaction_customer_id_fkey
    foreign key (customer_id) references public.tms_customer(id) on delete restrict,
  constraint tms_cash_transaction_direction_check
    check (direction in ('receipt', 'payment')),
  constraint tms_cash_transaction_receipt_customer_check
    check (direction <> 'receipt' or customer_id is not null),
  constraint tms_cash_transaction_counterparty_not_blank_check
    check (btrim(counterparty_name_snapshot) <> ''),
  constraint tms_cash_transaction_amount_check check (amount > 0),
  constraint tms_cash_transaction_allocated_amount_check
    check (allocated_amount >= 0 and allocated_amount <= amount),
  constraint tms_cash_transaction_payment_method_check
    check (payment_method in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other')),
  constraint tms_cash_transaction_status_check
    check (status in ('pending_allocation', 'partially_allocated', 'allocated', 'voided')),
  constraint tms_cash_transaction_voucher_urls_check
    check (jsonb_typeof(voucher_urls) = 'array')
);

create table if not exists public.tms_cash_allocation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  transaction_id uuid not null,
  statement_id uuid not null,
  customer_id uuid not null,
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
  constraint tms_cash_allocation_transaction_id_fkey
    foreign key (transaction_id) references public.tms_cash_transaction(id) on delete restrict,
  constraint tms_cash_allocation_statement_id_fkey
    foreign key (statement_id) references public.tms_customer_statement(id) on delete restrict,
  constraint tms_cash_allocation_customer_id_fkey
    foreign key (customer_id) references public.tms_customer(id) on delete restrict,
  constraint tms_cash_allocation_amount_check check (allocated_amount > 0),
  constraint tms_cash_allocation_reverse_state_check check (
    (is_active and reversed_at is null and reversed_by is null and reverse_reason is null)
    or (
      not is_active
      and reversed_at is not null
      and reversed_by is not null
      and btrim(coalesce(reverse_reason, '')) <> ''
    )
  )
);

create index if not exists tms_cash_transaction_tenant_status_date_idx
  on public.tms_cash_transaction (tenant_id, status, transaction_date desc, create_time desc);
create index if not exists tms_cash_transaction_tenant_customer_date_idx
  on public.tms_cash_transaction (tenant_id, customer_id, transaction_date desc);
create index if not exists tms_cash_transaction_customer_id_idx
  on public.tms_cash_transaction (customer_id);
create index if not exists tms_cash_allocation_transaction_id_idx
  on public.tms_cash_allocation (transaction_id);
create index if not exists tms_cash_allocation_statement_id_idx
  on public.tms_cash_allocation (statement_id);
create index if not exists tms_cash_allocation_customer_id_idx
  on public.tms_cash_allocation (customer_id);
create index if not exists tms_cash_allocation_tenant_active_transaction_idx
  on public.tms_cash_allocation (tenant_id, transaction_id, create_time desc)
  where is_active;
create index if not exists tms_cash_allocation_tenant_active_statement_idx
  on public.tms_cash_allocation (tenant_id, statement_id, create_time desc)
  where is_active;

comment on table public.tms_cash_transaction is 'TMS 收付款流水；当前客户收款核销链路使用 receipt 方向';
comment on table public.tms_cash_allocation is '客户收款与客户对账单之间的核销及撤销记录';
comment on column public.tms_cash_transaction.counterparty_name_snapshot is '登记时的往来单位名称快照';
comment on column public.tms_cash_transaction.voucher_urls is '银行回单或收款凭证图片地址数组';
comment on column public.tms_cash_allocation.is_active is 'true 为有效核销，false 为已撤销核销';

create or replace function public.trg_validate_tms_cash_transaction()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_customer_tenant_id uuid;
  v_customer_name text;
  v_expected_allocated numeric(14, 2);
  v_expected_status text;
  v_actor text;
begin
  if new.direction = 'receipt' then
    select c.tenant_id, c.customer_name
      into v_customer_tenant_id, v_customer_name
    from public.tms_customer c
    where c.id = new.customer_id and c.enabled;

    if not found then
      raise exception '收款客户不存在或已停用';
    end if;
  else
    v_customer_tenant_id := new.tenant_id;
    v_customer_name := new.counterparty_name_snapshot;
  end if;

  if new.amount <= 0 then
    raise exception '收付金额必须大于 0';
  end if;

  if jsonb_typeof(coalesce(new.voucher_urls, '[]'::jsonb)) <> 'array' then
    raise exception '收款凭证格式不正确';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_customer_tenant_id;
    new.counterparty_name_snapshot := v_customer_name;
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

  if old.status = 'voided' then
    raise exception '已作废收付款记录不可修改';
  end if;

  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.transaction_no is distinct from old.transaction_no
     or new.direction is distinct from old.direction
     or new.customer_id is distinct from old.customer_id
     or new.counterparty_name_snapshot is distinct from old.counterparty_name_snapshot
     or new.transaction_date is distinct from old.transaction_date
     or new.amount is distinct from old.amount
     or new.payment_method is distinct from old.payment_method
     or new.bank_reference is distinct from old.bank_reference
     or new.voucher_urls is distinct from old.voucher_urls then
    raise exception '收付款核心业务字段登记后不可修改';
  end if;

  select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
    into v_expected_allocated
  from public.tms_cash_allocation a
  where a.transaction_id = new.id;

  if new.allocated_amount is distinct from v_expected_allocated then
    raise exception '已核销金额必须等于有效核销明细合计';
  end if;

  if new.status = 'voided' then
    if v_expected_allocated <> 0 then
      raise exception '存在有效核销明细，不能作废；请先撤销核销';
    end if;
    if btrim(coalesce(new.void_reason, '')) = '' then
      raise exception '作废原因不能为空';
    end if;
    v_actor := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      'unknown'
    );
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

create or replace function public.trg_validate_tms_cash_allocation()
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
  select t.id, t.tenant_id, t.direction, t.customer_id, t.amount,
         t.allocated_amount, t.status
    into v_transaction
  from public.tms_cash_transaction t
  where t.id = new.transaction_id
  for update;

  if not found then
    raise exception '收款记录不存在';
  end if;

  select s.id, s.tenant_id, s.customer_id, s.status
    into v_statement
  from public.tms_customer_statement s
  where s.id = new.statement_id
  for update;

  if not found then
    raise exception '客户对账单不存在';
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.transaction_id is distinct from old.transaction_id
       or new.statement_id is distinct from old.statement_id
       or new.customer_id is distinct from old.customer_id
       or new.allocated_amount is distinct from old.allocated_amount
       or new.allocated_at is distinct from old.allocated_at
       or new.allocated_by is distinct from old.allocated_by
       or new.remark is distinct from old.remark then
      raise exception '核销明细业务字段不可修改';
    end if;

    if not old.is_active or new.is_active then
      raise exception '核销明细只能由有效状态撤销一次';
    end if;

    if btrim(coalesce(new.reverse_reason, '')) = '' then
      raise exception '撤销核销原因不能为空';
    end if;

    v_actor := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      'unknown'
    );
    new.reversed_at := now();
    new.reversed_by := v_actor;
    new.reverse_reason := btrim(new.reverse_reason);
    return new;
  end if;

  if v_transaction.direction <> 'receipt' or v_transaction.status = 'voided' then
    raise exception '只有未作废的客户收款可以核销';
  end if;

  if v_statement.status not in ('confirmed', 'partially_settled') then
    raise exception '只有已确认或部分结算的客户对账单可以核销';
  end if;

  if v_transaction.tenant_id is distinct from v_statement.tenant_id
     or v_transaction.customer_id is distinct from v_statement.customer_id then
    raise exception '收款记录与对账单必须属于同一租户和客户';
  end if;

  select coalesce(sum(i.line_amount), 0)::numeric(14, 2)
    into v_statement_amount
  from public.tms_customer_statement_item i
  where i.statement_id = v_statement.id;

  select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
    into v_statement_settled
  from public.tms_cash_allocation a
  where a.statement_id = v_statement.id;

  if new.allocated_amount <= 0 then
    raise exception '核销金额必须大于 0';
  end if;

  if new.allocated_amount > v_transaction.amount - v_transaction.allocated_amount then
    raise exception '核销金额超过本笔收款未核销余额';
  end if;

  if new.allocated_amount > v_statement_amount - v_statement_settled then
    raise exception '核销金额超过对账单未结金额';
  end if;

  v_actor := coalesce(
    nullif(public.get_app_user_display_name(), ''),
    nullif(auth.jwt() ->> 'email', ''),
    'unknown'
  );
  new.tenant_id := v_transaction.tenant_id;
  new.customer_id := v_transaction.customer_id;
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

create or replace function app_private.trg_sync_tms_cash_allocation_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction_id uuid;
  v_statement_id uuid;
  v_transaction_amount numeric(14, 2);
  v_transaction_allocated numeric(14, 2);
  v_statement_amount numeric(14, 2);
  v_statement_settled numeric(14, 2);
begin
  v_transaction_id := new.transaction_id;
  v_statement_id := new.statement_id;

  select t.amount
    into v_transaction_amount
  from public.tms_cash_transaction t
  where t.id = v_transaction_id;

  select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
    into v_transaction_allocated
  from public.tms_cash_allocation a
  where a.transaction_id = v_transaction_id;

  select coalesce(sum(i.line_amount), 0)::numeric(14, 2)
    into v_statement_amount
  from public.tms_customer_statement_item i
  where i.statement_id = v_statement_id;

  select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
    into v_statement_settled
  from public.tms_cash_allocation a
  where a.statement_id = v_statement_id;

  update public.tms_customer_statement
  set
    settled_amount = v_statement_settled,
    status = case
      when v_statement_settled = 0 then 'confirmed'
      when v_statement_settled < v_statement_amount then 'partially_settled'
      else 'settled'
    end
  where id = v_statement_id;

  update public.tms_cash_transaction
  set
    allocated_amount = v_transaction_allocated,
    status = case
      when v_transaction_allocated = 0 then 'pending_allocation'
      when v_transaction_allocated < v_transaction_amount then 'partially_allocated'
      else 'allocated'
    end
  where id = v_transaction_id;

  return new;
end;
$$;

revoke all on function app_private.trg_sync_tms_cash_allocation_totals() from public;

create or replace function public.trg_validate_tms_customer_statement()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_customer_tenant_id uuid;
  v_customer_name text;
  v_expected_settled numeric(14, 2);
  v_statement_amount numeric(14, 2);
  v_expected_status text;
  v_actor text;
begin
  select c.tenant_id, c.customer_name
    into v_customer_tenant_id, v_customer_name
  from public.tms_customer c
  where c.id = new.customer_id;

  if not found then
    raise exception '对账客户不存在';
  end if;

  if new.period_start > new.period_end then
    raise exception '账期开始日期不能晚于结束日期';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_customer_tenant_id;
    new.customer_name_snapshot := v_customer_name;
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
    raise exception '已作废对账单不可修改';
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.statement_no is distinct from old.statement_no
     or new.customer_id is distinct from old.customer_id
     or new.customer_name_snapshot is distinct from old.customer_name_snapshot
     or new.period_start is distinct from old.period_start
     or new.period_end is distinct from old.period_end then
    raise exception '对账单客户、账期和单号不可修改';
  end if;

  if new.settled_amount is distinct from old.settled_amount then
    select coalesce(sum(a.allocated_amount) filter (where a.is_active), 0)::numeric(14, 2)
      into v_expected_settled
    from public.tms_cash_allocation a
    where a.statement_id = new.id;

    select coalesce(sum(i.line_amount), 0)::numeric(14, 2)
      into v_statement_amount
    from public.tms_customer_statement_item i
    where i.statement_id = new.id;

    if new.settled_amount is distinct from v_expected_settled then
      raise exception '已结金额必须等于有效收款核销明细合计';
    end if;

    v_expected_status := case
      when v_expected_settled = 0 then 'confirmed'
      when v_expected_settled < v_statement_amount then 'partially_settled'
      else 'settled'
    end;

    if new.status is distinct from v_expected_status then
      raise exception '对账单状态与已结金额不一致';
    end if;
  end if;

  if new.status = 'voided' and new.settled_amount > 0 then
    raise exception '已核销对账单不能作废，请先撤销全部核销';
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
    or (old.status = 'settled' and new.status in ('confirmed', 'partially_settled', 'voided'))
  ) then
    raise exception '不允许的对账单状态流转：% -> %', old.status, new.status;
  end if;

  v_actor := coalesce(
    nullif(public.get_app_user_display_name(), ''),
    nullif(auth.jwt() ->> 'email', ''),
    'unknown'
  );

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

drop trigger if exists tms_cash_transaction_create_audit on public.tms_cash_transaction;
create trigger tms_cash_transaction_create_audit
before insert on public.tms_cash_transaction
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_cash_transaction_update_audit on public.tms_cash_transaction;
create trigger tms_cash_transaction_update_audit
before update on public.tms_cash_transaction
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_cash_transaction_validate on public.tms_cash_transaction;
create trigger tms_cash_transaction_validate
before insert or update on public.tms_cash_transaction
for each row execute function public.trg_validate_tms_cash_transaction();

drop trigger if exists tms_cash_allocation_create_audit on public.tms_cash_allocation;
create trigger tms_cash_allocation_create_audit
before insert on public.tms_cash_allocation
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_cash_allocation_update_audit on public.tms_cash_allocation;
create trigger tms_cash_allocation_update_audit
before update on public.tms_cash_allocation
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_cash_allocation_validate on public.tms_cash_allocation;
create trigger tms_cash_allocation_validate
before insert or update on public.tms_cash_allocation
for each row execute function public.trg_validate_tms_cash_allocation();

drop trigger if exists tms_cash_allocation_sync_totals on public.tms_cash_allocation;
create trigger tms_cash_allocation_sync_totals
after insert or update of is_active on public.tms_cash_allocation
for each row execute function app_private.trg_sync_tms_cash_allocation_totals();

alter table public.tms_cash_transaction enable row level security;
alter table public.tms_cash_allocation enable row level security;

drop policy if exists tms_cash_transaction_tenant_select on public.tms_cash_transaction;
create policy tms_cash_transaction_tenant_select
on public.tms_cash_transaction for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_cash_transaction_tenant_insert on public.tms_cash_transaction;
create policy tms_cash_transaction_tenant_insert
on public.tms_cash_transaction for insert to authenticated
with check (
  app_private.is_platform_super()
  or tenant_id = app_private.current_user_tenant_id()
);

drop policy if exists tms_cash_transaction_tenant_update on public.tms_cash_transaction;
create policy tms_cash_transaction_tenant_update
on public.tms_cash_transaction for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status <> 'voided'
)
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_cash_allocation_tenant_select on public.tms_cash_allocation;
create policy tms_cash_allocation_tenant_select
on public.tms_cash_allocation for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_cash_allocation_tenant_insert on public.tms_cash_allocation;
create policy tms_cash_allocation_tenant_insert
on public.tms_cash_allocation for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and is_active
);

drop policy if exists tms_cash_allocation_tenant_update on public.tms_cash_allocation;
create policy tms_cash_allocation_tenant_update
on public.tms_cash_allocation for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and is_active
)
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and not is_active
);

create or replace view public.tms_cash_transaction_summary
with (security_invoker = true)
as
select
  t.id,
  t.tenant_id,
  t.transaction_no,
  t.direction,
  t.customer_id,
  t.counterparty_name_snapshot as counterparty_name,
  t.transaction_date,
  t.amount,
  t.allocated_amount,
  greatest(t.amount - t.allocated_amount, 0)::numeric(14, 2) as unallocated_amount,
  count(a.id) filter (where a.is_active)::integer as allocation_count,
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
  t.update_time
from public.tms_cash_transaction t
left join public.tms_cash_allocation a on a.transaction_id = t.id
group by t.id;

create or replace view public.tms_customer_statement_allocatable
with (security_invoker = true)
as
select
  s.id,
  s.tenant_id,
  s.statement_no,
  s.customer_id,
  s.customer_name_snapshot as customer_name,
  s.period_start,
  s.period_end,
  count(i.id)::integer as waybill_count,
  coalesce(sum(i.line_amount), 0)::numeric(14, 2) as statement_amount,
  s.settled_amount,
  greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0)::numeric(14, 2)
    as outstanding_amount,
  s.status,
  s.create_time
from public.tms_customer_statement s
left join public.tms_customer_statement_item i on i.statement_id = s.id
where s.status in ('confirmed', 'partially_settled')
group by s.id
having greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0) > 0;

create or replace function public.create_tms_customer_receipt(
  p_customer_id uuid,
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
  v_customer_tenant_id uuid;
  v_allocation_total numeric(14, 2);
  v_statement_id uuid;
begin
  if p_transaction_date is null then
    raise exception '请选择收款日期';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception '收款金额必须大于 0';
  end if;
  if p_payment_method not in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other') then
    raise exception '请选择正确的收款方式';
  end if;
  if jsonb_typeof(coalesce(p_voucher_urls, '[]'::jsonb)) <> 'array' then
    raise exception '收款凭证格式不正确';
  end if;
  if jsonb_typeof(coalesce(p_allocations, '[]'::jsonb)) <> 'array' then
    raise exception '核销明细格式不正确';
  end if;

  select c.tenant_id
    into v_customer_tenant_id
  from public.tms_customer c
  where c.id = p_customer_id and c.enabled;

  if not found then
    raise exception '收款客户不存在或已停用';
  end if;

  if not app_private.is_platform_super()
     and v_customer_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户登记收款';
  end if;

  select coalesce(sum(item.amount), 0)::numeric(14, 2)
    into v_allocation_total
  from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb))
    as item(statement_id uuid, amount numeric);

  if v_allocation_total > p_amount then
    raise exception '核销合计不能超过收款金额';
  end if;

  for v_statement_id in
    select distinct item.statement_id
    from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb))
      as item(statement_id uuid, amount numeric)
    where item.statement_id is not null
    order by item.statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_statement_id::text, 841327));
  end loop;

  insert into public.tms_cash_transaction (
    tenant_id, direction, customer_id, counterparty_name_snapshot,
    transaction_date, amount, payment_method, bank_reference, voucher_urls, remark
  )
  select
    c.tenant_id, 'receipt', c.id, c.customer_name,
    p_transaction_date, round(p_amount, 2), p_payment_method,
    nullif(btrim(p_bank_reference), ''), coalesce(p_voucher_urls, '[]'::jsonb),
    nullif(btrim(p_remark), '')
  from public.tms_customer c
  where c.id = p_customer_id
  returning id into v_transaction_id;

  insert into public.tms_cash_allocation (
    tenant_id, transaction_id, statement_id, customer_id, allocated_amount, remark
  )
  select
    v_customer_tenant_id,
    v_transaction_id,
    item.statement_id,
    p_customer_id,
    round(sum(item.amount), 2),
    '登记收款时核销'
  from jsonb_to_recordset(coalesce(p_allocations, '[]'::jsonb))
    as item(statement_id uuid, amount numeric)
  where item.statement_id is not null
  group by item.statement_id;

  return v_transaction_id;
end;
$$;

create or replace function public.allocate_tms_customer_receipt(
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

  select t.*
    into v_transaction
  from public.tms_cash_transaction t
  where t.id = p_transaction_id
  for update;

  if not found or v_transaction.direction <> 'receipt' then
    raise exception '客户收款记录不存在';
  end if;
  if v_transaction.status = 'voided' then
    raise exception '已作废收款不能核销';
  end if;

  select coalesce(sum(item.amount), 0)::numeric(14, 2)
    into v_allocation_total
  from jsonb_to_recordset(p_allocations)
    as item(statement_id uuid, amount numeric);

  if v_allocation_total <= 0 then
    raise exception '核销金额必须大于 0';
  end if;
  if v_allocation_total > v_transaction.amount - v_transaction.allocated_amount then
    raise exception '核销合计超过本笔收款未核销余额';
  end if;

  for v_statement_id in
    select distinct item.statement_id
    from jsonb_to_recordset(p_allocations) as item(statement_id uuid, amount numeric)
    where item.statement_id is not null
    order by item.statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_statement_id::text, 841327));
  end loop;

  insert into public.tms_cash_allocation (
    tenant_id, transaction_id, statement_id, customer_id, allocated_amount, remark
  )
  select
    v_transaction.tenant_id,
    v_transaction.id,
    item.statement_id,
    v_transaction.customer_id,
    round(sum(item.amount), 2),
    '追加核销'
  from jsonb_to_recordset(p_allocations) as item(statement_id uuid, amount numeric)
  where item.statement_id is not null
  group by item.statement_id;

  get diagnostics v_inserted_count = row_count;
  if v_inserted_count = 0 then
    raise exception '没有可保存的核销明细';
  end if;
  return v_inserted_count;
end;
$$;

create or replace function public.reverse_tms_cash_allocation(
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
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception '撤销核销原因不能为空';
  end if;

  select a.*
    into v_allocation
  from public.tms_cash_allocation a
  where a.id = p_allocation_id
  for update;

  if not found or not v_allocation.is_active then
    raise exception '有效核销记录不存在或已撤销';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_allocation.transaction_id::text, 841326));
  perform pg_advisory_xact_lock(hashtextextended(v_allocation.statement_id::text, 841327));

  update public.tms_cash_allocation
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
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception '作废原因不能为空';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_transaction_id::text, 841326));

  if exists (
    select 1 from public.tms_cash_allocation a
    where a.transaction_id = p_transaction_id and a.is_active
  ) then
    raise exception '存在有效核销明细，不能作废；请先撤销核销';
  end if;

  update public.tms_cash_transaction
  set status = 'voided', void_reason = btrim(p_reason)
  where id = p_transaction_id and status <> 'voided';

  if not found then
    raise exception '收付款记录不存在或已作废';
  end if;
  return p_transaction_id;
end;
$$;

revoke all on table public.tms_cash_transaction from anon;
revoke all on table public.tms_cash_allocation from anon;
revoke all on table public.tms_cash_transaction_summary from anon;
revoke all on table public.tms_customer_statement_allocatable from anon;

grant select, insert, update on table public.tms_cash_transaction to authenticated;
grant select, insert, update on table public.tms_cash_allocation to authenticated;
grant select on table public.tms_cash_transaction_summary to authenticated;
grant select on table public.tms_customer_statement_allocatable to authenticated;
grant usage, select on sequence public.tms_cash_transaction_no_seq to authenticated;

grant all on table public.tms_cash_transaction to service_role;
grant all on table public.tms_cash_allocation to service_role;
grant select on table public.tms_cash_transaction_summary to service_role;
grant select on table public.tms_customer_statement_allocatable to service_role;
grant all on sequence public.tms_cash_transaction_no_seq to service_role;

revoke all on function public.create_tms_customer_receipt(
  uuid, date, numeric, text, text, jsonb, text, jsonb
) from public, anon;
grant execute on function public.create_tms_customer_receipt(
  uuid, date, numeric, text, text, jsonb, text, jsonb
) to authenticated, service_role;

revoke all on function public.allocate_tms_customer_receipt(uuid, jsonb) from public, anon;
grant execute on function public.allocate_tms_customer_receipt(uuid, jsonb)
  to authenticated, service_role;

revoke all on function public.reverse_tms_cash_allocation(uuid, text) from public, anon;
grant execute on function public.reverse_tms_cash_allocation(uuid, text)
  to authenticated, service_role;

revoke all on function public.void_tms_cash_transaction(uuid, text) from public, anon;
grant execute on function public.void_tms_cash_transaction(uuid, text)
  to authenticated, service_role;

revoke all on function public.trg_validate_tms_cash_transaction()
  from public, anon, authenticated;
revoke all on function public.trg_validate_tms_cash_allocation()
  from public, anon, authenticated;

;
