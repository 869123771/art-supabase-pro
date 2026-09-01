-- 承运商付款申请：申请 -> 审批 -> 实际付款 -> 自动核销。
-- 同时收紧普通用户直接登记付款，并为财务工作台补充关键异常指标。

create sequence if not exists public.tms_carrier_payment_application_no_seq;

create table public.tms_carrier_payment_application (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  application_no text not null default (
    'PA' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.tms_carrier_payment_application_no_seq'::regclass)::text, 6, '0')
  ),
  carrier_id uuid not null references public.tms_carrier(id) on delete restrict,
  carrier_name_snapshot text not null,
  planned_payment_date date not null,
  amount numeric(14, 2) not null check (amount > 0),
  payment_method text not null default 'bank_transfer'
    check (payment_method in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other')),
  basis_urls jsonb not null default '[]'::jsonb check (jsonb_typeof(basis_urls) = 'array'),
  status text not null default 'draft'
    check (status in ('draft', 'pending_review', 'approved', 'rejected', 'paid', 'cancelled')),
  paid_transaction_id uuid,
  submitted_at timestamptz,
  submitted_by text,
  reviewed_at timestamptz,
  reviewed_by text,
  review_remark text,
  paid_at timestamptz,
  paid_by text,
  cancelled_at timestamptz,
  cancelled_by text,
  cancel_reason text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  unique (tenant_id, application_no)
);

create table public.tms_carrier_payment_application_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  application_id uuid not null references public.tms_carrier_payment_application(id) on delete cascade,
  statement_id uuid not null references public.tms_carrier_statement(id) on delete restrict,
  carrier_id uuid not null references public.tms_carrier(id) on delete restrict,
  statement_no_snapshot text not null,
  statement_amount_snapshot numeric(14, 2) not null,
  outstanding_amount_snapshot numeric(14, 2) not null,
  applied_amount numeric(14, 2) not null check (applied_amount > 0),
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  unique (application_id, statement_id)
);

alter table public.tms_cash_transaction
  add column payment_application_id uuid
  references public.tms_carrier_payment_application(id) on delete restrict;

alter table public.tms_carrier_payment_application
  add constraint tms_carrier_payment_application_paid_transaction_fkey
  foreign key (paid_transaction_id) references public.tms_cash_transaction(id) on delete restrict;

create unique index tms_cash_transaction_payment_application_uidx
  on public.tms_cash_transaction(payment_application_id)
  where payment_application_id is not null;
create unique index tms_cash_transaction_bank_reference_uidx
  on public.tms_cash_transaction(tenant_id, direction, bank_reference)
  where bank_reference is not null and btrim(bank_reference) <> '' and status <> 'voided';
create index tms_carrier_payment_application_status_date_idx
  on public.tms_carrier_payment_application(tenant_id, status, planned_payment_date, create_time desc);
create index tms_carrier_payment_application_carrier_idx
  on public.tms_carrier_payment_application(tenant_id, carrier_id, create_time desc);
create index tms_carrier_payment_application_paid_transaction_idx
  on public.tms_carrier_payment_application(paid_transaction_id)
  where paid_transaction_id is not null;
create index tms_carrier_payment_application_item_statement_idx
  on public.tms_carrier_payment_application_item(statement_id, application_id);
create index tms_carrier_payment_application_item_carrier_idx
  on public.tms_carrier_payment_application_item(tenant_id, carrier_id);

alter table public.tms_carrier_payment_application enable row level security;
alter table public.tms_carrier_payment_application_item enable row level security;

create policy tms_carrier_payment_application_tenant_select
on public.tms_carrier_payment_application for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_carrier_payment_application_tenant_insert
on public.tms_carrier_payment_application for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status = 'draft'
);

create policy tms_carrier_payment_application_tenant_update
on public.tms_carrier_payment_application for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status not in ('paid', 'cancelled')
)
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_carrier_payment_application_tenant_delete
on public.tms_carrier_payment_application for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status in ('draft', 'rejected')
);

create policy tms_carrier_payment_application_item_tenant_select
on public.tms_carrier_payment_application_item for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_carrier_payment_application_item_tenant_insert
on public.tms_carrier_payment_application_item for insert to authenticated
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_carrier_payment_application_item_tenant_update
on public.tms_carrier_payment_application_item for update to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_carrier_payment_application_item_tenant_delete
on public.tms_carrier_payment_application_item for delete to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create or replace function public.trg_validate_tms_carrier_payment_application()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_carrier record;
  v_engine text := coalesce(pg_catalog.current_setting('app.workflow_engine', true), 'off');
  v_payment_engine text := coalesce(pg_catalog.current_setting('app.payment_application_engine', true), 'off');
