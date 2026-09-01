-- Unify in-transit expense reporting with the canonical waybill cost ledger.
-- The migration preserves historical records, OCR audit data, reimbursement/payment
-- links and workflow integrity before removing the obsolete in-transit objects.

create table public.tms_expense_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  parent_id uuid null references public.tms_expense_item(id) on delete restrict,
  item_code text not null,
  item_name text not null,
  business_category text null,
  is_selectable boolean not null default true,
  reimbursement_allowed boolean not null default true,
  is_enabled boolean not null default true,
  sort integer not null default 0,
  remark text null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_expense_item_code_not_blank check (btrim(item_code) <> ''),
  constraint tms_expense_item_name_not_blank check (btrim(item_name) <> ''),
  constraint tms_expense_item_category_check check (
    business_category is null or business_category = any (array[
      'carrier_freight', 'toll', 'parking', 'fuel', 'loading', 'waiting',
      'driver_expense', 'cargo_damage', 'other', 'in_transit_energy',
      'in_transit_charging', 'in_transit_gas', 'in_transit_other'
    ]::text[])
  ),
  constraint tms_expense_item_selectable_category_check check (
    not is_selectable or business_category is not null
  )
);

create unique index tms_expense_item_tenant_code_unique
  on public.tms_expense_item(tenant_id, item_code);
create unique index tms_expense_item_tenant_parent_name_unique
  on public.tms_expense_item(tenant_id, parent_id, item_name) nulls not distinct;
create index tms_expense_item_parent_id_idx on public.tms_expense_item(parent_id);
create index tms_expense_item_tenant_enabled_idx
  on public.tms_expense_item(tenant_id, is_enabled, sort, id);
create index tms_expense_item_tenant_category_idx
  on public.tms_expense_item(tenant_id, business_category)
  where business_category is not null;

alter table public.tms_expense_item enable row level security;

