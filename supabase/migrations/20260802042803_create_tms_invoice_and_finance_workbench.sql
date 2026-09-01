
create sequence if not exists public.tms_invoice_record_no_seq;

create table if not exists public.tms_invoice (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  invoice_record_no text not null default (
    'IV' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.tms_invoice_record_no_seq')::text, 6, '0')
  ),
  direction text not null,
  invoice_type text not null,
  customer_id uuid references public.tms_customer(id) on delete restrict,
  carrier_id uuid references public.tms_carrier(id) on delete restrict,
  counterparty_name_snapshot text not null,
  invoice_title text,
  tax_number text,
  invoice_code text,
  invoice_no text,
  issue_date date not null default current_date,
  tax_rate numeric(7,4) not null default 0,
  amount_excluding_tax numeric(14,2) not null,
  tax_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null,
  status text not null default 'draft',
  attachments jsonb not null default '[]'::jsonb,
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
  constraint tms_invoice_tenant_record_no_key unique (tenant_id, invoice_record_no),
  constraint tms_invoice_direction_check check (direction in ('output', 'input')),
  constraint tms_invoice_type_check check (invoice_type in ('vat_special', 'vat_ordinary', 'electronic')),
  constraint tms_invoice_status_check check (status in ('draft', 'pending_review', 'issued', 'certified', 'voided')),
  constraint tms_invoice_counterparty_check check (
    (direction = 'output' and customer_id is not null and carrier_id is null)
    or (direction = 'input' and carrier_id is not null and customer_id is null)
  ),
  constraint tms_invoice_counterparty_name_check check (btrim(counterparty_name_snapshot) <> ''),
  constraint tms_invoice_amount_check check (
    amount_excluding_tax >= 0 and tax_amount >= 0 and total_amount > 0
    and abs((amount_excluding_tax + tax_amount) - total_amount) <= 0.01
  ),
  constraint tms_invoice_tax_rate_check check (tax_rate >= 0 and tax_rate <= 100),
  constraint tms_invoice_attachments_check check (jsonb_typeof(attachments) = 'array')
);

create table if not exists public.tms_invoice_statement_link (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  invoice_id uuid not null references public.tms_invoice(id) on delete cascade,
  customer_statement_id uuid references public.tms_customer_statement(id) on delete restrict,
  carrier_statement_id uuid references public.tms_carrier_statement(id) on delete restrict,
  linked_amount numeric(14,2) not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_invoice_statement_link_target_check check (
    (customer_statement_id is not null and carrier_statement_id is null)
    or (customer_statement_id is null and carrier_statement_id is not null)
  ),
  constraint tms_invoice_statement_link_amount_check check (linked_amount > 0)
);

create unique index if not exists tms_invoice_active_legal_no_key
  on public.tms_invoice (tenant_id, direction, invoice_no)
  where invoice_no is not null and btrim(invoice_no) <> '' and status <> 'voided';
create index if not exists tms_invoice_tenant_status_date_idx
  on public.tms_invoice (tenant_id, status, issue_date desc);
create index if not exists tms_invoice_tenant_direction_party_idx
  on public.tms_invoice (tenant_id, direction, customer_id, carrier_id);
create unique index if not exists tms_invoice_link_customer_key
  on public.tms_invoice_statement_link (invoice_id, customer_statement_id)
  where customer_statement_id is not null;
create unique index if not exists tms_invoice_link_carrier_key
  on public.tms_invoice_statement_link (invoice_id, carrier_statement_id)
  where carrier_statement_id is not null;
create index if not exists tms_invoice_link_tenant_invoice_idx
  on public.tms_invoice_statement_link (tenant_id, invoice_id);
create index if not exists tms_invoice_link_customer_statement_idx
  on public.tms_invoice_statement_link (customer_statement_id)
  where customer_statement_id is not null;
create index if not exists tms_invoice_link_carrier_statement_idx
  on public.tms_invoice_statement_link (carrier_statement_id)
  where carrier_statement_id is not null;

create or replace function app_private.trg_validate_tms_invoice()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_party_name text;
  v_party_tenant uuid;