begin
  select c.tenant_id, c.company_name, c.enabled
  into v_carrier
  from public.tms_carrier c
  where c.id = new.carrier_id;
  if not found then raise exception '付款承运商不存在'; end if;
  if (tg_op = 'INSERT' or new.carrier_id is distinct from old.carrier_id) and not v_carrier.enabled then
    raise exception '付款承运商已停用';
  end if;
  if not app_private.is_platform_super()
     and v_carrier.tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户创建付款申请';
  end if;

  new.tenant_id := v_carrier.tenant_id;
  if tg_op = 'INSERT' or new.carrier_id is distinct from old.carrier_id then
    new.carrier_name_snapshot := v_carrier.company_name;
  else
    new.carrier_name_snapshot := old.carrier_name_snapshot;
  end if;
  new.amount := round(new.amount, 2);

  new.remark := nullif(btrim(new.remark), '');
  if new.planned_payment_date is null then raise exception '请选择计划付款日期'; end if;
  if coalesce(new.amount, 0) <= 0 then raise exception '申请付款金额必须大于 0'; end if;
  if jsonb_typeof(coalesce(new.basis_urls, '[]'::jsonb)) <> 'array' then
    raise exception '付款依据格式不正确';
  end if;

  if tg_op = 'UPDATE' then
    if v_engine <> 'on' and (
      new.submitted_at is distinct from old.submitted_at
      or new.submitted_by is distinct from old.submitted_by
      or new.reviewed_at is distinct from old.reviewed_at
      or new.reviewed_by is distinct from old.reviewed_by
      or new.review_remark is distinct from old.review_remark
    ) then raise exception '审批信息只能由审批引擎更新'; end if;
    if v_payment_engine <> 'on' and (
      new.paid_transaction_id is distinct from old.paid_transaction_id
      or new.paid_at is distinct from old.paid_at
      or new.paid_by is distinct from old.paid_by
      or new.cancelled_at is distinct from old.cancelled_at
      or new.cancelled_by is distinct from old.cancelled_by
      or new.cancel_reason is distinct from old.cancel_reason
    ) then raise exception '付款执行信息只能由付款执行服务更新'; end if;
    if old.status not in ('draft', 'rejected') and (
      new.carrier_id is distinct from old.carrier_id
      or new.amount is distinct from old.amount
      or new.planned_payment_date is distinct from old.planned_payment_date
      or new.payment_method is distinct from old.payment_method
      or new.basis_urls is distinct from old.basis_urls
    ) then
      raise exception '审批中或已审批的付款申请不能修改核心信息';
    end if;

    if new.status is distinct from old.status then
      if new.status in ('pending_review', 'approved', 'rejected', 'draft') and v_engine <> 'on' then
        raise exception '付款申请状态必须由审批引擎更新';
      end if;
      if new.status in ('paid', 'cancelled') and v_payment_engine <> 'on' then
        raise exception '付款申请状态必须由付款执行服务更新';
      end if;
      if not (
        (old.status in ('draft', 'rejected') and new.status in ('pending_review', 'cancelled'))
        or (old.status = 'pending_review' and new.status in ('approved', 'rejected', 'draft', 'cancelled'))
        or (old.status = 'approved' and new.status in ('paid', 'cancelled'))
      ) then
        raise exception '不允许将付款申请从 % 变更为 %', old.status, new.status;
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.trg_validate_tms_carrier_payment_application_item()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_app record;
  v_statement record;
  v_statement_amount numeric(14,2);
  v_outstanding numeric(14,2);
begin
  select a.tenant_id, a.carrier_id, a.status into v_app
  from public.tms_carrier_payment_application a
  where a.id = coalesce(new.application_id, old.application_id);
  if not found then raise exception '付款申请不存在'; end if;
  if v_app.status not in ('draft', 'rejected') then
    raise exception '只有草稿或已驳回付款申请可以修改明细';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  select s.tenant_id, s.carrier_id, s.statement_no, s.status, s.settled_amount
  into v_statement
  from public.tms_carrier_statement s where s.id = new.statement_id;
  if not found then raise exception '承运商对账单不存在'; end if;
  if v_statement.tenant_id is distinct from v_app.tenant_id
     or v_statement.carrier_id is distinct from v_app.carrier_id then
    raise exception '付款明细必须属于申请承运商和当前租户';
  end if;
  if v_statement.status not in ('confirmed', 'partially_settled') then
    raise exception '只能选择已确认且未结清的承运商对账单';
  end if;
  select coalesce(sum(i.line_amount) filter (where i.is_active), 0)::numeric(14,2)
  into v_statement_amount
  from public.tms_carrier_statement_item i where i.statement_id = new.statement_id;
  v_outstanding := greatest(v_statement_amount - v_statement.settled_amount, 0)::numeric(14,2);
  if coalesce(new.applied_amount, 0) <= 0 or round(new.applied_amount, 2) > v_outstanding then
    raise exception '申请金额必须大于 0 且不能超过对账单未付余额';
  end if;
  new.tenant_id := v_app.tenant_id;
  new.carrier_id := v_app.carrier_id;
  new.statement_no_snapshot := v_statement.statement_no;
  new.statement_amount_snapshot := v_statement_amount;
  new.outstanding_amount_snapshot := v_outstanding;
  new.applied_amount := round(new.applied_amount, 2);
  return new;
end;
$$;

create trigger tms_carrier_payment_application_validate
before insert or update on public.tms_carrier_payment_application
for each row execute function public.trg_validate_tms_carrier_payment_application();
create trigger tms_carrier_payment_application_create_audit
before insert on public.tms_carrier_payment_application
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger tms_carrier_payment_application_update_audit
before update on public.tms_carrier_payment_application
for each row execute function public.trg_set_update_time_and_by();

create trigger tms_carrier_payment_application_item_validate
before insert or update or delete on public.tms_carrier_payment_application_item
for each row execute function public.trg_validate_tms_carrier_payment_application_item();
create trigger tms_carrier_payment_application_item_create_audit
before insert on public.tms_carrier_payment_application_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger tms_carrier_payment_application_item_update_audit
before update on public.tms_carrier_payment_application_item
for each row execute function public.trg_set_update_time_and_by();

