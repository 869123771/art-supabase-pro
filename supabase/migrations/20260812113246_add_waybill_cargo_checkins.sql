-- Loading and unloading check-ins, evidence, geofence policy, and RBAC boundaries.

create table public.tms_waybill_cargo_operation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  waybill_id uuid not null references public.tms_waybill(id) on delete cascade,
  operation_type text not null,
  operation_status text not null default 'checked_in',
  checkin_time timestamptz not null default now(),
  checkin_mode text not null,
  operator_name text,
  longitude numeric(10, 7) not null,
  latitude numeric(10, 7) not null,
  location_accuracy_m numeric(10, 2),
  location_text text,
  geofence_center_longitude numeric(10, 7) not null,
  geofence_center_latitude numeric(10, 7) not null,
  geofence_radius_m integer not null,
  distance_m numeric(12, 2) not null,
  inside_geofence boolean not null,
  outside_reason text,
  weight_ton numeric(12, 3),
  photo_urls jsonb not null default '[]'::jsonb,
  weighbridge_ticket_urls jsonb not null default '[]'::jsonb,
  completed_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint tms_waybill_cargo_operation_type_check
    check (operation_type in ('loading', 'unloading')),
  constraint tms_waybill_cargo_operation_status_check
    check (operation_status in ('checked_in', 'completed')),
  constraint tms_waybill_cargo_operation_checkin_mode_check
    check (checkin_mode in ('manual', 'automatic', 'admin')),
  constraint tms_waybill_cargo_operation_coordinates_check
    check (
      longitude between -180 and 180
      and latitude between -90 and 90
      and geofence_center_longitude between -180 and 180
      and geofence_center_latitude between -90 and 90
    ),
  constraint tms_waybill_cargo_operation_radius_check
    check (geofence_radius_m between 50 and 50000),
  constraint tms_waybill_cargo_operation_distance_check
    check (distance_m >= 0),
  constraint tms_waybill_cargo_operation_accuracy_check
    check (location_accuracy_m is null or location_accuracy_m >= 0),
  constraint tms_waybill_cargo_operation_weight_check
    check (weight_ton is null or weight_ton > 0),
  constraint tms_waybill_cargo_operation_photo_urls_check
    check (jsonb_typeof(photo_urls) = 'array'),
  constraint tms_waybill_cargo_operation_ticket_urls_check
    check (jsonb_typeof(weighbridge_ticket_urls) = 'array'),
  constraint tms_waybill_cargo_operation_outside_reason_check
    check (inside_geofence or nullif(btrim(outside_reason), '') is not null),
  constraint tms_waybill_cargo_operation_completion_check
    check (
      operation_status <> 'completed'
      or (
        completed_at is not null
        and weight_ton is not null
        and jsonb_array_length(photo_urls) > 0
        and jsonb_array_length(weighbridge_ticket_urls) > 0
      )
    )
);

comment on table public.tms_waybill_cargo_operation is
  'Auditable loading/unloading check-in and evidence for one assigned waybill.';
comment on column public.tms_waybill_cargo_operation.checkin_mode is
  'manual: driver action, automatic: geofence entry, admin: authorised PC operation.';
comment on column public.tms_waybill_cargo_operation.operation_status is
  'checked_in locks server time/location; completed means weight, photo, and weighbridge ticket are present.';

create unique index tms_waybill_cargo_operation_waybill_type_uidx
  on public.tms_waybill_cargo_operation (waybill_id, operation_type);
create index tms_waybill_cargo_operation_tenant_time_idx
  on public.tms_waybill_cargo_operation (tenant_id, checkin_time desc);
create index tms_waybill_cargo_operation_waybill_status_idx
  on public.tms_waybill_cargo_operation (waybill_id, operation_status);

create trigger tms_waybill_cargo_operation_create_audit
before insert on public.tms_waybill_cargo_operation
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger tms_waybill_cargo_operation_update_audit
before update on public.tms_waybill_cargo_operation
for each row execute function public.trg_set_update_time_and_by();