begin
  new.invoice_code := nullif(btrim(new.invoice_code), '');
  new.invoice_no := nullif(btrim(new.invoice_no), '');
  new.invoice_title := nullif(btrim(new.invoice_title), '');
  new.tax_number := nullif(btrim(new.tax_number), '');
  new.remark := nullif(btrim(new.remark), '');
  new.attachments := coalesce(new.attachments, '[]'::jsonb);

  if new.direction = 'output' then
    select c.customer_name, c.tenant_id
      into v_party_name, v_party_tenant
    from public.tms_customer c
    where c.id = new.customer_id and c.enabled;
    if not found then raise exception '开票客户不存在或已停用'; end if;
    new.carrier_id := null;
  elsif new.direction = 'input' then
    select c.company_name, c.tenant_id
      into v_party_name, v_party_tenant
    from public.tms_carrier c
    where c.id = new.carrier_id and c.enabled;
    if not found then raise exception '来票承运商不存在或已停用'; end if;
    new.customer_id := null;
  else
    raise exception '发票方向不正确';
  end if;

  if new.tenant_id is distinct from v_party_tenant then
    raise exception '发票与往来单位不属于同一租户';
  end if;
  new.counterparty_name_snapshot := v_party_name;

  if jsonb_typeof(new.attachments) <> 'array' then
    raise exception '发票附件格式不正确';
  end if;
  if abs((new.amount_excluding_tax + new.tax_amount) - new.total_amount) > 0.01 then
    raise exception '价税合计必须等于不含税金额加税额';
  end if;

  if tg_op = 'UPDATE' then
    if old.status <> 'draft'
       and (
         new.direction is distinct from old.direction
         or new.invoice_type is distinct from old.invoice_type
         or new.customer_id is distinct from old.customer_id
         or new.carrier_id is distinct from old.carrier_id
         or new.invoice_title is distinct from old.invoice_title
         or new.tax_number is distinct from old.tax_number
         or new.invoice_code is distinct from old.invoice_code
         or new.invoice_no is distinct from old.invoice_no
         or new.issue_date is distinct from old.issue_date
         or new.tax_rate is distinct from old.tax_rate
         or new.amount_excluding_tax is distinct from old.amount_excluding_tax
         or new.tax_amount is distinct from old.tax_amount
         or new.total_amount is distinct from old.total_amount
         or new.attachments is distinct from old.attachments
         or new.remark is distinct from old.remark
       )
    then
      raise exception '仅草稿发票允许修改业务信息';
    end if;

    if new.status is distinct from old.status then
      if not (
        (old.status = 'draft' and new.status in ('pending_review', 'voided'))
        or (old.status = 'pending_review' and new.status in ('draft', 'issued', 'certified', 'voided'))
        or (old.status in ('issued', 'certified') and new.status = 'voided')
      ) then
        raise exception '发票状态流转不合法';
      end if;
    end if;
  end if;

  if new.status = 'issued' and new.direction <> 'output' then
    raise exception '只有销项发票可以进入已开票状态';
  end if;
  if new.status = 'certified' and new.direction <> 'input' then
    raise exception '只有进项发票可以进入已认证状态';
  end if;
  if new.status in ('issued', 'certified') and new.invoice_no is null then
    raise exception '审核通过前必须填写发票号码';
  end if;

  return new;
end;
$$;

create or replace function app_private.trg_validate_tms_invoice_statement_link()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.tms_invoice%rowtype;
  v_statement_amount numeric(14,2);
  v_statement_tenant uuid;
  v_statement_party uuid;
  v_statement_status text;
  v_used_amount numeric(14,2);
  v_invoice_linked numeric(14,2);
  v_target_id uuid;
