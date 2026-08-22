begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fe100000-0000-4000-8000-000000000001', 'qa_violation_field', 'QA violation field', '1', 'qa', 'qa'),
  ('fe100000-0000-4000-8000-000000000002', 'qa_violation_other', 'QA violation other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fe200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-violation-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fe200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-violation-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fe200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-violation-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fe200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-violation-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fe200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-violation-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fe400000-0000-4000-8000-000000000001', 'QA violation owner', 'QA_VIOLATION_OWNER', true, 'fe100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fe400000-0000-4000-8000-000000000002', 'QA violation manager', 'QA_VIOLATION_MANAGER', true, 'fe100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fe400000-0000-4000-8000-000000000003', 'QA violation viewer', 'QA_VIOLATION_VIEWER', true, 'fe100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fe300000-0000-4000-8000-000000000001', 'qa-violation-owner', 'QA Violation Owner', 'qa-violation-owner@example.invalid', '1', array['QA_VIOLATION_OWNER']::text[], 'fe200000-0000-4000-8000-000000000001', 'fe100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fe300000-0000-4000-8000-000000000002', 'qa-violation-manager', 'QA Violation Manager', 'qa-violation-manager@example.invalid', '1', array['QA_VIOLATION_MANAGER']::text[], 'fe200000-0000-4000-8000-000000000002', 'fe100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fe300000-0000-4000-8000-000000000003', 'qa-violation-viewer', 'QA Violation Viewer', 'qa-violation-viewer@example.invalid', '1', array['QA_VIOLATION_VIEWER']::text[], 'fe200000-0000-4000-8000-000000000003', 'fe100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fe300000-0000-4000-8000-000000000004', 'qa-violation-no-menu', 'QA Violation No Menu', 'qa-violation-no-menu@example.invalid', '1', array[]::text[], 'fe200000-0000-4000-8000-000000000004', 'fe100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fe300000-0000-4000-8000-000000000005', 'qa-violation-other', 'QA Violation Other', 'qa-violation-other@example.invalid', '1', array[]::text[], 'fe200000-0000-4000-8000-000000000005', 'fe100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fe100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_VIOLATION_OWNER', 'QA_VIOLATION_MANAGER')
  and menu_row.name in ('VehicleViolation', 'VehicleViolation:Export')
) or (
  role_row.role_code = 'QA_VIOLATION_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fe100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fe100000-0000-4000-8000-000000000001',
  'fe400000-0000-4000-8000-000000000002',
  resource_row.id,
  field_row.id,
  case field_row.field_key
    when 'driverIdentity' then 'masked'
    when 'violationLocation' then 'masked'
    when 'violationNarrative' then 'read'
    when 'penaltyAmounts' then 'masked'
  end,
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fe100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_violation';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fe500000-0000-4000-8000-000000000001', 'fe100000-0000-4000-8000-000000000001', 'QA-VIO-001', 'QA-VIO-VIN-001', 'truck', 'operating', 'pending', 'fe300000-0000-4000-8000-000000000001', 'qa-violation-owner@example.invalid', 'qa-violation-owner@example.invalid'),
  ('fe500000-0000-4000-8000-000000000002', 'fe100000-0000-4000-8000-000000000002', 'QA-VIO-OTHER', 'QA-VIO-VIN-OTHER', 'truck', 'operating', 'pending', 'fe300000-0000-4000-8000-000000000005', 'qa-violation-other@example.invalid', 'qa-violation-other@example.invalid');

insert into public.vehicle_violation_record(
  id, tenant_id, vehicle_id, plate_no, company_name, driver_name,
  violation_behavior, violation_time, violation_location, penalty_points,
  fine_amount, processed, remark, create_by, update_by
) values
  ('fe600000-0000-4000-8000-000000000001', 'fe100000-0000-4000-8000-000000000001', 'fe500000-0000-4000-8000-000000000001', 'QA-VIO-001', 'QA Company', 'Owner Driver', 'SECRET-VIOLATION-BEHAVIOR', '2026-08-22 09:00:00+08', 'Shanghai Secret Road 100', 6, 1200, false, 'SECRET-VIOLATION-REMARK', 'qa-violation-owner@example.invalid', 'qa-violation-owner@example.invalid'),
  ('fe600000-0000-4000-8000-000000000002', 'fe100000-0000-4000-8000-000000000001', 'fe500000-0000-4000-8000-000000000001', 'QA-VIO-SYSTEM', 'QA Company', 'System Driver', 'SYSTEM-VIOLATION-BEHAVIOR', '2026-08-21 09:00:00+08', 'Shanghai System Road 200', 3, 500, true, 'SYSTEM-VIOLATION-REMARK', 'external-system', 'external-system'),
  ('fe600000-0000-4000-8000-000000000003', 'fe100000-0000-4000-8000-000000000002', 'fe500000-0000-4000-8000-000000000002', 'QA-VIO-OTHER', 'Other Company', 'Other Driver', 'OTHER-VIOLATION', '2026-08-20 09:00:00+08', 'Other Road', 2, 200, false, 'OTHER-REMARK', 'qa-violation-other@example.invalid', 'qa-violation-other@example.invalid');

