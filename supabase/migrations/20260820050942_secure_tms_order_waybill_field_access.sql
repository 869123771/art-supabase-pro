-- Secure order snapshots, waybill execution data, and every read surface that
-- consumes their sensitive contacts, addresses, prices, coordinates, or proof files.

alter table public.tms_order
  add column if not exists created_by_user_id uuid;

alter table public.tms_waybill
  add column if not exists created_by_user_id uuid;

-- Backfill immutable ownership without invoking operational status/audit guards.
-- The migration holds the table locks and reenables every user trigger in the
-- same transaction before exposing the schema.
alter table public.tms_order disable trigger user;
alter table public.tms_waybill disable trigger user;

update public.tms_order order_row
set created_by_user_id = creator.id
from public.sys_user creator
where order_row.created_by_user_id is null
  and creator.tenant_id = order_row.tenant_id
  and lower(btrim(creator.user_email)) = lower(btrim(order_row.create_by));

update public.tms_waybill waybill_row
set created_by_user_id = creator.id
from public.sys_user creator
where waybill_row.created_by_user_id is null
  and creator.tenant_id = waybill_row.tenant_id
  and lower(btrim(creator.user_email)) = lower(btrim(waybill_row.create_by));

alter table public.tms_order enable trigger user;
alter table public.tms_waybill enable trigger user;

do $$
begin
  if exists (select 1 from public.tms_order where created_by_user_id is null) then
    raise exception 'Cannot secure tms_order: one or more creator identities could not be backfilled';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_order_creator_tenant_fkey'
      and conrelid = 'public.tms_order'::regclass
  ) then
    alter table public.tms_order
      add constraint tms_order_creator_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user(id, tenant_id)
      on update restrict
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_waybill_creator_tenant_fkey'
      and conrelid = 'public.tms_waybill'::regclass
  ) then
    alter table public.tms_waybill
      add constraint tms_waybill_creator_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user(id, tenant_id)
      on update restrict
      on delete restrict;
  end if;
end
$$;

alter table public.tms_order
  alter column created_by_user_id set not null;

-- One historical waybill was created by an account that is no longer a member
-- of its tenant. Keep that row ownerless instead of assigning a false owner or
-- linking to the same email in another tenant. New authenticated rows are strict.
create index if not exists idx_tms_order_tenant_creator
  on public.tms_order (tenant_id, created_by_user_id, create_time desc);
create index if not exists tms_order_creator_tenant_fk_idx
  on public.tms_order (created_by_user_id, tenant_id);
create index if not exists idx_tms_waybill_tenant_creator
  on public.tms_waybill (tenant_id, created_by_user_id, create_time desc);
create index if not exists tms_waybill_creator_tenant_fk_idx
  on public.tms_waybill (created_by_user_id, tenant_id);

comment on column public.tms_order.created_by_user_id is
  'Stable creator identity used for record-owner field permission resolution.';
comment on column public.tms_waybill.created_by_user_id is
  'Stable creator identity. Historical rows may be null when the original tenant member no longer exists.';

create or replace function app_private.set_tms_transport_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      if v_current_user_id is null then
        raise exception 'Authenticated application user not found' using errcode = '42501';
      end if;
      new.created_by_user_id := v_current_user_id;
    elsif tg_table_name = 'tms_order' and new.created_by_user_id is null then
      raise exception 'Creator identity is required';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Keep the previous catalog seeder as the stable base and extend the canonical
-- entry point for current and future tenants.
alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_base;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_base(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.order', '订单与开单快照', 'TmsOrderList', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'shipperContact', '发货联系人电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'shipperAddress', '发货详细地址与定位', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'receiverContact', '收货联系人电话', 'hidden', 'phone', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'receiverAddress', '收货详细地址与定位', 'hidden', 'address', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'cargoPricing', '货物单价与分项运费', 'hidden', 'amount', true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'freightAmounts', '运费与附加费用', 'hidden', 'amount', true, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'settlementAmounts', '收付款与代收金额', 'hidden', 'amount', true, 70, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'driverPhone', '承运司机电话', 'hidden', 'phone', true, 80, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'proofAttachments', '订单与回单附件', 'hidden', 'none', true, 90, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'routeCoordinates', '收发货精确坐标', 'hidden', 'none', true, 100, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.waybill', '运单与运输执行', 'TmsWaybillManagement', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'shipperContact', '托运方联系电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'shipperAddress', '装货详细地址', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'receiverContact', '收货方联系电话', 'hidden', 'phone', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'receiverAddress', '卸货详细地址', 'hidden', 'address', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'cargoPricing', '货物计价信息', 'hidden', 'amount', true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'freightAmounts', '运单运费', 'hidden', 'amount', true, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'settlementAmounts', '签收与代收金额', 'hidden', 'amount', true, 70, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'driverPhone', '司机联系电话', 'hidden', 'phone', true, 80, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'carrierPhone', '承运商联系电话', 'hidden', 'phone', true, 90, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'proofAttachments', '装卸、签名与回单凭证', 'hidden', 'none', true, 100, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'routeCoordinates', '轨迹与作业精确定位', 'hidden', 'none', true, 110, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

do $$
declare
  tenant_row record;
begin
  for tenant_row in select id from public.sys_tenant loop
    perform app_private.seed_field_permission_catalog(tenant_row.id);
  end loop;
end
$$;

-- Existing roles keep their current operational visibility. Roles with actual
-- edit/lifecycle actions retain edit; read-only and unrelated existing roles
-- receive read so dashboards and established shared selectors do not regress.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  role_row.tenant_id,
  role_row.id,
  resource_row.id,
  field_row.id,
  case when exists (
    select 1
    from public.sys_role_menu role_menu
    join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
    where role_menu.tenant_id = role_row.tenant_id
      and role_menu.role_id = role_row.id
      and menu_row.type = 'button'
      and (
        (resource_row.resource_key = 'tms.order' and (
          menu_row.name like 'TmsWaybill:%'
          or menu_row.name in (
            'TmsOrderList:Edit', 'TmsOrderList:EditFreight', 'TmsOrderOpen:Create',
            'TmsDeliveryManagement:ArchiveReceipt', 'TmsDeliveryManagement:ManageException'
          )
        ))
        or (resource_row.resource_key = 'tms.waybill' and (
          menu_row.name like 'TmsWaybill:%'
          or menu_row.name in (
            'TmsDeliveryManagement:ArchiveReceipt', 'TmsDeliveryManagement:ManageException'
          )
        ))
      )
  ) then 'edit' else 'read' end,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role role_row
join public.sys_permission_resource resource_row
  on resource_row.tenant_id = role_row.tenant_id
 and resource_row.resource_key in ('tms.order', 'tms.waybill')
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
where role_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.secure_scalar_json(
  p_data jsonb,
  p_column text,
  p_value text,
  p_level text,
  p_strategy text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_level, 'hidden') = 'hidden' then p_data - p_column
    when p_level = 'masked' then jsonb_set(
      p_data,
      array[p_column],
      coalesce(to_jsonb(app_private.mask_permission_value(p_value, p_strategy)), 'null'::jsonb),
      true
    )
    else p_data
  end;
$$;

create or replace function app_private.secure_tms_order_cargo_items(
  p_items jsonb,
  p_level text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    case
      when coalesce(p_level, 'hidden') = 'hidden' then item - 'unit_price' - 'freight'
      when p_level = 'masked' then
        jsonb_set(
          jsonb_set(
            item,
            '{unit_price}',
            coalesce(to_jsonb(app_private.mask_permission_value(item->>'unit_price', 'amount')), 'null'::jsonb),
            true
          ),
          '{freight}',
          coalesce(to_jsonb(app_private.mask_permission_value(item->>'freight', 'amount')), 'null'::jsonb),
          true
        )
      else item
    end
    order by ordinal
  ), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end)
    with ordinality as cargo(item, ordinal);
$$;

