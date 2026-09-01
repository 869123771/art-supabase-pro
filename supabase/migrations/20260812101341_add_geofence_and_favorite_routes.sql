-- Electronic geofence defaults, address-level fence settings, and tenant favorite routes.

alter table public.tms_customer_address
  add column geofence_enabled boolean not null default false,
  add column geofence_radius_m integer,
  add column geofence_updated_at timestamptz;

alter table public.tms_customer_address
  add constraint tms_customer_address_geofence_radius_check
    check (geofence_radius_m is null or geofence_radius_m between 50 and 50000),
  add constraint tms_customer_address_geofence_ready_check
    check (
      not geofence_enabled
      or (
        longitude is not null
        and latitude is not null
        and geofence_radius_m is not null
      )
    );

comment on column public.tms_customer_address.geofence_enabled is
  'Whether arrival/departure checks should use the address geofence.';
comment on column public.tms_customer_address.geofence_radius_m is
  'Circular geofence radius in metres; the address longitude/latitude is the center.';
comment on column public.tms_customer_address.geofence_updated_at is
  'Last business time at which the address geofence was configured.';

create table public.tms_favorite_route (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  route_name text not null,
  customer_id uuid not null references public.tms_customer(id) on delete restrict,
  origin_address_id uuid not null
    references public.tms_customer_address(id) on delete restrict,
  destination_address_id uuid not null
    references public.tms_customer_address(id) on delete restrict,
  distance_km numeric(10, 2),
  estimated_minutes integer,
  enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_favorite_route_name_not_blank check (btrim(route_name) <> ''),
  constraint tms_favorite_route_distinct_addresses_check
    check (origin_address_id <> destination_address_id),
  constraint tms_favorite_route_distance_check
    check (distance_km is null or distance_km > 0),
  constraint tms_favorite_route_duration_check
    check (estimated_minutes is null or estimated_minutes > 0)
);

comment on table public.tms_favorite_route is
  'Tenant favorite transport routes that reference reusable customer shipping and receiving addresses.';

create unique index tms_favorite_route_tenant_name_uidx
  on public.tms_favorite_route (tenant_id, lower(route_name));
create index tms_favorite_route_tenant_enabled_idx
  on public.tms_favorite_route (tenant_id, enabled, update_time desc);
create index tms_favorite_route_customer_idx
  on public.tms_favorite_route (customer_id);
create index tms_favorite_route_origin_address_idx
  on public.tms_favorite_route (origin_address_id);
create index tms_favorite_route_destination_address_idx
  on public.tms_favorite_route (destination_address_id);

create or replace function app_private.validate_tms_favorite_route_refs()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  customer_tenant_id uuid;
  origin_record record;
  destination_record record;
begin
  select customer.tenant_id
    into customer_tenant_id
  from public.tms_customer customer
  where customer.id = new.customer_id;

  select address.tenant_id, address.customer_id, address.address_type
    into origin_record
  from public.tms_customer_address address
  where address.id = new.origin_address_id;

  select address.tenant_id, address.customer_id, address.address_type
    into destination_record
  from public.tms_customer_address address
  where address.id = new.destination_address_id;

  if customer_tenant_id is null
    or customer_tenant_id <> new.tenant_id
    or origin_record.tenant_id is null
    or origin_record.tenant_id <> new.tenant_id
    or origin_record.customer_id is distinct from new.customer_id
    or origin_record.address_type <> 'shipping'
    or destination_record.tenant_id is null
    or destination_record.tenant_id <> new.tenant_id
    or destination_record.customer_id is distinct from new.customer_id
    or destination_record.address_type <> 'receiving'
  then
    raise exception 'Favorite route customer and addresses must belong to the same tenant and use shipping/receiving endpoints.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function app_private.validate_tms_favorite_route_refs() from public;

create trigger tms_favorite_route_validate_refs
before insert or update of tenant_id, customer_id, origin_address_id, destination_address_id
on public.tms_favorite_route
for each row execute function app_private.validate_tms_favorite_route_refs();

create trigger tms_favorite_route_create_audit
before insert on public.tms_favorite_route
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger tms_favorite_route_update_audit
before update on public.tms_favorite_route
for each row execute function public.trg_set_update_time_and_by();

