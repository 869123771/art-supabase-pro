create sequence if not exists public.tms_customer_statement_no_seq;

create table if not exists public.tms_customer_statement (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  statement_no text not null default (
    'CS' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' ||
    lpad(nextval('public.tms_customer_statement_no_seq'::regclass)::text, 6, '0')
  ),
  customer_id uuid not null,
  customer_name_snapshot text not null,
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
  constraint tms_customer_statement_tenant_no_key unique (tenant_id, statement_no),
  constraint tms_customer_statement_customer_id_fkey
    foreign key (customer_id) references public.tms_customer(id) on delete restrict,
  constraint tms_customer_statement_period_check check (period_start <= period_end),
  constraint tms_customer_statement_status_check check (
    status in ('draft', 'pending_review', 'confirmed', 'partially_settled', 'settled', 'voided')
  ),
  constraint tms_customer_statement_settled_amount_check check (settled_amount >= 0),
  constraint tms_customer_statement_customer_name_not_blank_check
    check (btrim(customer_name_snapshot) <> '')
);

create table if not exists public.tms_customer_statement_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  statement_id uuid not null,
  customer_id uuid not null,
  waybill_id uuid not null,
  order_id uuid not null,
  waybill_no_snapshot text not null,
  order_no_snapshot text not null,
  origin_station_snapshot text,
  destination_station_snapshot text,
  completed_at_snapshot timestamptz,
  receivable_amount numeric(14, 2) not null,
  adjustment_amount numeric(14, 2) not null default 0,
  line_amount numeric(14, 2) not null,
  is_active boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_customer_statement_item_statement_id_fkey
    foreign key (statement_id) references public.tms_customer_statement(id) on delete cascade,
  constraint tms_customer_statement_item_customer_id_fkey
    foreign key (customer_id) references public.tms_customer(id) on delete restrict,
  constraint tms_customer_statement_item_waybill_id_fkey
    foreign key (waybill_id) references public.tms_waybill(id) on delete restrict,
  constraint tms_customer_statement_item_order_id_fkey
    foreign key (order_id) references public.tms_order(id) on delete restrict,
  constraint tms_customer_statement_item_statement_waybill_key
    unique (statement_id, waybill_id),
  constraint tms_customer_statement_item_receivable_amount_check
    check (receivable_amount >= 0),
  constraint tms_customer_statement_item_line_amount_check
    check (line_amount = receivable_amount + adjustment_amount and line_amount >= 0),
  constraint tms_customer_statement_item_waybill_no_not_blank_check
    check (btrim(waybill_no_snapshot) <> ''),
  constraint tms_customer_statement_item_order_no_not_blank_check
    check (btrim(order_no_snapshot) <> '')
);

create index if not exists tms_customer_statement_tenant_status_time_idx
  on public.tms_customer_statement (tenant_id, status, create_time desc);
create index if not exists tms_customer_statement_customer_period_idx
  on public.tms_customer_statement (tenant_id, customer_id, period_start, period_end);
create index if not exists tms_customer_statement_item_statement_idx
  on public.tms_customer_statement_item (statement_id);
create index if not exists tms_customer_statement_item_customer_idx
  on public.tms_customer_statement_item (tenant_id, customer_id);
create index if not exists tms_customer_statement_item_order_idx
  on public.tms_customer_statement_item (order_id);
create unique index if not exists tms_customer_statement_item_active_waybill_uk
  on public.tms_customer_statement_item (tenant_id, waybill_id)
  where is_active;

comment on table public.tms_customer_statement is '客户应收对账单';
comment on table public.tms_customer_statement_item is '客户应收对账单运单明细';
comment on column public.tms_customer_statement.customer_name_snapshot is '生成对账单时的客户名称快照';
comment on column public.tms_customer_statement_item.is_active is '是否占用运单；对账单作废后置为 false';

create or replace function public.trg_validate_tms_customer_statement()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_customer_tenant_id uuid;
  v_customer_name text;
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

  if new.settled_amount is distinct from old.settled_amount and pg_trigger_depth() <= 1 then
    raise exception '已结金额只能由收款核销流程更新';
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

create or replace function public.trg_validate_tms_customer_statement_item()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_statement_tenant_id uuid;
  v_statement_customer_id uuid;
  v_statement_status text;
  v_period_start date;
  v_period_end date;
  v_source record;
