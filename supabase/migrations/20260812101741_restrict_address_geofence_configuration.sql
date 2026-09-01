create or replace function app_private.guard_tms_address_geofence_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app_private
as $$
begin
  if (
    new.geofence_enabled is distinct from old.geofence_enabled
    or new.geofence_radius_m is distinct from old.geofence_radius_m
    or new.geofence_updated_at is distinct from old.geofence_updated_at
  ) and not app_private.is_platform_super()
  then
    raise exception 'Only a platform super administrator can change address geofence settings.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_tms_address_geofence_update() from public;

create trigger tms_customer_address_guard_geofence_update
before update of geofence_enabled, geofence_radius_m, geofence_updated_at
on public.tms_customer_address
for each row execute function app_private.guard_tms_address_geofence_update();;