alter table public.tms_favorite_route enable row level security;

create policy tenant_select on public.tms_favorite_route
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

create policy tenant_insert on public.tms_favorite_route
for insert to authenticated
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

create policy tenant_update on public.tms_favorite_route
for update to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

create policy tenant_delete on public.tms_favorite_route
for delete to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

grant select, insert, update, delete on public.tms_favorite_route to authenticated;
grant all on public.tms_favorite_route to service_role;

insert into public.sys_param (
  tenant_id,
  param_name,
  param_key,
  group_code,
  group_name,
  param_type,
  default_value,
  param_value,
  extend_config,
  enabled,
  builtin,
  sort,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  '电子围栏配置',
  'tms.geofence.config',
  'tms',
  '运输管理',
  'json',
  '{"enabled":true,"loadingRadiusM":1000,"unloadingRadiusM":1000,"allowOutsideCheckIn":false,"autoConfirmLoading":false,"autoConfirmDelivery":false}',
  '{"enabled":true,"loadingRadiusM":1000,"unloadingRadiusM":1000,"allowOutsideCheckIn":false,"autoConfirmLoading":false,"autoConfirmDelivery":false}',
  '{"schemaVersion":1,"radiusMinM":50,"radiusMaxM":50000}',
  true,
  true,
  32,
  '统一维护装货与卸货地址的默认围栏半径、围栏外打卡和自动确认策略。',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_tenant tenant
where tenant.tenant_code = 'platform'
on conflict (tenant_id, param_key) do update
set
  param_name = excluded.param_name,
  group_code = excluded.group_code,
  group_name = excluded.group_name,
  param_type = excluded.param_type,
  default_value = excluded.default_value,
  extend_config = excluded.extend_config,
  enabled = true,
  builtin = true,
  sort = excluded.sort,
  remark = excluded.remark,
  update_by = excluded.update_by,
  update_time = now();

with system_parent as (
  select id
  from public.sys_menu
  where path = '/system' and type = 'folder'
  limit 1
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  gen_random_uuid(),
  system_parent.id,
  'GeofenceConfig',
  'geofence-config',
  '/system/geofence-config',
  '{"icon":"ri:radar-line","roles":[],"title":"电子围栏配置","authList":[{"title":"编辑","authMark":"edit"}],"is_enable":true,"keep_alive":true}'::jsonb,
  12,
  'menu',
  '624944977@qq.com',
  '624944977@qq.com'
from system_parent
where not exists (
  select 1 from public.sys_menu where name = 'GeofenceConfig'
);

with basic_parent as (
  select id
  from public.sys_menu
  where name = 'TmsBasicData' and type = 'folder'
  limit 1
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  gen_random_uuid(),
  basic_parent.id,
  'TmsFavoriteRoute',
  'favorite-route',
  '/tms-transportation/basic-data/favorite-route',
  '{"icon":"ri:route-line","roles":[],"title":"常用线路","is_enable":true,"keep_alive":true}'::jsonb,
  3,
  'menu',
  '624944977@qq.com',
  '624944977@qq.com'
from basic_parent
where not exists (
  select 1 from public.sys_menu where name = 'TmsFavoriteRoute'
);

insert into public.sys_role_menu (
  id, role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  gen_random_uuid(),
  role.id,
  menu.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  role.tenant_id
from public.sys_role role
join public.sys_role_menu parent_grant on parent_grant.role_id = role.id
join public.sys_menu menu on menu.name = 'GeofenceConfig'
where role.enabled
  and parent_grant.menu_id = menu.parent_id
on conflict (role_id, menu_id) do nothing;

insert into public.sys_role_menu (
  id, role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  gen_random_uuid(),
  role.id,
  menu.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  role.tenant_id
from public.sys_role role
join public.sys_role_menu parent_grant on parent_grant.role_id = role.id
join public.sys_menu menu on menu.name = 'TmsFavoriteRoute'
where role.enabled
  and parent_grant.menu_id = menu.parent_id
on conflict (role_id, menu_id) do nothing;

;
