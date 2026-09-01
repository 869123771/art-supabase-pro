create or replace function public.tms_get_driver_mobile_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_user public.sys_user%rowtype;
  v_driver public.tms_driver%rowtype;
  v_carrier public.tms_carrier%rowtype;
  v_vehicle public.vehicle_archive%rowtype;
  v_completed_count integer := 0;
  v_total_mileage_km numeric := 0;
begin
  if v_auth_user_id is null or v_tenant_id is null or v_driver_id is null then
    raise exception '当前账号未绑定启用的司机档案' using errcode = '42501';
  end if;

  select user_row.*
  into v_user
  from public.sys_user user_row
  where user_row.auth_user_id = v_auth_user_id
    and user_row.tenant_id = v_tenant_id
    and user_row.status = '1'
    and user_row.deleted_at is null
  limit 1;

  select driver_row.*
  into v_driver
  from public.tms_driver driver_row
  where driver_row.id = v_driver_id
    and driver_row.tenant_id = v_tenant_id
    and driver_row.enabled is true;

  if not found then
    raise exception '当前账号未绑定启用的司机档案' using errcode = '42501';
  end if;

  if v_driver.carrier_id is not null then
    select carrier_row.*
    into v_carrier
    from public.tms_carrier carrier_row
    where carrier_row.id = v_driver.carrier_id
      and carrier_row.tenant_id = v_tenant_id;
  end if;

  select vehicle_row.*
  into v_vehicle
  from public.vehicle_archive vehicle_row
  where vehicle_row.tenant_id = v_tenant_id
    and vehicle_row.primary_driver_id = v_driver_id
  order by vehicle_row.create_time desc
  limit 1;

  if not found then
    select vehicle_row.*
    into v_vehicle
    from public.tms_waybill waybill_row
    join public.vehicle_archive vehicle_row
      on vehicle_row.id = waybill_row.vehicle_id
     and vehicle_row.tenant_id = waybill_row.tenant_id
    where waybill_row.tenant_id = v_tenant_id
      and waybill_row.driver_id = v_driver_id
    order by waybill_row.create_time desc
    limit 1;
  end if;

  if not found and v_driver.carrier_id is not null then
    select vehicle_row.*
    into v_vehicle
    from public.vehicle_archive vehicle_row
    where vehicle_row.tenant_id = v_tenant_id
      and vehicle_row.carrier_id = v_driver.carrier_id
    order by vehicle_row.create_time desc
    limit 1;
  end if;

  select count(*)::integer,
         coalesce(sum(coalesce(waybill_row.remaining_distance_km, 0)), 0)
  into v_completed_count, v_total_mileage_km
  from public.tms_waybill waybill_row
  where waybill_row.tenant_id = v_tenant_id
    and waybill_row.driver_id = v_driver_id
    and waybill_row.status = 'completed';

  return jsonb_build_object(
    'user', jsonb_build_object(
      'id', v_user.id,
      'auth_user_id', v_user.auth_user_id,
      'tenant_id', v_user.tenant_id,
      'user_name', v_user.user_name,
      'nick_name', v_user.nick_name,
      'user_phone', v_user.user_phone,
      'user_email', v_user.user_email,
      'user_type', v_user.user_type,
      'status', v_user.status,
      'avatar', v_user.avatar
    ),
    'driver', jsonb_build_object(
      'id', v_driver.id,
      'tenant_id', v_driver.tenant_id,
      'carrier_id', v_driver.carrier_id,
      'driver_name', v_driver.driver_name,
      'phone', v_driver.phone,
      'gender', v_driver.gender,
      'id_card_no', v_driver.id_card_no,
      'license_type', v_driver.license_type,
      'driver_license_front_url', v_driver.driver_license_front_url,
      'driver_license_back_url', v_driver.driver_license_back_url,
      'enabled', v_driver.enabled
    ),
    'carrier', case when v_carrier.id is null then null else jsonb_build_object(
      'id', v_carrier.id,
      'carrier_code', v_carrier.carrier_code,
      'company_name', v_carrier.company_name,
      'contact_name', v_carrier.contact_name,
      'contact_phone', v_carrier.contact_phone
    ) end,
    'vehicle', case when v_vehicle.id is null then null else jsonb_build_object(
      'id', v_vehicle.id,
      'plate_no', v_vehicle.plate_no,
      'carrier_id', v_vehicle.carrier_id,
      'primary_driver_id', v_vehicle.primary_driver_id,
      'company_name', v_vehicle.company_name,
      'vehicle_type', v_vehicle.vehicle_type,
      'brand_model', v_vehicle.brand_model,
      'operation_status', v_vehicle.operation_status,
      'vehicle_photo_url', v_vehicle.vehicle_photo_url,
      'approved_load_mass', v_vehicle.approved_load_mass,
      'overall_length', v_vehicle.overall_length,
      'fuel_type', v_vehicle.fuel_type,
      'audit_status', v_vehicle.audit_status,
      'driving_license_front_url', v_vehicle.driving_license_front_url,
      'driving_license_back_url', v_vehicle.driving_license_back_url,
      'operation_license_url', v_vehicle.operation_license_url,
      'license_plate_code', v_vehicle.license_plate_code
    ) end,
    'completed_count', v_completed_count,
    'total_mileage_km', round(v_total_mileage_km, 1),
    'rating', 0
  );
