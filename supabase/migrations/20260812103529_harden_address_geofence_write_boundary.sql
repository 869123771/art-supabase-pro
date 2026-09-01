create or replace function app_private.guard_tms_address_geofence_write()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app_private
as $$
begin
  if app_private.is_platform_super() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if (
      coalesce(new.geofence_enabled, false)
      or new.geofence_radius_m is not null
      or new.geofence_updated_at is not null
    ) then
      raise exception 'Only a platform super administrator can configure an address geofence.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if (
    new.geofence_enabled is distinct from old.geofence_enabled
    or new.geofence_radius_m is distinct from old.geofence_radius_m
    or new.geofence_updated_at is distinct from old.geofence_updated_at
  ) then
    raise exception 'Only a platform super administrator can change address geofence settings.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function app_private.guard_tms_address_geofence_write() from public;
drop trigger if exists tms_customer_address_guard_geofence_update on public.tms_customer_address;
create trigger tms_customer_address_guard_geofence_write
before insert or update of geofence_enabled, geofence_radius_m, geofence_updated_at
on public.tms_customer_address
for each row execute function app_private.guard_tms_address_geofence_write();

with basic_data as (
  select id from public.sys_menu where name = 'TmsBasicData' limit 1
)
update public.sys_menu child
set sort = child.sort + 1
from basic_data
where child.parent_id = basic_data.id
  and child.name <> 'TmsFavoriteRoute'
  and child.sort >= 3;

with basic_data as (
  select id from public.sys_menu where name = 'TmsBasicData' limit 1
)
update public.sys_menu child
set sort = 3
from basic_data
where child.parent_id = basic_data.id
  and child.name = 'TmsFavoriteRoute';;