create policy tms_expense_item_tenant_select
on public.tms_expense_item for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_expense_item_tenant_insert
on public.tms_expense_item for insert to authenticated
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_expense_item_tenant_update
on public.tms_expense_item for update to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
with check (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create policy tms_expense_item_tenant_delete
on public.tms_expense_item for delete to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

grant select, insert, update, delete on public.tms_expense_item to authenticated;
grant all privileges on public.tms_expense_item to service_role;
revoke all on public.tms_expense_item from anon;

create or replace function app_private.trg_validate_tms_expense_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_tenant_id uuid;
  v_cursor_id uuid;
begin
  new.item_code := upper(btrim(new.item_code));
  new.item_name := btrim(new.item_name);
  new.remark := nullif(btrim(coalesce(new.remark, '')), '');

  if new.parent_id is null then
    return new;
  end if;

  select tenant_id into v_parent_tenant_id
  from public.tms_expense_item
  where id = new.parent_id;
  if not found then
    raise exception '上级费用项目不存在';
  end if;
  if v_parent_tenant_id is distinct from new.tenant_id then
    raise exception '上级费用项目与当前项目必须属于同一租户';
  end if;
  if new.parent_id = new.id then
    raise exception '费用项目不能将自己设为上级';
  end if;

  v_cursor_id := new.parent_id;
  while v_cursor_id is not null loop
    if v_cursor_id = new.id then
      raise exception '费用项目层级不能形成循环';
    end if;
    select parent_id into v_cursor_id
    from public.tms_expense_item
    where id = v_cursor_id;
  end loop;

  return new;
end;
$$;

create trigger tms_expense_item_validate
before insert or update on public.tms_expense_item
for each row execute function app_private.trg_validate_tms_expense_item();

create trigger tms_expense_item_create_audit
before insert on public.tms_expense_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger tms_expense_item_update_audit
before update on public.tms_expense_item
for each row execute function public.trg_set_update_time_and_by();

create or replace function app_private.seed_tms_expense_items(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_tenant_id is null or not exists (
    select 1 from public.sys_tenant where id = p_tenant_id
  ) then
    raise exception '费用项目初始化租户不存在';
  end if;

  insert into public.tms_expense_item(
    tenant_id, item_code, item_name, business_category, is_selectable,
    reimbursement_allowed, is_enabled, sort, remark, create_by, update_by
  )
  select p_tenant_id, x.item_code, x.item_name, null, false, false, true,
         x.sort, x.remark, 'expense-item-engine', 'expense-item-engine'
  from (values
    ('FYXM-YS', '运输成本', 10, '承运、路桥、装卸及运输过程成本'),
    ('FYXM-ZT', '在途支出', 20, '能源补给及运输途中发生的费用'),
    ('FYXM-QT', '异常与其他', 30, '司机费用、货损及其他费用')
  ) as x(item_code, item_name, sort, remark)
  on conflict (tenant_id, item_code) do nothing;

  insert into public.tms_expense_item(
    tenant_id, parent_id, item_code, item_name, business_category,
    is_selectable, reimbursement_allowed, is_enabled, sort, remark,
    create_by, update_by
  )
  select p_tenant_id, parent.id, x.item_code, x.item_name, x.business_category,
         true, x.reimbursement_allowed, true, x.sort, x.remark,
         'expense-item-engine', 'expense-item-engine'
  from (values
    ('FYXM-YS', 'FYXM-CYF', '承运费', 'carrier_freight', false, 10, '承运商结算费用'),
    ('FYXM-YS', 'FYXM-LQF', '路桥费', 'toll', true, 20, '高速、桥梁及道路通行费'),
    ('FYXM-YS', 'FYXM-TCF', '停车费', 'parking', true, 30, '运输相关停车费用'),
    ('FYXM-YS', 'FYXM-RYF', '燃油费', 'fuel', true, 40, '车辆燃油支出'),
    ('FYXM-YS', 'FYXM-ZXF', '装卸费', 'loading', true, 50, '装车、卸车及搬运费用'),
    ('FYXM-YS', 'FYXM-YCF', '压车等候费', 'waiting', true, 60, '压车、排队及等候费用'),
    ('FYXM-ZT', 'FYXM-NYF', '能源费', 'in_transit_energy', true, 10, '运输途中综合能源费用'),
    ('FYXM-ZT', 'FYXM-CDF', '充电费', 'in_transit_charging', true, 20, '新能源车辆充电费用'),
    ('FYXM-ZT', 'FYXM-JQF', '加气费', 'in_transit_gas', true, 30, '燃气车辆加气费用'),
    ('FYXM-ZT', 'FYXM-ZTQT', '其他在途费', 'in_transit_other', true, 40, '其他运输途中费用'),
    ('FYXM-QT', 'FYXM-SJF', '司机费用', 'driver_expense', true, 10, '司机垫付、补贴及相关费用'),
    ('FYXM-QT', 'FYXM-HSP', '货损赔付', 'cargo_damage', true, 20, '货损、差异及赔付成本'),
    ('FYXM-QT', 'FYXM-QTF', '其他费用', 'other', true, 30, '未归入其他项目的运单费用')
  ) as x(
    parent_code, item_code, item_name, business_category,
    reimbursement_allowed, sort, remark
  )
  join public.tms_expense_item parent
    on parent.tenant_id = p_tenant_id and parent.item_code = x.parent_code
  on conflict (tenant_id, item_code) do nothing;
end;
$$;

do $$
declare
  v_tenant_id uuid;
begin
  for v_tenant_id in select id from public.sys_tenant loop
    perform app_private.seed_tms_expense_items(v_tenant_id);
  end loop;
end;
$$;

create or replace function app_private.trg_seed_tms_expense_items_for_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.seed_tms_expense_items(new.id);
  return new;
end;
$$;

create trigger sys_tenant_seed_tms_expense_items
after insert on public.sys_tenant
for each row execute function app_private.trg_seed_tms_expense_items_for_tenant();

alter table public.tms_waybill_cost
  add column cost_no text,
  add column expense_item_id uuid,
  add column quantity numeric(14,4),
  add column unit_price numeric(14,4),
  add column provider_name text,
  add column payment_channel text,
  add column invoice_no text,
  add column meter_no text,
  add column expense_location text,
  add column waybill_no_snapshot text,
  add column order_no_snapshot text,
  add column plate_no_snapshot text,
  add column driver_name_snapshot text,
  add column driver_phone_snapshot text,
  add column route_snapshot text,
  add column latest_ocr_run_id uuid references public.ai_run(id) on delete set null,
  add column ocr_artifact_id uuid references public.ai_artifact_review(id) on delete set null,
  add column ocr_status text not null default 'not_started',
  add column expense_region text,
  add column expense_region_adcode text,
  add column expense_longitude numeric(10,7),
  add column expense_latitude numeric(10,7),
  add column expense_coordinate_system text,
  add column expense_coordinate_source text,
  add column expense_coordinate_status text not null default 'pending',
  add column expense_geocode_provider text,
  add column expense_geocoded_at timestamptz;

alter table public.tms_waybill_cost
  add constraint tms_waybill_cost_expense_item_id_fkey
    foreign key (expense_item_id) references public.tms_expense_item(id) on delete restrict,
  add constraint tms_waybill_cost_quantity_check check (quantity is null or quantity >= 0),
  add constraint tms_waybill_cost_unit_price_check check (unit_price is null or unit_price >= 0),
  add constraint tms_waybill_cost_ocr_status_check check (
    ocr_status = any (array['not_started', 'processing', 'succeeded', 'failed']::text[])
  ),
  add constraint tms_waybill_cost_longitude_check check (
    expense_longitude is null or expense_longitude between -180 and 180
  ),
  add constraint tms_waybill_cost_latitude_check check (
    expense_latitude is null or expense_latitude between -90 and 90
  ),
  add constraint tms_waybill_cost_coordinate_system_check check (
    expense_coordinate_system is null
    or expense_coordinate_system = any (array['gcj02', 'wgs84', 'bd09']::text[])
  ),
  add constraint tms_waybill_cost_coordinate_source_check check (
    expense_coordinate_source is null
    or expense_coordinate_source = any (
      array['browser', 'manual', 'ocr', 'map_pick', 'geocode', 'import']::text[]
    )
  ),
  add constraint tms_waybill_cost_coordinate_status_check check (
    expense_coordinate_status = any (
      array['pending', 'located', 'failed', 'unconfirmed']::text[]
    )
  );

create index idx_tms_waybill_cost_expense_item_id
  on public.tms_waybill_cost(expense_item_id);
create index idx_tms_waybill_cost_latest_ocr_run_id
  on public.tms_waybill_cost(latest_ocr_run_id);
create index idx_tms_waybill_cost_ocr_artifact_id
  on public.tms_waybill_cost(ocr_artifact_id);

update public.tms_waybill_cost c
set expense_item_id = (
  select i.id
  from public.tms_expense_item i
  where i.tenant_id = c.tenant_id and i.business_category = c.cost_type
  order by i.sort, i.id
  limit 1
)
where c.expense_item_id is null;

update public.tms_waybill_cost c
set cost_no = concat(
  'YDFY', to_char(coalesce(c.create_time, now()) at time zone 'Asia/Shanghai', 'YYYYMM'), '-',
  upper(substr(replace(c.id::text, '-', ''), 1, 8))
)
where c.cost_no is null;

set local session_replication_role = replica;

update public.tms_waybill_cost c
set cost_no = coalesce(nullif(c.cost_no, ''), e.expense_no),
    expense_item_id = item.id,
    quantity = e.quantity,
    unit_price = e.unit_price,
    provider_name = e.provider_name,
    payment_channel = e.payment_channel,
    invoice_no = e.invoice_no,
    meter_no = e.meter_no,
    expense_location = e.expense_location,
    waybill_no_snapshot = e.waybill_no_snapshot,
    order_no_snapshot = e.order_no_snapshot,
    plate_no_snapshot = e.plate_no_snapshot,
    driver_name_snapshot = e.driver_name_snapshot,
    driver_phone_snapshot = e.driver_phone_snapshot,
    route_snapshot = e.route_snapshot,
    latest_ocr_run_id = e.latest_ocr_run_id,
    ocr_artifact_id = e.ocr_artifact_id,
    ocr_status = e.ocr_status,
    expense_region = e.expense_region,
    expense_region_adcode = e.expense_region_adcode,
    expense_longitude = e.expense_longitude,
    expense_latitude = e.expense_latitude,
    expense_coordinate_system = e.expense_coordinate_system,
    expense_coordinate_source = e.expense_coordinate_source,
    expense_coordinate_status = e.expense_coordinate_status,
    expense_geocode_provider = e.expense_geocode_provider,
    expense_geocoded_at = e.expense_geocoded_at,
    source_type = null,
    source_id = null
from public.tms_in_transit_expense e
join lateral (
  select i.id
  from public.tms_expense_item i
  where i.tenant_id = e.tenant_id
    and i.business_category = case e.expense_type
      when 'energy' then 'in_transit_energy'
      when 'charging' then 'in_transit_charging'
      when 'gas' then 'in_transit_gas'
      else 'in_transit_other'
    end
  order by i.sort, i.id
  limit 1
) item on true
where e.cost_id = c.id;

insert into public.tms_waybill_cost(
  id, tenant_id, cost_no, waybill_id, expense_item_id, cost_type, amount,
  occurred_on, quantity, unit_price, provider_name, payee_name, payment_channel,
  invoice_no, meter_no, expense_location, carrier_id, driver_id, remark,
  attachments, audit_status, submitted_at, submitted_by, reviewed_at,
  reviewed_by, review_remark, settlement_status, reimbursement_id,
  expense_payment_id, paid_at, reporter_user_id, reporter_name_snapshot,
  reporter_department_snapshot, waybill_no_snapshot, order_no_snapshot,
  plate_no_snapshot, driver_name_snapshot, driver_phone_snapshot, route_snapshot,
  latest_ocr_run_id, ocr_artifact_id, ocr_status, expense_region,
  expense_region_adcode, expense_longitude, expense_latitude,
  expense_coordinate_system, expense_coordinate_source, expense_coordinate_status,
  expense_geocode_provider, expense_geocoded_at, source_type, source_id,
  create_by, create_time, update_by, update_time
)
select
  e.id, e.tenant_id, e.expense_no, e.waybill_id, item.id,
  item.business_category, e.amount, e.occurred_at::date, e.quantity,
  e.unit_price, e.provider_name, coalesce(e.payee_name, e.provider_name),
  e.payment_channel, e.invoice_no, e.meter_no, e.expense_location,
  w.carrier_id, e.driver_id, e.description, e.attachments,
  case e.report_status
    when 'pending_review' then 'pending_review'
    when 'approved' then 'approved'
    when 'rejected' then 'rejected'
    when 'cancelled' then 'voided'
    else 'draft'
  end,
  e.submitted_at, e.submitted_by, e.reviewed_at, e.reviewed_by, e.review_remark,
  case
    when e.payment_status = 'paid' then 'paid'
    when e.reimbursement_status = 'converted' then 'pending_payment'
    else 'unsettled'
  end,
  r.reimbursement_id, p.id, p.payment_date::timestamptz,
  reporter.id,
  coalesce(reporter.nick_name, reporter.user_name, reporter.user_email, e.create_by, '历史填报人'),
  coalesce(org.organization_name, '未归属部门'),
  e.waybill_no_snapshot, e.order_no_snapshot, e.plate_no_snapshot,
  e.driver_name_snapshot, e.driver_phone_snapshot, e.route_snapshot,
  e.latest_ocr_run_id, e.ocr_artifact_id, e.ocr_status, e.expense_region,
  e.expense_region_adcode, e.expense_longitude, e.expense_latitude,
  e.expense_coordinate_system, e.expense_coordinate_source,
  e.expense_coordinate_status, e.expense_geocode_provider, e.expense_geocoded_at,
  null, null, e.create_by, e.create_time, e.update_by, e.update_time
from public.tms_in_transit_expense e
join public.tms_waybill w on w.id = e.waybill_id
join lateral (
  select i.id, i.business_category
  from public.tms_expense_item i
  where i.tenant_id = e.tenant_id
    and i.business_category = case e.expense_type
      when 'energy' then 'in_transit_energy'
      when 'charging' then 'in_transit_charging'
      when 'gas' then 'in_transit_gas'
      else 'in_transit_other'
    end
  order by i.sort, i.id
  limit 1

) item on true
left join public.tms_expense_reimbursement_item r on r.expense_id = e.id
left join public.tms_expense_payment p on p.reimbursement_id = r.reimbursement_id
left join lateral (
  select u.*
  from public.sys_user u
  where u.tenant_id = e.tenant_id and u.status = '1' and u.deleted_at is null
  order by
    case when u.user_email = e.create_by or u.user_name = e.create_by then 0 else 1 end,
    u.create_time,
    u.id
  limit 1
) reporter on true
left join public.sys_organization org on org.id = reporter.organization_id
where e.cost_id is null
   or not exists (select 1 from public.tms_waybill_cost c where c.id = e.cost_id)
on conflict (id) do nothing;

update public.tms_in_transit_expense e
set cost_id = e.id
where (e.cost_id is null or not exists (
  select 1 from public.tms_waybill_cost c where c.id = e.cost_id
)) and exists (
  select 1 from public.tms_waybill_cost c where c.id = e.id
);

set local session_replication_role = origin;

do $$
begin
  if exists (select 1 from public.tms_waybill_cost where expense_item_id is null) then
    raise exception '运单费用项目迁移不完整，已中止删除旧在途费用对象';
  end if;
  if exists (
    select 1 from public.tms_in_transit_expense e
    where e.cost_id is null
       or not exists (select 1 from public.tms_waybill_cost c where c.id = e.cost_id)
  ) then
    raise exception '在途费用迁移不完整，已中止删除旧表';
  end if;
  if exists (
    select 1 from public.wf_instance where business_type = 'tms_in_transit_expense'
  ) then
    raise exception '仍存在在途费用审批实例，请先完成流程归档再执行合并迁移';
  end if;
end;
$$;

alter table public.tms_waybill_cost
  alter column cost_no set not null,
  alter column expense_item_id set not null;

create unique index tms_waybill_cost_tenant_cost_no_unique
  on public.tms_waybill_cost(tenant_id, cost_no);

create or replace function app_private.trg_prepare_tms_waybill_cost()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_waybill record;
  v_item record;
begin
  select w.tenant_id, w.order_id, w.waybill_no, w.carrier_id, w.driver_id,
         o.order_no, o.dispatch_plate_no,
         coalesce(d.driver_name, o.dispatch_driver_name) as driver_name,
         coalesce(d.phone, o.dispatch_driver_phone) as driver_phone,
         concat_ws(' → ', nullif(w.origin_city, ''), nullif(w.destination_city, '')) as route_name
  into v_waybill
  from public.tms_waybill w
  left join public.tms_order o on o.id = w.order_id and o.tenant_id = w.tenant_id
  left join public.tms_driver d on d.id = w.driver_id
  where w.id = new.waybill_id;
  if not found then raise exception '关联运单不存在'; end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_waybill.tenant_id;
  elsif new.tenant_id is distinct from old.tenant_id then
    raise exception '费用所属租户不可修改';
  elsif old.audit_status in ('pending_review', 'approved') and (
    new.expense_item_id is distinct from old.expense_item_id
    or new.quantity is distinct from old.quantity
    or new.unit_price is distinct from old.unit_price
    or new.provider_name is distinct from old.provider_name
    or new.payment_channel is distinct from old.payment_channel
    or new.invoice_no is distinct from old.invoice_no
    or new.meter_no is distinct from old.meter_no
    or new.expense_location is distinct from old.expense_location
    or new.expense_longitude is distinct from old.expense_longitude
    or new.expense_latitude is distinct from old.expense_latitude
  ) then
    raise exception '待审核或已审核费用不可修改费用项目及票据业务字段';
  end if;

  if new.tenant_id is distinct from v_waybill.tenant_id then
    raise exception '费用与运单必须属于同一租户';
  end if;

  select i.business_category, i.is_selectable, i.is_enabled
  into v_item
  from public.tms_expense_item i
  where i.id = new.expense_item_id and i.tenant_id = new.tenant_id;
  if not found then raise exception '费用项目不存在或不属于当前租户'; end if;
  if (tg_op = 'INSERT' or new.expense_item_id is distinct from old.expense_item_id)
     and (not v_item.is_selectable or not v_item.is_enabled) then
    raise exception '只能选择已启用的末级费用项目';
  end if;

  new.cost_type := v_item.business_category;
  new.waybill_no_snapshot := v_waybill.waybill_no;
  new.order_no_snapshot := v_waybill.order_no;
  new.plate_no_snapshot := v_waybill.dispatch_plate_no;
  new.driver_id := coalesce(new.driver_id, v_waybill.driver_id);
  new.carrier_id := coalesce(new.carrier_id, v_waybill.carrier_id);
  new.driver_name_snapshot := v_waybill.driver_name;
  new.driver_phone_snapshot := v_waybill.driver_phone;
  new.route_snapshot := v_waybill.route_name;
  new.amount := round(new.amount, 2);
  new.provider_name := nullif(btrim(coalesce(new.provider_name, '')), '');
  new.payee_name := nullif(btrim(coalesce(new.payee_name, '')), '');
  new.payment_channel := nullif(btrim(coalesce(new.payment_channel, '')), '');
  new.invoice_no := nullif(btrim(coalesce(new.invoice_no, '')), '');
  new.meter_no := nullif(btrim(coalesce(new.meter_no, '')), '');
  new.expense_location := nullif(btrim(coalesce(new.expense_location, '')), '');
  new.remark := nullif(btrim(coalesce(new.remark, '')), '');
  return new;
end;
$$;

create trigger tms_waybill_cost_prepare_expense
before insert or update on public.tms_waybill_cost
for each row execute function app_private.trg_prepare_tms_waybill_cost();

delete from public.sys_document_number_rule where rule_key = 'tms.in_transit_expense';

update public.sys_document_number_scene
set rule_key = 'tms.waybill_cost',
    rule_name = '运单费用单号',
    field_label = '费用单号',
    menu_id = (select id from public.sys_menu where name = 'TmsWaybillCost' limit 1),
    target_table = 'tms_waybill_cost',
    target_column = 'cost_no',
    default_template = 'YDFY{YYYYMM}-{SEQ:4}',
    default_reset_cycle = 'month',
    manual_required = true,
    enabled = true,
    remark = '运单费用统一台账编号',
    update_by = '624944977@qq.com',
    update_time = now()
where rule_key = 'tms.in_transit_expense';

insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table,
  target_column, default_template, default_reset_cycle, manual_required,
  enabled, remark, create_by, update_by, tenant_id
)
select
  'tms.waybill_cost', '运单费用单号', '费用单号', 'business_document',
  menu.id, 'tms_waybill_cost', 'cost_no', 'YDFY{YYYYMM}-{SEQ:4}',
  'month', true, true, '运单费用统一台账编号',
  '624944977@qq.com', '624944977@qq.com', tenant.id
from public.sys_tenant tenant
cross join public.sys_menu menu
where tenant.tenant_code = 'platform'
  and menu.name = 'TmsWaybillCost'
  and not exists (
    select 1 from public.sys_document_number_scene where rule_key = 'tms.waybill_cost'
  );

do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app_private'
    and p.proname = 'seed_document_number_rules'
    and pg_get_function_identity_arguments(p.oid) = 'p_tenant_id uuid';

  v_updated := replace(
    v_definition,
    $old$('tms.in_transit_expense', '在途费用单号', 'business_document', 'tms_in_transit_expense', 'expense_no', 'ZTFY{YYYYMM}-{SEQ:4}', 'month', true, null)$old$,
    $new$('tms.waybill_cost', '运单费用单号', 'business_document', 'tms_waybill_cost', 'cost_no', 'YDFY{YYYYMM}-{SEQ:4}', 'month', true, '运单费用统一台账编号')$new$
  );
  if v_definition is null or v_updated = v_definition then
    raise exception '未能更新租户单号规则初始化函数';
  end if;
  execute v_updated;
end;
$$;

insert into public.sys_document_number_rule(
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select t.id, 'tms.waybill_cost', '运单费用单号', 'business_document',
       'tms_waybill_cost', 'cost_no', true, 'YDFY{YYYYMM}-{SEQ:4}',
       'month', 1, 'Asia/Shanghai', true, true, true,
       '运单费用统一台账编号', 'number-engine', 'number-engine'
from public.sys_tenant t
on conflict (tenant_id, rule_key) do update
set rule_name = excluded.rule_name,
    target_table = excluded.target_table,
    target_column = excluded.target_column,
    template = excluded.template,
    remark = excluded.remark,
    enabled = true,
    update_by = 'number-engine',
    update_time = now();

create trigger document_number_cost_no
before insert on public.tms_waybill_cost
for each row execute function app_private.trg_assign_configurable_number('tms.waybill_cost', 'cost_no');

drop view if exists public.tms_in_transit_expense_summary;
drop view if exists public.tms_in_transit_expense_overview;

alter table public.tms_expense_reimbursement_item
  drop constraint tms_expense_reimbursement_item_expense_id_fkey;

update public.tms_expense_reimbursement_item i
set expense_id = e.cost_id
from public.tms_in_transit_expense e
where e.id = i.expense_id;

alter table public.tms_expense_reimbursement_item
  rename column expense_id to cost_id;
alter table public.tms_expense_reimbursement_item
  rename column expense_no_snapshot to cost_no_snapshot;
alter table public.tms_expense_reimbursement_item
  rename column expense_type_snapshot to expense_item_name_snapshot;
alter table public.tms_expense_reimbursement_item
  rename column occurred_at_snapshot to occurred_on_snapshot;
alter table public.tms_expense_reimbursement_item
  alter column occurred_on_snapshot type date using occurred_on_snapshot::date;

update public.tms_expense_reimbursement_item i
set cost_no_snapshot = c.cost_no,
    expense_item_name_snapshot = item.item_name,
    occurred_on_snapshot = c.occurred_on
from public.tms_waybill_cost c
join public.tms_expense_item item on item.id = c.expense_item_id
where c.id = i.cost_id;

alter table public.tms_expense_reimbursement_item
  add constraint tms_expense_reimbursement_item_cost_id_fkey
    foreign key (cost_id) references public.tms_waybill_cost(id) on delete restrict;

drop index if exists public.idx_tms_expense_reimbursement_item_expense_id;
create index idx_tms_expense_reimbursement_item_cost_id
  on public.tms_expense_reimbursement_item(cost_id);

drop function if exists public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
);
drop function if exists public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text, text
);