create or replace function app_private.tms_order_to_secure_json(
  p_order public.tms_order,
  p_resource_key text default 'tms.order',
  p_access jsonb default null,
  p_owner_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_effective_owner_id uuid := case when p_access is null then p_order.created_by_user_id else p_owner_id end;
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map(p_resource_key, p_order.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_order) - 'tenant_id' - 'created_by_user_id';
  v_level text;
  v_column text;
  v_origin_station jsonb;
  v_destination_station jsonb;
  v_transfer_station jsonb;
  v_shipping_customer jsonb;
  v_receiving_customer jsonb;
  v_latest_waybill jsonb;
  v_latest_waybill_id uuid;
  v_unloading_status text;
  v_execution public.tms_waybill_execution_record%rowtype;
begin
  if p_resource_key not in ('tms.order', 'tms.waybill') then
    raise exception 'Unsupported transport field-permission resource';
  end if;

  v_data := app_private.secure_scalar_json(
    v_data, 'shipping_contact_phone', p_order.shipping_contact_phone,
    v_access->>'shipperContact', 'phone'
  );
  v_data := app_private.secure_scalar_json(
    v_data, 'receiving_contact_phone', p_order.receiving_contact_phone,
    v_access->>'receiverContact', 'phone'
  );

  v_level := coalesce(v_access->>'shipperAddress', 'hidden');
  v_data := app_private.secure_scalar_json(
    v_data, 'shipping_address_detail', p_order.shipping_address_detail, v_level, 'address'
  );
  if v_level not in ('read', 'edit') then
    v_data := v_data - 'shipping_address_id' - 'shipping_longitude' - 'shipping_latitude';
  end if;

  v_level := coalesce(v_access->>'receiverAddress', 'hidden');
  v_data := app_private.secure_scalar_json(
    v_data, 'receiving_address_detail', p_order.receiving_address_detail, v_level, 'address'
  );
  if v_level not in ('read', 'edit') then
    v_data := v_data - 'receiving_address_id' - 'receiving_longitude' - 'receiving_latitude';
  end if;

  v_data := jsonb_set(
    v_data,
    '{cargo_items}',
    app_private.secure_tms_order_cargo_items(
      p_order.cargo_items,
      coalesce(v_access->>'cargoPricing', 'hidden')
    ),
    true
  );

  v_level := coalesce(v_access->>'freightAmounts', 'hidden');
  foreach v_column in array array[
    'transport_fee', 'delivery_fee', 'unloading_fee', 'collect_payment_fee',
    'transfer_fee', 'insurance_fee', 'package_fee', 'other_fee', 'total_fee'
  ] loop
    v_data := app_private.secure_scalar_json(v_data, v_column, v_data->>v_column, v_level, 'amount');
  end loop;

  v_level := coalesce(v_access->>'settlementAmounts', 'hidden');
  foreach v_column in array array[
    'declared_value', 'cash_amount', 'collect_amount', 'monthly_amount', 'cod_amount',
    'handling_fee', 'payment_total', 'signed_cod_amount'
  ] loop
    v_data := app_private.secure_scalar_json(v_data, v_column, v_data->>v_column, v_level, 'amount');
  end loop;

  v_data := app_private.secure_scalar_json(
    v_data, 'dispatch_driver_phone', p_order.dispatch_driver_phone,
    v_access->>'driverPhone', 'phone'
  );

  if coalesce(v_access->>'proofAttachments', 'hidden') not in ('read', 'edit') then
    v_data := v_data - 'image_urls' - 'receipt_image_urls';
  end if;

  if coalesce(v_access->>'routeCoordinates', 'hidden') not in ('read', 'edit') then
    v_data := v_data
      - 'shipping_longitude' - 'shipping_latitude'
      - 'receiving_longitude' - 'receiving_latitude';
  end if;

  select jsonb_build_object(
    'id', station_row.id,
    'station_code', station_row.station_code,
    'station_name', station_row.station_name,
    'station_type', station_row.station_type,
    'region_code', station_row.region_code
  ) into v_origin_station
  from public.tms_station station_row
  where station_row.id = p_order.origin_station_id and station_row.tenant_id = p_order.tenant_id;

  select jsonb_build_object(
    'id', station_row.id,
    'station_code', station_row.station_code,
    'station_name', station_row.station_name,
    'station_type', station_row.station_type,
    'region_code', station_row.region_code
  ) into v_destination_station
  from public.tms_station station_row
  where station_row.id = p_order.destination_station_id and station_row.tenant_id = p_order.tenant_id;

  select jsonb_build_object(
    'id', station_row.id,
    'station_code', station_row.station_code,
    'station_name', station_row.station_name,
    'station_type', station_row.station_type,
    'region_code', station_row.region_code
  ) into v_transfer_station
  from public.tms_station station_row
  where station_row.id = p_order.transfer_station_id and station_row.tenant_id = p_order.tenant_id;

  select jsonb_build_object(
    'id', customer_row.id,
    'customer_code', customer_row.customer_code,
    'customer_name', customer_row.customer_name,
    'contact_name', customer_row.contact_name
  ) into v_shipping_customer
  from public.tms_customer customer_row
  where customer_row.id = p_order.shipping_customer_id and customer_row.tenant_id = p_order.tenant_id;

  select jsonb_build_object(
    'id', customer_row.id,
    'customer_code', customer_row.customer_code,
    'customer_name', customer_row.customer_name,
    'contact_name', customer_row.contact_name
  ) into v_receiving_customer
  from public.tms_customer customer_row
  where customer_row.id = p_order.receiving_customer_id and customer_row.tenant_id = p_order.tenant_id;

  select waybill_row.id, jsonb_build_object(
    'waybill_no', waybill_row.waybill_no,
    'driver_waybill_id', waybill_row.id,
    'driver_waybill_accepted_at', waybill_row.accepted_at,
    'driver_waybill_loaded_at', waybill_row.loaded_at,
    'driver_waybill_departed_at', waybill_row.departed_at,
    'driver_waybill_unloaded_at', waybill_row.unloaded_at,
    'driver_waybill_completed_at', waybill_row.completed_at,
    'waybill_status', waybill_row.status,
    'update_time', greatest(p_order.update_time, waybill_row.update_time)
  )
  into v_latest_waybill_id, v_latest_waybill
  from public.tms_waybill waybill_row
  where waybill_row.order_id = p_order.id and waybill_row.tenant_id = p_order.tenant_id
  order by waybill_row.create_time desc, waybill_row.id
  limit 1;

  if v_latest_waybill_id is not null then
    select operation_row.operation_status into v_unloading_status
    from public.tms_waybill_cargo_operation operation_row
    where operation_row.waybill_id = v_latest_waybill_id
      and operation_row.tenant_id = p_order.tenant_id
      and operation_row.operation_type = 'unloading'
    order by operation_row.create_time desc, operation_row.id
    limit 1;

    select * into v_execution
    from public.tms_waybill_execution_record execution_row
    where execution_row.waybill_id = v_latest_waybill_id
      and execution_row.tenant_id = p_order.tenant_id
    order by execution_row.create_time desc, execution_row.id
    limit 1;

    v_latest_waybill := coalesce(v_latest_waybill, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'driver_waybill_unloading_status', v_unloading_status,
      'driver_waybill_signed_at', v_execution.signed_at,
      'driver_waybill_signed_by', v_execution.signer_name,
      'driver_waybill_return_time', v_execution.return_time,
      'driver_waybill_return_odometer_km', v_execution.return_odometer_km
    ));

    if coalesce(v_access->>'proofAttachments', 'hidden') in ('read', 'edit') then
      v_latest_waybill := v_latest_waybill || jsonb_build_object(
        'driver_waybill_signature_proof_count', coalesce(jsonb_array_length(v_execution.signature_urls), 0),
        'driver_waybill_return_photo_count', coalesce(jsonb_array_length(v_execution.return_photo_urls), 0)
      );
    end if;
  end if;

  return v_data
    || jsonb_strip_nulls(jsonb_build_object(
      'origin_station_ref', v_origin_station,
      'destination_station_ref', v_destination_station,
      'transfer_station_ref', v_transfer_station,
      'shipping_customer', v_shipping_customer,
      'receiving_customer', v_receiving_customer
    ))
    || coalesce(v_latest_waybill, '{}'::jsonb)
    || jsonb_build_object(
      'field_access', v_access,
      'is_record_owner', v_effective_owner_id is not null
        and v_effective_owner_id = app_private.current_app_user_id()
    );
end;
$$;

