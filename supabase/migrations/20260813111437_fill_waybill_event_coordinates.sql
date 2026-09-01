create or replace function app_private.tms_fill_waybill_event_coordinate()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_longitude numeric;
  v_latitude numeric;
  v_coordinate_source text;
begin
  if new.event_type not in (
    'accepted',
    'loading_checked_in',
    'loaded',
    'departed',
    'arrived',
    'unloaded',
    'signed',
    'completed'
  ) then
    return new;
  end if;

  if new.longitude is not null
    and new.latitude is not null
    and new.longitude between -180 and 180
    and new.latitude between -90 and 90
    and not (new.longitude = 0 and new.latitude = 0)
  then
    return new;
  end if;

  if new.event_type in ('loading_checked_in', 'loaded', 'departed') then
    select operation.longitude, operation.latitude
      into v_longitude, v_latitude
    from public.tms_waybill_cargo_operation as operation
    where operation.waybill_id = new.waybill_id
      and operation.operation_type = 'loading'
      and operation.longitude is not null
      and operation.latitude is not null
      and not (operation.longitude = 0 and operation.latitude = 0)
    order by operation.checkin_time desc
    limit 1;

    if v_longitude is not null and v_latitude is not null then
      v_coordinate_source := 'loading_operation';
    end if;
  elsif new.event_type in ('arrived', 'unloaded', 'signed', 'completed') then
    select operation.longitude, operation.latitude
      into v_longitude, v_latitude
    from public.tms_waybill_cargo_operation as operation
    where operation.waybill_id = new.waybill_id
      and operation.operation_type = 'unloading'
      and operation.longitude is not null
      and operation.latitude is not null
      and not (operation.longitude = 0 and operation.latitude = 0)
    order by operation.checkin_time desc
    limit 1;

    if v_longitude is not null and v_latitude is not null then
      v_coordinate_source := 'unloading_operation';
    end if;
  end if;

  if v_longitude is null or v_latitude is null then
    select
      case
        when new.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
          then waybill.shipper_longitude
        else waybill.receiver_longitude
      end,
      case
        when new.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
          then waybill.shipper_latitude
        else waybill.receiver_latitude
      end,
      case
        when new.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
          then 'shipper_address'
        else 'receiver_address'
      end
      into v_longitude, v_latitude, v_coordinate_source
    from public.tms_waybill as waybill
    where waybill.id = new.waybill_id;
  end if;

  if v_longitude is null
    or v_latitude is null
    or v_longitude not between -180 and 180
    or v_latitude not between -90 and 90
    or (v_longitude = 0 and v_latitude = 0)
  then
    return new;
  end if;

  new.longitude := v_longitude;
  new.latitude := v_latitude;
  new.payload := coalesce(new.payload, '{}'::jsonb) || jsonb_build_object(
    'coordinateDerived', true,
    'coordinateSource', v_coordinate_source
  );
  return new;
end;
$$;

revoke all on function app_private.tms_fill_waybill_event_coordinate() from public;
revoke all on function app_private.tms_fill_waybill_event_coordinate() from anon;
revoke all on function app_private.tms_fill_waybill_event_coordinate() from authenticated;

drop trigger if exists tms_fill_waybill_event_coordinate on public.tms_waybill_event;

create trigger tms_fill_waybill_event_coordinate
before insert on public.tms_waybill_event
for each row
execute function app_private.tms_fill_waybill_event_coordinate();

with operation_coordinates as (
  select distinct on (operation.waybill_id, operation.operation_type)
    operation.waybill_id,
    operation.operation_type,
    operation.longitude,
    operation.latitude
  from public.tms_waybill_cargo_operation as operation
  where operation.longitude is not null
    and operation.latitude is not null
    and operation.longitude between -180 and 180
    and operation.latitude between -90 and 90
    and not (operation.longitude = 0 and operation.latitude = 0)
  order by operation.waybill_id, operation.operation_type, operation.checkin_time desc
), resolved_coordinates as (
  select
    event.id,
    coalesce(
      case
        when event.event_type in ('loading_checked_in', 'loaded', 'departed')
          then loading.longitude
        when event.event_type in ('arrived', 'unloaded', 'signed', 'completed')
          then unloading.longitude
      end,
      case
        when event.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
          then waybill.shipper_longitude
        else waybill.receiver_longitude
      end
    ) as longitude,
    coalesce(
      case
        when event.event_type in ('loading_checked_in', 'loaded', 'departed')
          then loading.latitude
        when event.event_type in ('arrived', 'unloaded', 'signed', 'completed')
          then unloading.latitude
      end,
      case
        when event.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
          then waybill.shipper_latitude
        else waybill.receiver_latitude
      end
    ) as latitude,
    case
      when event.event_type in ('loading_checked_in', 'loaded', 'departed')
        and loading.longitude is not null then 'loading_operation'
      when event.event_type in ('arrived', 'unloaded', 'signed', 'completed')
        and unloading.longitude is not null then 'unloading_operation'
      when event.event_type in ('accepted', 'loading_checked_in', 'loaded', 'departed')
        then 'shipper_address'
      else 'receiver_address'
    end as coordinate_source
  from public.tms_waybill_event as event
  join public.tms_waybill as waybill on waybill.id = event.waybill_id
  left join operation_coordinates as loading
    on loading.waybill_id = event.waybill_id
    and loading.operation_type = 'loading'
  left join operation_coordinates as unloading
    on unloading.waybill_id = event.waybill_id
    and unloading.operation_type = 'unloading'
  where event.event_type in (
      'accepted',
      'loading_checked_in',
      'loaded',
      'departed',
      'arrived',
      'unloaded',
      'signed',
      'completed'
    )
    and (
      event.longitude is null
      or event.latitude is null
      or (event.longitude = 0 and event.latitude = 0)
    )
)
update public.tms_waybill_event as event
set
  longitude = resolved.longitude,
  latitude = resolved.latitude,
  payload = event.payload || jsonb_build_object(
    'coordinateDerived', true,
    'coordinateSource', resolved.coordinate_source
  ),
  update_time = now()
from resolved_coordinates as resolved
where event.id = resolved.id
  and resolved.longitude is not null
  and resolved.latitude is not null
  and resolved.longitude between -180 and 180
  and resolved.latitude between -90 and 90
  and not (resolved.longitude = 0 and resolved.latitude = 0);

;
