begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fd100000-0000-4000-8000-000000000001', 'qa_accident_field', 'QA accident field', '1', 'qa', 'qa'),
  ('fd100000-0000-4000-8000-000000000002', 'qa_accident_other', 'QA accident other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fd200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-accident-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fd200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-accident-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fd200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-accident-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fd200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-accident-smis@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fd200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-accident-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fd200000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'qa-accident-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fd400000-0000-4000-8000-000000000001', 'QA accident owner', 'QA_ACCIDENT_OWNER', true, 'fd100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fd400000-0000-4000-8000-000000000002', 'QA accident manager', 'QA_ACCIDENT_MANAGER', true, 'fd100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fd400000-0000-4000-8000-000000000003', 'QA accident viewer', 'QA_ACCIDENT_VIEWER', true, 'fd100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fd400000-0000-4000-8000-000000000004', 'QA accident SMIS', 'QA_ACCIDENT_SMIS', true, 'fd100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fd300000-0000-4000-8000-000000000001', 'qa-accident-owner', 'QA Accident Owner', 'qa-accident-owner@example.invalid', '1', array['QA_ACCIDENT_OWNER']::text[], 'fd200000-0000-4000-8000-000000000001', 'fd100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fd300000-0000-4000-8000-000000000002', 'qa-accident-manager', 'QA Accident Manager', 'qa-accident-manager@example.invalid', '1', array['QA_ACCIDENT_MANAGER']::text[], 'fd200000-0000-4000-8000-000000000002', 'fd100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fd300000-0000-4000-8000-000000000003', 'qa-accident-viewer', 'QA Accident Viewer', 'qa-accident-viewer@example.invalid', '1', array['QA_ACCIDENT_VIEWER']::text[], 'fd200000-0000-4000-8000-000000000003', 'fd100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fd300000-0000-4000-8000-000000000004', 'qa-accident-smis', 'QA Accident SMIS', 'qa-accident-smis@example.invalid', '1', array['QA_ACCIDENT_SMIS']::text[], 'fd200000-0000-4000-8000-000000000004', 'fd100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fd300000-0000-4000-8000-000000000005', 'qa-accident-no-menu', 'QA Accident No Menu', 'qa-accident-no-menu@example.invalid', '1', array[]::text[], 'fd200000-0000-4000-8000-000000000005', 'fd100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fd300000-0000-4000-8000-000000000006', 'qa-accident-other', 'QA Accident Other', 'qa-accident-other@example.invalid', '1', array[]::text[], 'fd200000-0000-4000-8000-000000000006', 'fd100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fd100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_ACCIDENT_OWNER', 'QA_ACCIDENT_MANAGER')
  and menu_row.name in (
    'VehicleAccident', 'VehicleAccident:Add', 'VehicleAccident:Edit',
    'VehicleAccident:View', 'VehicleAccident:Delete', 'VehicleAccident:Export'
  )
) or (
  role_row.role_code = 'QA_ACCIDENT_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
) or (
  role_row.role_code = 'QA_ACCIDENT_SMIS'
  and menu_row.name in ('SmisAccidentEmergency', 'SmisAccidentEmergency:View')
)
where role_row.tenant_id = 'fd100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fd100000-0000-4000-8000-000000000001',
  'fd400000-0000-4000-8000-000000000002',
  resource_row.id,
  field_row.id,
  case field_row.field_key
    when 'driverContact' then 'masked'
    when 'accidentLocation' then 'read'
    when 'lossAmounts' then 'read'
    else 'hidden'
  end,
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fd100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_accident';