create function public.create_tms_expense_reimbursement(
  p_cost_ids uuid[],
  p_payee_name text,
  p_payee_bank text,
  p_payee_account text,
  p_planned_payment_date date,
  p_payment_method text,
  p_basis_urls jsonb default '[]'::jsonb,
  p_remark text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
  v_actor_name text;
  v_id uuid;
  v_count integer;
  v_total numeric(14,2);
begin
  if auth.uid() is null or v_tenant_id is null or v_user_id is null then
    raise exception '请登录后操作';
  end if;
  if coalesce(array_length(p_cost_ids, 1), 0) = 0 then
    raise exception '请选择要转报销的运单费用';
  end if;
  if nullif(btrim(coalesce(p_payee_name, '')), '') is null then
    raise exception '请填写收款人';
  end if;
  if p_planned_payment_date is null then raise exception '请选择计划付款日期'; end if;
  if p_payment_method not in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other') then
    raise exception '付款方式不正确';
  end if;
  if jsonb_typeof(coalesce(p_basis_urls, '[]'::jsonb)) <> 'array' then
    raise exception '报销依据格式不正确';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tenant_id::text || ':expense-reimbursement', 841331));
  perform 1 from public.tms_waybill_cost
  where id = any(p_cost_ids) and tenant_id = v_tenant_id
  order by id for update;

  select count(*)::integer, coalesce(sum(c.amount), 0)::numeric(14,2)
  into v_count, v_total
  from public.tms_waybill_cost c
  join public.tms_expense_item item on item.id = c.expense_item_id
  where c.id = any(p_cost_ids)
    and c.tenant_id = v_tenant_id
    and c.audit_status = 'approved'
    and c.settlement_status = 'unsettled'
    and c.reimbursement_id is null
    and c.expense_payment_id is null
    and item.reimbursement_allowed;
  if v_count <> cardinality(p_cost_ids) then
    raise exception '仅已审核、未结算且允许报销的运单费用可以转换，请刷新后重试';
  end if;

  select coalesce(nullif(nick_name, ''), nullif(user_name, ''), user_email, id::text)
  into v_actor_name from public.sys_user where id = v_user_id;

  insert into public.tms_expense_reimbursement(
    tenant_id, reimbursement_no, applicant_user_id, applicant_name_snapshot,
    payee_name, payee_bank, payee_account, planned_payment_date, payment_method,
    total_amount, basis_urls, remark, create_by, update_by
  ) values (
    v_tenant_id, '', v_user_id, v_actor_name, btrim(p_payee_name),
    nullif(btrim(coalesce(p_payee_bank, '')), ''),
    nullif(btrim(coalesce(p_payee_account, '')), ''), p_planned_payment_date,
    p_payment_method, v_total, coalesce(p_basis_urls, '[]'::jsonb),
    nullif(btrim(coalesce(p_remark, '')), ''), v_actor, v_actor
  ) returning id into v_id;

  insert into public.tms_expense_reimbursement_item(
    tenant_id, reimbursement_id, cost_id, waybill_id, cost_no_snapshot,
    waybill_no_snapshot, expense_item_name_snapshot, amount_snapshot,
    occurred_on_snapshot, create_by, update_by
  )
  select c.tenant_id, v_id, c.id, c.waybill_id, c.cost_no,
         c.waybill_no_snapshot, item.item_name, c.amount, c.occurred_on,
         v_actor, v_actor
  from public.tms_waybill_cost c
  join public.tms_expense_item item on item.id = c.expense_item_id
  where c.id = any(p_cost_ids);

  update public.tms_waybill_cost
  set reimbursement_id = v_id, settlement_status = 'pending_payment'
  where id = any(p_cost_ids);
  return v_id;