create or replace function app_private.tms_distance_m(
  p_from_longitude numeric,
  p_from_latitude numeric,
  p_to_longitude numeric,
  p_to_latitude numeric
)
returns numeric
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select round((
    6371000 * 2 * asin(sqrt(
      power(sin(radians((p_to_latitude - p_from_latitude)::double precision) / 2), 2)
      + cos(radians(p_from_latitude::double precision))
        * cos(radians(p_to_latitude::double precision))
        * power(sin(radians((p_to_longitude - p_from_longitude)::double precision) / 2), 2)
    ))
  )::numeric, 2);
$$;

revoke all on function app_private.tms_distance_m(numeric, numeric, numeric, numeric)
  from public;

create or replace function app_private.tms_cargo_operation_policy()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  raw_value text;
  parsed jsonb;
begin
  select param.param_value
    into raw_value
  from public.sys_param param
  where param.param_key = 'tms.geofence.config'
    and param.enabled
    and param.tenant_id = app_private.platform_tenant_id()
  order by param.update_time desc
  limit 1;

  begin
    parsed := coalesce(raw_value, '{}')::jsonb;
  exception when others then
    parsed := '{}'::jsonb;
  end;

  return jsonb_build_object(
    'enabled', coalesce((parsed ->> 'enabled')::boolean, true),
    'loadingRadiusM', coalesce((parsed ->> 'loadingRadiusM')::integer, 1000),
    'unloadingRadiusM', coalesce((parsed ->> 'unloadingRadiusM')::integer, 1000),
    'loadingAllowOutsideCheckIn', coalesce(
      (parsed ->> 'loadingAllowOutsideCheckIn')::boolean,
      (parsed ->> 'allowOutsideCheckIn')::boolean,
      false
    ),
    'unloadingAllowOutsideCheckIn', coalesce(
      (parsed ->> 'unloadingAllowOutsideCheckIn')::boolean,
      (parsed ->> 'allowOutsideCheckIn')::boolean,
      false
    ),
    'autoConfirmLoading', coalesce((parsed ->> 'autoConfirmLoading')::boolean, false),
    'autoConfirmUnloading', coalesce(
      (parsed ->> 'autoConfirmUnloading')::boolean,
      (parsed ->> 'autoConfirmDelivery')::boolean,
      false
    )
  );
end;
$$;

revoke all on function app_private.tms_cargo_operation_policy() from public;

