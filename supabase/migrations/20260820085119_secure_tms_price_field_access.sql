-- Secure field-level access for customer and carrier rate-card snapshots.
-- Price records intentionally preserve point-in-time contact, address and amount data.

alter table public.tms_carrier_price
  add column created_by_user_id uuid;

alter table public.tms_customer_price
  add column created_by_user_id uuid;

update public.tms_carrier_price price_row
set created_by_user_id = creator.id
from public.sys_user creator
where creator.tenant_id = price_row.tenant_id
  and lower(creator.user_email) = lower(price_row.create_by)
  and price_row.created_by_user_id is null;

update public.tms_customer_price price_row
set created_by_user_id = creator.id
from public.sys_user creator
where creator.tenant_id = price_row.tenant_id
  and lower(creator.user_email) = lower(price_row.create_by)
  and price_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.tms_carrier_price where created_by_user_id is null
  ) then
    raise exception 'Cannot secure carrier prices: creator identity backfill is incomplete';
  end if;
  if exists (
    select 1 from public.tms_customer_price where created_by_user_id is null
  ) then
    raise exception 'Cannot secure customer prices: creator identity backfill is incomplete';
  end if;
end;
$$;

alter table public.tms_carrier_price
  alter column created_by_user_id set not null;

alter table public.tms_customer_price
  alter column created_by_user_id set not null;

alter table public.tms_carrier_price
  add constraint tms_carrier_price_created_by_user_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on delete restrict;

alter table public.tms_customer_price
  add constraint tms_customer_price_created_by_user_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on delete restrict;

create index tms_carrier_price_creator_tenant_idx
  on public.tms_carrier_price(created_by_user_id, tenant_id);

create index tms_carrier_price_tenant_creator_time_idx
  on public.tms_carrier_price(tenant_id, created_by_user_id, create_time desc);

create index tms_customer_price_creator_tenant_idx
  on public.tms_customer_price(created_by_user_id, tenant_id);

create index tms_customer_price_tenant_creator_time_idx
  on public.tms_customer_price(tenant_id, created_by_user_id, create_time desc);

create or replace function app_private.set_tms_price_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      limit 1;
    end if;

    if new.created_by_user_id is null then
      raise exception 'Authenticated price creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Record creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger tms_carrier_price_creator_identity
before insert or update on public.tms_carrier_price
for each row execute function app_private.set_tms_price_creator_identity();