create or replace function public.save_tms_carrier_payment_application(
  p_application_id uuid,
  p_carrier_id uuid,
  p_planned_payment_date date,
  p_amount numeric,
  p_payment_method text,
  p_basis_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_app record;
  v_total numeric(14,2);
  v_statement_id uuid;
begin
  if jsonb_typeof(coalesce(p_allocations, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_allocations, '[]'::jsonb)) = 0 then
    raise exception '请至少选择一份待付款对账单';
  end if;
  select coalesce(sum(x.amount), 0)::numeric(14,2) into v_total
  from jsonb_to_recordset(p_allocations) as x(statement_id uuid, amount numeric);
  if v_total <= 0 or v_total is distinct from round(p_amount, 2) then
    raise exception '付款分配合计必须等于申请金额';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_allocations) as x(statement_id uuid, amount numeric)
    where x.statement_id is null or coalesce(x.amount,0) <= 0
  ) then raise exception '付款分配明细不完整'; end if;

  for v_statement_id in
    select distinct x.statement_id
    from jsonb_to_recordset(p_allocations) as x(statement_id uuid, amount numeric)
    order by 1
  loop

    perform pg_advisory_xact_lock(hashtextextended(v_statement_id::text, 841329));
  end loop;

  if p_application_id is null then
    insert into public.tms_carrier_payment_application(
      carrier_id, planned_payment_date, amount, payment_method, basis_urls, remark
    ) values (
      p_carrier_id, p_planned_payment_date, round(p_amount,2), p_payment_method,
      coalesce(p_basis_urls,'[]'::jsonb), nullif(btrim(p_remark),'')
    ) returning id into v_id;
  else
    select * into v_app from public.tms_carrier_payment_application
    where id = p_application_id for update;
    if not found then raise exception '付款申请不存在'; end if;
    if v_app.status not in ('draft','rejected') then raise exception '当前付款申请不能编辑'; end if;
    update public.tms_carrier_payment_application set
      carrier_id=p_carrier_id, planned_payment_date=p_planned_payment_date,
      amount=round(p_amount,2), payment_method=p_payment_method,
      basis_urls=coalesce(p_basis_urls,'[]'::jsonb), remark=nullif(btrim(p_remark),'')
    where id=p_application_id;
    delete from public.tms_carrier_payment_application_item where application_id=p_application_id;
    v_id := p_application_id;
  end if;

  insert into public.tms_carrier_payment_application_item(
    application_id, statement_id, carrier_id,
    statement_no_snapshot, statement_amount_snapshot, outstanding_amount_snapshot, applied_amount
  )
  select v_id, x.statement_id, p_carrier_id, '', 0, 0, round(sum(x.amount),2)
  from jsonb_to_recordset(p_allocations) as x(statement_id uuid, amount numeric)
  group by x.statement_id;
  return v_id;
end;
$$;

create or replace function public.validate_tms_carrier_payment_application_submission(p_application_id uuid)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_app record;
  v_item record;
  v_item_count integer;
  v_total numeric(14,2);
  v_outstanding numeric(14,2);
  v_reserved numeric(14,2);
begin
  select * into v_app from public.tms_carrier_payment_application
  where id=p_application_id for update;
  if not found then raise exception '付款申请不存在'; end if;
  if v_app.status not in ('draft','rejected') then raise exception '只有草稿或已驳回申请可以提交审批'; end if;
  if not app_private.is_platform_super() and v_app.tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权提交其他租户付款申请';
  end if;
  select count(*)::integer, coalesce(sum(applied_amount),0)::numeric(14,2)
  into v_item_count, v_total
  from public.tms_carrier_payment_application_item where application_id=p_application_id;
  if v_item_count < 1 then raise exception '请至少选择一份待付款对账单'; end if;
  if v_total is distinct from v_app.amount then raise exception '付款分配合计必须等于申请金额'; end if;

  for v_item in
    select i.*, s.status statement_status, s.settled_amount,
      coalesce((select sum(si.line_amount) from public.tms_carrier_statement_item si
                where si.statement_id=s.id and si.is_active),0)::numeric(14,2) statement_amount
    from public.tms_carrier_payment_application_item i
    join public.tms_carrier_statement s on s.id=i.statement_id
    where i.application_id=p_application_id order by i.statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_item.statement_id::text, 841329));
    if v_item.statement_status not in ('confirmed','partially_settled') then
      raise exception '对账单 % 当前状态不允许付款', v_item.statement_no_snapshot;
    end if;
    v_outstanding := greatest(v_item.statement_amount-v_item.settled_amount,0)::numeric(14,2);
    select coalesce(sum(i.applied_amount),0)::numeric(14,2) into v_reserved
    from public.tms_carrier_payment_application_item i
    join public.tms_carrier_payment_application a on a.id=i.application_id
    where i.statement_id=v_item.statement_id
      and a.status in ('pending_review','approved')
      and a.id<>p_application_id;
    if v_item.applied_amount > v_outstanding-v_reserved then
      raise exception '对账单 % 可申请余额不足，当前可申请 %',
        v_item.statement_no_snapshot, greatest(v_outstanding-v_reserved,0);
    end if;
  end loop;
  return true;
end;
$$;