create or replace function app_private.can_manage_waybill_cargo_operation(
  p_operation_type text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private
as $$
  select app_private.is_platform_super()
    or app_private.has_permission(
      case p_operation_type
        when 'loading' then 'TmsWaybill:Loading'
        when 'unloading' then 'TmsWaybill:Unloading'
        else ''
      end
    );
$$;

revoke all on function app_private.can_manage_waybill_cargo_operation(text) from public;

create or replace function app_private.can_access_waybill_cargo_operation(
  p_waybill_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private
as $$
  select app_private.can_access_assigned_waybill(p_waybill_id)
    or (
      app_private.can_manage_tms()
      and exists (
        select 1
        from public.tms_waybill waybill
        where waybill.id = p_waybill_id
          and (
            app_private.is_platform_super()
            or waybill.tenant_id = app_private.current_user_tenant_id()
          )
      )
    );
$$;

revoke all on function app_private.can_access_waybill_cargo_operation(uuid) from public;

alter table public.tms_waybill_cargo_operation enable row level security;

create policy tms_waybill_cargo_operation_select
on public.tms_waybill_cargo_operation
for select to authenticated
using (
  app_private.can_access_waybill_cargo_operation(waybill_id)
);

grant select on public.tms_waybill_cargo_operation to authenticated;
grant all on public.tms_waybill_cargo_operation to service_role;

create or replace function public.tms_get_waybill_cargo_operation_context(
  p_waybill_id uuid,
  p_operation_type text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  policy_value jsonb;
  center_longitude numeric;
  center_latitude numeric;
  radius_value integer;
  allow_outside boolean;
  auto_checkin boolean;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id;

  if not found or not app_private.can_access_waybill_cargo_operation(p_waybill_id) then
    raise exception '无权查看该运单的装卸货信息' using errcode = '42501';
  end if;

  select * into operation_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id
    and operation_type = p_operation_type;

  policy_value := app_private.tms_cargo_operation_policy();
  if p_operation_type = 'loading' then
    center_longitude := waybill_record.shipper_longitude;
    center_latitude := waybill_record.shipper_latitude;
    radius_value := (policy_value ->> 'loadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'loadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmLoading')::boolean;
  else
    center_longitude := waybill_record.receiver_longitude;
    center_latitude := waybill_record.receiver_latitude;
    radius_value := (policy_value ->> 'unloadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'unloadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmUnloading')::boolean;
  end if;

  return jsonb_build_object(
    'waybillId', waybill_record.id,
    'operationType', p_operation_type,
    'waybillStatus', waybill_record.status,
    'centerLongitude', center_longitude,
    'centerLatitude', center_latitude,
    'radiusM', radius_value,
    'allowOutsideCheckIn', allow_outside,
    'autoCheckIn', auto_checkin,
    'geofenceEnabled', (policy_value ->> 'enabled')::boolean,
    'canManage', app_private.can_manage_waybill_cargo_operation(p_operation_type),
    'operation', case
      when operation_record.id is null then null
      else jsonb_build_object(
        'id', operation_record.id,
        'tenantId', operation_record.tenant_id,
        'waybillId', operation_record.waybill_id,
        'operationType', operation_record.operation_type,
        'operationStatus', operation_record.operation_status,
        'checkinTime', operation_record.checkin_time,
        'checkinMode', operation_record.checkin_mode,
        'operatorName', operation_record.operator_name,
        'longitude', operation_record.longitude,
        'latitude', operation_record.latitude,
        'locationAccuracyM', operation_record.location_accuracy_m,
        'locationText', operation_record.location_text,
        'geofenceCenterLongitude', operation_record.geofence_center_longitude,
        'geofenceCenterLatitude', operation_record.geofence_center_latitude,
        'geofenceRadiusM', operation_record.geofence_radius_m,
        'distanceM', operation_record.distance_m,
        'insideGeofence', operation_record.inside_geofence,
        'outsideReason', operation_record.outside_reason,
        'weightTon', operation_record.weight_ton,
        'photoUrls', operation_record.photo_urls,
        'weighbridgeTicketUrls', operation_record.weighbridge_ticket_urls,
        'completedAt', operation_record.completed_at,
        'remark', operation_record.remark,
        'createBy', operation_record.create_by,
        'createTime', operation_record.create_time,
        'updateBy', operation_record.update_by,
        'updateTime', operation_record.update_time
      )
    end
  );
end;
$$;

revoke all on function public.tms_get_waybill_cargo_operation_context(uuid, text)
  from public;
grant execute on function public.tms_get_waybill_cargo_operation_context(uuid, text)
  to authenticated;

create or replace function public.tms_check_in_waybill_cargo_operation(
  p_waybill_id uuid,
  p_operation_type text,
  p_longitude numeric,
  p_latitude numeric,
  p_accuracy_m numeric default null,
  p_location_text text default null,
  p_outside_reason text default null,
  p_automatic boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  policy_value jsonb;
  center_longitude numeric;
  center_latitude numeric;
  radius_value integer;
  distance_value numeric;
  inside_value boolean;
  allow_outside boolean;
  auto_checkin boolean;
  is_driver boolean;
  is_manager boolean;
  mode_value text;
  operator_value text;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;
  if p_longitude is null or p_longitude not between -180 and 180
    or p_latitude is null or p_latitude not between -90 and 90 then
    raise exception '定位坐标无效，请重新定位' using errcode = '22023';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;

  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_cargo_operation(p_operation_type)
    and (
      app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id()
    );
  if not is_driver and not is_manager then
    raise exception '无权操作该运单' using errcode = '42501';
  end if;

  if p_operation_type = 'loading'
    and waybill_record.status not in ('accepted', 'loading') then
    raise exception '当前运单状态不支持装货打卡' using errcode = '23514';
  end if;
  if p_operation_type = 'unloading'
    and waybill_record.status not in ('transporting', 'unloading', 'signed') then
    raise exception '当前运单状态不支持卸货打卡' using errcode = '23514';
  end if;

  policy_value := app_private.tms_cargo_operation_policy();
  if p_operation_type = 'loading' then
    center_longitude := waybill_record.shipper_longitude;
    center_latitude := waybill_record.shipper_latitude;
    radius_value := (policy_value ->> 'loadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'loadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmLoading')::boolean;
  else
    center_longitude := waybill_record.receiver_longitude;
    center_latitude := waybill_record.receiver_latitude;
    radius_value := (policy_value ->> 'unloadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'unloadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmUnloading')::boolean;
  end if;

  if center_longitude is null or center_latitude is null then
    raise exception '该运单未配置%坐标，请联系调度维护地址',
      case p_operation_type when 'loading' then '装货地' else '卸货地' end
      using errcode = '23514';
  end if;

  distance_value := app_private.tms_distance_m(
    p_longitude,
    p_latitude,
    center_longitude,
    center_latitude
  );
  inside_value := coalesce((policy_value ->> 'enabled')::boolean, true) is false
    or distance_value <= radius_value;

  if p_automatic and (not auto_checkin or not inside_value) then
    raise exception '当前定位不满足自动打卡条件' using errcode = '23514';
  end if;
  if not p_automatic and not inside_value and not allow_outside then
    raise exception '当前不在%围栏内，请到达现场后重新打卡',
      case p_operation_type when 'loading' then '装货地' else '卸货地' end
      using errcode = '23514';
  end if;
  if not inside_value and nullif(btrim(p_outside_reason), '') is null then
    raise exception '围栏外打卡必须填写原因' using errcode = '23514';
  end if;

  mode_value := case
    when p_automatic then 'automatic'
    when is_driver then 'manual'
    else 'admin'
  end;
  select coalesce(nullif(user_row.nick_name, ''), nullif(user_row.user_name, ''), user_row.user_email)
    into operator_value
  from public.sys_user user_row
  where user_row.auth_user_id = auth.uid()
    and user_row.status = '1'
  limit 1;

  insert into public.tms_waybill_cargo_operation (
    tenant_id,
    waybill_id,
    operation_type,
    operation_status,
    checkin_time,
    checkin_mode,
    operator_name,
    longitude,
    latitude,
    location_accuracy_m,
    location_text,
    geofence_center_longitude,
    geofence_center_latitude,
    geofence_radius_m,
    distance_m,
    inside_geofence,
    outside_reason
  ) values (
    waybill_record.tenant_id,
    waybill_record.id,
    p_operation_type,
    'checked_in',
    now(),
    mode_value,
    operator_value,
    p_longitude,
    p_latitude,
    p_accuracy_m,
    nullif(btrim(p_location_text), ''),
    center_longitude,
    center_latitude,
    radius_value,
    distance_value,
    inside_value,
    nullif(btrim(p_outside_reason), '')
  )
  on conflict (waybill_id, operation_type) do nothing
  returning * into operation_record;

  if operation_record.id is null then
    select * into operation_record
    from public.tms_waybill_cargo_operation
    where waybill_id = p_waybill_id
      and operation_type = p_operation_type;
  else
    insert into public.tms_waybill_event (
      tenant_id,
      waybill_id,
      event_type,
      event_time,
      operator_name,
      location_text,
      longitude,
      latitude,
      payload
    ) values (
      waybill_record.tenant_id,
      waybill_record.id,
      p_operation_type || '_checked_in',
      operation_record.checkin_time,
      operator_value,
      operation_record.location_text,
      p_longitude,
      p_latitude,
      jsonb_build_object(
        'action', p_operation_type || '_checkin',
        'checkinMode', mode_value,
        'insideGeofence', inside_value,
        'distanceM', distance_value,
        'radiusM', radius_value
      )
    );
  end if;

  return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
end;
$$;

revoke all on function public.tms_check_in_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, text, text, boolean
) from public;
grant execute on function public.tms_check_in_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, text, text, boolean
) to authenticated;

create or replace function public.tms_complete_waybill_cargo_operation(
  p_waybill_id uuid,
  p_operation_type text,
  p_weight_ton numeric,
  p_photo_urls jsonb,
  p_weighbridge_ticket_urls jsonb,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  is_driver boolean;
  is_manager boolean;
  operator_value text;
  target_status text;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;
  if p_weight_ton is null or p_weight_ton <= 0 then
    raise exception '%重量必须大于 0 吨',
      case p_operation_type when 'loading' then '装货' else '卸货' end
      using errcode = '23514';
  end if;
  if jsonb_typeof(coalesce(p_photo_urls, 'null'::jsonb)) <> 'array'
    or jsonb_array_length(p_photo_urls) = 0 then
    raise exception '请至少上传 1 张现场照片' using errcode = '23514';
  end if;
  if jsonb_typeof(coalesce(p_weighbridge_ticket_urls, 'null'::jsonb)) <> 'array'
    or jsonb_array_length(p_weighbridge_ticket_urls) = 0 then
    raise exception '请至少上传 1 张磅单' using errcode = '23514';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;

  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;
  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_cargo_operation(p_operation_type)
    and (
      app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id()
    );
  if not is_driver and not is_manager then
    raise exception '无权操作该运单' using errcode = '42501';
  end if;

  select * into operation_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id
    and operation_type = p_operation_type
  for update;

  if not found then
    raise exception '请先完成%打卡',
      case p_operation_type when 'loading' then '装货' else '卸货' end
      using errcode = '23514';
  end if;

  if operation_record.operation_status = 'completed' then
    return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
  end if;

  if p_operation_type = 'loading'
    and waybill_record.status not in ('accepted', 'loading') then
    raise exception '当前运单状态不支持提交装货信息' using errcode = '23514';
  end if;
  if p_operation_type = 'unloading'
    and waybill_record.status not in ('transporting', 'unloading', 'signed') then
    raise exception '当前运单状态不支持提交卸货信息' using errcode = '23514';
  end if;

  update public.tms_waybill_cargo_operation
  set operation_status = 'completed',
      weight_ton = p_weight_ton,
      photo_urls = p_photo_urls,
      weighbridge_ticket_urls = p_weighbridge_ticket_urls,
      completed_at = coalesce(completed_at, now()),
      remark = nullif(btrim(p_remark), '')
  where id = operation_record.id
  returning * into operation_record;

  target_status := case p_operation_type when 'loading' then 'loading' else 'signed' end;
  if p_operation_type = 'loading' and waybill_record.status = 'accepted' then
    update public.tms_waybill
    set status = target_status,
        loaded_at = operation_record.completed_at,
        cargo_weight_ton = p_weight_ton,
        pickup_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb) || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  elsif p_operation_type = 'loading' then
    update public.tms_waybill
    set loaded_at = coalesce(loaded_at, operation_record.completed_at),
        cargo_weight_ton = p_weight_ton,
        pickup_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb) || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  elsif waybill_record.status = 'transporting' then
    update public.tms_waybill set status = 'unloading', arrived_at = operation_record.checkin_time
    where id = waybill_record.id;
    update public.tms_waybill
    set status = target_status,
        unloaded_at = operation_record.completed_at,
        delivery_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb) || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  elsif waybill_record.status = 'unloading' then
    update public.tms_waybill
    set status = target_status,
        unloaded_at = operation_record.completed_at,
        delivery_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb) || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  else
    update public.tms_waybill
    set unloaded_at = coalesce(unloaded_at, operation_record.completed_at),
        delivery_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb) || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  end if;

  select coalesce(nullif(user_row.nick_name, ''), nullif(user_row.user_name, ''), user_row.user_email)
    into operator_value
  from public.sys_user user_row
  where user_row.auth_user_id = auth.uid()
    and user_row.status = '1'
  limit 1;

  insert into public.tms_waybill_event (
    tenant_id,
    waybill_id,
    event_type,
    event_time,
    operator_name,
    location_text,
    longitude,
    latitude,
    payload
  ) values (
    waybill_record.tenant_id,
    waybill_record.id,
    case p_operation_type when 'loading' then 'loaded' else 'unloaded' end,
    operation_record.completed_at,
    operator_value,
    operation_record.location_text,
    operation_record.longitude,
    operation_record.latitude,
    jsonb_build_object(
      'action', 'complete_' || p_operation_type,
      'weightTon', p_weight_ton,
      'photoCount', jsonb_array_length(p_photo_urls),
      'ticketCount', jsonb_array_length(p_weighbridge_ticket_urls),
      'checkinMode', operation_record.checkin_mode,
      'insideGeofence', operation_record.inside_geofence
    )
  );

  return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
end;
$$;

revoke all on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, jsonb, jsonb, text
) from public;
grant execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, jsonb, jsonb, text
) to authenticated;