insert into public.sys_user_field_permission(
  tenant_id, user_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fd100000-0000-4000-8000-000000000001',
  'fd300000-0000-4000-8000-000000000002',
  resource_row.id,
  field_row.id,
  'hidden', 'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fd100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_accident'
  and field_row.field_key = 'lossAmounts';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fd500000-0000-4000-8000-000000000001', 'fd100000-0000-4000-8000-000000000001', 'QA-ACC-001', 'QA-ACC-VIN-001', 'truck', 'operating', 'pending', 'fd300000-0000-4000-8000-000000000001', 'qa-accident-owner@example.invalid', 'qa-accident-owner@example.invalid'),
  ('fd500000-0000-4000-8000-000000000002', 'fd100000-0000-4000-8000-000000000002', 'QA-ACC-OTHER', 'QA-ACC-VIN-OTHER', 'truck', 'operating', 'pending', 'fd300000-0000-4000-8000-000000000006', 'qa-accident-other@example.invalid', 'qa-accident-other@example.invalid');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fd200000-0000-4000-8000-000000000001","email":"qa-accident-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fd200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_id uuid;
  v_detail jsonb;
begin
  v_id := public.vms_create_vehicle_accident_secure(jsonb_build_object(
    'vehicle_id', 'fd500000-0000-4000-8000-000000000001',
    'driver_name', 'Owner Driver',
    'driver_phone', '13800138000',
    'accident_time', '2026-08-22 09:00:00+08',
    'accident_location', 'Shanghai Secret Road 100',
    'accident_longitude', 121.4737,
    'accident_latitude', 31.2304,
    'accident_summary', 'SECRET-ACCIDENT-NARRATIVE',
    'damage_level', 'major',
    'responsibility_type', 'full',
    'responsibility_percent', 100,
    'company_bear_amount', 3000,
    'economic_loss', 8000,
    'reported', true,
    'insurance_reported', true,
    'processed', false,
    'data_source', 'self',
    'remark', 'SECRET-ACCIDENT-REMARK',
    'attachments', jsonb_build_array(jsonb_build_object(
      'name', 'evidence.jpg', 'url', 'https://example.invalid/evidence.jpg'
    ))
  ));
  v_detail := public.vms_get_vehicle_accident_secure(v_id);
  if v_detail->>'driver_phone' <> '13800138000'
     or v_detail->>'accident_summary' <> 'SECRET-ACCIDENT-NARRATIVE'
     or (v_detail->>'economic_loss')::numeric <> 8000
     or jsonb_array_length(v_detail->'attachments') <> 1
     or v_detail->'field_access'->>'lossAmounts' <> 'edit'
     or (v_detail->>'is_record_owner')::boolean is not true then
    raise exception 'accident owner override failed';
  end if;

  perform public.vms_update_vehicle_accident_secure(
    v_id, jsonb_build_object('economic_loss', 9000)
  );
  if (public.vms_get_vehicle_accident_secure(v_id)->>'economic_loss')::numeric <> 9000 then
    raise exception 'accident owner could not update protected loss amount';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fd200000-0000-4000-8000-000000000002","email":"qa-accident-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fd200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_id uuid;
begin
  v_list := public.vms_list_vehicle_accidents_secure(p_plate_no => 'QA-ACC-001');
  if jsonb_array_length(v_list->'records') <> 1 then
    raise exception 'accident manager list failed';
  end if;
  if v_list->'records'->0->>'driver_name' <> '***'
     or v_list->'records'->0->>'driver_phone' <> '138****8000'
     or v_list->'records'->0->>'accident_location' <> 'Shanghai Secret Road 100'
     or not ((v_list->'records'->0) ? 'accident_longitude')
     or (v_list->'records'->0) ? 'accident_summary'
     or (v_list->'records'->0) ? 'economic_loss'
     or (v_list->'records'->0) ? 'company_bear_amount'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'accident field filtering or user override failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_accidents_secure(
    p_driver_name => 'Owner Driver'
  )->'records') <> 0 then
    raise exception 'masked accident driver remained searchable';
  end if;

  v_id := (v_list->'records'->0->>'id')::uuid;
  perform public.vms_update_vehicle_accident_secure(v_id, jsonb_build_object('damage_level', 'medium'));

  begin
    perform public.vms_update_vehicle_accident_secure(
      v_id, jsonb_build_object('accident_summary', 'leak')
    );
    raise exception 'manager unexpectedly updated hidden accident narrative';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_accident_secure(v_id, jsonb_build_object('economic_loss', 1));
    raise exception 'user override did not block accident loss update';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_accident_secure(
      v_id, jsonb_build_object('vehicle_id', 'fd500000-0000-4000-8000-000000000002')
    );
    raise exception 'cross-tenant accident vehicle reference unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fd200000-0000-4000-8000-000000000003","email":"qa-accident-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fd200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
  v_context jsonb;
begin
  v_list := public.vms_list_vehicle_accidents_secure(
    p_vehicle_id => 'fd500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1
     or (v_list->'records'->0) ? 'driver_phone'
     or (v_list->'records'->0) ? 'accident_location'
     or (v_list->'records'->0) ? 'accident_summary'
     or (v_list->'records'->0) ? 'economic_loss'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'vehicle query leaked protected accident fields';
  end if;

  v_context := public.vms_get_vehicle_accident_health_context_secure(
    p_vehicle_id => 'fd500000-0000-4000-8000-000000000001', p_limit => 10
  );
  if jsonb_array_length(v_context) <> 1
     or not ((v_context->0) ? 'processed')
     or not ((v_context->0) ? 'damage_level')
     or (v_context->0) ? 'accident_summary'
     or (v_context->0) ? 'economic_loss'
     or (v_context->0) ? 'driver_phone'
     or (v_context->0) ? 'accident_location' then
    raise exception 'accident AI context leaked protected fields';
  end if;

  begin
    perform (select accident_summary from public.vehicle_accident_record limit 1);
    raise exception 'direct accident select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fd200000-0000-4000-8000-000000000004","email":"qa-accident-smis@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fd200000-0000-4000-8000-000000000004', true);

do $qa$
declare
  v_options jsonb;
begin
  v_options := public.vms_list_vehicle_accident_options_secure(null, 100);
  if jsonb_array_length(v_options) <> 1
     or (v_options->0) ? 'accident_location'
     or (v_options->0) ? 'accident_summary'
     or (v_options->0) ? 'economic_loss' then
    raise exception 'SMIS accident options leaked protected VMS fields';
  end if;
  if jsonb_array_length(public.vms_list_vehicle_accident_options_secure(
    'SECRET-ACCIDENT-NARRATIVE', 100
  )) <> 0 then
    raise exception 'hidden accident narrative remained searchable from SMIS';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fd200000-0000-4000-8000-000000000005","email":"qa-accident-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fd200000-0000-4000-8000-000000000005', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_accidents_secure();
    raise exception 'accident list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_list_vehicle_accident_options_secure(null, 100);
    raise exception 'SMIS accident options unexpectedly allowed without the SMIS menu';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.vehicle_accident_record set damage_level = 'direct leak';
    raise exception 'direct accident update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_accidents_secure(integer,integer,uuid,text,text,text,boolean,text,timestamptz,timestamptz,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure accident list';
  end if;
  if has_function_privilege(
    'anon', 'public.vms_list_vehicle_accident_options_secure(text,integer)', 'execute'
  ) then
    raise exception 'anon retained execute on secure accident options';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_accident_record', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_accident_record', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_accident_record', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_accident_record', 'delete') then
    raise exception 'authenticated retained direct accident table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_accident_field_access_regression_passed' as result;