begin
  select * into v_invoice
  from public.tms_invoice
  where id = new.invoice_id
  for update;

  if not found then raise exception '发票记录不存在'; end if;
  if v_invoice.status <> 'draft' then raise exception '仅草稿发票允许调整关联对账单'; end if;
  if new.tenant_id is distinct from v_invoice.tenant_id then raise exception '发票关联租户不一致'; end if;

  v_target_id := coalesce(new.customer_statement_id, new.carrier_statement_id);
  perform pg_advisory_xact_lock(hashtextextended(v_target_id::text, 932817));

  if v_invoice.direction = 'output' then
    if new.customer_statement_id is null or new.carrier_statement_id is not null then
      raise exception '销项发票只能关联客户对账单';
    end if;
    select s.statement_amount, s.tenant_id, s.customer_id, s.status
      into v_statement_amount, v_statement_tenant, v_statement_party, v_statement_status
    from public.tms_customer_statement_summary s
    where s.id = new.customer_statement_id;
    if not found then raise exception '客户对账单不存在'; end if;
    if v_statement_party is distinct from v_invoice.customer_id then raise exception '客户对账单与发票客户不一致'; end if;
  else
    if new.carrier_statement_id is null or new.customer_statement_id is not null then
      raise exception '进项发票只能关联承运商对账单';
    end if;
    select s.statement_amount, s.tenant_id, s.carrier_id, s.status
      into v_statement_amount, v_statement_tenant, v_statement_party, v_statement_status
    from public.tms_carrier_statement_summary s
    where s.id = new.carrier_statement_id;
    if not found then raise exception '承运商对账单不存在'; end if;
    if v_statement_party is distinct from v_invoice.carrier_id then raise exception '承运商对账单与发票承运商不一致'; end if;
  end if;

  if v_statement_tenant is distinct from v_invoice.tenant_id then raise exception '对账单与发票租户不一致'; end if;
  if v_statement_status not in ('confirmed', 'partially_settled', 'settled') then
    raise exception '只能关联已确认的有效对账单';
  end if;

  select coalesce(sum(l.linked_amount), 0)
    into v_used_amount
  from public.tms_invoice_statement_link l
  join public.tms_invoice i on i.id = l.invoice_id
  where coalesce(l.customer_statement_id, l.carrier_statement_id) = v_target_id
    and i.status <> 'voided'
    and l.id is distinct from new.id;

  if v_used_amount + new.linked_amount > v_statement_amount + 0.01 then
    raise exception '对账单可开票金额不足，请刷新后重试';
  end if;

  select coalesce(sum(l.linked_amount), 0)
    into v_invoice_linked
  from public.tms_invoice_statement_link l
  where l.invoice_id = new.invoice_id
    and l.id is distinct from new.id;

  if v_invoice_linked + new.linked_amount > v_invoice.total_amount + 0.01 then
    raise exception '关联金额不能超过发票价税合计';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_invoice_validate on public.tms_invoice;
create trigger tms_invoice_validate
before insert or update on public.tms_invoice
for each row execute function app_private.trg_validate_tms_invoice();

drop trigger if exists tms_invoice_create_audit on public.tms_invoice;
create trigger tms_invoice_create_audit
before insert on public.tms_invoice
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_invoice_update_audit on public.tms_invoice;
create trigger tms_invoice_update_audit
before update on public.tms_invoice
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_invoice_statement_link_validate on public.tms_invoice_statement_link;
create trigger tms_invoice_statement_link_validate
before insert or update on public.tms_invoice_statement_link
for each row execute function app_private.trg_validate_tms_invoice_statement_link();

drop trigger if exists tms_invoice_statement_link_create_audit on public.tms_invoice_statement_link;
create trigger tms_invoice_statement_link_create_audit
before insert on public.tms_invoice_statement_link
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_invoice_statement_link_update_audit on public.tms_invoice_statement_link;
create trigger tms_invoice_statement_link_update_audit
before update on public.tms_invoice_statement_link
for each row execute function public.trg_set_update_time_and_by();

alter table public.tms_invoice enable row level security;
alter table public.tms_invoice_statement_link enable row level security;

drop policy if exists tms_invoice_tenant_select on public.tms_invoice;
create policy tms_invoice_tenant_select on public.tms_invoice
for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_invoice_tenant_insert on public.tms_invoice;
create policy tms_invoice_tenant_insert on public.tms_invoice
for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status = 'draft'
);

drop policy if exists tms_invoice_tenant_update on public.tms_invoice;
create policy tms_invoice_tenant_update on public.tms_invoice
for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status <> 'voided'
)
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_invoice_tenant_delete on public.tms_invoice;
create policy tms_invoice_tenant_delete on public.tms_invoice
for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status = 'draft'
);

drop policy if exists tms_invoice_statement_link_tenant_select on public.tms_invoice_statement_link;
create policy tms_invoice_statement_link_tenant_select on public.tms_invoice_statement_link
for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_invoice_statement_link_tenant_insert on public.tms_invoice_statement_link;
create policy tms_invoice_statement_link_tenant_insert on public.tms_invoice_statement_link
for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and exists (
    select 1 from public.tms_invoice i
    where i.id = invoice_id and i.tenant_id = tenant_id and i.status = 'draft'
  )
);