begin
  select s.tenant_id, s.customer_id, s.status, s.period_start, s.period_end
    into v_statement_tenant_id, v_statement_customer_id, v_statement_status,
         v_period_start, v_period_end
  from public.tms_customer_statement s
  where s.id = new.statement_id;

  if not found then
    raise exception '所属对账单不存在';
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.statement_id is distinct from old.statement_id
       or new.customer_id is distinct from old.customer_id
       or new.waybill_id is distinct from old.waybill_id
       or new.order_id is distinct from old.order_id
       or new.waybill_no_snapshot is distinct from old.waybill_no_snapshot
       or new.order_no_snapshot is distinct from old.order_no_snapshot
       or new.origin_station_snapshot is distinct from old.origin_station_snapshot
       or new.destination_station_snapshot is distinct from old.destination_station_snapshot
       or new.completed_at_snapshot is distinct from old.completed_at_snapshot
       or new.receivable_amount is distinct from old.receivable_amount
       or new.adjustment_amount is distinct from old.adjustment_amount
       or new.line_amount is distinct from old.line_amount
       or new.remark is distinct from old.remark then
      raise exception '对账单明细业务字段不可直接修改';
    end if;

    if new.is_active is distinct from old.is_active
       and not (old.is_active and not new.is_active and v_statement_status = 'voided') then
      raise exception '运单占用状态只能在对账单作废时释放';
    end if;
    return new;
  end if;

  if v_statement_status <> 'draft' then
    raise exception '只有草稿对账单可以新增明细';
  end if;

  select
    w.tenant_id,
    w.order_id,
    w.waybill_no,
    o.order_no,
    o.shipping_customer_id,
    o.origin_station,
    o.destination_station,
    coalesce(w.completed_at, o.signed_at, w.update_time) as completed_at,
    o.total_fee
    into v_source
  from public.tms_waybill w
  join public.tms_order o on o.id = w.order_id
  where w.id = new.waybill_id
    and w.status in ('signed', 'completed');

  if not found then
    raise exception '运单不存在、未关联订单或尚未签收完成';
  end if;

  if v_source.tenant_id is distinct from v_statement_tenant_id
     or v_source.shipping_customer_id is distinct from v_statement_customer_id then
    raise exception '运单、客户与对账单必须属于同一租户和客户';
  end if;

  if v_source.completed_at::date not between v_period_start and v_period_end then
    raise exception '运单完成日期不在对账账期内';
  end if;

  if coalesce(v_source.total_fee, 0) <= 0 then
    raise exception '运单应收金额必须大于 0';
  end if;

  new.tenant_id := v_statement_tenant_id;
  new.customer_id := v_statement_customer_id;
  new.order_id := v_source.order_id;
  new.waybill_no_snapshot := v_source.waybill_no;
  new.order_no_snapshot := v_source.order_no;
  new.origin_station_snapshot := v_source.origin_station;
  new.destination_station_snapshot := v_source.destination_station;
  new.completed_at_snapshot := v_source.completed_at;
  new.receivable_amount := round(v_source.total_fee, 2);
  new.adjustment_amount := 0;
  new.line_amount := round(v_source.total_fee, 2);
  new.is_active := true;
  return new;
end;
$$;

create or replace function app_private.trg_release_customer_statement_waybills()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'voided' and old.status <> 'voided' then
    update public.tms_customer_statement_item
    set is_active = false
    where statement_id = new.id and is_active;
  end if;
  return new;
end;
$$;

revoke all on function app_private.trg_release_customer_statement_waybills() from public;

drop trigger if exists tms_customer_statement_create_audit on public.tms_customer_statement;
create trigger tms_customer_statement_create_audit
before insert on public.tms_customer_statement
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_customer_statement_update_audit on public.tms_customer_statement;
create trigger tms_customer_statement_update_audit
before update on public.tms_customer_statement
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_customer_statement_validate on public.tms_customer_statement;
create trigger tms_customer_statement_validate
before insert or update on public.tms_customer_statement
for each row execute function public.trg_validate_tms_customer_statement();