create or replace function public.delete_tms_carrier_payment_application(p_application_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_app record;
begin
  select * into v_app from public.tms_carrier_payment_application where id=p_application_id for update;
  if not found then raise exception '付款申请不存在'; end if;
  if v_app.status not in ('draft','rejected') then raise exception '只有草稿或已驳回申请可以删除'; end if;
  delete from public.tms_carrier_payment_application where id=p_application_id;
  return p_application_id;
end; $$;

create or replace function public.cancel_tms_carrier_payment_application(p_application_id uuid, p_reason text)
returns uuid language plpgsql set search_path='' as $$
declare v_app record;
begin
  if nullif(btrim(p_reason),'') is null then raise exception '请填写取消原因'; end if;
  select * into v_app from public.tms_carrier_payment_application where id=p_application_id for update;
  if not found then raise exception '付款申请不存在'; end if;
  if v_app.status <> 'approved' then raise exception '只有已批准且未付款的申请可以取消'; end if;
  perform pg_catalog.set_config('app.payment_application_engine','on',true);
  update public.tms_carrier_payment_application set status='cancelled', cancelled_at=now(),
    cancelled_by=coalesce(auth.jwt()->>'email',auth.uid()::text), cancel_reason=nullif(btrim(p_reason),'')
  where id=p_application_id;
  return p_application_id;
end; $$;

create or replace function public.trg_guard_tms_cash_payment_application()
returns trigger language plpgsql set search_path='' as $$
declare v_app record;
begin
  if tg_op <> 'INSERT' or new.direction <> 'payment' then return new; end if;
  if new.payment_application_id is null then
    if not app_private.is_platform_super() then
      raise exception '承运商付款必须先提交付款申请并完成审批';
    end if;
    return new;
  end if;
  if coalesce(pg_catalog.current_setting('app.payment_application_engine',true),'off') <> 'on' then
    raise exception '付款流水只能由已批准付款申请生成';
  end if;
  select * into v_app from public.tms_carrier_payment_application
  where id=new.payment_application_id for update;
  if not found or v_app.status <> 'approved' then raise exception '付款申请不存在或尚未批准'; end if;
  if new.tenant_id is distinct from v_app.tenant_id
     or new.carrier_id is distinct from v_app.carrier_id
     or round(new.amount,2) is distinct from v_app.amount then
    raise exception '付款流水与付款申请的租户、承运商或金额不一致';
  end if;
  return new;
end; $$;

create trigger tms_cash_transaction_payment_application_guard
before insert on public.tms_cash_transaction
for each row execute function public.trg_guard_tms_cash_payment_application();

create or replace function public.trg_guard_tms_carrier_allocation_reservation()
returns trigger language plpgsql set search_path='' as $$
declare
  v_statement record;
  v_statement_amount numeric(14,2);
  v_reserved numeric(14,2);
  v_own_application uuid;
begin
  if tg_op <> 'INSERT' or not new.is_active then return new; end if;
  select t.payment_application_id into v_own_application
  from public.tms_cash_transaction t where t.id=new.transaction_id;
  select s.settled_amount into v_statement
  from public.tms_carrier_statement s where s.id=new.statement_id for update;
  if not found then return new; end if;
  select coalesce(sum(i.line_amount) filter(where i.is_active),0)::numeric(14,2)
  into v_statement_amount from public.tms_carrier_statement_item i where i.statement_id=new.statement_id;

  select coalesce(sum(i.applied_amount),0)::numeric(14,2) into v_reserved
  from public.tms_carrier_payment_application_item i
  join public.tms_carrier_payment_application a on a.id=i.application_id
  where i.statement_id=new.statement_id and a.status in ('pending_review','approved')
    and (v_own_application is null or a.id<>v_own_application);
  if new.allocated_amount > greatest(v_statement_amount-v_statement.settled_amount-v_reserved,0) then
    raise exception '本次核销将占用其他审批中或已批准付款申请的预留额度';
  end if;
  return new;
end; $$;

create trigger tms_carrier_cash_allocation_reservation_guard
before insert on public.tms_carrier_cash_allocation
for each row execute function public.trg_guard_tms_carrier_allocation_reservation();

create or replace function public.execute_tms_carrier_payment_application(
  p_application_id uuid,
  p_transaction_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
set search_path=''
as $$
declare
  v_app record;
  v_transaction_id uuid;
  v_item record;
begin
  if p_transaction_date is null then raise exception '请选择实际付款日期'; end if;
  if jsonb_typeof(coalesce(p_voucher_urls,'[]'::jsonb)) <> 'array' then raise exception '付款凭证格式不正确'; end if;
  select * into v_app from public.tms_carrier_payment_application
  where id=p_application_id for update;
  if not found then raise exception '付款申请不存在'; end if;
  if v_app.status <> 'approved' then raise exception '只有已批准且未付款的申请可以登记付款'; end if;
  if not app_private.is_platform_super() and v_app.tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权执行其他租户付款申请';
  end if;
  if v_app.payment_method='bank_transfer' and nullif(btrim(p_bank_reference),'') is null then
    raise exception '银行转账必须填写银行流水号';
  end if;

  perform pg_catalog.set_config('app.payment_application_engine','on',true);
  insert into public.tms_cash_transaction(
    tenant_id, transaction_no, direction, carrier_id, counterparty_name_snapshot,
    transaction_date, amount, payment_method, bank_reference, voucher_urls, remark,
    payment_application_id
  ) values (
    v_app.tenant_id,
    'CP'||to_char(clock_timestamp(),'YYYYMMDD')||'-'||lpad(nextval('public.tms_cash_transaction_no_seq'::regclass)::text,6,'0'),
    'payment',v_app.carrier_id,v_app.carrier_name_snapshot,p_transaction_date,v_app.amount,
    v_app.payment_method,nullif(btrim(p_bank_reference),''),coalesce(p_voucher_urls,'[]'::jsonb),
    '付款申请 '||v_app.application_no||coalesce(' · '||nullif(v_app.remark,''),''),v_app.id
  ) returning id into v_transaction_id;

  for v_item in
    select * from public.tms_carrier_payment_application_item
    where application_id=v_app.id order by statement_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_item.statement_id::text,841329));
    insert into public.tms_carrier_cash_allocation(
      tenant_id,transaction_id,statement_id,carrier_id,allocated_amount,remark
    ) values (
      v_app.tenant_id,v_transaction_id,v_item.statement_id,v_app.carrier_id,
      v_item.applied_amount,'按付款申请 '||v_app.application_no||' 自动核销'
    );
  end loop;
  if not found then raise exception '付款申请没有可执行的核销明细'; end if;

  update public.tms_carrier_payment_application set
    status='paid',paid_transaction_id=v_transaction_id,paid_at=now(),
    paid_by=coalesce(auth.jwt()->>'email',auth.uid()::text)
  where id=v_app.id;
  return v_transaction_id;