do $qa$
begin
  if (select created_by_user_id from public.vehicle_violation_record where id = 'fe600000-0000-4000-8000-000000000001') <> 'fe300000-0000-4000-8000-000000000001' then
    raise exception 'violation creator identity was not resolved';
  end if;
  if (select created_by_user_id from public.vehicle_violation_record where id = 'fe600000-0000-4000-8000-000000000002') is not null then
    raise exception 'system-imported violation unexpectedly required a human creator';
  end if;
end;
$qa$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fe200000-0000-4000-8000-000000000001","email":"qa-violation-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fe200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_violations_secure(p_plate_no => 'QA-VIO-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'driver_name' <> 'Owner Driver'
     or v_list->'records'->0->>'violation_behavior' <> 'SECRET-VIOLATION-BEHAVIOR'
     or (v_list->'records'->0->>'fine_amount')::numeric <> 1200
     or v_list->'records'->0->'field_access'->>'penaltyAmounts' <> 'edit'
     or (v_list->'records'->0->>'is_record_owner')::boolean is not true then
    raise exception 'violation owner override failed';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fe200000-0000-4000-8000-000000000002","email":"qa-violation-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fe200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_export jsonb;
begin
  v_list := public.vms_list_vehicle_violations_secure(p_plate_no => 'QA-VIO-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'driver_name' <> '***'
     or v_list->'records'->0->>'violation_location' <> 'Shangh***'
     or v_list->'records'->0->>'violation_behavior' <> 'SECRET-VIOLATION-BEHAVIOR'
     or v_list->'records'->0->>'remark' <> 'SECRET-VIOLATION-REMARK'
     or v_list->'records'->0->>'penalty_points' <> '***'
     or v_list->'records'->0->>'fine_amount' <> '***' then
    raise exception 'violation field filtering failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_violations_secure(
    p_driver_name => 'Owner Driver'
  )->'records') <> 0 then
    raise exception 'masked violation driver remained searchable';
  end if;
  if jsonb_array_length(public.vms_list_vehicle_violations_secure(
    p_violation_behavior => 'SECRET-VIOLATION-BEHAVIOR'
  )->'records') <> 1 then
    raise exception 'readable violation narrative was not searchable';
  end if;

  v_export := public.vms_list_vehicle_violations_secure(
    p_from => 0, p_to => 99, p_plate_no => 'QA-VIO-001', p_purpose => 'export'
  );
  if v_export->'records'->0->>'fine_amount' <> '***'
     or v_export->'records'->0->>'driver_name' <> '***' then
    raise exception 'violation export leaked protected fields';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fe200000-0000-4000-8000-000000000003","email":"qa-violation-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fe200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_violations_secure(
    p_vehicle_id => 'fe500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 2
     or (v_list->'records'->0) ? 'driver_name'
     or (v_list->'records'->0) ? 'violation_location'
     or (v_list->'records'->0) ? 'violation_behavior'
     or (v_list->'records'->0) ? 'penalty_points'
     or (v_list->'records'->0) ? 'fine_amount' then
    raise exception 'vehicle query leaked protected violation fields';
  end if;

  begin
    perform (select violation_behavior from public.vehicle_violation_record limit 1);
    raise exception 'direct violation select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fe200000-0000-4000-8000-000000000004","email":"qa-violation-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fe200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_violations_secure();
    raise exception 'violation list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.vehicle_violation_record(
      plate_no, violation_behavior, violation_time, processed, tenant_id
    ) values ('DIRECT', 'DIRECT', now(), false, 'fe100000-0000-4000-8000-000000000001');
    raise exception 'direct violation insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_violations_secure(integer,integer,uuid,text,text,text,text,boolean,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure violation list';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_violation_record', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_violation_record', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_violation_record', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_violation_record', 'delete') then
    raise exception 'authenticated retained direct violation table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_violation_field_access_regression_passed' as result;
