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
    'driver', to_jsonb(v_driver),
    'carrier', case when v_carrier.id is null then null else to_jsonb(v_carrier) end,
    'vehicle', case when v_vehicle.id is null then null else to_jsonb(v_vehicle) end,
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
      to_jsonb(waybill_row) || jsonb_build_object('driver', to_jsonb(driver_row))
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
  select to_jsonb(waybill_row) || jsonb_build_object('driver', to_jsonb(driver_row))
  from public.tms_waybill waybill_row
  join public.tms_driver driver_row
    on driver_row.id = waybill_row.driver_id
   and driver_row.tenant_id = waybill_row.tenant_id
  where waybill_row.id = p_waybill_id
    and waybill_row.tenant_id = app_private.current_user_tenant_id()
    and waybill_row.driver_id = app_private.current_user_driver_id()
  limit 1;
$$;

create or replace function public.tms_list_driver_mobile_waybill_events(p_waybill_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(event_row) order by event_row.event_time), '[]'::jsonb)
  from public.tms_waybill_event event_row
  join public.tms_waybill waybill_row
    on waybill_row.id = event_row.waybill_id
   and waybill_row.tenant_id = event_row.tenant_id
  where waybill_row.id = p_waybill_id
    and waybill_row.tenant_id = app_private.current_user_tenant_id()
    and waybill_row.driver_id = app_private.current_user_driver_id();
$$;

create or replace function public.tms_list_driver_mobile_waybill_proofs(p_waybill_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(proof_row) order by proof_row.uploaded_at desc), '[]'::jsonb)
  from public.tms_waybill_proof proof_row
  join public.tms_waybill waybill_row
    on waybill_row.id = proof_row.waybill_id
   and waybill_row.tenant_id = proof_row.tenant_id
  where waybill_row.id = p_waybill_id
    and waybill_row.tenant_id = app_private.current_user_tenant_id()
    and waybill_row.driver_id = app_private.current_user_driver_id();
$$;

create or replace function public.tms_create_driver_mobile_waybill_proof(
  p_waybill_id uuid,
  p_proof_type text,
  p_file_url text,
  p_file_name text default null,
  p_mime_type text default null,
  p_file_size bigint default null,
  p_uploaded_at timestamptz default now(),
  p_uploader_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_proof public.tms_waybill_proof%rowtype;
begin
  if not exists (
    select 1
    from public.tms_waybill waybill_row
    where waybill_row.id = p_waybill_id
      and waybill_row.tenant_id = v_tenant_id
      and waybill_row.driver_id = v_driver_id
  ) then
    raise exception '运单不存在或无权访问' using errcode = '42501';
  end if;

  insert into public.tms_waybill_proof (
    tenant_id,
    waybill_id,
    proof_type,
    file_url,
    file_name,
    mime_type,
    file_size,
    uploaded_at,
    uploader_name
  ) values (
    v_tenant_id,
    p_waybill_id,
    p_proof_type,
    p_file_url,
    p_file_name,
    p_mime_type,
    p_file_size,
    coalesce(p_uploaded_at, now()),
    p_uploader_name
  )
  returning * into v_proof;

  return to_jsonb(v_proof);
end;
$$;

revoke all on function public.tms_get_driver_mobile_profile() from public, anon;
revoke all on function public.tms_list_driver_mobile_waybills(text, integer) from public, anon;
revoke all on function public.tms_get_driver_mobile_waybill(uuid) from public, anon;
revoke all on function public.tms_list_driver_mobile_waybill_events(uuid) from public, anon;
revoke all on function public.tms_list_driver_mobile_waybill_proofs(uuid) from public, anon;
revoke all on function public.tms_create_driver_mobile_waybill_proof(
  uuid, text, text, text, text, bigint, timestamptz, text
) from public, anon;

grant execute on function public.tms_get_driver_mobile_profile() to authenticated, service_role;
grant execute on function public.tms_list_driver_mobile_waybills(text, integer) to authenticated, service_role;
grant execute on function public.tms_get_driver_mobile_waybill(uuid) to authenticated, service_role;
grant execute on function public.tms_list_driver_mobile_waybill_events(uuid) to authenticated, service_role;
grant execute on function public.tms_list_driver_mobile_waybill_proofs(uuid) to authenticated, service_role;
grant execute on function public.tms_create_driver_mobile_waybill_proof(
  uuid, text, text, text, text, bigint, timestamptz, text
) to authenticated, service_role;

;