create or replace function public.tms_save_geofence_config(p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  normalized jsonb;
  param_record public.sys_param%rowtype;
begin
  if not (
    app_private.is_platform_super()
    or app_private.has_permission('System:GeofenceConfig:Edit')
  ) then
    raise exception '无权修改电子围栏配置' using errcode = '42501';
  end if;

  normalized := jsonb_build_object(
    'enabled', coalesce((p_config ->> 'enabled')::boolean, true),
    'loadingRadiusM', coalesce((p_config ->> 'loadingRadiusM')::integer, 1000),
    'unloadingRadiusM', coalesce((p_config ->> 'unloadingRadiusM')::integer, 1000),
    'loadingAllowOutsideCheckIn', coalesce((p_config ->> 'loadingAllowOutsideCheckIn')::boolean, false),
    'unloadingAllowOutsideCheckIn', coalesce((p_config ->> 'unloadingAllowOutsideCheckIn')::boolean, false),
    'autoConfirmLoading', coalesce((p_config ->> 'autoConfirmLoading')::boolean, false),
    'autoConfirmUnloading', coalesce((p_config ->> 'autoConfirmUnloading')::boolean, false)
  );

  if (normalized ->> 'loadingRadiusM')::integer not between 50 and 50000
    or (normalized ->> 'unloadingRadiusM')::integer not between 50 and 50000 then
    raise exception '围栏半径应在 50 至 50000 米之间' using errcode = '23514';
  end if;

  update public.sys_param
  set param_value = normalized::text
  where param_key = 'tms.geofence.config'
    and tenant_id = app_private.platform_tenant_id()
  returning * into param_record;

  if param_record.id is null then
    raise exception '电子围栏系统参数不存在' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'id', param_record.id,
    'tenantId', param_record.tenant_id,
    'enabled', (normalized ->> 'enabled')::boolean,
    'loadingRadiusM', (normalized ->> 'loadingRadiusM')::integer,
    'unloadingRadiusM', (normalized ->> 'unloadingRadiusM')::integer,
    'loadingAllowOutsideCheckIn', (normalized ->> 'loadingAllowOutsideCheckIn')::boolean,
    'unloadingAllowOutsideCheckIn', (normalized ->> 'unloadingAllowOutsideCheckIn')::boolean,
    'autoConfirmLoading', (normalized ->> 'autoConfirmLoading')::boolean,
    'autoConfirmUnloading', (normalized ->> 'autoConfirmUnloading')::boolean,
    'updateBy', param_record.update_by,
    'updateTime', param_record.update_time
  );