create trigger tms_customer_price_creator_identity
before insert or update on public.tms_customer_price
for each row execute function app_private.set_tms_price_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_price;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_price(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.carrier_price', '承运商报价', 'TmsCarrierPrice',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
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
    (p_tenant_id, v_resource_id, 'contactPhones', '承运商与司机联系电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'costAmounts', '成本与拆分运费', 'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'paymentAmounts', '付款金额拆分', 'hidden', 'amount', true, 30, '624944977@qq.com', '624944977@qq.com')
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
    p_tenant_id, 'tms.customer_price', '客户报价', 'TmsCustomerPrice',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
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
    (p_tenant_id, v_resource_id, 'contactPhones', '收发货联系电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'addressDetails', '收发货详细地址与坐标', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'quoteAmounts', '客户报价与费用明细', 'hidden', 'amount', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'paymentAmounts', '付款金额拆分', 'hidden', 'amount', true, 40, '624944977@qq.com', '624944977@qq.com')
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
end;
$$;

-- Preserve the existing rollout experience: roles already owning a price page start with
-- edit access to its newly catalogued sensitive fields. Administrators can tighten it later.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id
 and field_row.tenant_id = resource_row.tenant_id
 and field_row.enabled
join public.sys_menu page_menu
  on page_menu.name = resource_row.menu_name
 and page_menu.type = 'menu'
join public.sys_role_menu role_menu
  on role_menu.menu_id = page_menu.id
 and role_menu.tenant_id = resource_row.tenant_id
where resource_row.resource_key in ('tms.carrier_price', 'tms.customer_price')
  and resource_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

revoke all on function app_private.set_tms_price_creator_identity() from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog_before_price(uuid) from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;

create or replace function app_private.apply_jsonb_amount_access(
  p_data jsonb,
  p_keys text[],
  p_access text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb := coalesce(p_data, '{}'::jsonb);
  v_key text;
begin
  foreach v_key in array p_keys loop
    if p_access = 'hidden' then
      v_result := v_result - v_key;
    elsif p_access = 'masked' and v_result ? v_key then
      v_result := jsonb_set(v_result, array[v_key], '"***"'::jsonb, true);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function app_private.apply_carrier_price_cargo_cost_access(
  p_items jsonb,
  p_access text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      app_private.apply_jsonb_amount_access(
        item.value,
        array['split_transport_fee', 'loading_fee', 'package_fee']::text[],
        p_access
      )
      order by item.ordinality
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    case when jsonb_typeof(coalesce(p_items, '[]'::jsonb)) = 'array'
      then coalesce(p_items, '[]'::jsonb)
      else '[]'::jsonb
    end
  ) with ordinality as item(value, ordinality);
$$;

create or replace function app_private.carrier_price_cargo_cost_signature(p_items jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_array(
        coalesce(nullif(item.value->>'split_transport_fee', '')::numeric, 0),
        coalesce(nullif(item.value->>'loading_fee', '')::numeric, 0),
        coalesce(nullif(item.value->>'package_fee', '')::numeric, 0)
      )
      order by item.ordinality
    ) filter (
      where coalesce(nullif(item.value->>'split_transport_fee', '')::numeric, 0) <> 0
         or coalesce(nullif(item.value->>'loading_fee', '')::numeric, 0) <> 0
         or coalesce(nullif(item.value->>'package_fee', '')::numeric, 0) <> 0
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    case when jsonb_typeof(coalesce(p_items, '[]'::jsonb)) = 'array'
      then coalesce(p_items, '[]'::jsonb)
      else '[]'::jsonb
    end
  ) with ordinality as item(value, ordinality);
$$;

create or replace function app_private.tms_carrier_price_to_secure_json(
  p_price public.tms_carrier_price,
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
    app_private.field_access_map('tms.carrier_price', p_price.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_price) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_data := v_data || jsonb_build_object(
    'carrier', (
      select jsonb_build_object(
        'id', carrier_row.id,
        'carrier_code', carrier_row.carrier_code,
        'company_name', carrier_row.company_name,
        'contact_name', carrier_row.contact_name
      )
      from public.tms_carrier carrier_row
      where carrier_row.id = p_price.carrier_id
        and carrier_row.tenant_id = p_price.tenant_id
    ),
    'driver', (
      select jsonb_build_object(
        'id', driver_row.id,
        'carrier_id', driver_row.carrier_id,
        'driver_name', driver_row.driver_name
      )
      from public.tms_driver driver_row
      where driver_row.id = p_price.driver_id
        and driver_row.tenant_id = p_price.tenant_id
    ),
    'vehicle', (
      select jsonb_build_object(
        'id', vehicle_row.id,
        'carrier_id', vehicle_row.carrier_id,
        'plate_no', vehicle_row.plate_no,
        'company_name', vehicle_row.company_name,
        'vehicle_type', vehicle_row.vehicle_type,
        'vin', vehicle_row.vin,
        'self_no', vehicle_row.self_no
      )
      from public.vehicle_archive vehicle_row
      where vehicle_row.id = p_price.vehicle_id
        and vehicle_row.tenant_id = p_price.tenant_id
    )
  );

  v_level := coalesce(v_access->>'contactPhones', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'contact_phone' - 'driver_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.contact_phone, 'phone')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{driver_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.driver_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'costAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'transport_cost', 'split_transport_fee', 'loading_fee', 'package_fee',
      'other_fee', 'total_fee'
    ]::text[],
    v_level
  );
  v_data := jsonb_set(
    v_data,
    '{cargo_items}',
    app_private.apply_carrier_price_cargo_cost_access(p_price.cargo_items, v_level),
    true
  );

  v_level := coalesce(v_access->>'paymentAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'cash_amount', 'prepaid_amount', 'collect_amount', 'periodic_amount', 'payment_total'
    ]::text[],
    v_level
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_price.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_customer_price_to_secure_json(
  p_price public.tms_customer_price,
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
    app_private.field_access_map('tms.customer_price', p_price.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_price) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_data := v_data || jsonb_build_object(
    'customer', (
      select jsonb_build_object(
        'id', customer_row.id,
        'customer_code', customer_row.customer_code,
        'customer_name', customer_row.customer_name,
        'contact_name', customer_row.contact_name
      )
      from public.tms_customer customer_row
      where customer_row.id = p_price.customer_id
        and customer_row.tenant_id = p_price.tenant_id
    )
  );

  v_level := coalesce(v_access->>'contactPhones', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'shipping_contact_phone' - 'receiving_contact_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{shipping_contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.shipping_contact_phone, 'phone')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{receiving_contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.receiving_contact_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'addressDetails', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'shipping_address_id' - 'shipping_address_detail'
      - 'shipping_longitude' - 'shipping_latitude'
      - 'receiving_address_id' - 'receiving_address_detail'
      - 'receiving_longitude' - 'receiving_latitude';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{shipping_address_detail}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.shipping_address_detail, 'address')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{receiving_address_detail}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_price.receiving_address_detail, 'address')
    ), 'null'::jsonb));
    v_data := v_data
      - 'shipping_address_id' - 'shipping_longitude' - 'shipping_latitude'
      - 'receiving_address_id' - 'receiving_longitude' - 'receiving_latitude';
  end if;

  v_level := coalesce(v_access->>'quoteAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'transport_fee', 'insurance_fee', 'package_fee', 'loading_fee', 'transfer_fee',
      'fuel_fee', 'service_fee', 'other_fee', 'total_fee'
    ]::text[],
    v_level
  );

  v_level := coalesce(v_access->>'paymentAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'cash_amount', 'prepaid_amount', 'collect_amount', 'periodic_amount', 'payment_total'
    ]::text[],
    v_level
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_price.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.assert_tms_carrier_price_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Carrier price payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'quote_no', 'carrier_id', 'driver_id', 'vehicle_id', 'origin_region',
    'destination_region', 'transport_mode', 'contact_name', 'contact_phone',
    'driver_name', 'driver_phone', 'plate_no', 'vehicle_type', 'vehicle_length',
    'cargo_items', 'cargo_quantity_total', 'cargo_volume_total', 'cargo_weight_total',
    'billing_method', 'transport_cost', 'split_transport_fee', 'loading_fee',
    'package_fee', 'other_fee', 'total_fee', 'cash_amount', 'prepaid_amount',
    'collect_amount', 'periodic_amount', 'payment_total', 'remark'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Carrier price payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_customer_price_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Customer price payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'customer_id', 'origin_region', 'destination_region', 'transport_type', 'cargo_type',
    'shipping_contact_name', 'shipping_contact_phone', 'shipping_address_detail',
    'receiving_contact_name', 'receiving_contact_phone', 'receiving_address_detail',
    'cargo_items', 'cargo_quantity_total', 'cargo_volume_total', 'cargo_weight_total',
    'vehicle_type', 'vehicle_length', 'vehicle_count', 'billing_method', 'transport_fee',
    'insurance_fee', 'package_fee', 'loading_fee', 'transfer_fee', 'fuel_fee',
    'service_fee', 'other_fee', 'total_fee', 'cash_amount', 'prepaid_amount',
    'collect_amount', 'periodic_amount', 'payment_total', 'remark', 'shipping_address_id',
    'receiving_address_id', 'shipping_longitude', 'shipping_latitude',
    'receiving_longitude', 'receiving_latitude'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Customer price payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_carrier_price_reference_scope(
  p_tenant_id uuid,
  p_carrier_id uuid,
  p_driver_id uuid,
  p_vehicle_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id
      and carrier_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Carrier is outside the current tenant' using errcode = '42501';
  end if;
  if p_driver_id is not null and not exists (
    select 1 from public.tms_driver driver_row
    where driver_row.id = p_driver_id
      and driver_row.tenant_id = p_tenant_id
      and driver_row.carrier_id = p_carrier_id
  ) then
    raise exception 'Driver does not belong to the selected carrier' using errcode = '42501';
  end if;
  if p_vehicle_id is not null and not exists (
    select 1 from public.vehicle_archive vehicle_row
    where vehicle_row.id = p_vehicle_id
      and vehicle_row.tenant_id = p_tenant_id
      and (vehicle_row.carrier_id is null or vehicle_row.carrier_id = p_carrier_id)
  ) then
    raise exception 'Vehicle does not belong to the selected carrier' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.assert_tms_customer_price_reference_scope(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_shipping_address_id uuid,
  p_receiving_address_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.tms_customer customer_row
    where customer_row.id = p_customer_id
      and customer_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Customer is outside the current tenant' using errcode = '42501';
  end if;
  if p_shipping_address_id is not null and not exists (
    select 1 from public.tms_customer_address address_row
    where address_row.id = p_shipping_address_id
      and address_row.tenant_id = p_tenant_id
      and address_row.customer_id = p_customer_id
      and address_row.address_type = 'shipping'
  ) then
    raise exception 'Shipping address does not belong to the selected customer'
      using errcode = '42501';
  end if;
  if p_receiving_address_id is not null and not exists (
    select 1 from public.tms_customer_address address_row
    where address_row.id = p_receiving_address_id
      and address_row.tenant_id = p_tenant_id
      and address_row.address_type = 'receiving'
  ) then
    raise exception 'Receiving address is outside the current tenant' using errcode = '42501';
  end if;
end;
$$;

revoke all on function app_private.apply_jsonb_amount_access(jsonb, text[], text) from public, anon, authenticated;
revoke all on function app_private.apply_carrier_price_cargo_cost_access(jsonb, text) from public, anon, authenticated;
revoke all on function app_private.carrier_price_cargo_cost_signature(jsonb) from public, anon, authenticated;
revoke all on function app_private.tms_carrier_price_to_secure_json(public.tms_carrier_price, jsonb) from public, anon, authenticated;
revoke all on function app_private.tms_customer_price_to_secure_json(public.tms_customer_price, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_carrier_price_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_price_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_carrier_price_reference_scope(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_price_reference_scope(uuid, uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.tms_list_carrier_prices_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_carrier_id uuid default null,
  p_record_id uuid default null,
  p_origin_region text default null,
  p_destination_region text default null,
  p_transport_mode text default null,
  p_billing_method text default null,
  p_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_permission text := case when p_purpose = 'export'
    then 'TmsCarrierPrice:Export' else 'TmsCarrierPrice:View' end;
  v_limit integer;
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid carrier price read purpose';
  end if;
  if not app_private.can_execute_business_action('TmsCarrierPrice', v_permission, null, false) then
    raise exception 'Missing carrier price read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.carrier_price', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhones', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select price_row as price_record
    from public.tms_carrier_price price_row
    where (app_private.is_platform_super() or price_row.tenant_id = v_tenant_id)
      and (p_carrier_id is null or price_row.carrier_id = p_carrier_id)
      and (p_record_id is null or price_row.id = p_record_id)
      and (p_ids is null or price_row.id = any(p_ids))
      and (p_origin_region is null or price_row.origin_region = p_origin_region)
      and (p_destination_region is null or price_row.destination_region = p_destination_region)
      and (p_transport_mode is null or price_row.transport_mode = p_transport_mode)
      and (p_billing_method is null or price_row.billing_method = p_billing_method)
      and (p_create_time_from is null or price_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or price_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or price_row.quote_no ilike '%' || btrim(p_keyword) || '%'
        or price_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or price_row.driver_name ilike '%' || btrim(p_keyword) || '%'
        or price_row.plate_no ilike '%' || btrim(p_keyword) || '%'
        or price_row.remark ilike '%' || btrim(p_keyword) || '%'
        or exists (
          select 1 from public.tms_carrier carrier_row
          where carrier_row.id = price_row.carrier_id
            and carrier_row.tenant_id = price_row.tenant_id
            and (
              carrier_row.company_name ilike '%' || btrim(p_keyword) || '%'
              or carrier_row.carrier_code ilike '%' || btrim(p_keyword) || '%'
            )
        )
        or (
          (v_can_search_phone or price_row.created_by_user_id = v_user_id)
          and (
            price_row.contact_phone ilike '%' || btrim(p_keyword) || '%'
            or price_row.driver_phone ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
  ), paged as (
    select filtered.price_record
    from filtered
    order by (filtered.price_record).create_time desc, (filtered.price_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_carrier_price_to_secure_json(paged.price_record, null)
        order by (paged.price_record).create_time desc, (paged.price_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_get_carrier_price_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_price public.tms_carrier_price%rowtype;
begin
  if not app_private.can_execute_business_action(
    'TmsCarrierPrice', 'TmsCarrierPrice:View', null, false
  ) then
    raise exception 'Missing carrier price view permission' using errcode = '42501';
  end if;
  select * into v_price
  from public.tms_carrier_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;
  return app_private.tms_carrier_price_to_secure_json(v_price, null);
end;
$$;

create or replace function public.tms_create_carrier_price_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_carrier_price%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action(
    'TmsCarrierPrice', 'TmsCarrierPrice:Add', null, false
  ) then
    raise exception 'Missing carrier price create permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;
  perform app_private.assert_tms_carrier_price_payload_keys(p_payload);
  select * into v_input
  from jsonb_populate_record(null::public.tms_carrier_price, p_payload);
  perform app_private.assert_tms_carrier_price_reference_scope(
    v_tenant_id, v_input.carrier_id, v_input.driver_id, v_input.vehicle_id
  );

  insert into public.tms_carrier_price (
    quote_no, carrier_id, driver_id, vehicle_id, origin_region, destination_region,
    transport_mode, contact_name, contact_phone, driver_name, driver_phone, plate_no,
    vehicle_type, vehicle_length, cargo_items, cargo_quantity_total, cargo_volume_total,
    cargo_weight_total, billing_method, transport_cost, split_transport_fee, loading_fee,
    package_fee, other_fee, total_fee, cash_amount, prepaid_amount, collect_amount,
    periodic_amount, payment_total, remark, tenant_id
  ) values (
    nullif(v_input.quote_no, ''), v_input.carrier_id, v_input.driver_id, v_input.vehicle_id,
    v_input.origin_region, v_input.destination_region, v_input.transport_mode,
    v_input.contact_name, v_input.contact_phone, v_input.driver_name, v_input.driver_phone,
    v_input.plate_no, v_input.vehicle_type, v_input.vehicle_length,
    coalesce(v_input.cargo_items, '[]'::jsonb), coalesce(v_input.cargo_quantity_total, 0),
    coalesce(v_input.cargo_volume_total, 0), coalesce(v_input.cargo_weight_total, 0),
    v_input.billing_method, coalesce(v_input.transport_cost, 0),
    coalesce(v_input.split_transport_fee, 0), coalesce(v_input.loading_fee, 0),
    coalesce(v_input.package_fee, 0), coalesce(v_input.other_fee, 0),
    coalesce(v_input.total_fee, 0), coalesce(v_input.cash_amount, 0),
    coalesce(v_input.prepaid_amount, 0), coalesce(v_input.collect_amount, 0),
    coalesce(v_input.periodic_amount, 0), coalesce(v_input.payment_total, 0),
    v_input.remark, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_carrier_price_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_carrier_price%rowtype;
  v_candidate public.tms_carrier_price%rowtype;
  v_updated public.tms_carrier_price%rowtype;
begin
  select * into v_old
  from public.tms_carrier_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Carrier price not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsCarrierPrice', 'TmsCarrierPrice:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing carrier price edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_carrier_price_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_carrier_price_reference_scope(
    v_old.tenant_id, v_candidate.carrier_id, v_candidate.driver_id, v_candidate.vehicle_id
  );

  if (v_candidate.carrier_id, v_candidate.driver_id, v_candidate.contact_phone, v_candidate.driver_phone)
     is distinct from (v_old.carrier_id, v_old.driver_id, v_old.contact_phone, v_old.driver_phone)
     and app_private.resolve_field_access(
       'tms.carrier_price', 'contactPhones', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier price contact phones' using errcode = '42501';
  end if;

  if (
    v_candidate.transport_cost, v_candidate.split_transport_fee, v_candidate.loading_fee,
    v_candidate.package_fee, v_candidate.other_fee, v_candidate.total_fee,
    app_private.carrier_price_cargo_cost_signature(v_candidate.cargo_items)
  ) is distinct from (
    v_old.transport_cost, v_old.split_transport_fee, v_old.loading_fee,
    v_old.package_fee, v_old.other_fee, v_old.total_fee,
    app_private.carrier_price_cargo_cost_signature(v_old.cargo_items)
  ) and app_private.resolve_field_access(
    'tms.carrier_price', 'costAmounts', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for carrier price costs' using errcode = '42501';
  end if;

  if (v_candidate.cash_amount, v_candidate.prepaid_amount, v_candidate.collect_amount,
      v_candidate.periodic_amount, v_candidate.payment_total)
     is distinct from (v_old.cash_amount, v_old.prepaid_amount, v_old.collect_amount,
      v_old.periodic_amount, v_old.payment_total)
     and app_private.resolve_field_access(
       'tms.carrier_price', 'paymentAmounts', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier price payment amounts' using errcode = '42501';
  end if;

  update public.tms_carrier_price set
    quote_no = v_candidate.quote_no,
    carrier_id = v_candidate.carrier_id,
    driver_id = v_candidate.driver_id,
    vehicle_id = v_candidate.vehicle_id,
    origin_region = v_candidate.origin_region,
    destination_region = v_candidate.destination_region,
    transport_mode = v_candidate.transport_mode,
    contact_name = v_candidate.contact_name,
    contact_phone = v_candidate.contact_phone,
    driver_name = v_candidate.driver_name,
    driver_phone = v_candidate.driver_phone,
    plate_no = v_candidate.plate_no,
    vehicle_type = v_candidate.vehicle_type,
    vehicle_length = v_candidate.vehicle_length,
    cargo_items = v_candidate.cargo_items,
    cargo_quantity_total = v_candidate.cargo_quantity_total,
    cargo_volume_total = v_candidate.cargo_volume_total,
    cargo_weight_total = v_candidate.cargo_weight_total,
    billing_method = v_candidate.billing_method,
    transport_cost = v_candidate.transport_cost,
    split_transport_fee = v_candidate.split_transport_fee,
    loading_fee = v_candidate.loading_fee,
    package_fee = v_candidate.package_fee,
    other_fee = v_candidate.other_fee,
    total_fee = v_candidate.total_fee,
    cash_amount = v_candidate.cash_amount,
    prepaid_amount = v_candidate.prepaid_amount,
    collect_amount = v_candidate.collect_amount,
    periodic_amount = v_candidate.periodic_amount,
    payment_total = v_candidate.payment_total,
    remark = v_candidate.remark
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_carrier_price_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_delete_carrier_price_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_price public.tms_carrier_price%rowtype;
begin
  select * into v_price
  from public.tms_carrier_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsCarrierPrice', 'TmsCarrierPrice:Delete', v_price.created_by_user_id, true
  ) then
    raise exception 'Missing carrier price delete permission' using errcode = '42501';
  end if;
  delete from public.tms_carrier_price where id = v_price.id;
  return true;
end;
$$;

create or replace function public.tms_delete_carrier_prices_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_deleted integer := 0;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'A maximum of 500 carrier prices can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_carrier_price_secure(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

create or replace function public.tms_list_customer_prices_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_customer_id uuid default null,
  p_record_id uuid default null,
  p_origin_region text default null,
  p_destination_region text default null,
  p_transport_type text default null,
  p_cargo_type text default null,
  p_billing_method text default null,
  p_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_permission text := case when p_purpose = 'export'
    then 'TmsCustomerPrice:Export' else 'TmsCustomerPrice:View' end;
  v_limit integer;
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_can_search_address boolean;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid customer price read purpose';
  end if;
  if not app_private.can_execute_business_action('TmsCustomerPrice', v_permission, null, false) then
    raise exception 'Missing customer price read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.customer_price', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhones', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_base_access->>'addressDetails', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select price_row as price_record
    from public.tms_customer_price price_row
    where (app_private.is_platform_super() or price_row.tenant_id = v_tenant_id)
      and (p_customer_id is null or price_row.customer_id = p_customer_id)
      and (p_record_id is null or price_row.id = p_record_id)
      and (p_ids is null or price_row.id = any(p_ids))
      and (p_origin_region is null or price_row.origin_region = p_origin_region)
      and (p_destination_region is null or price_row.destination_region = p_destination_region)
      and (p_transport_type is null or price_row.transport_type = p_transport_type)
      and (p_cargo_type is null or price_row.cargo_type = p_cargo_type)
      and (p_billing_method is null or price_row.billing_method = p_billing_method)
      and (p_create_time_from is null or price_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or price_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or price_row.shipping_contact_name ilike '%' || btrim(p_keyword) || '%'
        or price_row.receiving_contact_name ilike '%' || btrim(p_keyword) || '%'
        or price_row.remark ilike '%' || btrim(p_keyword) || '%'
        or exists (
          select 1 from public.tms_customer customer_row
          where customer_row.id = price_row.customer_id
            and customer_row.tenant_id = price_row.tenant_id
            and (
              customer_row.customer_name ilike '%' || btrim(p_keyword) || '%'
              or customer_row.customer_code ilike '%' || btrim(p_keyword) || '%'
            )
        )
        or (
          (v_can_search_phone or price_row.created_by_user_id = v_user_id)
          and (
            price_row.shipping_contact_phone ilike '%' || btrim(p_keyword) || '%'
            or price_row.receiving_contact_phone ilike '%' || btrim(p_keyword) || '%'
          )
        )
        or (
          (v_can_search_address or price_row.created_by_user_id = v_user_id)
          and (
            price_row.shipping_address_detail ilike '%' || btrim(p_keyword) || '%'
            or price_row.receiving_address_detail ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
  ), paged as (
    select filtered.price_record
    from filtered
    order by (filtered.price_record).create_time desc, (filtered.price_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_customer_price_to_secure_json(paged.price_record, null)
        order by (paged.price_record).create_time desc, (paged.price_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_get_customer_price_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_price public.tms_customer_price%rowtype;
begin
  if not app_private.can_execute_business_action(
    'TmsCustomerPrice', 'TmsCustomerPrice:View', null, false
  ) then
    raise exception 'Missing customer price view permission' using errcode = '42501';
  end if;
  select * into v_price
  from public.tms_customer_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;
  return app_private.tms_customer_price_to_secure_json(v_price, null);
end;
$$;

create or replace function public.tms_create_customer_price_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_customer_price%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action(
    'TmsCustomerPrice', 'TmsCustomerPrice:Add', null, false
  ) then
    raise exception 'Missing customer price create permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;
  perform app_private.assert_tms_customer_price_payload_keys(p_payload);
  select * into v_input
  from jsonb_populate_record(null::public.tms_customer_price, p_payload);
  perform app_private.assert_tms_customer_price_reference_scope(
    v_tenant_id, v_input.customer_id, v_input.shipping_address_id, v_input.receiving_address_id
  );

  insert into public.tms_customer_price (
    customer_id, origin_region, destination_region, transport_type, cargo_type,
    shipping_contact_name, shipping_contact_phone, shipping_address_detail,
    receiving_contact_name, receiving_contact_phone, receiving_address_detail,
    cargo_items, cargo_quantity_total, cargo_volume_total, cargo_weight_total,
    vehicle_type, vehicle_length, vehicle_count, billing_method, transport_fee,
    insurance_fee, package_fee, loading_fee, transfer_fee, fuel_fee, service_fee,
    other_fee, total_fee, cash_amount, prepaid_amount, collect_amount, periodic_amount,
    payment_total, remark, shipping_address_id, receiving_address_id,
    shipping_longitude, shipping_latitude, receiving_longitude, receiving_latitude,
    tenant_id
  ) values (
    v_input.customer_id, v_input.origin_region, v_input.destination_region,
    v_input.transport_type, v_input.cargo_type, v_input.shipping_contact_name,
    v_input.shipping_contact_phone, v_input.shipping_address_detail,
    v_input.receiving_contact_name, v_input.receiving_contact_phone,
    v_input.receiving_address_detail, coalesce(v_input.cargo_items, '[]'::jsonb),
    coalesce(v_input.cargo_quantity_total, 0), coalesce(v_input.cargo_volume_total, 0),
    coalesce(v_input.cargo_weight_total, 0), v_input.vehicle_type, v_input.vehicle_length,
    v_input.vehicle_count, v_input.billing_method, coalesce(v_input.transport_fee, 0),
    coalesce(v_input.insurance_fee, 0), coalesce(v_input.package_fee, 0),
    coalesce(v_input.loading_fee, 0), coalesce(v_input.transfer_fee, 0),
    coalesce(v_input.fuel_fee, 0), coalesce(v_input.service_fee, 0),
    coalesce(v_input.other_fee, 0), coalesce(v_input.total_fee, 0),
    coalesce(v_input.cash_amount, 0), coalesce(v_input.prepaid_amount, 0),
    coalesce(v_input.collect_amount, 0), coalesce(v_input.periodic_amount, 0),
    coalesce(v_input.payment_total, 0), v_input.remark, v_input.shipping_address_id,
    v_input.receiving_address_id, v_input.shipping_longitude, v_input.shipping_latitude,
    v_input.receiving_longitude, v_input.receiving_latitude, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_customer_price_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_customer_price%rowtype;
  v_candidate public.tms_customer_price%rowtype;
  v_updated public.tms_customer_price%rowtype;
begin
  select * into v_old
  from public.tms_customer_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Customer price not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsCustomerPrice', 'TmsCustomerPrice:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing customer price edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_customer_price_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_customer_price_reference_scope(
    v_old.tenant_id, v_candidate.customer_id,
    v_candidate.shipping_address_id, v_candidate.receiving_address_id
  );

  if (v_candidate.customer_id, v_candidate.shipping_contact_phone,
      v_candidate.receiving_contact_phone)
     is distinct from (v_old.customer_id, v_old.shipping_contact_phone,
      v_old.receiving_contact_phone)
     and app_private.resolve_field_access(
       'tms.customer_price', 'contactPhones', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for customer price contact phones' using errcode = '42501';
  end if;

  if (
    v_candidate.customer_id,
    v_candidate.shipping_address_id, v_candidate.shipping_address_detail,
    v_candidate.shipping_longitude, v_candidate.shipping_latitude,
    v_candidate.receiving_address_id, v_candidate.receiving_address_detail,
    v_candidate.receiving_longitude, v_candidate.receiving_latitude
  ) is distinct from (
    v_old.customer_id,
    v_old.shipping_address_id, v_old.shipping_address_detail,
    v_old.shipping_longitude, v_old.shipping_latitude,
    v_old.receiving_address_id, v_old.receiving_address_detail,
    v_old.receiving_longitude, v_old.receiving_latitude
  ) and app_private.resolve_field_access(
    'tms.customer_price', 'addressDetails', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for customer price addresses' using errcode = '42501';
  end if;

  if (
    v_candidate.transport_fee, v_candidate.insurance_fee, v_candidate.package_fee,
    v_candidate.loading_fee, v_candidate.transfer_fee, v_candidate.fuel_fee,
    v_candidate.service_fee, v_candidate.other_fee, v_candidate.total_fee
  ) is distinct from (
    v_old.transport_fee, v_old.insurance_fee, v_old.package_fee,
    v_old.loading_fee, v_old.transfer_fee, v_old.fuel_fee,
    v_old.service_fee, v_old.other_fee, v_old.total_fee
  ) and app_private.resolve_field_access(
    'tms.customer_price', 'quoteAmounts', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for customer price quote amounts' using errcode = '42501';
  end if;

  if (v_candidate.cash_amount, v_candidate.prepaid_amount, v_candidate.collect_amount,
      v_candidate.periodic_amount, v_candidate.payment_total)
     is distinct from (v_old.cash_amount, v_old.prepaid_amount, v_old.collect_amount,
      v_old.periodic_amount, v_old.payment_total)
     and app_private.resolve_field_access(
       'tms.customer_price', 'paymentAmounts', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for customer price payment amounts' using errcode = '42501';
  end if;

  update public.tms_customer_price set
    customer_id = v_candidate.customer_id,
    origin_region = v_candidate.origin_region,
    destination_region = v_candidate.destination_region,
    transport_type = v_candidate.transport_type,
    cargo_type = v_candidate.cargo_type,
    shipping_contact_name = v_candidate.shipping_contact_name,
    shipping_contact_phone = v_candidate.shipping_contact_phone,
    shipping_address_detail = v_candidate.shipping_address_detail,
    receiving_contact_name = v_candidate.receiving_contact_name,
    receiving_contact_phone = v_candidate.receiving_contact_phone,
    receiving_address_detail = v_candidate.receiving_address_detail,
    cargo_items = v_candidate.cargo_items,
    cargo_quantity_total = v_candidate.cargo_quantity_total,
    cargo_volume_total = v_candidate.cargo_volume_total,
    cargo_weight_total = v_candidate.cargo_weight_total,
    vehicle_type = v_candidate.vehicle_type,
    vehicle_length = v_candidate.vehicle_length,
    vehicle_count = v_candidate.vehicle_count,
    billing_method = v_candidate.billing_method,
    transport_fee = v_candidate.transport_fee,
    insurance_fee = v_candidate.insurance_fee,
    package_fee = v_candidate.package_fee,
    loading_fee = v_candidate.loading_fee,
    transfer_fee = v_candidate.transfer_fee,
    fuel_fee = v_candidate.fuel_fee,
    service_fee = v_candidate.service_fee,
    other_fee = v_candidate.other_fee,
    total_fee = v_candidate.total_fee,
    cash_amount = v_candidate.cash_amount,
    prepaid_amount = v_candidate.prepaid_amount,
    collect_amount = v_candidate.collect_amount,
    periodic_amount = v_candidate.periodic_amount,
    payment_total = v_candidate.payment_total,
    remark = v_candidate.remark,
    shipping_address_id = v_candidate.shipping_address_id,
    receiving_address_id = v_candidate.receiving_address_id,
    shipping_longitude = v_candidate.shipping_longitude,
    shipping_latitude = v_candidate.shipping_latitude,
    receiving_longitude = v_candidate.receiving_longitude,
    receiving_latitude = v_candidate.receiving_latitude
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_customer_price_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_delete_customer_price_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_price public.tms_customer_price%rowtype;
begin
  select * into v_price
  from public.tms_customer_price price_row
  where price_row.id = p_id
    and (app_private.is_platform_super()
      or price_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsCustomerPrice', 'TmsCustomerPrice:Delete', v_price.created_by_user_id, true
  ) then
    raise exception 'Missing customer price delete permission' using errcode = '42501';
  end if;
  delete from public.tms_customer_price where id = v_price.id;
  return true;
end;
$$;

create or replace function public.tms_delete_customer_prices_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_deleted integer := 0;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'A maximum of 500 customer prices can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_customer_price_secure(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

revoke all on table public.tms_carrier_price from anon, authenticated;
revoke all on table public.tms_customer_price from anon, authenticated;

-- Keep only the non-sensitive reference columns required by existing dependency previews.
grant select (id, vehicle_id) on table public.tms_carrier_price to authenticated;
grant select (id, customer_id, shipping_address_id, receiving_address_id)
  on table public.tms_customer_price to authenticated;

revoke all on function public.tms_list_carrier_prices_secure(
  integer, integer, uuid, uuid, text, text, text, text, text,
  timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.tms_get_carrier_price_secure(uuid) from public, anon;
revoke all on function public.tms_create_carrier_price_secure(jsonb) from public, anon;
revoke all on function public.tms_update_carrier_price_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_carrier_price_secure(uuid) from public, anon;
revoke all on function public.tms_delete_carrier_prices_secure(uuid[]) from public, anon;

revoke all on function public.tms_list_customer_prices_secure(
  integer, integer, uuid, uuid, text, text, text, text, text, text,
  timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.tms_get_customer_price_secure(uuid) from public, anon;
revoke all on function public.tms_create_customer_price_secure(jsonb) from public, anon;
revoke all on function public.tms_update_customer_price_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_customer_price_secure(uuid) from public, anon;
revoke all on function public.tms_delete_customer_prices_secure(uuid[]) from public, anon;

grant execute on function public.tms_list_carrier_prices_secure(
  integer, integer, uuid, uuid, text, text, text, text, text,
  timestamptz, timestamptz, uuid[], text
) to authenticated;
grant execute on function public.tms_get_carrier_price_secure(uuid) to authenticated;
grant execute on function public.tms_create_carrier_price_secure(jsonb) to authenticated;
grant execute on function public.tms_update_carrier_price_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_carrier_price_secure(uuid) to authenticated;
grant execute on function public.tms_delete_carrier_prices_secure(uuid[]) to authenticated;

grant execute on function public.tms_list_customer_prices_secure(
  integer, integer, uuid, uuid, text, text, text, text, text, text,
  timestamptz, timestamptz, uuid[], text
) to authenticated;
grant execute on function public.tms_get_customer_price_secure(uuid) to authenticated;
grant execute on function public.tms_create_customer_price_secure(jsonb) to authenticated;
grant execute on function public.tms_update_customer_price_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_customer_price_secure(uuid) to authenticated;
grant execute on function public.tms_delete_customer_prices_secure(uuid[]) to authenticated;

comment on column public.tms_carrier_price.created_by_user_id is
  'Immutable application-user creator identity used for field-access owner override.';
comment on column public.tms_customer_price.created_by_user_id is
  'Immutable application-user creator identity used for field-access owner override.';

;
