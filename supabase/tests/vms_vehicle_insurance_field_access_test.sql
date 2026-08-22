begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fa100000-0000-4000-8000-000000000001', 'qa_insurance_field', 'QA insurance field', '1', 'qa', 'qa'),
  ('fa100000-0000-4000-8000-000000000002', 'qa_insurance_other', 'QA insurance other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fa200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-insurance-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-insurance-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-insurance-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-insurance-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fa200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-insurance-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fa400000-0000-4000-8000-000000000001', 'QA insurance owner', 'QA_INSURANCE_OWNER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fa400000-0000-4000-8000-000000000002', 'QA insurance manager', 'QA_INSURANCE_MANAGER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fa400000-0000-4000-8000-000000000003', 'QA insurance viewer', 'QA_INSURANCE_VIEWER', true, 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fa300000-0000-4000-8000-000000000001', 'qa-insurance-owner', 'QA Insurance Owner', 'qa-insurance-owner@example.invalid', '1', array['QA_INSURANCE_OWNER']::text[], 'fa200000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000002', 'qa-insurance-manager', 'QA Insurance Manager', 'qa-insurance-manager@example.invalid', '1', array['QA_INSURANCE_MANAGER']::text[], 'fa200000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000003', 'qa-insurance-viewer', 'QA Insurance Viewer', 'qa-insurance-viewer@example.invalid', '1', array['QA_INSURANCE_VIEWER']::text[], 'fa200000-0000-4000-8000-000000000003', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000004', 'qa-insurance-no-menu', 'QA Insurance No Menu', 'qa-insurance-no-menu@example.invalid', '1', array[]::text[], 'fa200000-0000-4000-8000-000000000004', 'fa100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fa300000-0000-4000-8000-000000000005', 'qa-insurance-other', 'QA Insurance Other', 'qa-insurance-other@example.invalid', '1', array[]::text[], 'fa200000-0000-4000-8000-000000000005', 'fa100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fa100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_INSURANCE_OWNER', 'QA_INSURANCE_MANAGER')
  and menu_row.name in (
    'VehicleInsurance', 'VehicleInsurance:Add', 'VehicleInsurance:Edit',
    'VehicleInsurance:View', 'VehicleInsurance:Delete', 'VehicleInsurance:Export'
  )
) or (
  role_row.role_code = 'QA_INSURANCE_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fa100000-0000-4000-8000-000000000001';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values (
  'fa500000-0000-4000-8000-000000000001',
  'fa100000-0000-4000-8000-000000000001', 'QA-INS-001', 'QA-INS-VIN-001', 'truck',
  'operating', 'pending', 'fa300000-0000-4000-8000-000000000001',
  'qa-insurance-owner@example.invalid', 'qa-insurance-owner@example.invalid'
);

insert into public.vehicle_insurance_company(
  id, company_name, tenant_id, create_by, update_by
) values
  ('fa600000-0000-4000-8000-000000000001', 'QA insurer', 'fa100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fa600000-0000-4000-8000-000000000002', 'QA other insurer', 'fa100000-0000-4000-8000-000000000002', 'qa', 'qa');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000001","email":"qa-insurance-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_id uuid;
  v_detail jsonb;
begin
  v_id := public.vms_create_vehicle_insurance_secure(jsonb_build_object(
    'vehicle_id', 'fa500000-0000-4000-8000-000000000001',
    'commercial_policy_no', 'COMMERCIAL-SECRET-001',
    'commercial_company_id', 'fa600000-0000-4000-8000-000000000001',
    'commercial_insure_date', '2026-01-01',
    'commercial_premium', 12000.50,
    'commercial_expire_date', '2027-01-01',
    'compulsory_policy_no', 'COMPULSORY-SECRET-001',
    'compulsory_company_id', 'fa600000-0000-4000-8000-000000000001',
    'compulsory_insure_date', '2026-01-01',
    'compulsory_premium', 1200.25,
    'compulsory_expire_date', '2027-01-01',
    'attachments', jsonb_build_array(jsonb_build_object('name', 'secret.pdf', 'url', 'https://example.invalid/secret.pdf'))
  ));
  v_detail := public.vms_get_vehicle_insurance_secure(v_id);
  if v_detail->>'commercial_policy_no' <> 'COMMERCIAL-SECRET-001'
     or (v_detail->>'commercial_premium')::numeric <> 12000.50
     or v_detail->'field_access'->>'policyNumbers' <> 'edit'
     or (v_detail->>'is_record_owner')::boolean is not true then
    raise exception 'insurance owner override failed';
  end if;

  perform public.vms_update_vehicle_insurance_secure(
    v_id, jsonb_build_object('commercial_premium', 13000.50)
  );
  if (public.vms_get_vehicle_insurance_secure(v_id)->>'commercial_premium')::numeric <> 13000.50 then
    raise exception 'insurance owner could not update a protected premium';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000003","email":"qa-insurance-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_insurance_secure(
    p_from => 0, p_to => 9, p_vehicle_id => 'fa500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1 then
    raise exception 'vehicle query did not return insurance lifecycle data';
  end if;
  if (v_list->'records'->0) ? 'commercial_policy_no'
     or (v_list->'records'->0) ? 'commercial_premium'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'hidden insurance fields leaked through list';
  end if;

  v_list := public.vms_list_vehicle_insurance_secure(
    p_commercial_policy_no => 'COMMERCIAL-SECRET-001'
  );
  if jsonb_array_length(v_list->'records') <> 0 then
    raise exception 'hidden policy number remained searchable';
  end if;

  begin
    perform (select commercial_policy_no from public.vehicle_insurance limit 1);
    raise exception 'direct insurance select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000002","email":"qa-insurance-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_id uuid;
begin
  v_id := (
    public.vms_list_vehicle_insurance_secure(
      p_from => 0, p_to => 9, p_plate_no => 'QA-INS-001'
    )->'records'->0->>'id'
  )::uuid;
  perform public.vms_update_vehicle_insurance_secure(v_id, jsonb_build_object('remark', 'safe manager update'));

  begin
    perform public.vms_update_vehicle_insurance_secure(v_id, jsonb_build_object('commercial_premium', 1));
    raise exception 'manager unexpectedly updated a hidden premium';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_insurance_secure(
      v_id, jsonb_build_object('commercial_company_id', 'fa600000-0000-4000-8000-000000000002')
    );
    raise exception 'cross-tenant insurance company reference unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-000000000004","email":"qa-insurance-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_insurance_secure();
    raise exception 'insurance list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.vehicle_insurance set remark = 'direct leak';
    raise exception 'direct insurance update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_insurance_secure(integer,integer,uuid,text,text,text,text,date,date,date,date,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure insurance list';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_insurance', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_insurance', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_insurance', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_insurance', 'delete') then
    raise exception 'authenticated retained direct insurance table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_insurance_field_access_regression_passed' as result;
