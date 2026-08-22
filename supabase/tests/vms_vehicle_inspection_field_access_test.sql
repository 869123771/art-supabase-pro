begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fb100000-0000-4000-8000-000000000001', 'qa_inspection_field', 'QA inspection field', '1', 'qa', 'qa'),
  ('fb100000-0000-4000-8000-000000000002', 'qa_inspection_other', 'QA inspection other', '1', 'qa', 'qa');

update public.sys_document_number_rule
set auto_enabled = false
where tenant_id = 'fb100000-0000-4000-8000-000000000001'
  and rule_key = 'vehicle.inspection';

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fb200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-inspection-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-inspection-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-inspection-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-inspection-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-inspection-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fb400000-0000-4000-8000-000000000001', 'QA inspection owner', 'QA_INSPECTION_OWNER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000002', 'QA inspection manager', 'QA_INSPECTION_MANAGER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000003', 'QA inspection viewer', 'QA_INSPECTION_VIEWER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fb300000-0000-4000-8000-000000000001', 'qa-inspection-owner', 'QA Inspection Owner', 'qa-inspection-owner@example.invalid', '1', array['QA_INSPECTION_OWNER']::text[], 'fb200000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000002', 'qa-inspection-manager', 'QA Inspection Manager', 'qa-inspection-manager@example.invalid', '1', array['QA_INSPECTION_MANAGER']::text[], 'fb200000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000003', 'qa-inspection-viewer', 'QA Inspection Viewer', 'qa-inspection-viewer@example.invalid', '1', array['QA_INSPECTION_VIEWER']::text[], 'fb200000-0000-4000-8000-000000000003', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000004', 'qa-inspection-no-menu', 'QA Inspection No Menu', 'qa-inspection-no-menu@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000004', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000005', 'qa-inspection-other', 'QA Inspection Other', 'qa-inspection-other@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000005', 'fb100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fb100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_INSPECTION_OWNER', 'QA_INSPECTION_MANAGER')
  and menu_row.name in (
    'VehicleInspection', 'VehicleInspection:Add', 'VehicleInspection:Edit',
    'VehicleInspection:View', 'VehicleInspection:Delete', 'VehicleInspection:Export'
  )
) or (
  role_row.role_code = 'QA_INSPECTION_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fb100000-0000-4000-8000-000000000001';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values (
  'fb500000-0000-4000-8000-000000000001',
  'fb100000-0000-4000-8000-000000000001', 'QA-CHK-001', 'QA-CHK-VIN-001', 'truck',
  'operating', 'pending', 'fb300000-0000-4000-8000-000000000001',
  'qa-inspection-owner@example.invalid', 'qa-inspection-owner@example.invalid'
);

insert into public.vehicle_insurance_company(
  id, company_name, tenant_id, create_by, update_by
) values
  ('fb600000-0000-4000-8000-000000000001', 'QA inspection insurer', 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb600000-0000-4000-8000-000000000002', 'QA other insurer', 'fb100000-0000-4000-8000-000000000002', 'qa', 'qa');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000001","email":"qa-inspection-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_id uuid;
  v_detail jsonb;
begin
  v_id := public.vms_create_vehicle_inspection_secure(jsonb_build_object(
    'vehicle_id', 'fb500000-0000-4000-8000-000000000001',
    'inspection_no', 'INSPECTION-SECRET-001',
    'inspection_date', '2026-01-01',
    'inspection_amount', 860.50,
    'vehicle_office', 'QA vehicle office',
    'expire_date', '2027-01-01',
    'compulsory_policy_no', 'COMPULSORY-SECRET-001',
    'compulsory_company_id', 'fb600000-0000-4000-8000-000000000001',
    'compulsory_insure_date', '2026-01-01',
    'compulsory_premium', 1200.25,
    'compulsory_expire_date', '2027-01-01',
    'attachments', jsonb_build_array(jsonb_build_object('name', 'secret.pdf', 'url', 'https://example.invalid/secret.pdf'))
  ));
  v_detail := public.vms_get_vehicle_inspection_secure(v_id);
  if v_detail->>'inspection_no' <> 'INSPECTION-SECRET-001'
     or (v_detail->>'inspection_amount')::numeric <> 860.50
     or v_detail->'field_access'->>'inspectionIdentifiers' <> 'edit'
     or (v_detail->>'is_record_owner')::boolean is not true then
    raise exception 'inspection owner override failed';
  end if;

  perform public.vms_update_vehicle_inspection_secure(
    v_id, jsonb_build_object('inspection_amount', 960.50)
  );
  if (public.vms_get_vehicle_inspection_secure(v_id)->>'inspection_amount')::numeric <> 960.50 then
    raise exception 'inspection owner could not update a protected amount';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000003","email":"qa-inspection-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
  v_context jsonb;
begin
  v_list := public.vms_list_vehicle_inspections_secure(
    p_from => 0, p_to => 9, p_vehicle_id => 'fb500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1 then
    raise exception 'vehicle query did not return inspection lifecycle data';
  end if;
  if (v_list->'records'->0) ? 'inspection_no'
     or (v_list->'records'->0) ? 'inspection_amount'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'hidden inspection fields leaked through list';
  end if;

  v_list := public.vms_list_vehicle_inspections_secure(
    p_inspection_no => 'INSPECTION-SECRET-001'
  );
  if jsonb_array_length(v_list->'records') <> 0 then
    raise exception 'hidden inspection number remained searchable';
  end if;

  v_context := public.vms_get_vehicle_inspection_expiry_context_secure(
    p_vehicle_id => 'fb500000-0000-4000-8000-000000000001', p_limit => 10
  );
  if jsonb_array_length(v_context) <> 1
     or (v_context->0) ? 'inspection_no'
     or (v_context->0) ? 'inspection_amount' then
    raise exception 'inspection AI context leaked protected fields';
  end if;

  begin
    perform (select inspection_no from public.vehicle_inspection limit 1);
    raise exception 'direct inspection select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000002","email":"qa-inspection-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_id uuid;
begin
  v_id := (
    public.vms_list_vehicle_inspections_secure(
      p_from => 0, p_to => 9, p_plate_no => 'QA-CHK-001'
    )->'records'->0->>'id'
  )::uuid;
  perform public.vms_update_vehicle_inspection_secure(v_id, jsonb_build_object('remark', 'safe manager update'));

  begin
    perform public.vms_update_vehicle_inspection_secure(v_id, jsonb_build_object('inspection_amount', 1));
    raise exception 'manager unexpectedly updated a hidden inspection amount';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_inspection_secure(
      v_id, jsonb_build_object('compulsory_company_id', 'fb600000-0000-4000-8000-000000000002')
    );
    raise exception 'cross-tenant inspection company reference unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000004","email":"qa-inspection-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_inspections_secure();
    raise exception 'inspection list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.vehicle_inspection set remark = 'direct leak';
    raise exception 'direct inspection update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_inspections_secure(integer,integer,uuid,text,text,text,date,date,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure inspection list';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_inspection', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_inspection', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_inspection', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_inspection', 'delete') then
    raise exception 'authenticated retained direct inspection table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_inspection_field_access_regression_passed' as result;