drop policy if exists tms_invoice_statement_link_tenant_update on public.tms_invoice_statement_link;
create policy tms_invoice_statement_link_tenant_update on public.tms_invoice_statement_link
for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and exists (select 1 from public.tms_invoice i where i.id = invoice_id and i.status = 'draft')
)
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and exists (select 1 from public.tms_invoice i where i.id = invoice_id and i.status = 'draft')
);

drop policy if exists tms_invoice_statement_link_tenant_delete on public.tms_invoice_statement_link;
create policy tms_invoice_statement_link_tenant_delete on public.tms_invoice_statement_link
for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and exists (select 1 from public.tms_invoice i where i.id = invoice_id and i.status = 'draft')
);

create or replace view public.tms_invoice_summary
with (security_invoker = true)
as
select
  i.*,
  count(l.id)::integer as statement_count,
  coalesce(sum(l.linked_amount), 0)::numeric(14,2) as linked_amount,
  greatest(i.total_amount - coalesce(sum(l.linked_amount), 0), 0)::numeric(14,2) as unlinked_amount
from public.tms_invoice i
left join public.tms_invoice_statement_link l on l.invoice_id = i.id
group by i.id;

create or replace view public.tms_invoice_detail_link
with (security_invoker = true)
as
select
  l.id,
  l.tenant_id,
  l.invoice_id,
  'output'::text as direction,
  l.customer_statement_id as statement_id,
  s.statement_no,
  s.customer_id as counterparty_id,
  s.customer_name as counterparty_name,
  s.period_start,
  s.period_end,
  s.statement_amount,
  l.linked_amount,
  l.create_by,
  l.create_time
from public.tms_invoice_statement_link l
join public.tms_customer_statement_summary s on s.id = l.customer_statement_id
where l.customer_statement_id is not null
union all
select
  l.id,
  l.tenant_id,
  l.invoice_id,
  'input'::text as direction,
  l.carrier_statement_id as statement_id,
  s.statement_no,
  s.carrier_id as counterparty_id,
  s.carrier_name as counterparty_name,
  s.period_start,
  s.period_end,
  s.statement_amount,
  l.linked_amount,
  l.create_by,
  l.create_time
from public.tms_invoice_statement_link l
join public.tms_carrier_statement_summary s on s.id = l.carrier_statement_id
where l.carrier_statement_id is not null;

create or replace view public.tms_invoiceable_statement
with (security_invoker = true)
as
select
  'output'::text as direction,
  s.id as statement_id,
  s.tenant_id,
  s.statement_no,
  s.customer_id as counterparty_id,
  s.customer_name as counterparty_name,
  s.period_start,
  s.period_end,
  s.status,
  s.statement_amount,
  coalesce(sum(case when i.status <> 'voided' then l.linked_amount else 0 end), 0)::numeric(14,2) as invoiced_amount,
  greatest(
    s.statement_amount - coalesce(sum(case when i.status <> 'voided' then l.linked_amount else 0 end), 0),
    0
  )::numeric(14,2) as uninvoiced_amount
from public.tms_customer_statement_summary s
left join public.tms_invoice_statement_link l on l.customer_statement_id = s.id
left join public.tms_invoice i on i.id = l.invoice_id
where s.status in ('confirmed', 'partially_settled', 'settled')
group by s.id, s.tenant_id, s.statement_no, s.customer_id, s.customer_name, s.period_start, s.period_end, s.status, s.statement_amount
union all
select
  'input'::text as direction,
  s.id as statement_id,
  s.tenant_id,
  s.statement_no,
  s.carrier_id as counterparty_id,
  s.carrier_name as counterparty_name,
  s.period_start,
  s.period_end,
  s.status,
  s.statement_amount,
  coalesce(sum(case when i.status <> 'voided' then l.linked_amount else 0 end), 0)::numeric(14,2) as invoiced_amount,
  greatest(
    s.statement_amount - coalesce(sum(case when i.status <> 'voided' then l.linked_amount else 0 end), 0),
    0
  )::numeric(14,2) as uninvoiced_amount
from public.tms_carrier_statement_summary s
left join public.tms_invoice_statement_link l on l.carrier_statement_id = s.id
left join public.tms_invoice i on i.id = l.invoice_id
where s.status in ('confirmed', 'partially_settled', 'settled')
group by s.id, s.tenant_id, s.statement_no, s.carrier_id, s.carrier_name, s.period_start, s.period_end, s.status, s.statement_amount;

