-- TMS 财务结算中心第二阶段：运单成本登记、审核流与利润查询。

create table if not exists public.tms_waybill_cost (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  waybill_id uuid not null references public.tms_waybill(id) on delete restrict,
  cost_type text not null,
  amount numeric(14, 2) not null,
  occurred_on date not null default current_date,
  payee_name text,
  carrier_id uuid references public.tms_carrier(id) on delete set null,
  driver_id uuid references public.tms_driver(id) on delete set null,
  remark text,
  attachments jsonb not null default '[]'::jsonb,
  audit_status text not null default 'draft',
  submitted_at timestamptz,
  submitted_by text,
  reviewed_at timestamptz,
  reviewed_by text,
  review_remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_waybill_cost_type_check check (
    cost_type in (
      'carrier_freight', 'toll', 'parking', 'fuel', 'loading', 'waiting',
      'driver_expense', 'cargo_damage', 'other'
    )
  ),
  constraint tms_waybill_cost_amount_positive check (amount > 0),
  constraint tms_waybill_cost_audit_status_check check (
    audit_status in ('draft', 'pending_review', 'approved', 'rejected', 'voided')
  ),
  constraint tms_waybill_cost_attachments_array_check check (jsonb_typeof(attachments) = 'array')
);

comment on table public.tms_waybill_cost is '运单成本明细；只有审核通过的费用进入利润与后续结算口径';
comment on column public.tms_waybill_cost.cost_type is 'carrier_freight=承运运费，其余为附加成本';

create index if not exists idx_tms_waybill_cost_waybill_id
  on public.tms_waybill_cost (waybill_id);
create index if not exists idx_tms_waybill_cost_carrier_id
  on public.tms_waybill_cost (carrier_id) where carrier_id is not null;
create index if not exists idx_tms_waybill_cost_driver_id
  on public.tms_waybill_cost (driver_id) where driver_id is not null;
create index if not exists idx_tms_waybill_cost_tenant_occurred
  on public.tms_waybill_cost (tenant_id, occurred_on desc, id desc);
create index if not exists idx_tms_waybill_cost_tenant_status
  on public.tms_waybill_cost (tenant_id, audit_status, occurred_on desc, id desc);
create index if not exists idx_tms_waybill_cost_profit_approved
  on public.tms_waybill_cost (waybill_id, cost_type, amount)
  where audit_status = 'approved';

create or replace function public.trg_validate_tms_waybill_cost()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_waybill_tenant_id uuid;
  v_waybill_carrier_id uuid;
  v_waybill_driver_id uuid;
  v_actor text;
begin
  select w.tenant_id, w.carrier_id, w.driver_id
    into v_waybill_tenant_id, v_waybill_carrier_id, v_waybill_driver_id
  from public.tms_waybill w
  where w.id = new.waybill_id;

  if not found then
    raise exception '关联运单不存在';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_waybill_tenant_id;
    new.audit_status := 'draft';
    new.carrier_id := coalesce(new.carrier_id, v_waybill_carrier_id);
    new.driver_id := coalesce(new.driver_id, v_waybill_driver_id);
  elsif new.tenant_id is distinct from old.tenant_id then
    raise exception '费用所属租户不可修改';
  elsif new.waybill_id is distinct from old.waybill_id then
    new.tenant_id := v_waybill_tenant_id;
    new.carrier_id := coalesce(new.carrier_id, v_waybill_carrier_id);
    new.driver_id := coalesce(new.driver_id, v_waybill_driver_id);
  end if;

  if new.tenant_id is distinct from v_waybill_tenant_id then
    raise exception '费用与运单必须属于同一租户';
  end if;

  if new.carrier_id is not null and not exists (
    select 1 from public.tms_carrier c
    where c.id = new.carrier_id and c.tenant_id = new.tenant_id
  ) then
    raise exception '承运商与费用必须属于同一租户';
  end if;

  if new.driver_id is not null and not exists (
    select 1 from public.tms_driver d
    where d.id = new.driver_id and d.tenant_id = new.tenant_id
  ) then
    raise exception '司机与费用必须属于同一租户';
  end if;

  if tg_op = 'UPDATE' then
    if old.audit_status = 'voided' then
      raise exception '已作废费用不可修改';
    end if;

    if old.audit_status in ('pending_review', 'approved') and (
      new.waybill_id is distinct from old.waybill_id
      or new.cost_type is distinct from old.cost_type
      or new.amount is distinct from old.amount
      or new.occurred_on is distinct from old.occurred_on
      or new.payee_name is distinct from old.payee_name
      or new.carrier_id is distinct from old.carrier_id
      or new.driver_id is distinct from old.driver_id
      or new.remark is distinct from old.remark
      or new.attachments is distinct from old.attachments
    ) then
      raise exception '待审核或已审核费用不可修改业务字段';
    end if;

    if new.audit_status is distinct from old.audit_status and not (
      (old.audit_status = 'draft' and new.audit_status in ('pending_review', 'voided'))
      or (old.audit_status = 'pending_review' and new.audit_status in ('approved', 'rejected'))
      or (old.audit_status = 'rejected' and new.audit_status in ('draft', 'pending_review', 'voided'))
      or (old.audit_status = 'approved' and new.audit_status = 'voided')
    ) then
      raise exception '不允许的费用审核状态流转：% -> %', old.audit_status, new.audit_status;
    end if;

    v_actor := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      'unknown'
    );

    if new.audit_status = 'pending_review' and old.audit_status <> 'pending_review' then
      new.submitted_at := now();
      new.submitted_by := v_actor;
      new.reviewed_at := null;
      new.reviewed_by := null;
      new.review_remark := null;
    elsif new.audit_status in ('approved', 'rejected')
      and new.audit_status is distinct from old.audit_status then
      new.reviewed_at := now();
      new.reviewed_by := v_actor;
    elsif new.audit_status = 'draft' and old.audit_status = 'rejected' then
      new.reviewed_at := null;
      new.reviewed_by := null;
      new.review_remark := null;
    end if;
  end if;

  return new;