create or replace function app_private.tms_order_scope_resource(p_scope text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_scope in ('order_list', 'order_export', 'order_detail', 'order_open', 'dashboard')
      then 'tms.order'
    when p_scope in ('waybill_list', 'waybill_export', 'delivery_list', 'delivery_export', 'in_transit')
      then 'tms.waybill'
    else null
  end;
$$;

create or replace function app_private.can_read_tms_order_scope(p_scope text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_scope
    when 'order_list' then app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:View', null, false)
    when 'order_export' then app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:Export', null, false)
    when 'order_detail' then app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:View', null, false)
    when 'order_open' then app_private.can_access_business_menu('TmsOrderOpen')
    when 'waybill_list' then
      app_private.can_execute_business_action('TmsPendingWaybillList', 'TmsPendingWaybillList:View', null, false)
      or app_private.can_execute_business_action('TmsLoadedWaybillList', 'TmsLoadedWaybillList:View', null, false)
    when 'waybill_export' then
      app_private.can_execute_business_action('TmsPendingWaybillList', 'TmsPendingWaybillList:Export', null, false)
      or app_private.can_execute_business_action('TmsLoadedWaybillList', 'TmsLoadedWaybillList:Export', null, false)
    when 'delivery_list' then app_private.can_execute_business_action('TmsDeliveryManagement', 'TmsDeliveryManagement:View', null, false)
    when 'delivery_export' then app_private.can_execute_business_action('TmsDeliveryManagement', 'TmsDeliveryManagement:Export', null, false)
    when 'in_transit' then app_private.can_execute_business_action('TmsInTransitMonitor', 'TmsInTransitMonitor:View', null, false)
    when 'dashboard' then app_private.can_access_business_menu('Console')
    else false
  end;
$$;

create or replace function public.tms_list_orders_secure(
  p_scope text,
  p_from integer default 0,
  p_to integer default 9,
  p_record_id uuid default null,
  p_ids uuid[] default null,
  p_order_status text default null,
  p_order_statuses text[] default null,
  p_payment_method text default null,
  p_origin_station_id uuid default null,
  p_destination_station_id uuid default null,
  p_transfer_station_id uuid default null,
  p_dispatch_status text default null,
  p_dispatch_statuses text[] default null,
  p_dispatch_vehicle_id uuid default null,
  p_waybill_status text default null,
  p_cargo_keyword text default null,
  p_shipping_keyword text default null,
  p_receiving_keyword text default null,
  p_vehicle_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
  p_planned_time_from timestamptz default null,
  p_planned_time_to timestamptz default null,
  p_signed_time_from timestamptz default null,
  p_signed_time_to timestamptz default null,
  p_count_only boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_resource_key text := app_private.tms_order_scope_resource(p_scope);
  v_base_access jsonb;
  v_limit integer;
  v_can_search_shipper boolean;
  v_can_search_shipper_address boolean;
  v_can_search_receiver boolean;
  v_can_search_receiver_address boolean;
  v_can_search_driver boolean;
  v_result jsonb;
begin
  if v_resource_key is null or not app_private.can_read_tms_order_scope(p_scope) then
    raise exception 'Missing order or waybill read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := case when p_count_only then 0 else least(
    case when p_scope in ('order_export', 'waybill_export', 'delivery_export', 'dashboard') then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  ) end;
  v_base_access := app_private.field_access_map(v_resource_key, null);
  v_can_search_shipper := coalesce(v_base_access->>'shipperContact', 'hidden') in ('read', 'edit');
  v_can_search_shipper_address := coalesce(v_base_access->>'shipperAddress', 'hidden') in ('read', 'edit');
  v_can_search_receiver := coalesce(v_base_access->>'receiverContact', 'hidden') in ('read', 'edit');
  v_can_search_receiver_address := coalesce(v_base_access->>'receiverAddress', 'hidden') in ('read', 'edit');
  v_can_search_driver := coalesce(v_base_access->>'driverPhone', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select order_row as order_record
    from public.tms_order order_row
    where (app_private.is_platform_super() or order_row.tenant_id = v_tenant_id)
      and (p_record_id is null or order_row.id = p_record_id)
      and (p_ids is null or order_row.id = any(p_ids))
      and (p_order_status is null or order_row.order_status = p_order_status)
      and (p_order_statuses is null or order_row.order_status = any(p_order_statuses))
      and (p_payment_method is null or order_row.payment_method = p_payment_method)
      and (p_origin_station_id is null or order_row.origin_station_id = p_origin_station_id)
      and (p_destination_station_id is null or order_row.destination_station_id = p_destination_station_id)
      and (p_transfer_station_id is null or order_row.transfer_station_id = p_transfer_station_id)
      and (p_dispatch_status is null or order_row.dispatch_status = p_dispatch_status)
      and (p_dispatch_statuses is null or order_row.dispatch_status = any(p_dispatch_statuses))
      and (p_dispatch_vehicle_id is null or order_row.dispatch_vehicle_id = p_dispatch_vehicle_id)
      and (p_create_time_from is null or order_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or order_row.create_time <= p_create_time_to)
      and (p_planned_time_from is null or order_row.planned_departure_time >= p_planned_time_from)
      and (p_planned_time_to is null or order_row.planned_departure_time <= p_planned_time_to)
      and (p_signed_time_from is null or order_row.signed_at >= p_signed_time_from)
      and (p_signed_time_to is null or order_row.signed_at <= p_signed_time_to)
      and (
        p_waybill_status is null
        or exists (
          select 1 from public.tms_waybill waybill_row
          where waybill_row.order_id = order_row.id
            and waybill_row.tenant_id = order_row.tenant_id
            and waybill_row.status = p_waybill_status
        )
      )
      and (
        nullif(btrim(p_cargo_keyword), '') is null
        or order_row.order_no ilike '%' || btrim(p_cargo_keyword) || '%'
        or order_row.cargo_no ilike '%' || btrim(p_cargo_keyword) || '%'
      )
      and (
        nullif(btrim(p_shipping_keyword), '') is null
        or order_row.shipping_contact_name ilike '%' || btrim(p_shipping_keyword) || '%'
        or (v_can_search_shipper and order_row.shipping_contact_phone ilike '%' || btrim(p_shipping_keyword) || '%')
        or (v_can_search_shipper_address and order_row.shipping_address_detail ilike '%' || btrim(p_shipping_keyword) || '%')
      )
      and (
        nullif(btrim(p_receiving_keyword), '') is null
        or order_row.receiving_contact_name ilike '%' || btrim(p_receiving_keyword) || '%'
        or (v_can_search_receiver and order_row.receiving_contact_phone ilike '%' || btrim(p_receiving_keyword) || '%')
        or (v_can_search_receiver_address and order_row.receiving_address_detail ilike '%' || btrim(p_receiving_keyword) || '%')
      )
      and (
        nullif(btrim(p_vehicle_keyword), '') is null
        or order_row.dispatch_plate_no ilike '%' || btrim(p_vehicle_keyword) || '%'
        or order_row.dispatch_vehicle_type ilike '%' || btrim(p_vehicle_keyword) || '%'
        or order_row.dispatch_driver_name ilike '%' || btrim(p_vehicle_keyword) || '%'
        or (v_can_search_driver and order_row.dispatch_driver_phone ilike '%' || btrim(p_vehicle_keyword) || '%')
      )
      and (p_scope not in ('order_list', 'order_export', 'order_detail') or order_row.order_status <> 'created')
  ), paged as (
    select filtered.order_record
    from filtered
    order by (filtered.order_record).create_time desc, (filtered.order_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_order_to_secure_json(paged.order_record, v_resource_key, null, null)
        order by (paged.order_record).create_time desc, (paged.order_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_get_order_detail_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_order public.tms_order%rowtype;
  v_access jsonb;
  v_data jsonb;
  v_related jsonb;
begin
  if not app_private.can_read_tms_order_scope('order_detail') then
    raise exception 'Missing order detail permission' using errcode = '42501';
  end if;

  select * into v_order
  from public.tms_order order_row
  where order_row.id = p_id
    and (app_private.is_platform_super() or order_row.tenant_id = v_tenant_id);
  if not found then return null; end if;

  v_access := app_private.field_access_map('tms.order', v_order.created_by_user_id);
  v_data := app_private.tms_order_to_secure_json(v_order, 'tms.order', v_access, v_order.created_by_user_id);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', waybill_row.id,
    'waybill_no', waybill_row.waybill_no,
    'status', waybill_row.status,
    'driver_name', driver_row.driver_name,
    'driver_phone', case
      when v_access->>'driverPhone' = 'hidden' then null
      when v_access->>'driverPhone' = 'masked'
        then app_private.mask_permission_value(driver_row.phone, 'phone')
      else driver_row.phone
    end,
    'plate_no', vehicle_row.plate_no,
    'accepted_at', waybill_row.accepted_at,
    'departed_at', waybill_row.departed_at,
    'completed_at', waybill_row.completed_at
  )) order by waybill_row.create_time desc), '[]'::jsonb)
  into v_related
  from public.tms_waybill waybill_row
  left join public.tms_driver driver_row
    on driver_row.id = waybill_row.driver_id and driver_row.tenant_id = waybill_row.tenant_id
  left join public.vehicle_archive vehicle_row
    on vehicle_row.id = waybill_row.vehicle_id and vehicle_row.tenant_id = waybill_row.tenant_id
  where waybill_row.order_id = v_order.id and waybill_row.tenant_id = v_order.tenant_id;

  return v_data || jsonb_build_object('related_waybills', v_related);
end;
$$;

create or replace function app_private.tms_waybill_to_secure_json(
  p_waybill public.tms_waybill,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map('tms.waybill', p_waybill.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_waybill) - 'tenant_id' - 'created_by_user_id';
  v_level text;
  v_driver jsonb;
  v_vehicle jsonb;
  v_carrier jsonb;
  v_cargo jsonb;
  v_order public.tms_order%rowtype;
  v_order_json jsonb;
begin
  v_data := app_private.secure_scalar_json(
    v_data, 'shipper_phone', p_waybill.shipper_phone, v_access->>'shipperContact', 'phone'
  );
  v_data := app_private.secure_scalar_json(
    v_data, 'receiver_phone', p_waybill.receiver_phone, v_access->>'receiverContact', 'phone'
  );

  v_level := coalesce(v_access->>'shipperAddress', 'hidden');
  v_data := app_private.secure_scalar_json(
    v_data, 'shipper_address', p_waybill.shipper_address, v_level, 'address'
  );
  if v_level not in ('read', 'edit') then
    v_data := v_data - 'shipper_address_id' - 'shipper_longitude' - 'shipper_latitude';
  end if;

  v_level := coalesce(v_access->>'receiverAddress', 'hidden');
  v_data := app_private.secure_scalar_json(
    v_data, 'receiver_address', p_waybill.receiver_address, v_level, 'address'
  );
  if v_level not in ('read', 'edit') then
    v_data := v_data - 'receiver_address_id' - 'receiver_longitude' - 'receiver_latitude';
  end if;

  v_data := app_private.secure_scalar_json(
    v_data, 'freight_amount', p_waybill.freight_amount::text,
    v_access->>'freightAmounts', 'amount'
  );

  if coalesce(v_access->>'proofAttachments', 'hidden') not in ('read', 'edit') then
    v_data := v_data - 'pickup_photos' - 'delivery_photos' - 'receipt_attachments';
  end if;
  if coalesce(v_access->>'routeCoordinates', 'hidden') not in ('read', 'edit') then
    v_data := v_data - 'route_points'
      - 'shipper_longitude' - 'shipper_latitude'
      - 'receiver_longitude' - 'receiver_latitude';
  end if;

  select jsonb_strip_nulls(jsonb_build_object(
    'id', driver_row.id,
    'driver_name', driver_row.driver_name,
    'phone', case
      when v_access->>'driverPhone' = 'hidden' then null
      when v_access->>'driverPhone' = 'masked'
        then app_private.mask_permission_value(driver_row.phone, 'phone')
      else driver_row.phone
    end,
    'license_type', driver_row.license_type
  )) into v_driver
  from public.tms_driver driver_row
  where driver_row.id = p_waybill.driver_id and driver_row.tenant_id = p_waybill.tenant_id;

  select jsonb_build_object(
    'id', vehicle_row.id,
    'plate_no', vehicle_row.plate_no,
    'vehicle_type', vehicle_row.vehicle_type,
    'brand_model', vehicle_row.brand_model,
    'approved_load_mass', vehicle_row.approved_load_mass,
    'vehicle_photo_url', vehicle_row.vehicle_photo_url
  ) into v_vehicle
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = p_waybill.vehicle_id and vehicle_row.tenant_id = p_waybill.tenant_id;

  select jsonb_strip_nulls(jsonb_build_object(
    'id', carrier_row.id,
    'company_name', carrier_row.company_name,
    'contact_name', carrier_row.contact_name,
    'contact_phone', case
      when v_access->>'carrierPhone' = 'hidden' then null
      when v_access->>'carrierPhone' = 'masked'
        then app_private.mask_permission_value(carrier_row.contact_phone, 'phone')
      else carrier_row.contact_phone
    end
  )) into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_waybill.carrier_id and carrier_row.tenant_id = p_waybill.tenant_id;

  select jsonb_build_object(
    'id', cargo_row.id,
    'cargo_code', cargo_row.cargo_code,
    'cargo_name', cargo_row.cargo_name,
    'unit', cargo_row.unit
  ) into v_cargo
  from public.tms_cargo cargo_row
  where cargo_row.id = p_waybill.cargo_id and cargo_row.tenant_id = p_waybill.tenant_id;

  if p_waybill.order_id is not null then
    select * into v_order from public.tms_order order_row
    where order_row.id = p_waybill.order_id and order_row.tenant_id = p_waybill.tenant_id;
    if found then
      v_order_json := app_private.tms_order_to_secure_json(
        v_order, 'tms.waybill', v_access, p_waybill.created_by_user_id
      );
    end if;
  end if;

  return v_data
    || jsonb_strip_nulls(jsonb_build_object(
      'driver', v_driver,
      'vehicle', v_vehicle,
      'carrier', v_carrier,
      'cargo', v_cargo,
      'order', v_order_json
    ))
    || jsonb_build_object(
      'field_access', v_access,
      'is_record_owner', p_waybill.created_by_user_id is not null
        and p_waybill.created_by_user_id = app_private.current_app_user_id()
    );
end;
$$;

create or replace function app_private.secure_waybill_event_json(
  p_event public.tms_waybill_event,
  p_route_visible boolean,
  p_proof_visible boolean,
  p_settlement_visible boolean
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(p_event) - 'tenant_id')
    - case when p_route_visible then array[]::text[] else array[
        'location_text', 'longitude', 'latitude'
      ]::text[] end
    || jsonb_build_object(
      'payload', (coalesce(p_event.payload, '{}'::jsonb)
        - case when p_route_visible then array[]::text[] else array[
            'longitude', 'latitude', 'location', 'locationText', 'address', 'routePoints'
          ]::text[] end)
        - case when p_proof_visible then array[]::text[] else array[
            'photoUrls', 'photo_urls', 'receiptUrls', 'receipt_urls',
            'signatureUrls', 'signature_urls', 'attachments'
          ]::text[] end
        - case when p_settlement_visible then array[]::text[] else array[
            'signedCodAmount', 'signed_cod_amount', 'codAmount', 'cod_amount', 'amount'
          ]::text[] end
    );
$$;

create or replace function public.tms_get_waybill_detail_secure(p_waybill_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_waybill public.tms_waybill%rowtype;
  v_access jsonb;
  v_data jsonb;
  v_route_visible boolean;
  v_proof_visible boolean;
  v_settlement_visible boolean;
  v_events jsonb;
  v_proofs jsonb;
  v_operations jsonb;
  v_execution jsonb;
  v_expense_locations jsonb;
begin
  if not (
    app_private.can_access_business_menu('TmsWaybillManagement')
    or app_private.can_access_business_menu('TmsWaybillDetail')
  ) then
    raise exception 'Missing waybill detail permission' using errcode = '42501';
  end if;

  select * into v_waybill
  from public.tms_waybill waybill_row
  where waybill_row.id = p_waybill_id
    and (app_private.is_platform_super() or waybill_row.tenant_id = v_tenant_id);
  if not found then return null; end if;

  v_access := app_private.field_access_map('tms.waybill', v_waybill.created_by_user_id);
  v_route_visible := coalesce(v_access->>'routeCoordinates', 'hidden') in ('read', 'edit');
  v_proof_visible := coalesce(v_access->>'proofAttachments', 'hidden') in ('read', 'edit');
  v_settlement_visible := coalesce(v_access->>'settlementAmounts', 'hidden') in ('read', 'edit');
  v_data := app_private.tms_waybill_to_secure_json(v_waybill, v_access);

  select coalesce(jsonb_agg(
    app_private.secure_waybill_event_json(
      event_row, v_route_visible, v_proof_visible, v_settlement_visible
    ) order by event_row.event_time desc
  ), '[]'::jsonb) into v_events
  from public.tms_waybill_event event_row
  where event_row.waybill_id = v_waybill.id and event_row.tenant_id = v_waybill.tenant_id;

  if v_proof_visible then
    select coalesce(jsonb_agg(to_jsonb(proof_row) - 'tenant_id' order by proof_row.uploaded_at desc), '[]'::jsonb)
    into v_proofs
    from public.tms_waybill_proof proof_row
    where proof_row.waybill_id = v_waybill.id and proof_row.tenant_id = v_waybill.tenant_id;
  else
    v_proofs := '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    (to_jsonb(operation_row) - 'tenant_id')
      - case when v_route_visible then array[]::text[] else array[
          'longitude', 'latitude', 'location_accuracy_m', 'location_text',
          'geofence_center_longitude', 'geofence_center_latitude', 'geofence_radius_m',
          'distance_m', 'inside_geofence', 'outside_reason'
        ]::text[] end
      - case when v_proof_visible then array[]::text[] else array[
          'photo_urls', 'weighbridge_ticket_urls', 'recognition_info', 'recognition_payload'
        ]::text[] end
    order by operation_row.checkin_time desc
  ), '[]'::jsonb) into v_operations
  from public.tms_waybill_cargo_operation operation_row
  where operation_row.waybill_id = v_waybill.id and operation_row.tenant_id = v_waybill.tenant_id;

  select case when execution_row.id is null then null else
    (to_jsonb(execution_row) - 'tenant_id')
      - case when v_proof_visible then array[]::text[] else array[
          'departure_photo_urls', 'receipt_urls', 'signature_urls', 'return_photo_urls'
        ]::text[] end
  end into v_execution
  from public.tms_waybill_execution_record execution_row
  where execution_row.waybill_id = v_waybill.id and execution_row.tenant_id = v_waybill.tenant_id
  order by execution_row.create_time desc limit 1;

  if v_route_visible then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', cost_row.id,
      'cost_type', cost_row.cost_type,
      'occurred_on', cost_row.occurred_on,
      'expense_location', cost_row.expense_location,
      'expense_longitude', cost_row.expense_longitude,
      'expense_latitude', cost_row.expense_latitude,
      'expense_coordinate_source', cost_row.expense_coordinate_source,
      'expense_item', jsonb_strip_nulls(jsonb_build_object(
        'id', item_row.id,
        'item_code', item_row.item_code,
        'item_name', item_row.item_name,
        'business_category', item_row.business_category
      ))
    )) order by cost_row.occurred_on, cost_row.create_time), '[]'::jsonb)
    into v_expense_locations
    from public.tms_waybill_cost cost_row
    left join public.tms_expense_item item_row
      on item_row.id = cost_row.expense_item_id and item_row.tenant_id = cost_row.tenant_id
    where cost_row.waybill_id = v_waybill.id
      and cost_row.tenant_id = v_waybill.tenant_id
      and cost_row.expense_longitude is not null
      and cost_row.expense_latitude is not null;
  else
    v_expense_locations := '[]'::jsonb;
  end if;

  return v_data || jsonb_build_object(
    'events', v_events,
    'proofs', v_proofs,
    'cargo_operations', v_operations,
    'execution', v_execution,
    'expense_locations', v_expense_locations
  );