end;
$$;

create or replace view public.tms_carrier_payment_application_summary
with (security_invoker=true)
as
select
  a.id,a.tenant_id,a.application_no,a.carrier_id,
  a.carrier_name_snapshot as carrier_name,a.planned_payment_date,a.amount,
  a.payment_method,a.basis_urls,a.status,a.paid_transaction_id,
  t.transaction_no as paid_transaction_no,
  count(i.id)::integer as statement_count,
  coalesce(string_agg(i.statement_no_snapshot, '、' order by i.statement_no_snapshot),'') as statement_nos,
  a.submitted_at,a.submitted_by,a.reviewed_at,a.reviewed_by,a.review_remark,
  a.paid_at,a.paid_by,a.cancelled_at,a.cancelled_by,a.cancel_reason,a.remark,
  a.create_by,a.create_time,a.update_by,a.update_time
from public.tms_carrier_payment_application a
left join public.tms_carrier_payment_application_item i on i.application_id=a.id
left join public.tms_cash_transaction t on t.id=a.paid_transaction_id
group by a.id,t.transaction_no;

create or replace view public.tms_cash_transaction_summary
with (security_invoker=true)
as
select
  t.id,t.tenant_id,t.transaction_no,t.direction,t.customer_id,t.carrier_id,
  t.counterparty_name_snapshot as counterparty_name,t.transaction_date,t.amount,t.allocated_amount,
  greatest(t.amount-t.allocated_amount,0)::numeric(14,2) as unallocated_amount,
  case when t.direction='receipt' then
    (select count(*)::integer from public.tms_cash_allocation a where a.transaction_id=t.id and a.is_active)
  else
    (select count(*)::integer from public.tms_carrier_cash_allocation a where a.transaction_id=t.id and a.is_active)
  end as allocation_count,
  t.payment_method,t.bank_reference,t.voucher_urls,t.status,t.voided_at,t.voided_by,t.void_reason,
  t.remark,t.create_by,t.create_time,t.update_by,t.update_time,t.payment_application_id
from public.tms_cash_transaction t;

create or replace view public.tms_carrier_statement_allocatable
with (security_invoker=true)
as
with statement_base as (
  select s.id,s.tenant_id,s.statement_no,s.carrier_id,s.carrier_name_snapshot,
    s.period_start,s.period_end,s.settled_amount,s.status,s.create_time,
    count(i.id) filter(where i.is_active)::integer as cost_count,
    count(distinct i.waybill_id) filter(where i.is_active)::integer as waybill_count,
    coalesce(sum(i.line_amount) filter(where i.is_active),0)::numeric(14,2) as statement_amount
  from public.tms_carrier_statement s
  left join public.tms_carrier_statement_item i on i.statement_id=s.id
  group by s.id
), reservation as (
  select i.statement_id,coalesce(sum(i.applied_amount),0)::numeric(14,2) reserved_amount
  from public.tms_carrier_payment_application_item i
  join public.tms_carrier_payment_application a on a.id=i.application_id
  where a.status in ('pending_review','approved') group by i.statement_id
)
select b.id,b.tenant_id,b.statement_no,b.carrier_id,b.carrier_name_snapshot as carrier_name,
  b.period_start,b.period_end,b.cost_count,b.waybill_count,b.statement_amount,b.settled_amount,
  greatest(b.statement_amount-b.settled_amount-coalesce(r.reserved_amount,0),0)::numeric(14,2) as outstanding_amount,
  b.status,b.create_time,
  greatest(b.statement_amount-b.settled_amount,0)::numeric(14,2) as statement_outstanding_amount,
  coalesce(r.reserved_amount,0)::numeric(14,2) as reserved_amount
from statement_base b left join reservation r on r.statement_id=b.id
where b.status in ('confirmed','partially_settled')
  and greatest(b.statement_amount-b.settled_amount-coalesce(r.reserved_amount,0),0)>0;

create or replace view public.tms_finance_exception_summary
with (security_invoker=true)
as
select
  (select count(*)::integer from public.tms_carrier_payment_application a where a.status='pending_review')
    as pending_payment_application_count,
  coalesce((select sum(a.amount) from public.tms_carrier_payment_application a where a.status='pending_review'),0)::numeric(14,2)
    as pending_payment_application_amount,
  (select count(*)::integer from public.tms_carrier_payment_application a where a.status='approved')
    as approved_unpaid_payment_count,
  coalesce((select sum(a.amount) from public.tms_carrier_payment_application a where a.status='approved'),0)::numeric(14,2)
    as approved_unpaid_payment_amount,
  (select count(*)::integer from public.tms_cash_transaction t
    where t.direction='payment' and t.status<>'voided' and t.payment_application_id is null)
    as unapproved_payment_count,
  coalesce((select sum(t.amount) from public.tms_cash_transaction t
    where t.direction='payment' and t.status<>'voided' and t.payment_application_id is null),0)::numeric(14,2)
    as unapproved_payment_amount,
  (select count(*)::integer from public.tms_customer_statement_summary s
    where s.status in ('confirmed','partially_settled') and s.outstanding_amount>0

      and s.period_end < current_date-30) as overdue_receivable_count,
  coalesce((select sum(s.outstanding_amount) from public.tms_customer_statement_summary s
    where s.status in ('confirmed','partially_settled') and s.outstanding_amount>0
      and s.period_end < current_date-30),0)::numeric(14,2) as overdue_receivable_amount,
  (select count(*)::integer from public.tms_customer_statement_summary s
    where s.status in ('confirmed','partially_settled','settled')
      and greatest(s.statement_amount-coalesce((
        select sum(l.linked_amount) from public.tms_invoice_statement_link l
        join public.tms_invoice inv on inv.id=l.invoice_id
        where l.customer_statement_id=s.id and inv.direction='output' and inv.status<>'voided'
      ),0),0)>0) as uninvoiced_receivable_count,
  coalesce((select sum(greatest(s.statement_amount-coalesce((
        select sum(l.linked_amount) from public.tms_invoice_statement_link l
        join public.tms_invoice inv on inv.id=l.invoice_id
        where l.customer_statement_id=s.id and inv.direction='output' and inv.status<>'voided'
      ),0),0)) from public.tms_customer_statement_summary s
    where s.status in ('confirmed','partially_settled','settled')),0)::numeric(14,2)
    as uninvoiced_receivable_amount;