end;
$$;

create function public.create_tms_expense_reimbursement(
  p_cost_ids uuid[], p_payee_name text, p_payee_bank text, p_payee_account text,
  p_planned_payment_date date, p_payment_method text, p_basis_urls jsonb,
  p_remark text, p_reimbursement_no text
)
returns uuid
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('app.document_number.tms_expense_reimbursement', coalesce(p_reimbursement_no, ''), true);
  return public.create_tms_expense_reimbursement(
    p_cost_ids, p_payee_name, p_payee_bank, p_payee_account,
    p_planned_payment_date, p_payment_method, p_basis_urls, p_remark
  );
end;
$$;

create or replace function public.delete_tms_expense_reimbursement(p_reimbursement_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_status text;
begin
  if auth.uid() is null or v_tenant_id is null then raise exception '请登录后操作'; end if;
  select status into v_status
  from public.tms_expense_reimbursement
  where id = p_reimbursement_id and tenant_id = v_tenant_id for update;
  if not found then raise exception '费用报销单不存在或无权删除'; end if;
  if v_status not in ('draft', 'rejected') then
    raise exception '仅草稿或已驳回报销单可以删除';
  end if;

  update public.tms_waybill_cost
  set reimbursement_id = null, settlement_status = 'unsettled'
  where reimbursement_id = p_reimbursement_id;

  delete from public.tms_expense_reimbursement where id = p_reimbursement_id;
  return p_reimbursement_id;
end;
$$;

create or replace function public.execute_tms_expense_reimbursement(
  p_reimbursement_id uuid,
  p_payment_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
  v_reimbursement public.tms_expense_reimbursement;
  v_payment_id uuid;
begin
  if auth.uid() is null or v_tenant_id is null then raise exception '请登录后操作'; end if;
  if p_payment_date is null then raise exception '请选择实际付款日期'; end if;
  if jsonb_typeof(coalesce(p_voucher_urls, '[]'::jsonb)) <> 'array' then
    raise exception '付款凭证格式不正确';
  end if;

  select * into v_reimbursement
  from public.tms_expense_reimbursement
  where id = p_reimbursement_id and tenant_id = v_tenant_id for update;
  if not found then raise exception '费用报销单不存在或无权付款'; end if;
  if v_reimbursement.status <> 'approved' then
    raise exception '仅审批通过且未支付的报销单可以登记付款';
  end if;
  if v_reimbursement.payment_method = 'bank_transfer'
     and nullif(btrim(coalesce(p_bank_reference, '')), '') is null then
    raise exception '银行转账必须填写银行流水号';
  end if;

  perform set_config('app.expense_payment_engine', 'on', true);
  insert into public.tms_expense_payment(
    tenant_id, payment_no, reimbursement_id, payee_name_snapshot, payment_date,
    amount, payment_method, bank_reference, voucher_urls, remark, paid_by,
    create_by, update_by
  ) values (
    v_reimbursement.tenant_id, '', v_reimbursement.id, v_reimbursement.payee_name,
    p_payment_date, v_reimbursement.total_amount, v_reimbursement.payment_method,
    nullif(btrim(coalesce(p_bank_reference, '')), ''), coalesce(p_voucher_urls, '[]'::jsonb),
    nullif(btrim(coalesce(p_remark, '')), ''), v_actor, v_actor, v_actor
  ) returning id into v_payment_id;

  update public.tms_expense_reimbursement
  set status = 'paid', paid_at = now(), paid_by = v_actor,
      payment_reference = nullif(btrim(coalesce(p_bank_reference, '')), ''),
      payment_voucher_urls = coalesce(p_voucher_urls, '[]'::jsonb)
  where id = v_reimbursement.id;

  update public.tms_waybill_cost c
  set settlement_status = 'paid', expense_payment_id = v_payment_id, paid_at = now()
  from public.tms_expense_reimbursement_item i
  where i.reimbursement_id = v_reimbursement.id and i.cost_id = c.id;
  return v_payment_id;
end;
$$;

revoke all on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) from public, anon;
revoke all on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text, text
) from public, anon;
grant execute on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text, text
) to authenticated, service_role;

