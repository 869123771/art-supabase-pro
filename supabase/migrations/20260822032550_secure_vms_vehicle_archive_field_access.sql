alter table public.vehicle_archive
  add column if not exists created_by_user_id uuid;

update public.vehicle_archive vehicle_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = vehicle_row.tenant_id
    and lower(user_row.user_email) = lower(vehicle_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where vehicle_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.vehicle_archive where created_by_user_id is null
  ) then
    raise exception 'Cannot resolve every vehicle archive creator identity';
  end if;
end;
$$;

alter table public.vehicle_archive
  alter column created_by_user_id set not null;

alter table public.vehicle_archive
  drop constraint if exists vehicle_archive_created_by_user_tenant_fkey;
alter table public.vehicle_archive
  add constraint vehicle_archive_created_by_user_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on delete restrict;

create or replace function app_private.set_vehicle_archive_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_user_tenant_id uuid;
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      select user_row.tenant_id
      into v_current_user_tenant_id
      from public.sys_user user_row
      where user_row.id = v_current_user_id;
    end if;

    if v_current_user_id is not null and v_current_user_tenant_id = new.tenant_id then
      new.created_by_user_id := v_current_user_id;
    elsif v_current_user_id is null and new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
        and user_row.deleted_at is null
      order by user_row.create_time, user_row.id
      limit 1;
    end if;

    if new.created_by_user_id is null or not exists (
      select 1
      from public.sys_user user_row
      where user_row.id = new.created_by_user_id
        and user_row.tenant_id = new.tenant_id
    ) then
      raise exception 'Authenticated vehicle archive creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle archive creator identity is immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists vehicle_archive_creator_identity on public.vehicle_archive;