-- 保留既有业务回调实现，并以同名分发器接入付款申请，避免复制其他业务的状态机。
alter function app_private.execute_workflow_business_callback(text,uuid,text,text,text)
  rename to execute_workflow_business_callback_legacy;

create or replace function app_private.execute_carrier_payment_application_workflow_callback(
  p_business_id uuid,p_status text,p_actor text,p_comment text
)
returns void language plpgsql security definer set search_path='' as $$
declare v_app record;
begin
  select * into v_app from public.tms_carrier_payment_application
  where id=p_business_id for update;
  if not found then raise exception '付款申请不存在或已被删除'; end if;
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  if p_status='running' then
    perform public.validate_tms_carrier_payment_application_submission(p_business_id);
    update public.tms_carrier_payment_application set
      status='pending_review',submitted_at=now(),submitted_by=p_actor,
      reviewed_at=null,reviewed_by=null,review_remark=null
    where id=p_business_id;
  elsif p_status='approved' then
    update public.tms_carrier_payment_application set
      status='approved',reviewed_at=now(),reviewed_by=p_actor,
      review_remark=nullif(btrim(coalesce(p_comment,'')),'')
    where id=p_business_id;
  elsif p_status='rejected' then
    update public.tms_carrier_payment_application set
      status='rejected',reviewed_at=now(),reviewed_by=p_actor,
      review_remark=nullif(btrim(coalesce(p_comment,'')),'')
    where id=p_business_id;
  elsif p_status in ('withdrawn','cancelled') then
    update public.tms_carrier_payment_application set
      status='draft',reviewed_at=now(),reviewed_by=p_actor,
      review_remark=nullif(btrim(coalesce(p_comment,'')),'')
    where id=p_business_id;
  end if;
end; $$;

create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,p_business_id uuid,p_status text,p_actor text,p_comment text
)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_business_type='tms_carrier_payment_application' then
    perform app_private.execute_carrier_payment_application_workflow_callback(
      p_business_id,p_status,p_actor,p_comment
    );
  else
    perform app_private.execute_workflow_business_callback_legacy(
      p_business_type,p_business_id,p_status,p_actor,p_comment
    );
  end if;
end; $$;

