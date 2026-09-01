
-- Route acceptance through a locked RPC and prevent driver-side lifecycle bypasses.

create or replace function public.tms_accept_assigned_waybill(p_waybill_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operator_value text;
  is_driver boolean;
  is_manager boolean;
begin
  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('accept')
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权接收该运单' using errcode = '42501';
  end if;
  if waybill_record.status = 'accepted' then
    return public.tms_get_waybill_execution_context(p_waybill_id);
  end if;
  if waybill_record.status <> 'pending' then
    raise exception '仅待接单运单可以确认接单' using errcode = '23514';
  end if;

  operator_value := app_private.tms_current_operator_name();
  update public.tms_waybill
  set status = 'accepted', accepted_at = coalesce(accepted_at, now())
  where id = waybill_record.id
  returning * into waybill_record;

  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, payload
  ) values (
    waybill_record.tenant_id, waybill_record.id, 'accepted',
    waybill_record.accepted_at, operator_value,
    concat_ws(' - ', waybill_record.origin_city, waybill_record.destination_city),
    jsonb_build_object(
      'action', 'accept',
      'source', case when is_driver then 'driver' else 'web' end
    )
  );

  return public.tms_get_waybill_execution_context(p_waybill_id);
end;
$$;

revoke all on function public.tms_accept_assigned_waybill(uuid) from public, anon;
grant execute on function public.tms_accept_assigned_waybill(uuid) to authenticated;

create or replace function public.trg_guard_tms_waybill_driver_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select app_private.can_manage_tms()) then
    return new;
  end if;

  if old.driver_id is distinct from (select app_private.current_user_driver_id()) then
    raise exception '司机只能维护分配给自己的运单';
  end if;

  if new.status is distinct from old.status
     or new.accepted_at is distinct from old.accepted_at
     or new.loaded_at is distinct from old.loaded_at
     or new.departed_at is distinct from old.departed_at
     or new.arrived_at is distinct from old.arrived_at
     or new.unloaded_at is distinct from old.unloaded_at
     or new.completed_at is distinct from old.completed_at
     or new.cancelled_at is distinct from old.cancelled_at then
    raise exception '司机必须通过受控作业接口变更运单状态';
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.order_id is distinct from old.order_id
     or new.waybill_no is distinct from old.waybill_no
     or new.carrier_id is distinct from old.carrier_id
     or new.driver_id is distinct from old.driver_id
     or new.vehicle_id is distinct from old.vehicle_id
     or new.cargo_id is distinct from old.cargo_id
     or new.shipper_address_id is distinct from old.shipper_address_id
     or new.receiver_address_id is distinct from old.receiver_address_id
     or new.origin_city is distinct from old.origin_city
     or new.destination_city is distinct from old.destination_city
     or new.shipper_name is distinct from old.shipper_name
     or new.shipper_phone is distinct from old.shipper_phone
     or new.shipper_address is distinct from old.shipper_address
     or new.receiver_name is distinct from old.receiver_name
     or new.receiver_phone is distinct from old.receiver_phone
     or new.receiver_address is distinct from old.receiver_address
     or new.planned_load_time is distinct from old.planned_load_time
     or new.planned_unload_time is distinct from old.planned_unload_time
     or new.cargo_name is distinct from old.cargo_name
     or new.cargo_type is distinct from old.cargo_type
     or new.cargo_weight_ton is distinct from old.cargo_weight_ton
     or new.cargo_volume_m3 is distinct from old.cargo_volume_m3
     or new.cargo_quantity is distinct from old.cargo_quantity
     or new.freight_amount is distinct from old.freight_amount then
    raise exception '司机无权修改运单主数据或计费字段';
  end if;

  return new;
end;
$$;

;