create or replace view public.tms_waybill_cost_overview
with (security_invoker = true)
as
select
  c.tenant_id,
  count(*)::integer as total_count,
  count(*) filter (where c.audit_status = 'pending_review')::integer as pending_review_count,
  count(*) filter (
    where c.audit_status = 'approved'
      and c.settlement_status = 'unsettled'
      and item.reimbursement_allowed
  )::integer as approved_unconverted_count,
  coalesce(sum(c.amount) filter (
    where c.settlement_status = 'pending_payment'
  ), 0)::numeric(14,2) as pending_payment_amount,
  coalesce(sum(c.amount) filter (
    where c.settlement_status = 'paid'
  ), 0)::numeric(14,2) as paid_amount
from public.tms_waybill_cost c
join public.tms_expense_item item on item.id = c.expense_item_id
where c.audit_status <> 'voided'
group by c.tenant_id;

grant select on public.tms_waybill_cost_overview to authenticated, service_role;
revoke all on public.tms_waybill_cost_overview from anon;

do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app_private'
    and p.proname = 'validate_workflow_business_config'
    and pg_get_function_identity_arguments(p.oid) = 'p_business_type text, p_config jsonb';

  v_updated := replace(
    v_definition,
    $old$array['amount','costType','payeeName','waybillNo','occurredOn']$old$,
    $new$array['amount','costType','expenseItemName','payeeName','waybillNo','plateNo','driverName','occurredOn','ocrStatus']$new$
  );
  v_updated := replace(
    v_updated,
    $old$    when 'tms_in_transit_expense' then array['amount','expenseType','waybillNo','plateNo','driverName','occurredOn']
$old$,
    ''
  );
  if v_definition is null or v_updated = v_definition then
    raise exception '未能移除在途费用工作流条件字段并扩展运单费用字段';
  end if;
  execute v_updated;

  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app_private'
    and p.proname = 'get_workflow_business_snapshot'
    and pg_get_function_identity_arguments(p.oid) = 'p_instance_id uuid';

  v_updated := replace(
    v_definition,
    $old$select c.*,w.waybill_no into v_r from public.tms_waybill_cost c
      left join public.tms_waybill w on w.id=c.waybill_id where c.id=v_i.business_id;$old$,
    $new$select c.*,w.waybill_no,item.item_name as expense_item_name into v_r from public.tms_waybill_cost c
      left join public.tms_waybill w on w.id=c.waybill_id
      left join public.tms_expense_item item on item.id=c.expense_item_id
      where c.id=v_i.business_id;$new$
  );
  v_updated := replace(
    v_updated,
    $old$v_subtitle:=concat_ws(' · ',v_r.cost_type,v_r.payee_name);$old$,
    $new$v_subtitle:=concat_ws(' · ',v_r.expense_item_name,v_r.payee_name);$new$
  );
  v_updated := replace(
    v_updated,
    $old$jsonb_build_object('label','费用类型','value',coalesce(v_r.cost_type,'--')),$old$,
    $new$jsonb_build_object('label','费用项目','value',coalesce(v_r.expense_item_name,'--')),$new$
  );
  if v_definition is null or v_updated = v_definition then
    raise exception '未能将工作流运单费用快照切换为费用项目';
  end if;
  execute v_updated;