drop trigger if exists tms_customer_statement_release_waybills on public.tms_customer_statement;
create trigger tms_customer_statement_release_waybills
after update of status on public.tms_customer_statement
for each row execute function app_private.trg_release_customer_statement_waybills();

drop trigger if exists tms_customer_statement_item_create_audit on public.tms_customer_statement_item;
create trigger tms_customer_statement_item_create_audit
before insert on public.tms_customer_statement_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_customer_statement_item_update_audit on public.tms_customer_statement_item;
create trigger tms_customer_statement_item_update_audit
before update on public.tms_customer_statement_item
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists tms_customer_statement_item_validate on public.tms_customer_statement_item;
create trigger tms_customer_statement_item_validate
before insert or update on public.tms_customer_statement_item
for each row execute function public.trg_validate_tms_customer_statement_item();

alter table public.tms_customer_statement enable row level security;
alter table public.tms_customer_statement_item enable row level security;

drop policy if exists tms_customer_statement_tenant_select on public.tms_customer_statement;
create policy tms_customer_statement_tenant_select
on public.tms_customer_statement for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_customer_statement_tenant_insert on public.tms_customer_statement;
create policy tms_customer_statement_tenant_insert
on public.tms_customer_statement for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status = 'draft'
  and exists (
    select 1 from public.tms_customer c
    where c.id = tms_customer_statement.customer_id
      and c.tenant_id = tms_customer_statement.tenant_id
  )
);

drop policy if exists tms_customer_statement_tenant_update on public.tms_customer_statement;
create policy tms_customer_statement_tenant_update
on public.tms_customer_statement for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status <> 'voided'
)
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_customer_statement_tenant_delete on public.tms_customer_statement;
create policy tms_customer_statement_tenant_delete
on public.tms_customer_statement for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and status = 'draft'
);

drop policy if exists tms_customer_statement_item_tenant_select
  on public.tms_customer_statement_item;
create policy tms_customer_statement_item_tenant_select
on public.tms_customer_statement_item for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_customer_statement_item_tenant_insert
  on public.tms_customer_statement_item;
create policy tms_customer_statement_item_tenant_insert
on public.tms_customer_statement_item for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and is_active
  and exists (
    select 1 from public.tms_customer_statement s
    where s.id = tms_customer_statement_item.statement_id
      and s.tenant_id = tms_customer_statement_item.tenant_id
      and s.customer_id = tms_customer_statement_item.customer_id
      and s.status = 'draft'
  )
);

create or replace view public.tms_customer_statement_summary
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
  s.status,
  count(i.id)::integer as waybill_count,
  coalesce(sum(i.line_amount), 0)::numeric(14, 2) as statement_amount,
  s.settled_amount,
  greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0)::numeric(14, 2)
    as outstanding_amount,
  s.submitted_at,
  s.submitted_by,
  s.reviewed_at,
  s.reviewed_by,
  s.review_remark,
  s.voided_at,
  s.voided_by,
  s.void_reason,
  s.remark,
  s.create_by,
  s.create_time,
  s.update_by,
  s.update_time
from public.tms_customer_statement s
left join public.tms_customer_statement_item i on i.statement_id = s.id
group by s.id;

create or replace view public.tms_customer_statement_eligible_waybill
with (security_invoker = true)
as
select
  w.id,
  w.tenant_id,
  w.waybill_no,
  w.status as waybill_status,
  w.order_id,
  o.order_no,
  o.shipping_customer_id as customer_id,
  c.customer_name,
  o.origin_station,
  o.destination_station,
  coalesce(w.completed_at, o.signed_at, w.update_time) as completed_at,
  o.total_fee::numeric(14, 2) as receivable_amount
from public.tms_waybill w
join public.tms_order o on o.id = w.order_id
join public.tms_customer c on c.id = o.shipping_customer_id
where w.status in ('signed', 'completed')
  and o.total_fee > 0
  and not exists (
    select 1
    from public.tms_customer_statement_item i
    where i.waybill_id = w.id and i.is_active
  );