end;
$$;

revoke all on function public.tms_save_geofence_config(jsonb) from public;
grant execute on function public.tms_save_geofence_config(jsonb) to authenticated;

update public.sys_param
set default_value = jsonb_build_object(
      'enabled', true,
      'loadingRadiusM', 1000,
      'unloadingRadiusM', 1000,
      'loadingAllowOutsideCheckIn', false,
      'unloadingAllowOutsideCheckIn', false,
      'autoConfirmLoading', false,
      'autoConfirmUnloading', false
    )::text,
    param_value = jsonb_build_object(
      'enabled', coalesce((param_value::jsonb ->> 'enabled')::boolean, true),
      'loadingRadiusM', coalesce((param_value::jsonb ->> 'loadingRadiusM')::integer, 1000),
      'unloadingRadiusM', coalesce((param_value::jsonb ->> 'unloadingRadiusM')::integer, 1000),
      'loadingAllowOutsideCheckIn', coalesce(
        (param_value::jsonb ->> 'loadingAllowOutsideCheckIn')::boolean,
        (param_value::jsonb ->> 'allowOutsideCheckIn')::boolean,
        false
      ),
      'unloadingAllowOutsideCheckIn', coalesce(
        (param_value::jsonb ->> 'unloadingAllowOutsideCheckIn')::boolean,
        (param_value::jsonb ->> 'allowOutsideCheckIn')::boolean,
        false
      ),
      'autoConfirmLoading', coalesce((param_value::jsonb ->> 'autoConfirmLoading')::boolean, false),
      'autoConfirmUnloading', coalesce(
        (param_value::jsonb ->> 'autoConfirmUnloading')::boolean,
        (param_value::jsonb ->> 'autoConfirmDelivery')::boolean,
        false
      )
    )::text,
    extend_config = '{"schemaVersion":2,"radiusMinM":50,"radiusMaxM":50000}'::jsonb,
    remark = '分别维护装货、卸货的打卡范围与自动打卡策略。',
    update_by = '624944977@qq.com'