end;
$$;

create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_business_type = 'tms_carrier_payment_application' then
    perform app_private.execute_carrier_payment_application_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  elsif p_business_type = 'tms_expense_reimbursement' then
    perform app_private.execute_expense_reimbursement_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  elsif p_business_type = 'vehicle_archive' then
    perform app_private.execute_vehicle_archive_workflow_callback(
      p_business_id, p_status, p_actor, p_comment
    );
  else
    perform app_private.execute_workflow_business_callback_legacy(
      p_business_type, p_business_id, p_status, p_actor, p_comment
    );
  end if;
end;
$$;

delete from public.wf_definition where business_type = 'tms_in_transit_expense';
delete from public.wf_business_callback_outbox where business_type = 'tms_in_transit_expense';

alter table public.ai_ocr_quality_threshold
  drop constraint ai_ocr_quality_threshold_feature_check;
alter table public.ai_ocr_quality_threshold
  add constraint ai_ocr_quality_threshold_feature_check check (
    feature = any (array[
      'invoice_ocr', 'waybill_receipt_ocr', 'cash_voucher_ocr',
      'bank_statement_batch_match', 'in_transit_expense_ocr', 'waybill_expense_ocr'
    ]::text[])
  );

set local session_replication_role = replica;
update public.ai_feature_config set feature = 'waybill_expense_ocr'
where feature = 'in_transit_expense_ocr';
update public.ai_run set feature = 'waybill_expense_ocr'
where feature = 'in_transit_expense_ocr';
update public.ai_artifact_review set feature = 'waybill_expense_ocr'
where feature = 'in_transit_expense_ocr';
update public.ai_ocr_quality_threshold set feature = 'waybill_expense_ocr'
where feature = 'in_transit_expense_ocr';
update public.ai_prompt_template set feature = 'waybill_expense_ocr'
where feature = 'in_transit_expense_ocr';
set local session_replication_role = origin;

