begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fb100000-0000-4000-8000-000000000001', 'qa_mileage_field', 'QA mileage field', '1', 'qa', 'qa'),
  ('fb100000-0000-4000-8000-000000000002', 'qa_mileage_other', 'QA mileage other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fb200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-mileage-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-mileage-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-mileage-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-mileage-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-mileage-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fb400000-0000-4000-8000-000000000001', 'QA mileage owner', 'QA_MILEAGE_OWNER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000002', 'QA mileage manager', 'QA_MILEAGE_MANAGER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000003', 'QA mileage viewer', 'QA_MILEAGE_VIEWER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fb300000-0000-4000-8000-000000000001', 'qa-mileage-owner', 'QA Mileage Owner', 'qa-mileage-owner@example.invalid', '1', array['QA_MILEAGE_OWNER']::text[], 'fb200000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000002', 'qa-mileage-manager', 'QA Mileage Manager', 'qa-mileage-manager@example.invalid', '1', array['QA_MILEAGE_MANAGER']::text[], 'fb200000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000003', 'qa-mileage-viewer', 'QA Mileage Viewer', 'qa-mileage-viewer@example.invalid', '1', array['QA_MILEAGE_VIEWER']::text[], 'fb200000-0000-4000-8000-000000000003', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000004', 'qa-mileage-no-menu', 'QA Mileage No Menu', 'qa-mileage-no-menu@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000004', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000005', 'qa-mileage-other', 'QA Mileage Other', 'qa-mileage-other@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000005', 'fb100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fb100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_MILEAGE_OWNER', 'QA_MILEAGE_MANAGER')
  and menu_row.name in ('VehicleMileage', 'VehicleMileage:Export')
) or (
  role_row.role_code = 'QA_MILEAGE_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fb100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fb100000-0000-4000-8000-000000000001',
  'fb400000-0000-4000-8000-000000000002',
  resource_row.id,
  field_row.id,
  'masked',
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fb100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_mileage';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fb500000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'QA-MIL-001', 'QA-MIL-VIN-001', 'truck', 'operating', 'pending', 'fb300000-0000-4000-8000-000000000001', 'qa-mileage-owner@example.invalid', 'qa-mileage-owner@example.invalid'),
  ('fb500000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000002', 'QA-MIL-OTHER', 'QA-MIL-VIN-OTHER', 'truck', 'operating', 'pending', 'fb300000-0000-4000-8000-000000000005', 'qa-mileage-other@example.invalid', 'qa-mileage-other@example.invalid');

insert into public.vehicle_mileage_record(
  id, tenant_id, vehicle_id, plate_no, company_name,
  start_time, end_time, start_mileage, end_mileage, running_mileage,
  create_by, update_by
) values
  ('fb600000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'fb500000-0000-4000-8000-000000000001', 'QA-MIL-001', 'QA Company', '2026-08-22 08:00:00+08', '2026-08-22 12:00:00+08', 10000, 10320, 320, 'qa-mileage-owner@example.invalid', 'qa-mileage-owner@example.invalid'),
  ('fb600000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000002', 'fb500000-0000-4000-8000-000000000002', 'QA-MIL-OTHER', 'Other Company', '2026-08-21 08:00:00+08', '2026-08-21 09:00:00+08', 20000, 20080, 80, 'qa-mileage-other@example.invalid', 'qa-mileage-other@example.invalid');

do $qa$
begin
  if (select created_by_user_id from public.vehicle_mileage_record where id = 'fb600000-0000-4000-8000-000000000001') <> 'fb300000-0000-4000-8000-000000000001' then
    raise exception 'mileage creator identity was not resolved';
  end if;
  begin
    update public.vehicle_mileage_record
    set created_by_user_id = 'fb300000-0000-4000-8000-000000000002'
    where id = 'fb600000-0000-4000-8000-000000000001';
    raise exception 'mileage creator identity was mutable';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000001","email":"qa-mileage-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_list jsonb;
  v_health jsonb;
begin
  v_list := public.vms_list_vehicle_mileage_secure(p_plate_no => 'QA-MIL-001');
  if jsonb_array_length(v_list->'records') <> 1
     or (v_list->'records'->0->>'start_mileage')::numeric <> 10000
     or (v_list->'records'->0->>'end_mileage')::numeric <> 10320
     or v_list->'records'->0->'field_access'->>'mileageValues' <> 'edit'
     or (v_list->'records'->0->>'is_record_owner')::boolean is not true then
    raise exception 'mileage owner override failed';
  end if;

  v_health := public.vms_get_vehicle_mileage_health_context_secure(
    'fb500000-0000-4000-8000-000000000001', 60
  );
  if jsonb_array_length(v_health) <> 1
     or (v_health->0->>'running_mileage')::numeric <> 320 then
    raise exception 'mileage owner health context failed';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000002","email":"qa-mileage-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_export jsonb;
begin
  v_list := public.vms_list_vehicle_mileage_secure(p_plate_no => 'QA-MIL-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'start_time' <> '***'
     or v_list->'records'->0->>'end_time' <> '***'
     or v_list->'records'->0->>'start_mileage' <> '***'
     or v_list->'records'->0->>'end_mileage' <> '***'
     or v_list->'records'->0->>'running_mileage' <> '***' then
    raise exception 'mileage field masking failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_mileage_secure(
    p_start_time_from => '2026-08-22 00:00:00+08'
  )->'records') <> 0 then
    raise exception 'masked mileage timeline remained filterable';
  end if;

  v_export := public.vms_list_vehicle_mileage_secure(
    p_from => 0, p_to => 99, p_plate_no => 'QA-MIL-001', p_purpose => 'export'
  );
  if v_export->'records'->0->>'running_mileage' <> '***'
     or v_export->'records'->0->>'start_time' <> '***' then
    raise exception 'mileage export leaked protected fields';
  end if;

  if jsonb_array_length(public.vms_get_vehicle_mileage_health_context_secure(
    'fb500000-0000-4000-8000-000000000001', 60
  )) <> 0 then
    raise exception 'mileage health context leaked masked values';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000003","email":"qa-mileage-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_mileage_secure(
    p_vehicle_id => 'fb500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1
     or (v_list->'records'->0) ? 'start_time'
     or (v_list->'records'->0) ? 'end_time'
     or (v_list->'records'->0) ? 'start_mileage'
     or (v_list->'records'->0) ? 'end_mileage'
     or (v_list->'records'->0) ? 'running_mileage' then
    raise exception 'vehicle query leaked protected mileage fields';
  end if;

  begin
    perform (select running_mileage from public.vehicle_mileage_record limit 1);
    raise exception 'direct mileage select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000004","email":"qa-mileage-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_mileage_secure();
    raise exception 'mileage list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.vehicle_mileage_record(
      plate_no, tenant_id, created_by_user_id
    ) values (
      'DIRECT', 'fb100000-0000-4000-8000-000000000001',
      'fb300000-0000-4000-8000-000000000004'
    );
    raise exception 'direct mileage insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_mileage_secure(integer,integer,uuid,text,text,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.vms_get_vehicle_mileage_health_context_secure(uuid,integer)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure mileage functions';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_mileage_record', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_mileage_record', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_mileage_record', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_mileage_record', 'delete') then
    raise exception 'authenticated retained direct mileage table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_mileage_field_access_regression_passed' as result;
