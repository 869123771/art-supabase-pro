-- Close the remaining order / waybill field-authorization gaps:
-- 1. split pending and loaded read scopes so one page grant cannot read the other page;
-- 2. enforce every sensitive order field on the database write boundary;
-- 3. retain legacy shared scopes only for callers that own both corresponding grants.

create or replace function app_private.tms_order_scope_resource(p_scope text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_scope in ('order_list', 'order_export', 'order_detail', 'order_open', 'dashboard')
      then 'tms.order'
    when p_scope in (
      'pending_waybill_list', 'pending_waybill_export',
      'loaded_waybill_list', 'loaded_waybill_export',
      'waybill_list', 'waybill_export',
      'delivery_list', 'delivery_export', 'in_transit'
    ) then 'tms.waybill'
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
    when 'order_list' then
      app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:View', null, false)
    when 'order_export' then
      app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:Export', null, false)
    when 'order_detail' then
      app_private.can_execute_business_action('TmsOrderList', 'TmsOrderList:View', null, false)
    when 'order_open' then app_private.can_access_business_menu('TmsOrderOpen')
    when 'pending_waybill_list' then
      app_private.can_execute_business_action(
        'TmsPendingWaybillList', 'TmsPendingWaybillList:View', null, false
      )
    when 'pending_waybill_export' then
      app_private.can_execute_business_action(
        'TmsPendingWaybillList', 'TmsPendingWaybillList:Export', null, false
      )
    when 'loaded_waybill_list' then
      app_private.can_execute_business_action(
        'TmsLoadedWaybillList', 'TmsLoadedWaybillList:View', null, false
      )
    when 'loaded_waybill_export' then
      app_private.can_execute_business_action(
        'TmsLoadedWaybillList', 'TmsLoadedWaybillList:Export', null, false
      )
    -- Compatibility for already-open clients: the old ambiguous scopes are safe only
    -- when the caller owns both page grants.
    when 'waybill_list' then
      app_private.can_execute_business_action(
        'TmsPendingWaybillList', 'TmsPendingWaybillList:View', null, false
      )
      and app_private.can_execute_business_action(
        'TmsLoadedWaybillList', 'TmsLoadedWaybillList:View', null, false
      )
    when 'waybill_export' then
      app_private.can_execute_business_action(
        'TmsPendingWaybillList', 'TmsPendingWaybillList:Export', null, false
      )
      and app_private.can_execute_business_action(
        'TmsLoadedWaybillList', 'TmsLoadedWaybillList:Export', null, false
      )
    when 'delivery_list' then
      app_private.can_execute_business_action(
        'TmsDeliveryManagement', 'TmsDeliveryManagement:View', null, false
      )
    when 'delivery_export' then
      app_private.can_execute_business_action(
        'TmsDeliveryManagement', 'TmsDeliveryManagement:Export', null, false
      )
    when 'in_transit' then
      app_private.can_execute_business_action(
        'TmsInTransitMonitor', 'TmsInTransitMonitor:View', null, false
      )
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
    case when p_scope in (
      'order_export', 'pending_waybill_export', 'loaded_waybill_export',
      'waybill_export', 'delivery_export', 'dashboard'
    ) then 10000 else 500 end,
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
        p_scope not in ('pending_waybill_list', 'pending_waybill_export')
        or order_row.dispatch_status = 'pending'
      )
      and (
        p_scope not in ('loaded_waybill_list', 'loaded_waybill_export')
        or order_row.dispatch_status in ('loaded', 'transporting', 'completed')
      )
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
  v_shipper_contact_access text;
  v_shipper_address_access text;
  v_receiver_contact_access text;
  v_receiver_address_access text;
  v_cargo_pricing_access text;
  v_freight_access text;
  v_settlement_access text;
  v_proof_access text;
  v_route_access text;
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

  v_shipper_contact_access := app_private.resolve_field_access(
    'tms.order', 'shipperContact', v_old.created_by_user_id
  );
  v_shipper_address_access := app_private.resolve_field_access(
    'tms.order', 'shipperAddress', v_old.created_by_user_id
  );
  v_receiver_contact_access := app_private.resolve_field_access(
    'tms.order', 'receiverContact', v_old.created_by_user_id
  );
  v_receiver_address_access := app_private.resolve_field_access(
    'tms.order', 'receiverAddress', v_old.created_by_user_id
  );
  v_cargo_pricing_access := app_private.resolve_field_access(
    'tms.order', 'cargoPricing', v_old.created_by_user_id
  );
  v_freight_access := app_private.resolve_field_access(
    'tms.order', 'freightAmounts', v_old.created_by_user_id
  );
  v_settlement_access := app_private.resolve_field_access(
    'tms.order', 'settlementAmounts', v_old.created_by_user_id
  );
  v_proof_access := app_private.resolve_field_access(
    'tms.order', 'proofAttachments', v_old.created_by_user_id
  );
  v_route_access := app_private.resolve_field_access(
    'tms.order', 'routeCoordinates', v_old.created_by_user_id
  );

  if v_shipper_contact_access <> 'edit' and (
    v_candidate.shipping_contact_phone is distinct from v_old.shipping_contact_phone
    or v_candidate.shipping_customer_id is distinct from v_old.shipping_customer_id
  ) then
    raise exception 'Missing shipper contact field edit permission' using errcode = '42501';
  end if;
  if v_shipper_address_access <> 'edit' and (
    v_candidate.shipping_address_detail is distinct from v_old.shipping_address_detail
    or v_candidate.shipping_address_id is distinct from v_old.shipping_address_id
    or v_candidate.shipping_customer_id is distinct from v_old.shipping_customer_id
  ) then
    raise exception 'Missing shipper address field edit permission' using errcode = '42501';
  end if;
  if v_receiver_contact_access <> 'edit' and (
    v_candidate.receiving_contact_phone is distinct from v_old.receiving_contact_phone
    or v_candidate.receiving_customer_id is distinct from v_old.receiving_customer_id
  ) then
    raise exception 'Missing receiver contact field edit permission' using errcode = '42501';
  end if;
  if v_receiver_address_access <> 'edit' and (
    v_candidate.receiving_address_detail is distinct from v_old.receiving_address_detail
    or v_candidate.receiving_address_id is distinct from v_old.receiving_address_id
    or v_candidate.receiving_customer_id is distinct from v_old.receiving_customer_id
  ) then
    raise exception 'Missing receiver address field edit permission' using errcode = '42501';
  end if;

  if v_cargo_pricing_access <> 'edit' then
    v_candidate.cargo_items := app_private.merge_tms_order_cargo_pricing(
      v_candidate.cargo_items, v_old.cargo_items
    );
  end if;

  if v_freight_access <> 'edit' and (
    v_candidate.transport_fee is distinct from v_old.transport_fee
    or v_candidate.delivery_fee is distinct from v_old.delivery_fee
    or v_candidate.unloading_fee is distinct from v_old.unloading_fee
    or v_candidate.collect_payment_fee is distinct from v_old.collect_payment_fee
    or v_candidate.transfer_fee is distinct from v_old.transfer_fee
    or v_candidate.insurance_fee is distinct from v_old.insurance_fee
    or v_candidate.package_fee is distinct from v_old.package_fee
    or v_candidate.other_fee is distinct from v_old.other_fee
    or v_candidate.total_fee is distinct from v_old.total_fee
  ) then
    raise exception 'Missing freight amount field edit permission' using errcode = '42501';
  end if;

  if v_settlement_access <> 'edit' and (
    v_candidate.declared_value is distinct from v_old.declared_value
    or v_candidate.cash_amount is distinct from v_old.cash_amount
    or v_candidate.collect_amount is distinct from v_old.collect_amount
    or v_candidate.monthly_amount is distinct from v_old.monthly_amount
    or v_candidate.cod_amount is distinct from v_old.cod_amount
    or v_candidate.handling_fee is distinct from v_old.handling_fee
    or v_candidate.payment_total is distinct from v_old.payment_total
  ) then
    raise exception 'Missing settlement amount field edit permission' using errcode = '42501';
  end if;

  if v_proof_access <> 'edit'
     and v_candidate.image_urls is distinct from v_old.image_urls then
    raise exception 'Missing proof attachment field edit permission' using errcode = '42501';
  end if;

  if v_route_access <> 'edit' and (
    v_candidate.shipping_longitude is distinct from v_old.shipping_longitude
    or v_candidate.shipping_latitude is distinct from v_old.shipping_latitude
    or v_candidate.receiving_longitude is distinct from v_old.receiving_longitude
    or v_candidate.receiving_latitude is distinct from v_old.receiving_latitude
  ) then
    raise exception 'Missing route coordinate field edit permission' using errcode = '42501';
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

revoke all on function app_private.tms_order_scope_resource(text) from public, anon, authenticated;
revoke all on function app_private.can_read_tms_order_scope(text) from public, anon, authenticated;

revoke all on function public.tms_list_orders_secure(
  text, integer, integer, uuid, uuid[], text, text[], text, uuid, uuid, uuid,
  text, text[], uuid, text, text, text, text, text, timestamptz, timestamptz,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean
) from public, anon;
revoke all on function public.tms_update_order_secure(uuid, jsonb, text) from public, anon;

grant execute on function public.tms_list_orders_secure(
  text, integer, integer, uuid, uuid[], text, text[], text, uuid, uuid, uuid,
  text, text[], uuid, text, text, text, text, text, timestamptz, timestamptz,
  timestamptz, timestamptz, timestamptz, timestamptz, boolean
) to authenticated, service_role;
grant execute on function public.tms_update_order_secure(uuid, jsonb, text)
  to authenticated, service_role;

;