create or replace view public.tms_finance_workbench
with (security_invoker = true)
as
select
  coalesce((select sum(outstanding_amount) from public.tms_customer_statement_summary where status in ('confirmed','partially_settled')), 0)::numeric(14,2) as customer_receivable_balance,
  coalesce((select sum(outstanding_amount) from public.tms_carrier_statement_summary where status in ('confirmed','partially_settled')), 0)::numeric(14,2) as carrier_payable_balance,
  coalesce((select sum(amount) from public.tms_cash_transaction_summary where direction='receipt' and status <> 'voided' and date_trunc('month', transaction_date::timestamp)=date_trunc('month', current_date::timestamp)), 0)::numeric(14,2) as month_receipt_amount,
  coalesce((select sum(amount) from public.tms_cash_transaction_summary where direction='payment' and status <> 'voided' and date_trunc('month', transaction_date::timestamp)=date_trunc('month', current_date::timestamp)), 0)::numeric(14,2) as month_payment_amount,
  coalesce((select sum(receivable_amount) from public.tms_waybill_profit where date_trunc('month', coalesce(completed_at,create_time))=date_trunc('month', current_date::timestamp)), 0)::numeric(14,2) as month_revenue_amount,
  coalesce((select sum(total_cost_amount) from public.tms_waybill_profit where date_trunc('month', coalesce(completed_at,create_time))=date_trunc('month', current_date::timestamp)), 0)::numeric(14,2) as month_cost_amount,
  coalesce((select sum(gross_profit) from public.tms_waybill_profit where date_trunc('month', coalesce(completed_at,create_time))=date_trunc('month', current_date::timestamp)), 0)::numeric(14,2) as month_gross_profit,
  coalesce((select round(100 * sum(settled_amount) / nullif(sum(statement_amount),0),2) from public.tms_customer_statement_summary where status in ('confirmed','partially_settled','settled')),0)::numeric(7,2) as receipt_completion_rate,
  coalesce((select round(100 * sum(settled_amount) / nullif(sum(statement_amount),0),2) from public.tms_carrier_statement_summary where status in ('confirmed','partially_settled','settled')),0)::numeric(7,2) as payment_completion_rate,
  coalesce((select round(100 * sum(linked_amount) / nullif(sum(total_amount),0),2) from public.tms_invoice_summary where status <> 'voided'),0)::numeric(7,2) as invoice_match_rate,
  coalesce((select round(100.0 * count(*) filter (where audit_status='approved') / nullif(count(*) filter (where audit_status <> 'voided'),0),2) from public.tms_waybill_cost),0)::numeric(7,2) as cost_approval_rate,
  (select count(*)::integer from public.tms_customer_statement_summary where status='pending_review') as pending_customer_statement_count,
  coalesce((select sum(statement_amount) from public.tms_customer_statement_summary where status='pending_review'),0)::numeric(14,2) as pending_customer_statement_amount,
  (select count(*)::integer from public.tms_carrier_statement_summary where status='pending_review') as pending_carrier_statement_count,
  coalesce((select sum(statement_amount) from public.tms_carrier_statement_summary where status='pending_review'),0)::numeric(14,2) as pending_carrier_statement_amount,
  (select count(*)::integer from public.tms_waybill_cost where audit_status='pending_review') as pending_cost_count,
  coalesce((select sum(amount) from public.tms_waybill_cost where audit_status='pending_review'),0)::numeric(14,2) as pending_cost_amount,
  (select count(*)::integer from public.tms_cash_transaction_summary where direction='receipt' and status in ('pending_allocation','partially_allocated')) as unallocated_receipt_count,
  coalesce((select sum(unallocated_amount) from public.tms_cash_transaction_summary where direction='receipt' and status in ('pending_allocation','partially_allocated')),0)::numeric(14,2) as unallocated_receipt_amount,
  (select count(*)::integer from public.tms_cash_transaction_summary where direction='payment' and status in ('pending_allocation','partially_allocated')) as unallocated_payment_count,
  coalesce((select sum(unallocated_amount) from public.tms_cash_transaction_summary where direction='payment' and status in ('pending_allocation','partially_allocated')),0)::numeric(14,2) as unallocated_payment_amount,
  (select count(*)::integer from public.tms_invoice_summary where status='draft') as draft_invoice_count,
  coalesce((select sum(total_amount) from public.tms_invoice_summary where status='draft'),0)::numeric(14,2) as draft_invoice_amount,
  (select count(*)::integer from public.tms_invoice_summary where status='pending_review') as pending_invoice_count,
  coalesce((select sum(total_amount) from public.tms_invoice_summary where status='pending_review'),0)::numeric(14,2) as pending_invoice_amount;