end
$function$;

drop trigger if exists tms_waybill_cost_validate on public.tms_waybill_cost;
create trigger tms_waybill_cost_validate
before insert or update on public.tms_waybill_cost
for each row execute function public.trg_validate_tms_waybill_cost();

drop trigger if exists tms_waybill_cost_create_audit on public.tms_waybill_cost;
create trigger tms_waybill_cost_create_audit
before insert on public.tms_waybill_cost
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_waybill_cost_update_audit on public.tms_waybill_cost;
create trigger tms_waybill_cost_update_audit
before update on public.tms_waybill_cost
for each row execute function public.trg_set_update_time_and_by();

alter table public.tms_waybill_cost enable row level security;

drop policy if exists tms_waybill_cost_tenant_select on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_select on public.tms_waybill_cost
for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_waybill_cost_tenant_insert on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_insert on public.tms_waybill_cost
for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and audit_status = 'draft'
  and exists (
    select 1 from public.tms_waybill w
    where w.id = waybill_id
      and (app_private.is_platform_super() or w.tenant_id = app_private.current_user_tenant_id())
  )
);

drop policy if exists tms_waybill_cost_tenant_update on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_update on public.tms_waybill_cost
for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and audit_status <> 'voided'
)
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

drop policy if exists tms_waybill_cost_tenant_delete on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_delete on public.tms_waybill_cost
for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and audit_status in ('draft', 'rejected')
);

revoke all on table public.tms_waybill_cost from anon;
revoke all on table public.tms_waybill_cost from authenticated;
grant select, insert, update, delete on table public.tms_waybill_cost to authenticated;
grant all on table public.tms_waybill_cost to service_role;

create or replace view public.tms_waybill_profit
with (security_invoker = true)
as
with approved_cost as (
  select
    cost.waybill_id,
    sum(cost.amount) filter (where cost.cost_type = 'carrier_freight') as carrier_payable_amount,
    sum(cost.amount) filter (where cost.cost_type <> 'carrier_freight') as other_cost_amount,
    sum(cost.amount) as total_cost_amount
  from public.tms_waybill_cost cost
  where cost.audit_status = 'approved'
  group by cost.waybill_id
)
select
  w.id,
  w.tenant_id,
  w.id as waybill_id,
  w.order_id,
  w.waybill_no,
  w.status as waybill_status,
  o.order_status,
  o.shipping_customer_id as customer_id,
  customer.customer_name,
  w.carrier_id,
  carrier.company_name as carrier_name,
  o.dispatch_plate_no as plate_no,
  o.dispatch_driver_name as driver_name,
  o.origin_station,
  o.destination_station,
  coalesce(o.total_fee, 0)::numeric(14, 2) as receivable_amount,
  coalesce(cost.carrier_payable_amount, 0)::numeric(14, 2) as carrier_payable_amount,
  coalesce(cost.other_cost_amount, 0)::numeric(14, 2) as other_cost_amount,
  coalesce(cost.total_cost_amount, 0)::numeric(14, 2) as total_cost_amount,
  (coalesce(o.total_fee, 0) - coalesce(cost.total_cost_amount, 0))::numeric(14, 2) as gross_profit,
  case
    when coalesce(o.total_fee, 0) = 0 then 0::numeric
    else round(
      ((coalesce(o.total_fee, 0) - coalesce(cost.total_cost_amount, 0)) / o.total_fee) * 100,
      2
    )
  end as gross_margin,
  w.completed_at,
  o.signed_at,
  w.create_time,
  w.update_time
from public.tms_waybill w
join public.tms_order o on o.id = w.order_id and o.tenant_id = w.tenant_id
left join public.tms_customer customer on customer.id = o.shipping_customer_id
left join public.tms_carrier carrier on carrier.id = w.carrier_id
left join approved_cost cost on cost.waybill_id = w.id;

comment on view public.tms_waybill_profit is '运单利润：订单应收减去审核通过的承运运费及附加成本';

revoke all on table public.tms_waybill_profit from anon;
revoke all on table public.tms_waybill_profit from authenticated;
grant select on table public.tms_waybill_profit to authenticated;
grant select on table public.tms_waybill_profit to service_role;

insert into public.sys_dictionary
  (id, type_id, code, status, value, label, sort, tenant_id, tag_type, create_by, update_by)
select
  'c1000000-0000-4000-8000-00000000002b'::uuid,
  t.id,
  'carrier_freight',
  '1',
  'carrier_freight',
  '承运运费',
  0,
  '028e6a68-a9db-4055-974c-1e05bfe94b0f'::uuid,
  'warning',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_dict_type t
where t.code = 'tmsWaybillCostType'
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  status = excluded.status,
  value = excluded.value,
  label = excluded.label,
  sort = excluded.sort,
  tenant_id = excluded.tenant_id,
  tag_type = excluded.tag_type,
  update_by = excluded.update_by,
  update_time = now();

;