end;
$$;

create or replace function public.tms_list_driver_mobile_waybills(
  p_group text default 'all',
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_group text := lower(coalesce(nullif(btrim(p_group), ''), 'all'));
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 1000);
  v_result jsonb;
begin
  if v_tenant_id is null or v_driver_id is null then
    raise exception '当前账号未绑定启用的司机档案' using errcode = '42501';
  end if;
  if v_group not in ('all', 'pending', 'active', 'completed') then
    raise exception '不支持的运单筛选条件' using errcode = '22023';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(waybill_row) || jsonb_build_object(
        'driver', jsonb_build_object(
          'id', driver_row.id,
          'tenant_id', driver_row.tenant_id,
          'carrier_id', driver_row.carrier_id,
          'driver_name', driver_row.driver_name,
          'phone', driver_row.phone,
          'gender', driver_row.gender,
          'id_card_no', driver_row.id_card_no,
          'license_type', driver_row.license_type,
          'driver_license_front_url', driver_row.driver_license_front_url,
          'driver_license_back_url', driver_row.driver_license_back_url,
          'enabled', driver_row.enabled
        )
      )
      order by waybill_row.create_time desc
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select scoped_waybill.*
    from public.tms_waybill scoped_waybill
    where scoped_waybill.tenant_id = v_tenant_id
      and scoped_waybill.driver_id = v_driver_id
      and (
        v_group = 'all'
        or (v_group = 'pending' and scoped_waybill.status = 'pending')
        or (
          v_group = 'active'
          and scoped_waybill.status = any(array[
            'accepted', 'loading', 'transporting', 'unloading', 'signed'
          ]::text[])
        )
        or (v_group = 'completed' and scoped_waybill.status = 'completed')
      )
    order by scoped_waybill.create_time desc
    limit v_limit
  ) waybill_row
  join public.tms_driver driver_row
    on driver_row.id = waybill_row.driver_id
   and driver_row.tenant_id = waybill_row.tenant_id;

  return v_result;
end;
$$;

create or replace function public.tms_get_driver_mobile_waybill(p_waybill_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(waybill_row) || jsonb_build_object(
    'driver', jsonb_build_object(
      'id', driver_row.id,
      'tenant_id', driver_row.tenant_id,
      'carrier_id', driver_row.carrier_id,
      'driver_name', driver_row.driver_name,
      'phone', driver_row.phone,
      'gender', driver_row.gender,
      'id_card_no', driver_row.id_card_no,
      'license_type', driver_row.license_type,
      'driver_license_front_url', driver_row.driver_license_front_url,
      'driver_license_back_url', driver_row.driver_license_back_url,
      'enabled', driver_row.enabled
    )
  )
  from public.tms_waybill waybill_row
  join public.tms_driver driver_row
    on driver_row.id = waybill_row.driver_id
   and driver_row.tenant_id = waybill_row.tenant_id
  where waybill_row.id = p_waybill_id
    and waybill_row.tenant_id = app_private.current_user_tenant_id()
    and waybill_row.driver_id = app_private.current_user_driver_id()
  limit 1;
$$;


;