create or replace function public.save_tms_invoice(
  p_invoice_id uuid,
  p_direction text,
  p_invoice_type text,
  p_customer_id uuid,
  p_carrier_id uuid,
  p_invoice_title text,
  p_tax_number text,
  p_invoice_code text,
  p_invoice_no text,
  p_issue_date date,
  p_tax_rate numeric,
  p_amount_excluding_tax numeric,
  p_tax_amount numeric,
  p_total_amount numeric,
  p_attachments jsonb,
  p_remark text,
  p_statement_links jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice_id uuid;
  v_tenant_id uuid;
  v_party_name text;
  v_link jsonb;
  v_statement_id uuid;
  v_linked_amount numeric(14,2);
begin
  if p_direction not in ('output','input') then raise exception '发票方向不正确'; end if;
  if p_invoice_type not in ('vat_special','vat_ordinary','electronic') then raise exception '发票类型不正确'; end if;
  if p_issue_date is null then raise exception '请选择开票日期'; end if;
  if p_amount_excluding_tax is null or p_amount_excluding_tax < 0
     or p_tax_amount is null or p_tax_amount < 0
     or p_total_amount is null or p_total_amount <= 0 then
    raise exception '发票金额不正确';
  end if;
  if abs((p_amount_excluding_tax + p_tax_amount) - p_total_amount) > 0.01 then
    raise exception '价税合计必须等于不含税金额加税额';
  end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then raise exception '税率不正确'; end if;
  if jsonb_typeof(coalesce(p_attachments,'[]'::jsonb)) <> 'array' then raise exception '附件格式不正确'; end if;
  if jsonb_typeof(coalesce(p_statement_links,'[]'::jsonb)) <> 'array' then raise exception '关联对账单格式不正确'; end if;

  if p_direction = 'output' then
    select c.tenant_id, c.customer_name into v_tenant_id, v_party_name
    from public.tms_customer c where c.id=p_customer_id and c.enabled;
    if not found then raise exception '开票客户不存在或已停用'; end if;
  else
    select c.tenant_id, c.company_name into v_tenant_id, v_party_name
    from public.tms_carrier c where c.id=p_carrier_id and c.enabled;
    if not found then raise exception '来票承运商不存在或已停用'; end if;
  end if;

  if not app_private.is_platform_super()
     and v_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权维护其他租户的发票';
  end if;

  if p_invoice_id is null then
    insert into public.tms_invoice (
      tenant_id,direction,invoice_type,customer_id,carrier_id,counterparty_name_snapshot,
      invoice_title,tax_number,invoice_code,invoice_no,issue_date,tax_rate,
      amount_excluding_tax,tax_amount,total_amount,attachments,remark
    ) values (
      v_tenant_id,p_direction,p_invoice_type,
      case when p_direction='output' then p_customer_id else null end,
      case when p_direction='input' then p_carrier_id else null end,
      v_party_name,nullif(btrim(p_invoice_title),''),nullif(btrim(p_tax_number),''),
      nullif(btrim(p_invoice_code),''),nullif(btrim(p_invoice_no),''),p_issue_date,p_tax_rate,
      p_amount_excluding_tax,p_tax_amount,p_total_amount,coalesce(p_attachments,'[]'::jsonb),
      nullif(btrim(p_remark),'')
    ) returning id into v_invoice_id;
  else
    perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text, 932816));
    update public.tms_invoice
    set direction=p_direction,
        invoice_type=p_invoice_type,
        customer_id=case when p_direction='output' then p_customer_id else null end,
        carrier_id=case when p_direction='input' then p_carrier_id else null end,
        counterparty_name_snapshot=v_party_name,
        invoice_title=nullif(btrim(p_invoice_title),''),
        tax_number=nullif(btrim(p_tax_number),''),
        invoice_code=nullif(btrim(p_invoice_code),''),
        invoice_no=nullif(btrim(p_invoice_no),''),
        issue_date=p_issue_date,
        tax_rate=p_tax_rate,
        amount_excluding_tax=p_amount_excluding_tax,
        tax_amount=p_tax_amount,
        total_amount=p_total_amount,
        attachments=coalesce(p_attachments,'[]'::jsonb),
        remark=nullif(btrim(p_remark),'')
    where id=p_invoice_id and status='draft'
    returning id into v_invoice_id;
    if not found then raise exception '发票不存在或不是可编辑草稿'; end if;
    delete from public.tms_invoice_statement_link where invoice_id=v_invoice_id;
  end if;

  for v_link in select value from jsonb_array_elements(coalesce(p_statement_links,'[]'::jsonb))
  loop
    v_statement_id := nullif(v_link->>'statementId','')::uuid;
    v_linked_amount := nullif(v_link->>'linkedAmount','')::numeric;
    if v_statement_id is null or v_linked_amount is null or v_linked_amount <= 0 then
      raise exception '关联对账单及金额不能为空';
    end if;

    insert into public.tms_invoice_statement_link (
      tenant_id,invoice_id,customer_statement_id,carrier_statement_id,linked_amount
    ) values (
      v_tenant_id,v_invoice_id,
      case when p_direction='output' then v_statement_id else null end,
      case when p_direction='input' then v_statement_id else null end,
      v_linked_amount
    );
  end loop;

  return v_invoice_id;