end;
$$;

create or replace function public.tms_list_waybills_secure(
  p_scope text default 'in_transit',
  p_from integer default 0,
  p_to integer default 199,
  p_statuses text[] default null,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb := app_private.field_access_map('tms.waybill', null);
  v_result jsonb;
begin
  if p_scope <> 'in_transit' or not app_private.can_read_tms_order_scope('in_transit') then
    raise exception 'Missing in-transit read permission' using errcode = '42501';
  end if;

  with filtered as materialized (
    select waybill_row as waybill_record
    from public.tms_waybill waybill_row
    where (app_private.is_platform_super() or waybill_row.tenant_id = v_tenant_id)
      and waybill_row.order_id is not null
      and (p_statuses is null or waybill_row.status = any(p_statuses))
      and (
        nullif(btrim(p_keyword), '') is null
        or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.origin_city ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.destination_city ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.cargo_name ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.shipper_name ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.receiver_name ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select filtered.waybill_record
    from filtered
    order by (filtered.waybill_record).update_time desc, (filtered.waybill_record).create_time desc
    offset greatest(coalesce(p_from, 0), 0)
    limit least(greatest(coalesce(p_to, 199) - greatest(coalesce(p_from, 0), 0) + 1, 1), 500)
  )
  select jsonb_build_object(
    'records', coalesce((select jsonb_agg(
      app_private.tms_waybill_to_secure_json(paged.waybill_record, null)
      order by (paged.waybill_record).update_time desc, (paged.waybill_record).create_time desc
    ) from paged), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function app_private.assert_tms_order_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Order payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'order_no', 'cargo_no', 'order_status', 'origin_station', 'destination_station',
    'transfer_station', 'delivery_method', 'shipping_customer_id', 'receiving_customer_id',
    'shipping_contact_name', 'shipping_contact_phone', 'shipping_address_detail',
    'receiving_contact_name', 'receiving_contact_phone', 'receiving_address_detail',
    'cargo_items', 'cargo_quantity_total', 'cargo_weight_total', 'cargo_volume_total',
    'transport_fee', 'delivery_fee', 'unloading_fee', 'collect_payment_fee', 'transfer_fee',
    'declared_value', 'insurance_fee', 'package_fee', 'other_fee', 'total_fee',
    'payment_method', 'cash_amount', 'collect_amount', 'monthly_amount', 'cod_amount',
    'handling_fee', 'payment_total', 'transport_mode', 'order_remark', 'image_urls',
    'origin_station_id', 'destination_station_id', 'transfer_station_id',
    'shipping_address_id', 'receiving_address_id', 'shipping_longitude', 'shipping_latitude',
    'receiving_longitude', 'receiving_latitude'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Order payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_order_reference_scope(
  p_tenant_id uuid,
  p_input public.tms_order
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_input.origin_station_id is not null and not exists (
    select 1 from public.tms_station row_ref
    where row_ref.id = p_input.origin_station_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Origin station is outside the current tenant'; end if;
  if p_input.destination_station_id is not null and not exists (
    select 1 from public.tms_station row_ref
    where row_ref.id = p_input.destination_station_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Destination station is outside the current tenant'; end if;
  if p_input.transfer_station_id is not null and not exists (
    select 1 from public.tms_station row_ref
    where row_ref.id = p_input.transfer_station_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Transfer station is outside the current tenant'; end if;
  if p_input.shipping_customer_id is not null and not exists (
    select 1 from public.tms_customer row_ref
    where row_ref.id = p_input.shipping_customer_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Shipping customer is outside the current tenant'; end if;
  if p_input.receiving_customer_id is not null and not exists (
    select 1 from public.tms_customer row_ref
    where row_ref.id = p_input.receiving_customer_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Receiving customer is outside the current tenant'; end if;
  if p_input.shipping_address_id is not null and not exists (
    select 1 from public.tms_customer_address row_ref
    where row_ref.id = p_input.shipping_address_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Shipping address is outside the current tenant'; end if;
  if p_input.receiving_address_id is not null and not exists (
    select 1 from public.tms_customer_address row_ref
    where row_ref.id = p_input.receiving_address_id and row_ref.tenant_id = p_tenant_id
  ) then raise exception 'Receiving address is outside the current tenant'; end if;
end;
$$;

create or replace function public.tms_create_order_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_order%rowtype;
  v_created public.tms_order%rowtype;
begin
  if not app_private.can_execute_business_action('TmsOrderOpen', 'TmsOrderOpen:Create', null, false) then
    raise exception 'Missing order create permission' using errcode = '42501';
  end if;
  perform app_private.assert_tms_order_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_order, p_payload);
  if coalesce(v_input.order_status, 'pending_load') not in ('created', 'pending_load') then
    raise exception 'New orders must start as created or pending_load' using errcode = '23514';
  end if;
  perform app_private.assert_tms_order_reference_scope(v_tenant_id, v_input);

  insert into public.tms_order (
    order_no, cargo_no, order_status, origin_station, destination_station, transfer_station,
    delivery_method, shipping_customer_id, receiving_customer_id, shipping_contact_name,
    shipping_contact_phone, shipping_address_detail, receiving_contact_name,
    receiving_contact_phone, receiving_address_detail, cargo_items, cargo_quantity_total,
    cargo_weight_total, cargo_volume_total, transport_fee, delivery_fee, unloading_fee,
    collect_payment_fee, transfer_fee, declared_value, insurance_fee, package_fee,
    other_fee, total_fee, payment_method, cash_amount, collect_amount, monthly_amount,
    cod_amount, handling_fee, payment_total, transport_mode, order_remark, image_urls,
    tenant_id, origin_station_id, destination_station_id, transfer_station_id,
    shipping_address_id, receiving_address_id, shipping_longitude, shipping_latitude,
    receiving_longitude, receiving_latitude
  ) values (
    v_input.order_no, v_input.cargo_no, coalesce(v_input.order_status, 'pending_load'),
    v_input.origin_station, v_input.destination_station, v_input.transfer_station,
    v_input.delivery_method, v_input.shipping_customer_id, v_input.receiving_customer_id,
    v_input.shipping_contact_name, v_input.shipping_contact_phone, v_input.shipping_address_detail,
    v_input.receiving_contact_name, v_input.receiving_contact_phone, v_input.receiving_address_detail,
    coalesce(v_input.cargo_items, '[]'::jsonb), coalesce(v_input.cargo_quantity_total, 0),
    coalesce(v_input.cargo_weight_total, 0), coalesce(v_input.cargo_volume_total, 0),
    coalesce(v_input.transport_fee, 0), coalesce(v_input.delivery_fee, 0),
    coalesce(v_input.unloading_fee, 0), coalesce(v_input.collect_payment_fee, 0),
    coalesce(v_input.transfer_fee, 0), coalesce(v_input.declared_value, 0),
    coalesce(v_input.insurance_fee, 0), coalesce(v_input.package_fee, 0),
    coalesce(v_input.other_fee, 0), coalesce(v_input.total_fee, 0), v_input.payment_method,
    coalesce(v_input.cash_amount, 0), coalesce(v_input.collect_amount, 0),
    coalesce(v_input.monthly_amount, 0), coalesce(v_input.cod_amount, 0),
    coalesce(v_input.handling_fee, 0), coalesce(v_input.payment_total, 0),
    v_input.transport_mode, v_input.order_remark, coalesce(v_input.image_urls, '[]'::jsonb),
    v_tenant_id, v_input.origin_station_id, v_input.destination_station_id,
    v_input.transfer_station_id, v_input.shipping_address_id, v_input.receiving_address_id,
    v_input.shipping_longitude, v_input.shipping_latitude,
    v_input.receiving_longitude, v_input.receiving_latitude
  ) returning * into v_created;

  return app_private.tms_order_to_secure_json(v_created, 'tms.order', null, null);
end;
$$;

create or replace function app_private.merge_tms_order_cargo_pricing(
  p_candidate jsonb,
  p_original jsonb
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    case when original.item is null then candidate.item - 'unit_price' - 'freight'
      else (candidate.item - 'unit_price' - 'freight') || jsonb_strip_nulls(jsonb_build_object(
        'unit_price', original.item->'unit_price',
        'freight', original.item->'freight'
      ))
    end
    order by candidate.ordinal
  ), '[]'::jsonb)
  from jsonb_array_elements(
    case when jsonb_typeof(p_candidate) = 'array' then p_candidate else '[]'::jsonb end
  ) with ordinality as candidate(item, ordinal)
  left join lateral (
    select old_item.item
    from jsonb_array_elements(
      case when jsonb_typeof(p_original) = 'array' then p_original else '[]'::jsonb end
    ) with ordinality as old_item(item, ordinal)
    where old_item.ordinal = candidate.ordinal
  ) original on true;
$$;

create or replace function public.tms_update_order_secure(
  p_id uuid,
  p_payload jsonb,
  p_action text default 'edit'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_order%rowtype;
  v_candidate public.tms_order%rowtype;
  v_updated public.tms_order%rowtype;
  v_button_name text;
begin
  v_button_name := case p_action
    when 'edit' then 'TmsOrderList:Edit'
    when 'edit_freight' then 'TmsOrderList:EditFreight'
    else null
  end;
  if v_button_name is null then raise exception 'Unsupported order update action'; end if;

  select * into v_old from public.tms_order order_row
  where order_row.id = p_id
    and (app_private.is_platform_super() or order_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Order not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsOrderList', v_button_name, v_old.created_by_user_id, true
  ) then raise exception 'Missing order update permission' using errcode = '42501'; end if;
  if p_action = 'edit' and v_old.order_status <> 'pending_load' then
    raise exception 'Only pending_load orders can be edited' using errcode = '23514';
  end if;

  perform app_private.assert_tms_order_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  if app_private.resolve_field_access('tms.order', 'cargoPricing', v_old.created_by_user_id) <> 'edit' then
    v_candidate.cargo_items := app_private.merge_tms_order_cargo_pricing(
      v_candidate.cargo_items, v_old.cargo_items
    );
  end if;
  if v_candidate.order_status is distinct from v_old.order_status then
    raise exception 'Order status cannot be changed through the edit form' using errcode = '42501';
  end if;
  perform app_private.assert_tms_order_reference_scope(v_old.tenant_id, v_candidate);

  update public.tms_order set
    order_no = v_candidate.order_no,
    cargo_no = v_candidate.cargo_no,
    origin_station = v_candidate.origin_station,
    destination_station = v_candidate.destination_station,
    transfer_station = v_candidate.transfer_station,
    delivery_method = v_candidate.delivery_method,
    shipping_customer_id = v_candidate.shipping_customer_id,
    receiving_customer_id = v_candidate.receiving_customer_id,
    shipping_contact_name = v_candidate.shipping_contact_name,
    shipping_contact_phone = v_candidate.shipping_contact_phone,
    shipping_address_detail = v_candidate.shipping_address_detail,
    receiving_contact_name = v_candidate.receiving_contact_name,
    receiving_contact_phone = v_candidate.receiving_contact_phone,
    receiving_address_detail = v_candidate.receiving_address_detail,
    cargo_items = v_candidate.cargo_items,
    cargo_quantity_total = v_candidate.cargo_quantity_total,
    cargo_weight_total = v_candidate.cargo_weight_total,
    cargo_volume_total = v_candidate.cargo_volume_total,
    transport_fee = v_candidate.transport_fee,
    delivery_fee = v_candidate.delivery_fee,
    unloading_fee = v_candidate.unloading_fee,
    collect_payment_fee = v_candidate.collect_payment_fee,
    transfer_fee = v_candidate.transfer_fee,
    declared_value = v_candidate.declared_value,
    insurance_fee = v_candidate.insurance_fee,
    package_fee = v_candidate.package_fee,
    other_fee = v_candidate.other_fee,
    total_fee = v_candidate.total_fee,
    payment_method = v_candidate.payment_method,
    cash_amount = v_candidate.cash_amount,
    collect_amount = v_candidate.collect_amount,
    monthly_amount = v_candidate.monthly_amount,
    cod_amount = v_candidate.cod_amount,
    handling_fee = v_candidate.handling_fee,
    payment_total = v_candidate.payment_total,
    transport_mode = v_candidate.transport_mode,
    order_remark = v_candidate.order_remark,
    image_urls = v_candidate.image_urls,
    origin_station_id = v_candidate.origin_station_id,
    destination_station_id = v_candidate.destination_station_id,
    transfer_station_id = v_candidate.transfer_station_id,
    shipping_address_id = v_candidate.shipping_address_id,
    receiving_address_id = v_candidate.receiving_address_id,
    shipping_longitude = v_candidate.shipping_longitude,
    shipping_latitude = v_candidate.shipping_latitude,
    receiving_longitude = v_candidate.receiving_longitude,
    receiving_latitude = v_candidate.receiving_latitude,
    update_time = now()
  where id = v_old.id
  returning * into v_updated;

  return app_private.tms_order_to_secure_json(v_updated, 'tms.order', null, null);
end;
$$;

create or replace function app_private.tms_cargo_price_projection(p_items jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'unit_price', item->'unit_price', 'freight', item->'freight'
  ) order by ordinal), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end)
    with ordinality as cargo(item, ordinal);
$$;

create or replace function app_private.enforce_tms_transport_sensitive_writes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_key text := case tg_table_name when 'tms_order' then 'tms.order' else 'tms.waybill' end;
  v_owner_id uuid := old.created_by_user_id;
begin
  if tg_op <> 'UPDATE' or (select auth.uid()) is null or app_private.is_platform_super() then
    return new;
  end if;

  if tg_table_name = 'tms_order' then
    if new.shipping_contact_phone is distinct from old.shipping_contact_phone
       and app_private.resolve_field_access(v_resource_key, 'shipperContact', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for shipper contact' using errcode = '42501'; end if;
    if new.receiving_contact_phone is distinct from old.receiving_contact_phone
       and app_private.resolve_field_access(v_resource_key, 'receiverContact', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for receiver contact' using errcode = '42501'; end if;
    if (new.shipping_address_detail, new.shipping_address_id, new.shipping_longitude, new.shipping_latitude)
       is distinct from
       (old.shipping_address_detail, old.shipping_address_id, old.shipping_longitude, old.shipping_latitude)
       and app_private.resolve_field_access(v_resource_key, 'shipperAddress', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for shipper address' using errcode = '42501'; end if;
    if (new.receiving_address_detail, new.receiving_address_id, new.receiving_longitude, new.receiving_latitude)
       is distinct from
       (old.receiving_address_detail, old.receiving_address_id, old.receiving_longitude, old.receiving_latitude)
       and app_private.resolve_field_access(v_resource_key, 'receiverAddress', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for receiver address' using errcode = '42501'; end if;
    if app_private.tms_cargo_price_projection(new.cargo_items)
       is distinct from app_private.tms_cargo_price_projection(old.cargo_items)
       and app_private.resolve_field_access(v_resource_key, 'cargoPricing', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for cargo pricing' using errcode = '42501'; end if;
    if (new.transport_fee, new.delivery_fee, new.unloading_fee, new.collect_payment_fee,
        new.transfer_fee, new.insurance_fee, new.package_fee, new.other_fee, new.total_fee)
       is distinct from
       (old.transport_fee, old.delivery_fee, old.unloading_fee, old.collect_payment_fee,
        old.transfer_fee, old.insurance_fee, old.package_fee, old.other_fee, old.total_fee)
       and app_private.resolve_field_access(v_resource_key, 'freightAmounts', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for freight amounts' using errcode = '42501'; end if;
    if (new.declared_value, new.cash_amount, new.collect_amount, new.monthly_amount,
        new.cod_amount, new.handling_fee, new.payment_total, new.signed_cod_amount)
       is distinct from
       (old.declared_value, old.cash_amount, old.collect_amount, old.monthly_amount,
        old.cod_amount, old.handling_fee, old.payment_total, old.signed_cod_amount)
       and app_private.resolve_field_access(v_resource_key, 'settlementAmounts', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for settlement amounts' using errcode = '42501'; end if;
    if new.dispatch_driver_phone is distinct from old.dispatch_driver_phone
       and app_private.resolve_field_access(v_resource_key, 'driverPhone', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for driver phone' using errcode = '42501'; end if;
    if (new.image_urls, new.receipt_image_urls) is distinct from (old.image_urls, old.receipt_image_urls)
       and app_private.resolve_field_access(v_resource_key, 'proofAttachments', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for order proofs' using errcode = '42501'; end if;
    if (new.shipping_longitude, new.shipping_latitude, new.receiving_longitude, new.receiving_latitude)
       is distinct from
       (old.shipping_longitude, old.shipping_latitude, old.receiving_longitude, old.receiving_latitude)
       and app_private.resolve_field_access(v_resource_key, 'routeCoordinates', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for order coordinates' using errcode = '42501'; end if;
  else
    if new.shipper_phone is distinct from old.shipper_phone
       and app_private.resolve_field_access(v_resource_key, 'shipperContact', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for shipper contact' using errcode = '42501'; end if;
    if new.receiver_phone is distinct from old.receiver_phone
       and app_private.resolve_field_access(v_resource_key, 'receiverContact', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for receiver contact' using errcode = '42501'; end if;
    if (new.shipper_address, new.shipper_address_id, new.shipper_longitude, new.shipper_latitude)
       is distinct from (old.shipper_address, old.shipper_address_id, old.shipper_longitude, old.shipper_latitude)
       and app_private.resolve_field_access(v_resource_key, 'shipperAddress', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for shipper address' using errcode = '42501'; end if;
    if (new.receiver_address, new.receiver_address_id, new.receiver_longitude, new.receiver_latitude)
       is distinct from (old.receiver_address, old.receiver_address_id, old.receiver_longitude, old.receiver_latitude)
       and app_private.resolve_field_access(v_resource_key, 'receiverAddress', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for receiver address' using errcode = '42501'; end if;
    if new.freight_amount is distinct from old.freight_amount
       and app_private.resolve_field_access(v_resource_key, 'freightAmounts', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for waybill freight' using errcode = '42501'; end if;
    if (new.pickup_photos, new.delivery_photos, new.receipt_attachments)
       is distinct from (old.pickup_photos, old.delivery_photos, old.receipt_attachments)
       and app_private.resolve_field_access(v_resource_key, 'proofAttachments', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for waybill proofs' using errcode = '42501'; end if;
    if (new.route_points, new.shipper_longitude, new.shipper_latitude,
        new.receiver_longitude, new.receiver_latitude)
       is distinct from
       (old.route_points, old.shipper_longitude, old.shipper_latitude,
        old.receiver_longitude, old.receiver_latitude)
       and app_private.resolve_field_access(v_resource_key, 'routeCoordinates', v_owner_id) <> 'edit'
      then raise exception 'No edit permission for waybill coordinates' using errcode = '42501'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tms_order_sensitive_write_guard on public.tms_order;
create trigger tms_order_sensitive_write_guard
before update on public.tms_order
for each row execute function app_private.enforce_tms_transport_sensitive_writes();

drop trigger if exists tms_waybill_sensitive_write_guard on public.tms_waybill;
create trigger tms_waybill_sensitive_write_guard
before update on public.tms_waybill
for each row execute function app_private.enforce_tms_transport_sensitive_writes();

alter function public.tms_get_waybill_cargo_operation_context(uuid, text)
  rename to tms_get_waybill_cargo_operation_context_raw;

create or replace function public.tms_get_waybill_cargo_operation_context(
  p_waybill_id uuid,
  p_operation_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_waybill public.tms_waybill%rowtype;
  v_access jsonb;
  v_data jsonb;
  v_operation jsonb;
begin
  select * into v_waybill from public.tms_waybill waybill_row
  where waybill_row.id = p_waybill_id
    and (app_private.is_platform_super() or waybill_row.tenant_id = app_private.current_user_tenant_id());
  if not found then raise exception 'Waybill not found or access denied'; end if;

  v_data := public.tms_get_waybill_cargo_operation_context_raw(p_waybill_id, p_operation_type);
  v_access := app_private.field_access_map('tms.waybill', v_waybill.created_by_user_id);
  v_operation := v_data->'operation';

  if coalesce(v_access->>'routeCoordinates', 'hidden') not in ('read', 'edit') then
    v_data := v_data - array[
      'centerLongitude', 'centerLatitude', 'arrivalAddress', 'arrivalLongitude', 'arrivalLatitude'
    ]::text[];
    if jsonb_typeof(v_operation) = 'object' then
      v_operation := v_operation - array[
        'longitude', 'latitude', 'locationAccuracyM', 'locationText',
        'geofenceCenterLongitude', 'geofenceCenterLatitude', 'geofenceRadiusM',
        'distanceM', 'insideGeofence', 'outsideReason'
      ]::text[];
    end if;
  end if;
  if coalesce(v_access->>'proofAttachments', 'hidden') not in ('read', 'edit')
     and jsonb_typeof(v_operation) = 'object' then
    v_operation := v_operation - array[
      'photoUrls', 'weighbridgeTicketUrls', 'recognitionInfo', 'recognitionPayload'
    ]::text[];
  end if;
  if jsonb_typeof(v_operation) = 'object' then
    v_data := jsonb_set(v_data, '{operation}', v_operation, true);
  end if;
  return v_data || jsonb_build_object('fieldAccess', v_access);
end;
$$;

alter function public.tms_get_waybill_execution_context(uuid)
  rename to tms_get_waybill_execution_context_raw;

create or replace function public.tms_get_waybill_execution_context(p_waybill_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_waybill public.tms_waybill%rowtype;
  v_access jsonb;
  v_data jsonb;
  v_record jsonb;
begin
  select * into v_waybill from public.tms_waybill waybill_row
  where waybill_row.id = p_waybill_id
    and (app_private.is_platform_super() or waybill_row.tenant_id = app_private.current_user_tenant_id());
  if not found then raise exception 'Waybill not found or access denied'; end if;

  v_data := public.tms_get_waybill_execution_context_raw(p_waybill_id);
  v_access := app_private.field_access_map('tms.waybill', v_waybill.created_by_user_id);
  v_record := v_data->'record';
  if coalesce(v_access->>'routeCoordinates', 'hidden') not in ('read', 'edit') then
    v_data := v_data - array['arrivalAddress', 'arrivalLongitude', 'arrivalLatitude']::text[];
  end if;
  if coalesce(v_access->>'proofAttachments', 'hidden') not in ('read', 'edit')
     and jsonb_typeof(v_record) = 'object' then
    v_record := v_record - array[
      'departurePhotoUrls', 'receiptUrls', 'signatureUrls', 'returnPhotoUrls'
    ]::text[];
    v_data := jsonb_set(v_data, '{record}', v_record, true);
  end if;
  return v_data || jsonb_build_object('fieldAccess', v_access);
end;
$$;

create or replace function public.tms_dispatch_orders_secure(p_order_ids uuid[], p_dispatch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'TmsPendingWaybillList', 'TmsPendingWaybillList:Dispatch', null, false
  ) then raise exception 'Missing waybill dispatch permission' using errcode = '42501'; end if;
  if p_order_ids is null or cardinality(p_order_ids) = 0 then raise exception 'No orders selected'; end if;
  if exists (
    select 1 from unnest(p_order_ids) requested(id)
    left join public.tms_order order_row on order_row.id = requested.id
    where order_row.id is null
      or (not app_private.is_platform_super() and order_row.tenant_id <> app_private.current_user_tenant_id())
  ) then raise exception 'One or more orders are outside the current tenant'; end if;

  select coalesce(jsonb_agg(
    app_private.tms_order_to_secure_json(dispatched, 'tms.waybill', null, null)
  ), '[]'::jsonb) into v_result
  from public.tms_dispatch_orders(p_order_ids, p_dispatch) dispatched;
  return v_result;
end;
$$;

create or replace function public.tms_revoke_order_dispatch_secure(p_order_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'TmsPendingWaybillList', 'TmsPendingWaybillList:Cancel', null, false
  ) then raise exception 'Missing dispatch cancellation permission' using errcode = '42501'; end if;
  if p_order_ids is null or cardinality(p_order_ids) = 0 then raise exception 'No orders selected'; end if;
  if exists (
    select 1 from unnest(p_order_ids) requested(id)
    left join public.tms_order order_row on order_row.id = requested.id
    where order_row.id is null
      or (not app_private.is_platform_super() and order_row.tenant_id <> app_private.current_user_tenant_id())
  ) then raise exception 'One or more orders are outside the current tenant'; end if;

  select coalesce(jsonb_agg(
    app_private.tms_order_to_secure_json(revoked, 'tms.waybill', null, null)
  ), '[]'::jsonb) into v_result
  from public.tms_revoke_order_dispatch(p_order_ids) revoked;
  return v_result;
end;
$$;

create or replace function public.tms_delete_order_secure(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select created_by_user_id into v_owner_id from public.tms_order order_row
  where order_row.id = p_order_id
    and (app_private.is_platform_super() or order_row.tenant_id = app_private.current_user_tenant_id());
  if not found then raise exception 'Order not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsOrderList', 'TmsOrderList:Delete', v_owner_id, true
  ) then raise exception 'Missing order delete permission' using errcode = '42501'; end if;
  perform public.tms_delete_order_with_waybill(p_order_id);
  return true;
end;
$$;

create or replace function public.tms_delete_orders_secure(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  foreach v_id in array coalesce(p_order_ids, array[]::uuid[]) loop
    perform public.tms_delete_order_secure(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.tms_cancel_waybill_order_secure(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'TmsPendingWaybillList', 'TmsPendingWaybillList:Cancel', null, false
  ) then raise exception 'Missing waybill cancellation permission' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.tms_order order_row where order_row.id = p_order_id
      and (app_private.is_platform_super() or order_row.tenant_id = app_private.current_user_tenant_id())
  ) then raise exception 'Order not found or access denied'; end if;
  perform public.tms_cancel_order_with_waybill(p_order_id);
  return true;
end;
$$;

create or replace function public.tms_cancel_waybill_orders_secure(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  foreach v_id in array coalesce(p_order_ids, array[]::uuid[]) loop
    perform public.tms_cancel_waybill_order_secure(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create table if not exists public.tms_transport_change_signal (
  tenant_id uuid primary key references public.sys_tenant(id) on delete cascade,
  version bigint not null default 1,
  update_time timestamptz not null default now()
);

alter table public.tms_transport_change_signal enable row level security;
drop policy if exists tms_transport_change_signal_select on public.tms_transport_change_signal;
create policy tms_transport_change_signal_select
on public.tms_transport_change_signal
for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());

create or replace function app_private.touch_tms_transport_change_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := case when tg_op = 'DELETE' then old.tenant_id else new.tenant_id end;
begin
  insert into public.tms_transport_change_signal (tenant_id, version, update_time)
  values (v_tenant_id, 1, now())
  on conflict (tenant_id) do update
    set version = public.tms_transport_change_signal.version + 1,
        update_time = excluded.update_time;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists tms_order_change_signal on public.tms_order;
create trigger tms_order_change_signal
after insert or update or delete on public.tms_order
for each row execute function app_private.touch_tms_transport_change_signal();

drop trigger if exists tms_waybill_change_signal on public.tms_waybill;
create trigger tms_waybill_change_signal
after insert or update or delete on public.tms_waybill
for each row execute function app_private.touch_tms_transport_change_signal();

drop trigger if exists tms_vehicle_change_signal on public.vehicle_archive;
create trigger tms_vehicle_change_signal
after insert or update or delete on public.vehicle_archive
for each row execute function app_private.touch_tms_transport_change_signal();

insert into public.tms_transport_change_signal (tenant_id)
select id from public.sys_tenant
on conflict (tenant_id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tms_transport_change_signal'
  ) then
    alter publication supabase_realtime add table public.tms_transport_change_signal;
  end if;
end
$$;

drop trigger if exists tms_order_creator_identity on public.tms_order;
create trigger tms_order_creator_identity
before insert or update on public.tms_order
for each row execute function app_private.set_tms_transport_creator_identity();

drop trigger if exists tms_waybill_creator_identity on public.tms_waybill;
create trigger tms_waybill_creator_identity
before insert or update on public.tms_waybill
for each row execute function app_private.set_tms_transport_creator_identity();

do $$
declare
  function_row record;
begin
  for function_row in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_private'
      and p.proname in (
        'set_tms_transport_creator_identity', 'secure_scalar_json',
        'secure_tms_order_cargo_items', 'tms_order_to_secure_json',
        'tms_order_scope_resource', 'can_read_tms_order_scope',
        'tms_waybill_to_secure_json', 'secure_waybill_event_json',
        'assert_tms_order_payload_keys', 'assert_tms_order_reference_scope',
        'merge_tms_order_cargo_pricing',
        'tms_cargo_price_projection', 'enforce_tms_transport_sensitive_writes',
        'touch_tms_transport_change_signal'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', function_row.signature);
  end loop;

  for function_row in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'tms_list_orders_secure', 'tms_get_order_detail_secure',
        'tms_get_waybill_detail_secure', 'tms_list_waybills_secure',
        'tms_create_order_secure', 'tms_update_order_secure',
        'tms_get_waybill_cargo_operation_context', 'tms_get_waybill_execution_context',
        'tms_dispatch_orders_secure', 'tms_revoke_order_dispatch_secure',
        'tms_delete_order_secure', 'tms_delete_orders_secure',
        'tms_cancel_waybill_order_secure', 'tms_cancel_waybill_orders_secure'
      )
  loop
    execute format('revoke all on function %s from public, anon', function_row.signature);
    execute format('grant execute on function %s to authenticated', function_row.signature);
  end loop;

  for function_row in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'tms_get_waybill_cargo_operation_context_raw',
        'tms_get_waybill_execution_context_raw',
        'tms_dispatch_orders', 'tms_revoke_order_dispatch',
        'tms_delete_order_with_waybill', 'tms_delete_orders_with_waybills',
        'tms_cancel_order_with_waybill', 'tms_cancel_orders_with_waybills'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', function_row.signature);
  end loop;
end
$$;

revoke all on table public.tms_order from anon, authenticated;
revoke all on table public.tms_waybill from anon, authenticated;
revoke all on table public.tms_waybill_event from anon, authenticated;
revoke all on table public.tms_waybill_proof from anon, authenticated;
revoke all on table public.tms_waybill_cargo_operation from anon, authenticated;
revoke all on table public.tms_waybill_execution_record from anon, authenticated;
revoke all on table public.tms_transport_change_signal from anon, authenticated;

-- Preserve only non-sensitive foreign-key embeds required by finance and shared
-- operational selectors. Sensitive values are available exclusively through RPCs.
grant select (
  id, order_no, cargo_no, order_status, origin_station, destination_station,
  transfer_station, delivery_method, shipping_customer_id, receiving_customer_id,
  shipping_contact_name, receiving_contact_name, cargo_quantity_total,
  cargo_weight_total, cargo_volume_total, payment_method, transport_mode,
  order_remark, create_by, create_time, update_by, update_time, tenant_id,
  origin_station_id, destination_station_id, transfer_station_id, dispatch_status,
  dispatch_vehicle_id, dispatch_driver_id, dispatch_plate_no, dispatch_vehicle_type,
  dispatch_vehicle_length, dispatch_driver_name, planned_departure_time,
  planned_arrival_time, dispatch_remark, dispatched_at, dispatch_by, signed_at
) on public.tms_order to authenticated;

grant select (
  id, tenant_id, waybill_no, status, carrier_id, driver_id, vehicle_id, cargo_id,
  origin_city, destination_city, shipper_name, receiver_name, planned_load_time,
  planned_unload_time, accepted_at, loaded_at, departed_at, arrived_at, unloaded_at,
  completed_at, cancelled_at, cargo_name, cargo_type, cargo_weight_ton,
  cargo_volume_m3, cargo_quantity, estimated_duration_min, remaining_distance_km,
  remark, create_by, create_time, update_by, update_time, order_id
) on public.tms_waybill to authenticated;

grant select on public.tms_transport_change_signal to authenticated;

;