alter table public.ai_ocr_quality_threshold
  drop constraint ai_ocr_quality_threshold_feature_check;
alter table public.ai_ocr_quality_threshold
  add constraint ai_ocr_quality_threshold_feature_check check (
    feature = any (array[
      'invoice_ocr', 'waybill_receipt_ocr', 'cash_voucher_ocr',
      'bank_statement_batch_match', 'waybill_expense_ocr'
    ]::text[])
  );

do $$
declare
  v_type_id uuid;
  v_tenant_id uuid;
  v_actor text := '624944977@qq.com';
  v_entry record;
begin
  select tenant_id into v_tenant_id
  from public.sys_dict_type
  where code = 'tmsCostAuditStatus'
  limit 1;

  if v_tenant_id is null then
    v_tenant_id := app_private.platform_tenant_id();
  end if;

  select id into v_type_id
  from public.sys_dict_type
  where code = 'tmsWaybillCostSettlementStatus'
  limit 1;

  if v_type_id is null then
    v_type_id := gen_random_uuid();
    insert into public.sys_dict_type(
      id, tenant_id, name, code, status, node_type, sort, create_by, update_by, remark
    ) values (
      v_type_id, v_tenant_id, '运单费用核销状态', 'tmsWaybillCostSettlementStatus',
      '1', 'dictionary', 12, v_actor, v_actor, '运单费用报销及支付核销状态'
    );
  end if;

  for v_entry in
    select * from (values
      ('unsettled', '未核销', 'unsettled', 'info', 1),
      ('pending_payment', '待支付', 'pending_payment', 'warning', 2),
      ('paid', '已支付', 'paid', 'success', 3)
    ) as entries(code, label, value, tag_type, sort)
  loop
    if not exists (
      select 1 from public.sys_dictionary
      where type_id = v_type_id and value = v_entry.value
    ) then
      insert into public.sys_dictionary(
        id, tenant_id, type_id, code, label, value, tag_type, sort,
        status, create_by, update_by
      ) values (
        gen_random_uuid(), v_tenant_id, v_type_id, v_entry.code, v_entry.label,
        v_entry.value, v_entry.tag_type, v_entry.sort, '1', v_actor, v_actor
      );
    end if;
  end loop;