end;
$$;

create or replace function public.update_tms_invoice_status(
  p_invoice_id uuid,
  p_action text,
  p_remark text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.tms_invoice%rowtype;
  v_next_status text;
  v_actor text := coalesce(auth.jwt()->>'email', auth.uid()::text, current_user);
begin
  perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text, 932816));
  select * into v_invoice from public.tms_invoice where id=p_invoice_id for update;
  if not found then raise exception '发票不存在或无权访问'; end if;

  if p_action='submit' and v_invoice.status='draft' then
    v_next_status := 'pending_review';
    update public.tms_invoice
    set status=v_next_status,submitted_at=now(),submitted_by=v_actor,
        review_remark=null,reviewed_at=null,reviewed_by=null
    where id=p_invoice_id;
  elsif p_action='approve' and v_invoice.status='pending_review' then
    v_next_status := case when v_invoice.direction='output' then 'issued' else 'certified' end;
    update public.tms_invoice
    set status=v_next_status,reviewed_at=now(),reviewed_by=v_actor,
        review_remark=nullif(btrim(p_remark),'')
    where id=p_invoice_id;
  elsif p_action='reject' and v_invoice.status='pending_review' then
    if btrim(coalesce(p_remark,''))='' then raise exception '驳回原因不能为空'; end if;
    v_next_status := 'draft';
    update public.tms_invoice
    set status=v_next_status,reviewed_at=now(),reviewed_by=v_actor,review_remark=btrim(p_remark)
    where id=p_invoice_id;
  elsif p_action='void' and v_invoice.status in ('issued','certified') then
    if btrim(coalesce(p_remark,''))='' then raise exception '作废原因不能为空'; end if;
    v_next_status := 'voided';
    update public.tms_invoice
    set status=v_next_status,voided_at=now(),voided_by=v_actor,void_reason=btrim(p_remark)
    where id=p_invoice_id;
  else
    raise exception '当前发票状态不允许执行该操作';
  end if;

  return v_next_status;
end;
$$;

grant usage, select on sequence public.tms_invoice_record_no_seq to authenticated, service_role;
grant select,insert,update,delete on table public.tms_invoice to authenticated, service_role;
grant select,insert,update,delete on table public.tms_invoice_statement_link to authenticated, service_role;
grant select on public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench to authenticated, service_role;

revoke all on function public.save_tms_invoice(uuid,text,text,uuid,uuid,text,text,text,text,date,numeric,numeric,numeric,numeric,jsonb,text,jsonb) from public, anon;
revoke all on function public.update_tms_invoice_status(uuid,text,text) from public, anon;
grant execute on function public.save_tms_invoice(uuid,text,text,uuid,uuid,text,text,text,text,date,numeric,numeric,numeric,numeric,jsonb,text,jsonb) to authenticated, service_role;
grant execute on function public.update_tms_invoice_status(uuid,text,text) to authenticated, service_role;

notify pgrst, 'reload schema';
;
