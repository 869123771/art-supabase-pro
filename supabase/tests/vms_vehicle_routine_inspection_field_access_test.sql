begin;

insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by) values
  ('fa100000-0000-4000-8000-000000000001', 'qa_routine_field', 'QA routine field', '1', 'qa', 'qa'),
  ('fa100000-0000-4000-8000-000000000002', 'qa_routine_other', 'QA routine other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fa200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-routine-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-routine-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-routine-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-routine-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-routine-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(id, role_name, role_code, enabled, tenant_id, create_by, update_by) values
  ('fa400000-0000-4000-8000-000000000001', 'QA routine owner', 'QA_ROUTINE_OWNER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fa400000-0000-4000-8000-000000000002', 'QA routine manager', 'QA_ROUTINE_MANAGER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fa400000-0000-4000-8000-000000000003', 'QA routine viewer', 'QA_ROUTINE_VIEWER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fa300000-0000-4000-8000-000000000001', 'qa-routine-owner', 'QA Routine Owner', 'qa-routine-owner@example.invalid', '1', array['QA_ROUTINE_OWNER']::text[], 'fa200000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000002', 'qa-routine-manager', 'QA Routine Manager', 'qa-routine-manager@example.invalid', '1', array['QA_ROUTINE_MANAGER']::text[], 'fa200000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000003', 'qa-routine-viewer', 'QA Routine Viewer', 'qa-routine-viewer@example.invalid', '1', array['QA_ROUTINE_VIEWER']::text[], 'fa200000-0000-4000-8000-000000000003', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000004', 'qa-routine-no-menu', 'QA Routine No Menu', 'qa-routine-no-menu@example.invalid', '1', array[]::text[], 'fa200000-0000-4000-8000-000000000004', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000005', 'qa-routine-other', 'QA Routine Other', 'qa-routine-other@example.invalid', '1', array[]::text[], 'fa200000-0000-4000-8000-000000000005', 'fa100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(tenant_id, role_id, menu_id, permission, create_by, update_by)
select 'fa100000-0000-4000-8000-000000000001', role_row.id, menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_ROUTINE_OWNER', 'QA_ROUTINE_MANAGER')
  and menu_row.name in (
    'VehicleRoutineInspection', 'VehicleRoutineInspection:Add',
    'VehicleRoutineInspection:View', 'VehicleRoutineInspection:Edit',
    'VehicleRoutineInspection:Delete', 'VehicleRoutineInspection:Export'
  )
) or (
  role_row.role_code = 'QA_ROUTINE_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fa100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fa100000-0000-4000-8000-000000000001',
  'fa400000-0000-4000-8000-000000000002',
  resource_row.id, field_row.id,
  case field_row.field_key
    when 'responsiblePeople' then 'masked'
    when 'inspectionFindings' then 'read'
    when 'remediationDetails' then 'masked'
    else 'hidden'
  end,
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fa100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_routine_inspection';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fa500000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000001', 'QA-RTN-001', 'QA-RTN-VIN-001', 'truck', 'operating', 'pending', 'fa300000-0000-4000-8000-000000000001', 'qa-routine-owner@example.invalid', 'qa-routine-owner@example.invalid'),
  ('fa500000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000002', 'QA-RTN-OTHER', 'QA-RTN-VIN-OTHER', 'truck', 'operating', 'pending', 'fa300000-0000-4000-8000-000000000005', 'qa-routine-other@example.invalid', 'qa-routine-other@example.invalid');

insert into public.vehicle_routine_inspection_record(
  id, tenant_id, vehicle_id, plate_no, company_name, routine_inspection_no,
  inspection_type, inspection_time, inspector, driver_name, check_condition,
  check_result, handling_method, remark, attachments, create_by, update_by
) values
  ('fa600000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000001', 'fa500000-0000-4000-8000-000000000001', 'QA-RTN-001', 'QA Company', 'QA-RTN-NO-001', 'daily', '2026-08-22 08:00:00+08', 'Owner Inspector', 'Owner Driver', 'SECRET-FAILED-CONDITION', 'unqualified', 'SECRET-HANDLING', 'SECRET-REMARK', '[{"name":"SECRET-DOCUMENT","url":"https://example.invalid/secret"}]'::jsonb, 'qa-routine-owner@example.invalid', 'qa-routine-owner@example.invalid'),
  ('fa600000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000002', 'fa500000-0000-4000-8000-000000000002', 'QA-RTN-OTHER', 'Other Company', 'QA-RTN-OTHER-001', 'daily', '2026-08-21 08:00:00+08', 'Other Inspector', 'Other Driver', 'OTHER-CONDITION', 'unqualified', 'OTHER-HANDLING', 'OTHER-REMARK', '[]'::jsonb, 'qa-routine-other@example.invalid', 'qa-routine-other@example.invalid');

do $qa$
begin
  if (select created_by_user_id from public.vehicle_routine_inspection_record where id = 'fa600000-0000-4000-8000-000000000001') <> 'fa300000-0000-4000-8000-000000000001' then
    raise exception 'routine inspection creator identity was not resolved';
  end if;
end;
$qa$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000001","email":"qa-routine-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_list jsonb;
  v_created_id uuid;
  v_created jsonb;
begin
  v_list := public.vms_list_vehicle_routine_inspections_secure(p_plate_no => 'QA-RTN-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'inspector' <> 'Owner Inspector'
     or v_list->'records'->0->>'check_condition' <> 'SECRET-FAILED-CONDITION'
     or v_list->'records'->0->'field_access'->>'documents' <> 'edit'
     or (v_list->'records'->0->>'is_record_owner')::boolean is not true then
    raise exception 'routine inspection owner override failed';
  end if;

  v_created_id := public.vms_create_vehicle_routine_inspection_secure(jsonb_build_object(
    'vehicle_id', 'fa500000-0000-4000-8000-000000000001',
    'routine_inspection_no', 'QA-RTN-CREATED',
    'inspection_type', 'daily',
    'inspection_time', '2026-08-23 08:00:00+08',
    'inspector', 'Created Inspector',
    'check_result', 'qualified',
    'attachments', '[]'::jsonb
  ));
  v_created := public.vms_get_vehicle_routine_inspection_secure(v_created_id);
  if (v_created->>'is_record_owner')::boolean is not true
     or v_created->>'inspector' <> 'Created Inspector' then
    raise exception 'secure routine inspection create lost creator identity';
  end if;
  if public.vms_delete_vehicle_routine_inspections_secure(array[v_created_id]) <> 1 then
    raise exception 'routine inspection owner delete failed';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000002","email":"qa-routine-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_export jsonb;
  v_health jsonb;
begin
  v_list := public.vms_list_vehicle_routine_inspections_secure(p_plate_no => 'QA-RTN-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'inspector' <> '***'
     or v_list->'records'->0->>'driver_name' <> '***'
     or v_list->'records'->0->>'check_condition' <> 'SECRET-FAILED-CONDITION'
     or v_list->'records'->0->>'handling_method' <> '***'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'routine inspection field filtering failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_routine_inspections_secure(
    p_check_result => 'unqualified'
  )->'records') <> 1 then
    raise exception 'readable routine inspection finding was not filterable';
  end if;

  v_export := public.vms_list_vehicle_routine_inspections_secure(
    p_from => 0, p_to => 99, p_plate_no => 'QA-RTN-001', p_purpose => 'export'
  );
  if v_export->'records'->0->>'inspector' <> '***'
     or v_export->'records'->0->>'handling_method' <> '***'
     or (v_export->'records'->0) ? 'attachments' then
    raise exception 'routine inspection export leaked protected fields';
  end if;

  v_health := public.vms_get_vehicle_routine_inspection_health_context_secure(
    'fa500000-0000-4000-8000-000000000001', 100
  );
  if jsonb_array_length(v_health) <> 1
     or v_health->0->>'check_condition' <> 'SECRET-FAILED-CONDITION' then
    raise exception 'routine inspection health context did not honor readable findings';
  end if;

  perform public.vms_update_vehicle_routine_inspection_secure(
    'fa600000-0000-4000-8000-000000000001', '{"inspection_type":"monthly"}'::jsonb
  );
  begin
    perform public.vms_update_vehicle_routine_inspection_secure(
      'fa600000-0000-4000-8000-000000000001',
      '{"check_condition":"UNAUTHORIZED-CHANGE"}'::jsonb
    );
    raise exception 'routine inspection protected finding was editable without permission';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000003","email":"qa-routine-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_routine_inspections_secure(
    p_vehicle_id => 'fa500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1
     or (v_list->'records'->0) ? 'inspector'
     or (v_list->'records'->0) ? 'check_result'
     or (v_list->'records'->0) ? 'handling_method'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'vehicle query leaked protected routine inspection fields';
  end if;
  if jsonb_array_length(public.vms_get_vehicle_routine_inspection_health_context_secure(
    'fa500000-0000-4000-8000-000000000001', 100
  )) <> 0 then
    raise exception 'routine inspection health context leaked hidden findings';
  end if;
  begin
    perform (select check_condition from public.vehicle_routine_inspection_record limit 1);
    raise exception 'direct routine inspection select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000004","email":"qa-routine-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_routine_inspections_secure();
    raise exception 'routine inspection list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.vehicle_routine_inspection_record(
      tenant_id, plate_no, routine_inspection_no, inspection_time,
      created_by_user_id, check_result
    ) values (
      'fa100000-0000-4000-8000-000000000001', 'DIRECT', 'DIRECT', now(),
      'fa300000-0000-4000-8000-000000000004', 'qualified'
    );
    raise exception 'direct routine inspection insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_routine_inspections_secure(integer,integer,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) or has_function_privilege(
    'anon', 'public.vms_get_vehicle_routine_inspection_secure(uuid)', 'execute'
  ) or has_function_privilege(
    'anon', 'public.vms_get_vehicle_routine_inspection_health_context_secure(uuid,integer)', 'execute'
  ) then
    raise exception 'anon retained execute on secure routine inspection functions';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_routine_inspection_record', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_routine_inspection_record', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_routine_inspection_record', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_routine_inspection_record', 'delete') then
    raise exception 'authenticated retained direct routine inspection table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_routine_inspection_field_access_regression_passed' as result;