create or replace function app_private.get_carrier_payment_application_workflow_snapshot(p_instance_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_i public.wf_instance; v_a record; v_warnings jsonb:='[]'::jsonb;
begin
  if (select auth.uid()) is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode='42501';
  end if;
  select * into v_i from public.wf_instance where id=p_instance_id;
  if not found then raise exception '审批实例不存在'; end if;
  select a.*,
    (select count(*)::integer from public.tms_carrier_payment_application_item i where i.application_id=a.id) statement_count,
    (select coalesce(string_agg(i.statement_no_snapshot,'、' order by i.statement_no_snapshot),'')
       from public.tms_carrier_payment_application_item i where i.application_id=a.id) statement_nos
  into v_a from public.tms_carrier_payment_application a where a.id=v_i.business_id;
  if not found then
    return jsonb_build_object('instanceId',v_i.id,'businessType',v_i.business_type,
      'businessId',v_i.business_id,'title',v_i.business_title,'metrics','[]'::jsonb,
      'fields','[]'::jsonb,'warnings',jsonb_build_array('业务原单已删除，当前仅展示流程快照'),
      'attachments','[]'::jsonb);
  end if;
  if v_i.status='running' and not exists(
    select 1 from public.wf_task t where t.instance_id=v_i.id and t.status='pending'
  ) then v_warnings:=jsonb_build_array('流程运行中但当前没有待办任务，请联系审批管理员检查流程条件。'); end if;
  return jsonb_build_object(
    'instanceId',v_i.id,'businessType',v_i.business_type,'businessId',v_i.business_id,
    'title',v_i.business_title,'subtitle',v_a.carrier_name_snapshot,
    'businessNo',v_a.application_no,'status',v_a.status,
    'routePath','/tms-transportation/finance-center/payment-application',
    'metrics',jsonb_build_array(
      jsonb_build_object('label','申请金额','value','¥ '||to_char(v_a.amount,'FM999,999,990.00'),'tone','warning'),
      jsonb_build_object('label','关联对账单','value',v_a.statement_count::text||' 份','tone','primary'),
      jsonb_build_object('label','计划付款日','value',v_a.planned_payment_date::text,'tone','info')
    ),
    'fields',jsonb_build_array(
      jsonb_build_object('label','申请单号','value',v_a.application_no),
      jsonb_build_object('label','付款承运商','value',v_a.carrier_name_snapshot),
      jsonb_build_object('label','关联对账单','value',coalesce(nullif(v_a.statement_nos,''),'--')),
      jsonb_build_object('label','付款方式','value',v_a.payment_method),
      jsonb_build_object('label','备注','value',coalesce(v_a.remark,'--'))
    ),'warnings',v_warnings,'attachments',app_private.workflow_attachment_list(v_a.basis_urls)
  );
end; $$;

create or replace function app_private.get_workflow_business_snapshot_v2(p_instance_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_type text;
begin
  select business_type into v_type from public.wf_instance where id=p_instance_id;
  if v_type='tms_carrier_payment_application' then
    return app_private.get_carrier_payment_application_workflow_snapshot(p_instance_id);
  end if;
  return app_private.get_workflow_business_snapshot(p_instance_id);
end; $$;

create or replace function public.get_workflow_business_snapshot(p_instance_id uuid)
returns jsonb language sql stable set search_path='' as $$
  select app_private.get_workflow_business_snapshot_v2(p_instance_id)
$$;

create or replace function app_private.validate_workflow_business_config(p_business_type text,p_config jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare v_node jsonb; v_operator text; v_field text; v_allowed_fields text[];
begin
  perform app_private.validate_workflow_config(p_config);
  if p_config?'allowAutoApprove' and jsonb_typeof(p_config->'allowAutoApprove')<>'boolean' then
    raise exception '全条件未命中策略必须是布尔值';
  end if;
  v_allowed_fields:=case p_business_type
    when 'tms_waybill_cost' then array['amount','costType','payeeName','waybillNo','occurredOn']
    when 'tms_invoice' then array['direction','invoiceType','invoiceNo','totalAmount','taxRate','counterpartyName']
    when 'tms_carrier_payment_application' then array['amount','applicationNo','carrierId','carrierName','plannedPaymentDate','statementCount']
    when 'tms_carrier_statement' then array['statementNo','statementAmount','carrierId','carrierName','costCount','settledAmount']
    when 'tms_customer_statement' then array['statementNo','statementAmount','customerId','customerName','waybillCount','settledAmount']
    when 'tms_contract' then array['contractNo','contractAmount','carrierId','billingMethod','signTime','handler']
    when 'vehicle_archive' then array['plateNo','companyName','vehicleType','approvedLoadMass','operationType','isNewEnergy']
    else null end;
  for v_node in select value from jsonb_array_elements(p_config->'nodes') loop
    v_operator:=coalesce(v_node#>>'{condition,operator}','always');
    if v_operator<>'always' then
      v_field:=btrim(coalesce(v_node#>>'{condition,field}',''));
      if v_field='' then raise exception '节点“%”必须选择条件字段',v_node->>'name'; end if;
      if v_allowed_fields is not null and not(v_field=any(v_allowed_fields)) then
        raise exception '节点“%”使用了业务类型 % 不支持的条件字段 %',v_node->>'name',p_business_type,v_field;
      end if;
      if v_operator='in' and jsonb_typeof(v_node#>'{condition,value}')<>'array' then
        raise exception '节点“%”的“属于”比较值必须是非空数组',v_node->>'name';
      end if;

      if v_operator='in' and jsonb_array_length(v_node#>'{condition,value}')=0 then
        raise exception '节点“%”的“属于”比较值不能为空',v_node->>'name';
      end if;
    end if;
  end loop;
end; $$;

do $$
declare
  v_tenant_id uuid := app_private.default_register_tenant_id();
  v_definition_id uuid;
  v_version_id uuid;
  v_finance_user_id uuid;
  v_manager_user_id uuid;
  v_config jsonb;
begin
  select u.id into v_finance_user_id from public.sys_user u
  where u.tenant_id=v_tenant_id and u.user_name='979260464' order by u.create_time limit 1;
  select u.id into v_manager_user_id from public.sys_user u
  where u.tenant_id=v_tenant_id and u.user_name='Helen' order by u.create_time limit 1;
  if v_finance_user_id is null or v_manager_user_id is null then
    raise exception '无法创建付款审批流程：缺少财务审核人或负责人';
  end if;
  v_config:=jsonb_build_object(
    'allowAutoApprove',false,
    'nodes',jsonb_build_array(
      jsonb_build_object(
        'key','finance-review','name','财务审核','order',1,
        'assignee',jsonb_build_object('type','users','userIds',jsonb_build_array(v_finance_user_id),'roleCodes','[]'::jsonb),
        'dueHours',24,'condition',jsonb_build_object('operator','always'),'approvalMode','any',
        'allowSelfApproval',false,'escalationEnabled',true,'rejectVetoEnabled',true,
        'escalateAfterHours',4,'reminderBeforeMinutes',60,'approvalThresholdPercent',100
      ),
      jsonb_build_object(
        'key','manager-review','name','负责人复核','order',2,
        'assignee',jsonb_build_object('type','users','userIds',jsonb_build_array(v_manager_user_id),'roleCodes','[]'::jsonb),
        'dueHours',12,'condition',jsonb_build_object('field','amount','operator','gt','value',50000),
        'approvalMode','any','allowSelfApproval',false,'escalationEnabled',true,'rejectVetoEnabled',true,
        'escalateAfterHours',2,'reminderBeforeMinutes',60,'approvalThresholdPercent',100
      )
    )
  );
  insert into public.wf_definition(
    tenant_id,code,name,business_type,description,status,published_at,published_by,create_by
  ) values (
    v_tenant_id,'tms-carrier-payment-approval','承运商付款审批','tms_carrier_payment_application',
    '承运商付款申请统一审批；超过 5 万元增加负责人复核。','published',now(),'system','system'
  ) returning id into v_definition_id;
  insert into public.wf_version(
    tenant_id,definition_id,version_no,status,config,change_note,published_at,published_by,create_by
  ) values (
    v_tenant_id,v_definition_id,1,'published',v_config,'付款执行闭环初始版本',now(),'system','system'
  ) returning id into v_version_id;
  update public.wf_definition set current_version_id=v_version_id where id=v_definition_id;
end;
$$;

-- 财务中心导航：在承运商对账后加入付款申请，并继承收付款管理的角色可见性。
update public.sys_menu set sort=sort+1,update_time=now(),update_by='system'
where parent_id='a1000000-0000-4000-8000-000000000001'::uuid and sort>=4;
insert into public.sys_menu(
  id,name,path,component,meta,sort,parent_id,type,create_by,update_by
) values (
  'a1000000-0000-4000-8000-000000000009','TmsCarrierPaymentApplication','payment-application',
  '/tms-transportation/finance-center/payment-application',
  '{"icon":"ri:secure-payment-line","title":"付款申请","is_enable":true,"keep_alive":true}'::jsonb,
  4,'a1000000-0000-4000-8000-000000000001','menu','system','system'
);
insert into public.sys_role_menu(tenant_id,role_id,menu_id,permission,create_by,update_by)
select rm.tenant_id,rm.role_id,'a1000000-0000-4000-8000-000000000009'::uuid,
  rm.permission,'system','system'
from public.sys_role_menu rm
where rm.menu_id='a1000000-0000-4000-8000-000000000005'::uuid
  and not exists(
    select 1 from public.sys_role_menu x where x.role_id=rm.role_id
      and x.menu_id='a1000000-0000-4000-8000-000000000009'::uuid
  );

insert into public.sys_dict_type(
  id,name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort,remark
) values (
  'b1000000-0000-4000-8000-00000000000c','付款申请状态','tmsCarrierPaymentApplicationStatus',
  '1','system','system',app_private.platform_tenant_id(),
  'b1000000-0000-4000-8000-000000000001','dictionary',8,'承运商付款申请状态'
);
insert into public.sys_dictionary(
  id,type_id,code,status,create_by,update_by,value,label,sort,tenant_id,tag_type
) values
('b1100000-0000-4000-8000-000000000091','b1000000-0000-4000-8000-00000000000c','draft','1','system','system','draft','草稿',1,app_private.platform_tenant_id(),'info'),
('b1100000-0000-4000-8000-000000000092','b1000000-0000-4000-8000-00000000000c','pending_review','1','system','system','pending_review','审批中',2,app_private.platform_tenant_id(),'warning'),
('b1100000-0000-4000-8000-000000000093','b1000000-0000-4000-8000-00000000000c','approved','1','system','system','approved','已批准待付款',3,app_private.platform_tenant_id(),'primary'),
('b1100000-0000-4000-8000-000000000094','b1000000-0000-4000-8000-00000000000c','rejected','1','system','system','rejected','已驳回',4,app_private.platform_tenant_id(),'danger'),
('b1100000-0000-4000-8000-000000000095','b1000000-0000-4000-8000-00000000000c','paid','1','system','system','paid','已付款',5,app_private.platform_tenant_id(),'success'),
('b1100000-0000-4000-8000-000000000096','b1000000-0000-4000-8000-00000000000c','cancelled','1','system','system','cancelled','已取消',6,app_private.platform_tenant_id(),'info');

grant usage,select on sequence public.tms_carrier_payment_application_no_seq to authenticated;
grant select,insert,update,delete on public.tms_carrier_payment_application to authenticated;
grant select,insert,update,delete on public.tms_carrier_payment_application_item to authenticated;
grant select on public.tms_carrier_payment_application_summary to authenticated;
grant select on public.tms_cash_transaction_summary to authenticated;
grant select on public.tms_carrier_statement_allocatable to authenticated;
grant select on public.tms_finance_exception_summary to authenticated;

revoke all on public.tms_carrier_payment_application from anon;
revoke all on public.tms_carrier_payment_application_item from anon;
revoke all on public.tms_carrier_payment_application_summary from anon;
revoke all on public.tms_finance_exception_summary from anon;

revoke all on function public.save_tms_carrier_payment_application(uuid,uuid,date,numeric,text,jsonb,text,jsonb) from public,anon;
revoke all on function public.validate_tms_carrier_payment_application_submission(uuid) from public,anon;
revoke all on function public.delete_tms_carrier_payment_application(uuid) from public,anon;
revoke all on function public.cancel_tms_carrier_payment_application(uuid,text) from public,anon;
revoke all on function public.execute_tms_carrier_payment_application(uuid,date,text,jsonb) from public,anon;
grant execute on function public.save_tms_carrier_payment_application(uuid,uuid,date,numeric,text,jsonb,text,jsonb) to authenticated;
grant execute on function public.validate_tms_carrier_payment_application_submission(uuid) to authenticated;
grant execute on function public.delete_tms_carrier_payment_application(uuid) to authenticated;
grant execute on function public.cancel_tms_carrier_payment_application(uuid,text) to authenticated;
grant execute on function public.execute_tms_carrier_payment_application(uuid,date,text,jsonb) to authenticated;

revoke all on function public.trg_validate_tms_carrier_payment_application() from public,anon,authenticated;
revoke all on function public.trg_validate_tms_carrier_payment_application_item() from public,anon,authenticated;
revoke all on function public.trg_guard_tms_cash_payment_application() from public,anon,authenticated;
revoke all on function public.trg_guard_tms_carrier_allocation_reservation() from public,anon,authenticated;
revoke all on function app_private.execute_carrier_payment_application_workflow_callback(uuid,text,text,text) from public,anon,authenticated;
revoke all on function app_private.execute_workflow_business_callback(text,uuid,text,text,text) from public,anon,authenticated;
revoke all on function app_private.get_carrier_payment_application_workflow_snapshot(uuid) from public,anon,authenticated;
revoke all on function app_private.get_workflow_business_snapshot_v2(uuid) from public,anon,authenticated;

comment on table public.tms_carrier_payment_application is '承运商付款申请；审批通过前锁定对账单可付额度';
comment on column public.tms_cash_transaction.payment_application_id is '实际付款关联的已批准承运商付款申请';
comment on view public.tms_finance_exception_summary is '租户隔离的财务闭环异常汇总';
;