create or replace function public.create_tms_customer_statement(
  p_customer_id uuid,
  p_period_start date,
  p_period_end date,
  p_waybill_ids uuid[],
  p_remark text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_statement_id uuid;
  v_customer_tenant_id uuid;
  v_waybill_ids uuid[];
  v_waybill_id uuid;
  v_expected_count integer;
  v_eligible_count integer;
  v_inserted_count integer;
begin
  if p_period_start is null or p_period_end is null or p_period_start > p_period_end then
    raise exception '请选择正确的对账账期';
  end if;

  select array_agg(distinct waybill_id order by waybill_id)
    into v_waybill_ids
  from unnest(coalesce(p_waybill_ids, array[]::uuid[])) as selected(waybill_id)
  where waybill_id is not null;

  v_expected_count := coalesce(cardinality(v_waybill_ids), 0);
  if v_expected_count = 0 then
    raise exception '请至少选择一条运单';
  end if;

  select c.tenant_id
    into v_customer_tenant_id
  from public.tms_customer c
  where c.id = p_customer_id and c.enabled;

  if not found then
    raise exception '对账客户不存在或已停用';
  end if;

  if not app_private.is_platform_super()
     and v_customer_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户生成对账单';
  end if;

  foreach v_waybill_id in array v_waybill_ids loop
    perform pg_advisory_xact_lock(hashtextextended(v_waybill_id::text, 731921));
  end loop;

  select count(*)::integer
    into v_eligible_count
  from public.tms_waybill w
  join public.tms_order o on o.id = w.order_id
  where w.id = any(v_waybill_ids)
    and w.tenant_id = v_customer_tenant_id
    and w.status in ('signed', 'completed')
    and o.shipping_customer_id = p_customer_id
    and o.total_fee > 0
    and coalesce(w.completed_at, o.signed_at, w.update_time)::date
      between p_period_start and p_period_end
    and not exists (
      select 1 from public.tms_customer_statement_item i
      where i.waybill_id = w.id and i.is_active
    );

  if v_eligible_count <> v_expected_count then
    raise exception '部分运单已被对账、客户不一致或不在所选账期，请刷新后重试';
  end if;

  insert into public.tms_customer_statement (
    tenant_id, customer_id, customer_name_snapshot, period_start, period_end, remark
  )
  select
    c.tenant_id, c.id, c.customer_name, p_period_start, p_period_end,
    nullif(btrim(p_remark), '')
  from public.tms_customer c
  where c.id = p_customer_id
  returning id into v_statement_id;

  insert into public.tms_customer_statement_item (
    tenant_id, statement_id, customer_id, waybill_id, order_id,
    waybill_no_snapshot, order_no_snapshot, receivable_amount, line_amount
  )
  select
    v_customer_tenant_id, v_statement_id, p_customer_id, w.id, o.id,
    w.waybill_no, o.order_no, o.total_fee, o.total_fee
  from public.tms_waybill w
  join public.tms_order o on o.id = w.order_id
  where w.id = any(v_waybill_ids);

  get diagnostics v_inserted_count = row_count;
  if v_inserted_count <> v_expected_count then
    raise exception '对账明细生成数量不一致';
  end if;

  return v_statement_id;
end;
$$;

revoke all on table public.tms_customer_statement from anon;
revoke all on table public.tms_customer_statement_item from anon;
revoke all on table public.tms_customer_statement_summary from anon;
revoke all on table public.tms_customer_statement_eligible_waybill from anon;

grant select, insert, update, delete on table public.tms_customer_statement to authenticated;
grant select, insert on table public.tms_customer_statement_item to authenticated;
grant select on table public.tms_customer_statement_summary to authenticated;
grant select on table public.tms_customer_statement_eligible_waybill to authenticated;
grant usage, select on sequence public.tms_customer_statement_no_seq to authenticated;

grant all on table public.tms_customer_statement to service_role;
grant all on table public.tms_customer_statement_item to service_role;
grant select on table public.tms_customer_statement_summary to service_role;
grant select on table public.tms_customer_statement_eligible_waybill to service_role;
grant all on sequence public.tms_customer_statement_no_seq to service_role;

revoke all on function public.create_tms_customer_statement(uuid, date, date, uuid[], text)
  from public, anon;
grant execute on function public.create_tms_customer_statement(uuid, date, date, uuid[], text)
  to authenticated, service_role;

revoke all on function public.trg_validate_tms_customer_statement() from public, anon, authenticated;
revoke all on function public.trg_validate_tms_customer_statement_item()
  from public, anon, authenticated;

;