end;
$$;

do $$
declare
  v_finance_menu_id uuid;
  v_waybill_cost_menu_id uuid;
  v_expense_item_menu_id uuid;
  v_in_transit_menu_id uuid;
begin
  select id into v_finance_menu_id
  from public.sys_menu where name = 'TmsFinanceCenter' limit 1;
  select id into v_waybill_cost_menu_id
  from public.sys_menu where name = 'TmsWaybillCost' limit 1;
  select id into v_in_transit_menu_id
  from public.sys_menu where name = 'TmsInTransitExpense' limit 1;

  if v_finance_menu_id is null or v_waybill_cost_menu_id is null then
    raise exception '财务中心或运单费用菜单不存在，无法完成费用项目菜单迁移';
  end if;

  select id into v_expense_item_menu_id
  from public.sys_menu where name = 'TmsExpenseItem' limit 1;
  if v_expense_item_menu_id is null then
    v_expense_item_menu_id := gen_random_uuid();
    insert into public.sys_menu(
      id, parent_id, name, path, component, meta, sort, type,
      create_by, update_by
    ) values (
      v_expense_item_menu_id, v_finance_menu_id, 'TmsExpenseItem', 'expense-item',
      '/tms-transportation/finance-center/expense-item',
      jsonb_build_object(
        'title', '费用项目', 'icon', 'ri:node-tree',
        'is_enable', true, 'keep_alive', true
      ),
      8, 'menu', '624944977@qq.com', '624944977@qq.com'
    );
  end if;

  insert into public.sys_role_menu(
    id, tenant_id, role_id, menu_id, permission, create_by, update_by
  )
  select gen_random_uuid(), rm.tenant_id, rm.role_id, v_expense_item_menu_id,
         coalesce(rm.permission, '{}'::jsonb), '624944977@qq.com', '624944977@qq.com'
  from public.sys_role_menu rm
  where rm.menu_id = v_waybill_cost_menu_id
    and not exists (
      select 1 from public.sys_role_menu existing
      where existing.tenant_id = rm.tenant_id
        and existing.role_id = rm.role_id
        and existing.menu_id = v_expense_item_menu_id
    );

  if v_in_transit_menu_id is not null then
    update public.sys_document_number_scene
    set menu_id = v_waybill_cost_menu_id,
        update_by = '624944977@qq.com',
        update_time = now()
    where menu_id = v_in_transit_menu_id;
    delete from public.sys_role_menu where menu_id = v_in_transit_menu_id;
    delete from public.sys_menu where id = v_in_transit_menu_id;
  end if;
end;
$$;

drop table public.tms_in_transit_expense;
drop function if exists app_private.execute_in_transit_expense_workflow_callback(uuid, text, text, text);
drop function if exists app_private.trg_prepare_tms_in_transit_expense();

comment on table public.tms_expense_item is '租户级费用项目树；末级项目供运单费用必选，业务分类驱动结算和利润规则';
comment on column public.tms_expense_item.business_category is '系统业务分类；由费用项目维护，运单费用不直接选择该值';
comment on column public.tms_expense_item.reimbursement_allowed is '是否允许进入费用报销/出纳付款链路；承运费由承运商结算处理';
comment on column public.tms_waybill_cost.expense_item_id is '费用项目主数据，用户登记运单费用时必选';
comment on column public.tms_waybill_cost.cost_type is '由费用项目派生的内部业务分类，保留用于利润与结算规则';

;