create trigger vehicle_archive_creator_identity
before insert or update on public.vehicle_archive
for each row execute function app_private.set_vehicle_archive_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_archive;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_archive(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_archive', '车辆档案', 'VehicleArchiveManage',
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

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'vehicleIdentifiers', '车辆证照与识别号码',
      'hidden', 'id_card', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'ownerIdentity', '车主身份信息',
      'hidden', 'id_card', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'contactPhones', '车主与随车联系电话',
      'hidden', 'phone', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'mailingAddress', '车主通讯地址',
      'hidden', 'address', true, true, true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'operationRoute', '车辆营运线路',
      'hidden', 'address', true, true, true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'documents', '车辆证件影像与附件',
      'hidden', 'none', true, true, true, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'deviceIdentity', '车载终端标识',
      'hidden', 'phone', true, true, true, 70, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sensitive = true,
        enabled = true,
        sort = excluded.sort,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve current behavior for roles that already manage the vehicle archive.
insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'VehicleArchiveManage'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_archive'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_reference_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and (
          menu_row.name like 'Vehicle%'
          or menu_row.name = any(array[
            'Console',
            'TmsCarrier',
            'TmsCarrierDetail',
            'TmsDriver',
            'TmsCarrierPrice',
            'TmsCarrierPriceDetail',
            'TmsCarrierPriceEdit',
            'TmsOrderOpen',
            'TmsOrderList',
            'TmsPendingWaybillList',
            'TmsLoadedWaybillList',
            'TmsWaybillDetail',
            'TmsInTransitMonitor'
          ]::text[])
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_archive_to_secure_json(
  p_vehicle public.vehicle_archive,
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
    app_private.field_access_map('vms.vehicle_archive', p_vehicle.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_vehicle) - 'tenant_id' - 'created_by_user_id';
  v_level text;
  v_carrier jsonb;
  v_primary_driver jsonb;
  v_secondary_driver jsonb;
begin
  v_level := coalesce(v_access->>'vehicleIdentifiers', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'vin' - 'operation_cert_no' - 'purchase_cert_no' - 'registration_cert_no'
      - 'chassis_no' - 'gearbox_serial_no' - 'engine_no' - 'license_plate_code';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{vin}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.vin, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{operation_cert_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.operation_cert_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{purchase_cert_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.purchase_cert_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{registration_cert_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.registration_cert_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{chassis_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.chassis_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{gearbox_serial_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.gearbox_serial_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{engine_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.engine_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{license_plate_code}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.license_plate_code, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'ownerIdentity', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'owner_id' - 'owner_name' - 'owner_gender' - 'id_card_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{owner_id}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.owner_id, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{owner_name}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.owner_name, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{owner_gender}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.owner_gender, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{id_card_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.id_card_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'contactPhones', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'owner_phone' - 'driver_one_phone' - 'driver_two_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{owner_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.owner_phone, 'phone')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{driver_one_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.driver_one_phone, 'phone')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{driver_two_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.driver_two_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'mailingAddress', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'mailing_address';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{mailing_address}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.mailing_address, 'address')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'operationRoute', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'operation_route';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{operation_route}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.operation_route, 'address')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'documents', 'hidden');
  if v_level in ('hidden', 'masked') then
    v_data := v_data
      - 'driving_license_front_url' - 'driving_license_back_url'
      - 'operation_license_url' - 'attachments';
  end if;

  v_level := coalesce(v_access->>'deviceIdentity', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'ac_code' - 'terminal_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{ac_code}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.ac_code, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{terminal_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_vehicle.terminal_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  -- Legacy snapshots are redundant with the tenant-checked driver relations.
  v_data := v_data
    - 'driver_one_name' - 'driver_one_phone'
    - 'driver_two_name' - 'driver_two_phone';

  select app_private.tms_carrier_option_to_secure_json(carrier_row)
  into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_vehicle.carrier_id
    and carrier_row.tenant_id = p_vehicle.tenant_id;

  select app_private.tms_driver_option_to_secure_json(driver_row)
  into v_primary_driver
  from public.tms_driver driver_row
  where driver_row.id = p_vehicle.primary_driver_id
    and driver_row.tenant_id = p_vehicle.tenant_id;

  select app_private.tms_driver_option_to_secure_json(driver_row)
  into v_secondary_driver
  from public.tms_driver driver_row
  where driver_row.id = p_vehicle.secondary_driver_id
    and driver_row.tenant_id = p_vehicle.tenant_id;

  return v_data || jsonb_build_object(
    'carrier', v_carrier,
    'primary_driver', v_primary_driver,
    'secondary_driver', v_secondary_driver,
    'field_access', v_access,
    'is_record_owner', p_vehicle.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_archives_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_record_id uuid default null,
  p_carrier_id uuid default null,
  p_plate_no text default null,
  p_company_name text default null,
  p_vehicle_type text default null,
  p_manufacturer text default null,
  p_vin text default null,
  p_operation_status text default null,
  p_audit_status text default null,
  p_audit_statuses text[] default null,
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
  v_limit integer;
  v_base_access jsonb;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid vehicle archive read purpose';
  end if;
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'VehicleArchiveManage', 'VehicleArchive:Export', null, false
    ) then
      raise exception 'Missing vehicle archive export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_reference_data() then
    raise exception 'Missing vehicle archive read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('vms.vehicle_archive', null);
  with filtered as materialized (
    select vehicle_row as vehicle_record
    from public.vehicle_archive vehicle_row
    where (app_private.is_platform_super() or vehicle_row.tenant_id = v_tenant_id)
      and (p_record_id is null or vehicle_row.id = p_record_id)
      and (p_ids is null or vehicle_row.id = any(p_ids))
      and (p_carrier_id is null or vehicle_row.carrier_id = p_carrier_id)
      and (nullif(btrim(p_plate_no), '') is null or vehicle_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (nullif(btrim(p_company_name), '') is null or vehicle_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (p_vehicle_type is null or vehicle_row.vehicle_type = p_vehicle_type)
      and (nullif(btrim(p_manufacturer), '') is null or vehicle_row.manufacturer ilike '%' || btrim(p_manufacturer) || '%')
      and (
        nullif(btrim(p_vin), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_archive', 'vehicleIdentifiers', vehicle_row.created_by_user_id
          ) in ('read', 'edit')
          and vehicle_row.vin ilike '%' || btrim(p_vin) || '%'
        )
      )
      and (p_operation_status is null or vehicle_row.operation_status = p_operation_status)
      and (p_audit_status is null or vehicle_row.audit_status = p_audit_status)
      and (p_audit_statuses is null or vehicle_row.audit_status = any(p_audit_statuses))
      and (p_create_time_from is null or vehicle_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or vehicle_row.create_time <= p_create_time_to)
  ), paged as (
    select filtered.vehicle_record
    from filtered
    order by (filtered.vehicle_record).create_time desc, (filtered.vehicle_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_archive_to_secure_json(paged.vehicle_record, null)
        order by (paged.vehicle_record).create_time desc, (paged.vehicle_record).id
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_archive_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_vehicle public.vehicle_archive%rowtype;
begin
  if not app_private.can_access_vms_vehicle_reference_data() then
    raise exception 'Missing vehicle archive view permission' using errcode = '42501';
  end if;

  select * into v_vehicle
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = p_id
    and (
      app_private.is_platform_super()
      or vehicle_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then return null; end if;

  return app_private.vehicle_archive_to_secure_json(v_vehicle, null);
end;
$$;

create or replace function public.vms_list_vehicle_archive_options_secure(
  p_carrier_id uuid default null,
  p_plate_no text default null,
  p_company_name text default null,
  p_ids uuid[] default null,
  p_max_rows integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_access_vms_vehicle_reference_data()
     or v_tenant_id is null then
    raise exception 'Missing vehicle reference data permission' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'id', vehicle_row.id,
        'carrier_id', vehicle_row.carrier_id,
        'plate_no', vehicle_row.plate_no,
        'company_name', vehicle_row.company_name,
        'vin', case
          when app_private.resolve_field_access(
            'vms.vehicle_archive', 'vehicleIdentifiers', vehicle_row.created_by_user_id
          ) in ('read', 'edit') then vehicle_row.vin
          when app_private.resolve_field_access(
            'vms.vehicle_archive', 'vehicleIdentifiers', vehicle_row.created_by_user_id
          ) = 'masked' then app_private.mask_permission_value(vehicle_row.vin, 'id_card')
          else null
        end,
        'self_no', vehicle_row.self_no,
        'vehicle_type', vehicle_row.vehicle_type,
        'field_access', app_private.field_access_map(
          'vms.vehicle_archive', vehicle_row.created_by_user_id
        ),
        'is_record_owner', vehicle_row.created_by_user_id = app_private.current_app_user_id()
      ))
      order by vehicle_row.plate_no, vehicle_row.id
    )
    from (
      select vehicle_record.*
      from public.vehicle_archive vehicle_record
      where (app_private.is_platform_super() or vehicle_record.tenant_id = v_tenant_id)
        and (p_carrier_id is null or vehicle_record.carrier_id = p_carrier_id)
        and (p_ids is null or vehicle_record.id = any(p_ids))
        and (
          nullif(btrim(p_plate_no), '') is null
          or vehicle_record.plate_no ilike '%' || btrim(p_plate_no) || '%'
        )
        and (
          nullif(btrim(p_company_name), '') is null
          or vehicle_record.company_name ilike '%' || btrim(p_company_name) || '%'
        )
      order by vehicle_record.plate_no, vehicle_record.id
      limit least(greatest(coalesce(p_max_rows, 200), 1), 1000)
    ) vehicle_row
  ), '[]'::jsonb);
end;
$$;

create or replace function app_private.assert_vms_vehicle_archive_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'plate_no', 'carrier_id', 'company_name', 'self_no', 'vehicle_type', 'origin_type',
    'vin', 'manufacturer', 'brand_model', 'operation_cert_no', 'purchase_cert_no',
    'registration_cert_no', 'vehicle_color', 'chassis_no', 'ac_code',
    'gearbox_serial_no', 'register_date', 'issue_date', 'invoice_date', 'start_use_date',
    'service_years', 'approved_passenger_count', 'seat_count', 'business_type',
    'is_air_conditioned', 'operation_status', 'operation_status_change_date',
    'purchase_status', 'purchase_status_change_date', 'inspection_start_date',
    'vehicle_level', 'is_new_energy', 'three_guarantee_mileage',
    'three_guarantee_duration', 'warranty_mileage', 'warranty_duration', 'remark',
    'gross_mass', 'curb_weight', 'approved_load_mass', 'overall_length', 'overall_width',
    'overall_height', 'platform', 'front_track', 'rear_track', 'wheelbase', 'axle_count',
    'tire_count', 'leaf_spring_count', 'is_double_deck', 'engine_no', 'engine_model',
    'fuel_type', 'displacement', 'emission_standard', 'engine_power',
    'rated_torque_speed', 'engine_torque', 'plate_color', 'transport_industry',
    'operation_type', 'owner_id', 'owner_name', 'owner_phone', 'terminal_phone',
    'owner_gender', 'id_card_no', 'mailing_address', 'tonnage_or_seat',
    'primary_driver_id', 'secondary_driver_id', 'operation_route', 'license_plate_code',
    'service_start_time', 'service_end_time', 'support_photo', 'vehicle_photo_url',
    'driving_license_front_url', 'driving_license_back_url', 'operation_license_url',
    'attachments'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Vehicle archive payload must be a JSON object';
  end if;

  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Unsupported vehicle archive field: %', v_key;
    end if;
  end loop;
end;
$$;

create or replace function app_private.assert_vms_vehicle_archive_reference_scope(
  p_tenant_id uuid,
  p_carrier_id uuid,
  p_primary_driver_id uuid,
  p_secondary_driver_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_company_name text;
begin
  if p_carrier_id is not null then
    select carrier_row.company_name
    into v_company_name
    from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id
      and carrier_row.tenant_id = p_tenant_id;
    if not found then
      raise exception 'Vehicle carrier is outside the current tenant' using errcode = '42501';
    end if;
  end if;

  if p_primary_driver_id is not null and not exists (
    select 1
    from public.tms_driver driver_row
    where driver_row.id = p_primary_driver_id
      and driver_row.tenant_id = p_tenant_id
      and (p_carrier_id is null or driver_row.carrier_id = p_carrier_id)
  ) then
    raise exception 'Primary driver is outside the vehicle carrier scope' using errcode = '42501';
  end if;

  if p_secondary_driver_id is not null and not exists (
    select 1
    from public.tms_driver driver_row
    where driver_row.id = p_secondary_driver_id
      and driver_row.tenant_id = p_tenant_id
      and (p_carrier_id is null or driver_row.carrier_id = p_carrier_id)
  ) then
    raise exception 'Secondary driver is outside the vehicle carrier scope' using errcode = '42501';
  end if;

  if p_primary_driver_id is not null
     and p_primary_driver_id = p_secondary_driver_id then
    raise exception 'Primary and secondary drivers must be different';
  end if;

  return v_company_name;
end;
$$;

create or replace function public.vms_create_vehicle_archive_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.vehicle_archive%rowtype;
  v_created public.vehicle_archive%rowtype;
begin
  if not app_private.can_execute_business_action(
    'VehicleArchiveManage', 'VehicleArchive:Add', null, false
  ) then
    raise exception 'Missing vehicle archive add permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  perform app_private.assert_vms_vehicle_archive_payload_keys(p_payload);
  select * into v_input
  from jsonb_populate_record(null::public.vehicle_archive, p_payload);

  v_input.id := gen_random_uuid();
  v_input.tenant_id := v_tenant_id;
  v_input.company_name := coalesce(
    app_private.assert_vms_vehicle_archive_reference_scope(
      v_tenant_id,
      v_input.carrier_id,
      v_input.primary_driver_id,
      v_input.secondary_driver_id
    ),
    v_input.company_name
  );
  v_input.is_air_conditioned := coalesce(v_input.is_air_conditioned, false);
  v_input.operation_status := coalesce(v_input.operation_status, 'operating');
  v_input.is_new_energy := coalesce(v_input.is_new_energy, false);
  v_input.is_double_deck := coalesce(v_input.is_double_deck, false);
  v_input.support_photo := coalesce(v_input.support_photo, false);
  v_input.attachments := coalesce(v_input.attachments, '[]'::jsonb);
  v_input.audit_status := 'pending';
  v_input.create_time := now();
  v_input.update_time := now();

  insert into public.vehicle_archive
  select (v_input).*
  returning * into v_created;

  return v_created.id;
end;
$$;

create or replace function public.vms_update_vehicle_archive_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.vehicle_archive%rowtype;
  v_candidate public.vehicle_archive%rowtype;
  v_updated public.vehicle_archive%rowtype;
  v_safe_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_company_name text;
  v_assignments text;
begin
  select * into v_old
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = p_id
    and (
      app_private.is_platform_super()
      or vehicle_row.tenant_id = app_private.current_user_tenant_id()
    )
  for update;
  if not found then
    raise exception 'Vehicle archive not found or access denied';
  end if;

  if not app_private.can_execute_business_action(
    'VehicleArchiveManage', 'VehicleArchive:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle archive edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_vms_vehicle_archive_payload_keys(v_safe_payload);
  select * into v_candidate
  from jsonb_populate_record(v_old, v_safe_payload);

  v_company_name := app_private.assert_vms_vehicle_archive_reference_scope(
    v_old.tenant_id,
    v_candidate.carrier_id,
    v_candidate.primary_driver_id,
    v_candidate.secondary_driver_id
  );
  if v_candidate.carrier_id is not null then
    v_safe_payload := jsonb_set(
      v_safe_payload,
      '{company_name}',
      coalesce(to_jsonb(v_company_name), 'null'::jsonb),
      true
    );
    v_candidate.company_name := v_company_name;
  end if;

  if (
    v_candidate.vin,
    v_candidate.operation_cert_no,
    v_candidate.purchase_cert_no,
    v_candidate.registration_cert_no,
    v_candidate.chassis_no,
    v_candidate.gearbox_serial_no,
    v_candidate.engine_no,
    v_candidate.license_plate_code
  ) is distinct from (
    v_old.vin,
    v_old.operation_cert_no,
    v_old.purchase_cert_no,
    v_old.registration_cert_no,
    v_old.chassis_no,
    v_old.gearbox_serial_no,
    v_old.engine_no,
    v_old.license_plate_code
  ) and app_private.resolve_field_access(
    'vms.vehicle_archive', 'vehicleIdentifiers', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for vehicle identifiers' using errcode = '42501';
  end if;

  if (
    v_candidate.owner_id,
    v_candidate.owner_name,
    v_candidate.owner_gender,
    v_candidate.id_card_no
  ) is distinct from (
    v_old.owner_id,
    v_old.owner_name,
    v_old.owner_gender,
    v_old.id_card_no
  ) and app_private.resolve_field_access(
    'vms.vehicle_archive', 'ownerIdentity', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for vehicle owner identity' using errcode = '42501';
  end if;

  if v_candidate.owner_phone is distinct from v_old.owner_phone
     and app_private.resolve_field_access(
       'vms.vehicle_archive', 'contactPhones', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle contact phones' using errcode = '42501';
  end if;

  if v_candidate.mailing_address is distinct from v_old.mailing_address
     and app_private.resolve_field_access(
       'vms.vehicle_archive', 'mailingAddress', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle mailing address' using errcode = '42501';
  end if;

  if v_candidate.operation_route is distinct from v_old.operation_route
     and app_private.resolve_field_access(
       'vms.vehicle_archive', 'operationRoute', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle operation route' using errcode = '42501';
  end if;

  if (
    v_candidate.driving_license_front_url,
    v_candidate.driving_license_back_url,
    v_candidate.operation_license_url,
    v_candidate.attachments
  ) is distinct from (
    v_old.driving_license_front_url,
    v_old.driving_license_back_url,
    v_old.operation_license_url,
    v_old.attachments
  ) and app_private.resolve_field_access(
    'vms.vehicle_archive', 'documents', v_old.created_by_user_id
  ) <> 'edit' then
    raise exception 'No edit permission for vehicle documents' using errcode = '42501';
  end if;

  if (v_candidate.ac_code, v_candidate.terminal_phone) is distinct from
     (v_old.ac_code, v_old.terminal_phone)
     and app_private.resolve_field_access(
       'vms.vehicle_archive', 'deviceIdentity', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle device identity' using errcode = '42501';
  end if;

  if v_safe_payload = '{}'::jsonb then
    return app_private.vehicle_archive_to_secure_json(v_old, null);
  end if;

  select string_agg(
    format('%1$I = ($1::public.vehicle_archive).%1$I', payload_key),
    ', '
  )
  into v_assignments
  from jsonb_object_keys(v_safe_payload) payload_key;

  execute format(
    'update public.vehicle_archive set %s where id = $2 returning *',
    v_assignments
  )
  into v_updated
  using v_candidate, v_old.id;

  return app_private.vehicle_archive_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.vms_get_vehicle_archive_delete_preview_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_vehicle public.vehicle_archive%rowtype;
  v_waybill_count integer;
  v_related_counts jsonb;
begin
  select * into v_vehicle
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = p_id
    and (
      app_private.is_platform_super()
      or vehicle_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception 'Vehicle archive not found or access denied';
  end if;
  if not app_private.can_execute_business_action(
    'VehicleArchiveManage', 'VehicleArchive:Delete', v_vehicle.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle archive delete permission' using errcode = '42501';
  end if;

  select count(*) into v_waybill_count
  from public.tms_waybill row_item
  where row_item.vehicle_id = v_vehicle.id
    and row_item.tenant_id = v_vehicle.tenant_id;

  select jsonb_build_array(
    jsonb_build_object('table_name', 'vehicle_insurance', 'label', '保险记录', 'count', (
      select count(*) from public.vehicle_insurance row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_inspection', 'label', '年检记录', 'count', (
      select count(*) from public.vehicle_inspection row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_maintenance_record', 'label', '保养维修记录', 'count', (
      select count(*) from public.vehicle_maintenance_record row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_routine_inspection_record', 'label', '例行检查记录', 'count', (
      select count(*) from public.vehicle_routine_inspection_record row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_mileage_record', 'label', '里程记录', 'count', (
      select count(*) from public.vehicle_mileage_record row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_part_usage', 'label', '零部件使用记录', 'count', (
      select count(*) from public.vehicle_part_usage row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_accident_record', 'label', '事故记录', 'count', (
      select count(*) from public.vehicle_accident_record row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'vehicle_violation_record', 'label', '违章记录', 'count', (
      select count(*) from public.vehicle_violation_record row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    )),
    jsonb_build_object('table_name', 'tms_carrier_price', 'label', '承运商车辆报价', 'count', (
      select count(*) from public.tms_carrier_price row_item
      where row_item.vehicle_id = v_vehicle.id and row_item.tenant_id = v_vehicle.tenant_id
    ))
  ) into v_related_counts;

  return jsonb_build_object(
    'waybill_count', v_waybill_count,
    'related_counts', v_related_counts,
    'related_total', (
      select coalesce(sum((item->>'count')::integer), 0)
      from jsonb_array_elements(v_related_counts) item
    )
  );
end;
$$;

create or replace function public.vms_delete_vehicle_archives_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, array[]::uuid[])));
  v_vehicle public.vehicle_archive%rowtype;
  v_deleted integer;
begin
  if cardinality(v_ids) = 0 then return 0; end if;

  if (
    select count(*)
    from public.vehicle_archive vehicle_row
    where vehicle_row.id = any(v_ids)
      and (
        app_private.is_platform_super()
        or vehicle_row.tenant_id = app_private.current_user_tenant_id()
      )
  ) <> cardinality(v_ids) then
    raise exception 'One or more vehicle archives are missing or outside the current tenant';
  end if;

  for v_vehicle in
    select * from public.vehicle_archive vehicle_row
    where vehicle_row.id = any(v_ids)
    for update
  loop
    if not app_private.can_execute_business_action(
      'VehicleArchiveManage', 'VehicleArchive:Delete', v_vehicle.created_by_user_id, true
    ) then
      raise exception 'Missing vehicle archive delete permission' using errcode = '42501';
    end if;
  end loop;

  if exists (
    select 1
    from public.tms_waybill waybill_row
    where waybill_row.vehicle_id = any(v_ids)
      and (
        app_private.is_platform_super()
        or waybill_row.tenant_id = app_private.current_user_tenant_id()
      )
  ) then
    raise exception 'A selected vehicle has linked waybills and cannot be deleted';
  end if;

  delete from public.vehicle_archive vehicle_row
  where vehicle_row.id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_list_dispatch_vehicle_options_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(
    200,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_result jsonb;
begin
  if not app_private.can_access_vms_vehicle_reference_data()
     or v_tenant_id is null then
    raise exception 'Missing dispatch vehicle reference permission' using errcode = '42501';
  end if;

  with filtered as materialized (
    select vehicle_row as vehicle_record
    from public.vehicle_archive vehicle_row
    left join public.tms_driver primary_driver_row
      on primary_driver_row.id = vehicle_row.primary_driver_id
     and primary_driver_row.tenant_id = vehicle_row.tenant_id
    where (app_private.is_platform_super() or vehicle_row.tenant_id = v_tenant_id)
      and vehicle_row.audit_status = 'approved'
      and (
        nullif(btrim(p_keyword), '') is null
        or vehicle_row.plate_no ilike '%' || btrim(p_keyword) || '%'
        or vehicle_row.company_name ilike '%' || btrim(p_keyword) || '%'
        or vehicle_row.self_no ilike '%' || btrim(p_keyword) || '%'
        or vehicle_row.vehicle_type ilike '%' || btrim(p_keyword) || '%'
        or primary_driver_row.driver_name ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'vms.vehicle_archive', 'vehicleIdentifiers', vehicle_row.created_by_user_id
          ) in ('read', 'edit')
          and vehicle_row.vin ilike '%' || btrim(p_keyword) || '%'
        )
      )
  ), paged as (
    select filtered.vehicle_record
    from filtered
    order by (filtered.vehicle_record).plate_no, (filtered.vehicle_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id', (paged.vehicle_record).id,
          'carrier_id', (paged.vehicle_record).carrier_id,
          'plate_no', (paged.vehicle_record).plate_no,
          'company_name', (paged.vehicle_record).company_name,
          'vin', case
            when app_private.resolve_field_access(
              'vms.vehicle_archive', 'vehicleIdentifiers',
              (paged.vehicle_record).created_by_user_id
            ) in ('read', 'edit') then (paged.vehicle_record).vin
            when app_private.resolve_field_access(
              'vms.vehicle_archive', 'vehicleIdentifiers',
              (paged.vehicle_record).created_by_user_id
            ) = 'masked' then app_private.mask_permission_value(
              (paged.vehicle_record).vin, 'id_card'
            )
            else null
          end,
          'self_no', (paged.vehicle_record).self_no,
          'vehicle_type', (paged.vehicle_record).vehicle_type,
          'primary_driver_id', (paged.vehicle_record).primary_driver_id,
          'tonnage_or_seat', (paged.vehicle_record).tonnage_or_seat,
          'overall_length', (paged.vehicle_record).overall_length,
          'primary_driver', (
            select app_private.tms_driver_option_to_secure_json(driver_row)
            from public.tms_driver driver_row
            where driver_row.id = (paged.vehicle_record).primary_driver_id
              and driver_row.tenant_id = (paged.vehicle_record).tenant_id
          ),
          'field_access', app_private.field_access_map(
            'vms.vehicle_archive', (paged.vehicle_record).created_by_user_id
          ),
          'is_record_owner',
            (paged.vehicle_record).created_by_user_id = app_private.current_app_user_id()
        ))
        order by (paged.vehicle_record).plate_no, (paged.vehicle_record).id
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.tms_get_dispatch_recommendation_context_secure(
  p_order_id uuid,
  p_history_from timestamptz,
  p_max_vehicles integer default 500,
  p_max_history integer default 2000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_order public.tms_order%rowtype;
  v_vehicles jsonb;
  v_assignments jsonb;
  v_history jsonb;
  v_vehicle_count integer;
begin
  if not app_private.can_execute_business_action(
    'TmsPendingWaybillList', 'TmsPendingWaybillList:Dispatch', null, false
  ) then
    raise exception 'Missing dispatch recommendation permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  select * into v_order
  from public.tms_order order_row
  where order_row.id = p_order_id
    and (app_private.is_platform_super() or order_row.tenant_id = v_tenant_id);
  if not found then return null; end if;

  select count(*) into v_vehicle_count
  from public.vehicle_archive vehicle_row
  where vehicle_row.tenant_id = v_order.tenant_id
    and vehicle_row.audit_status = 'approved'
    and vehicle_row.operation_status = 'operating';

  select coalesce(jsonb_agg(vehicle_json order by plate_no, id), '[]'::jsonb)
  into v_vehicles
  from (
    select
      vehicle_row.id,
      vehicle_row.plate_no,
      jsonb_strip_nulls(jsonb_build_object(
        'id', vehicle_row.id,
        'carrier_id', vehicle_row.carrier_id,
        'plate_no', vehicle_row.plate_no,
        'company_name', vehicle_row.company_name,
        'vehicle_type', vehicle_row.vehicle_type,
        'tonnage_or_seat', vehicle_row.tonnage_or_seat,
        'overall_length', vehicle_row.overall_length,
        'approved_load_mass', vehicle_row.approved_load_mass,
        'operation_route', case
          when app_private.resolve_field_access(
            'vms.vehicle_archive', 'operationRoute', vehicle_row.created_by_user_id
          ) in ('read', 'edit') then vehicle_row.operation_route
          else null
        end,
        'operation_status', vehicle_row.operation_status,
        'audit_status', vehicle_row.audit_status,
        'service_end_time', vehicle_row.service_end_time,
        'primary_driver_id', vehicle_row.primary_driver_id,
        'primaryDriver', (
          select app_private.tms_driver_option_to_secure_json(driver_row)
          from public.tms_driver driver_row
          where driver_row.id = vehicle_row.primary_driver_id
            and driver_row.tenant_id = vehicle_row.tenant_id
        )
      )) as vehicle_json
    from public.vehicle_archive vehicle_row
    where vehicle_row.tenant_id = v_order.tenant_id
      and vehicle_row.audit_status = 'approved'
      and vehicle_row.operation_status = 'operating'
    order by vehicle_row.plate_no, vehicle_row.id
    limit least(greatest(coalesce(p_max_vehicles, 500), 1), 1000)
  ) vehicle_context;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', order_row.id,
    'dispatch_status', order_row.dispatch_status,
    'dispatch_vehicle_id', order_row.dispatch_vehicle_id,
    'dispatch_driver_id', order_row.dispatch_driver_id
  )), '[]'::jsonb)
  into v_assignments
  from (
    select order_record.*
    from public.tms_order order_record
    where order_record.tenant_id = v_order.tenant_id
      and order_record.dispatch_status = any(array[
        'loaded', 'dispatched', 'loading', 'transporting', 'unloading'
      ]::text[])
    limit 2000
  ) order_row;

  select coalesce(jsonb_agg(jsonb_build_object(
    'dispatch_vehicle_id', order_row.dispatch_vehicle_id,
    'origin_station', order_row.origin_station,
    'destination_station', order_row.destination_station,
    'planned_arrival_time', order_row.planned_arrival_time,
    'signed_at', order_row.signed_at,
    'create_time', order_row.create_time
  ) order by order_row.create_time desc), '[]'::jsonb)
  into v_history
  from (
    select order_record.*
    from public.tms_order order_record
    where order_record.tenant_id = v_order.tenant_id
      and order_record.order_status = any(array['signed', 'completed']::text[])
      and order_record.dispatch_vehicle_id is not null
      and (p_history_from is null or order_record.create_time >= p_history_from)
    order by order_record.create_time desc
    limit least(greatest(coalesce(p_max_history, 2000), 1), 5000)
  ) order_row;

  return jsonb_build_object(
    'order', jsonb_build_object(
      'id', v_order.id,
      'order_no', v_order.order_no,
      'order_status', v_order.order_status,
      'dispatch_status', v_order.dispatch_status,
      'origin_station', v_order.origin_station,
      'destination_station', v_order.destination_station,
      'cargo_weight_total', v_order.cargo_weight_total,
      'cargo_volume_total', v_order.cargo_volume_total,
      'transport_mode', v_order.transport_mode,
      'planned_departure_time', v_order.planned_departure_time,
      'planned_arrival_time', v_order.planned_arrival_time
    ),
    'vehicles', v_vehicles,
    'active_assignments', v_assignments,
    'history', v_history,
    'vehicle_count', v_vehicle_count
  );
end;
$$;

-- Direct access is intentionally restricted to non-sensitive read models used by
-- dashboards and maintenance views. All writes and sensitive reads go through the
-- security-definer RPCs above.
revoke all on table public.vehicle_archive from anon, authenticated;

grant select (
  id, tenant_id, plate_no, company_name, self_no, vehicle_type, origin_type,
  manufacturer, brand_model, vehicle_color, register_date, issue_date, invoice_date,
  start_use_date, service_years, approved_passenger_count, seat_count, business_type,
  is_air_conditioned, operation_status, operation_status_change_date, purchase_status,
  purchase_status_change_date, inspection_start_date, vehicle_level, is_new_energy,
  three_guarantee_mileage, three_guarantee_duration, warranty_mileage,
  warranty_duration, remark, gross_mass, curb_weight, approved_load_mass,
  overall_length, overall_width, overall_height, platform, front_track, rear_track,
  wheelbase, axle_count, tire_count, leaf_spring_count, is_double_deck, engine_model,
  fuel_type, displacement, emission_standard, engine_power, rated_torque_speed,
  engine_torque, plate_color, transport_industry, operation_type, tonnage_or_seat,
  service_start_time, service_end_time, support_photo, vehicle_photo_url, audit_status,
  audit_remark, create_by, create_time, update_by, update_time, carrier_id,
  primary_driver_id, secondary_driver_id
) on public.vehicle_archive to authenticated;

drop policy if exists tenant_select on public.vehicle_archive;
drop policy if exists tenant_insert on public.vehicle_archive;
drop policy if exists tenant_update on public.vehicle_archive;
drop policy if exists tenant_delete on public.vehicle_archive;

create policy vehicle_archive_safe_select on public.vehicle_archive
for select to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_access_vms_vehicle_reference_data()
);

revoke all on function app_private.seed_field_permission_catalog(uuid)
from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid)
to service_role;

revoke all on function app_private.set_vehicle_archive_creator_identity()
from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_reference_data()
from public, anon, authenticated;
revoke all on function app_private.vehicle_archive_to_secure_json(
  public.vehicle_archive, jsonb
) from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_archive_payload_keys(jsonb)
from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_archive_reference_scope(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;

grant execute on function app_private.set_vehicle_archive_creator_identity()
to service_role;
grant execute on function app_private.can_access_vms_vehicle_reference_data()
to authenticated, service_role;
grant execute on function app_private.vehicle_archive_to_secure_json(
  public.vehicle_archive, jsonb
) to service_role;
grant execute on function app_private.assert_vms_vehicle_archive_payload_keys(jsonb)
to service_role;
grant execute on function app_private.assert_vms_vehicle_archive_reference_scope(
  uuid, uuid, uuid, uuid
) to service_role;

revoke all on function public.vms_list_vehicle_archives_secure(
  integer, integer, uuid, uuid, text, text, text, text, text, text, text, text[],
  timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.vms_get_vehicle_archive_secure(uuid)
from public, anon;
revoke all on function public.vms_list_vehicle_archive_options_secure(
  uuid, text, text, uuid[], integer
) from public, anon;
revoke all on function public.vms_create_vehicle_archive_secure(jsonb)
from public, anon;
revoke all on function public.vms_update_vehicle_archive_secure(uuid, jsonb)
from public, anon;
revoke all on function public.vms_get_vehicle_archive_delete_preview_secure(uuid)
from public, anon;
revoke all on function public.vms_delete_vehicle_archives_secure(uuid[])
from public, anon;
revoke all on function public.vms_list_dispatch_vehicle_options_secure(
  integer, integer, text
) from public, anon;
revoke all on function public.tms_get_dispatch_recommendation_context_secure(
  uuid, timestamptz, integer, integer
) from public, anon;

grant execute on function public.vms_list_vehicle_archives_secure(
  integer, integer, uuid, uuid, text, text, text, text, text, text, text, text[],
  timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_archive_secure(uuid)
to authenticated, service_role;
grant execute on function public.vms_list_vehicle_archive_options_secure(
  uuid, text, text, uuid[], integer
) to authenticated, service_role;
grant execute on function public.vms_create_vehicle_archive_secure(jsonb)
to authenticated, service_role;
grant execute on function public.vms_update_vehicle_archive_secure(uuid, jsonb)
to authenticated, service_role;
grant execute on function public.vms_get_vehicle_archive_delete_preview_secure(uuid)
to authenticated, service_role;
grant execute on function public.vms_delete_vehicle_archives_secure(uuid[])
to authenticated, service_role;
grant execute on function public.vms_list_dispatch_vehicle_options_secure(
  integer, integer, text
) to authenticated, service_role;
grant execute on function public.tms_get_dispatch_recommendation_context_secure(
  uuid, timestamptz, integer, integer
) to authenticated, service_role;

;