where param_key = 'tms.geofence.config'
  and tenant_id = app_private.platform_tenant_id();

insert into public.sys_menu (
  parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  parent.id,
  'System:GeofenceConfig:Edit',
  '',
  '',
  '{"title":"编辑电子围栏","authMark":"edit","is_enable":true,"is_auth_button":true}'::jsonb,
  1,
  'button',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_menu parent
where parent.name = 'GeofenceConfig'
  and not exists (
    select 1 from public.sys_menu existing
    where existing.name = 'System:GeofenceConfig:Edit'
  );

insert into public.sys_menu (
  parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  parent.id,
  action.name,
  '',
  '',
  jsonb_build_object(
    'title', action.title,
    'authMark', action.auth_mark,
    'is_enable', true,
    'is_auth_button', true
  ),
  action.sort,
  'button',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_menu parent
cross join (
  values
    ('TmsWaybill:Loading', '装货', 'loading', 1),
    ('TmsWaybill:Unloading', '卸货', 'unloading', 2)
) as action(name, title, auth_mark, sort)
where parent.name = 'TmsLoadedWaybillList'
  and not exists (
    select 1 from public.sys_menu existing
    where existing.name = action.name
  );

insert into public.sys_role_menu (
  role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  role.id,
  menu.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  role.tenant_id
from public.sys_role role
join public.sys_menu menu
  on menu.name in (
    'System:GeofenceConfig:Edit',
    'TmsWaybill:Loading',
    'TmsWaybill:Unloading'
  )
where role.builtin_type = 'platform_super'
on conflict (role_id, menu_id) do nothing;

;
