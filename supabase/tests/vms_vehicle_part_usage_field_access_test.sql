begin;

insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by) values
  ('fb100000-0000-4000-8000-000000000001', 'qa_part_field', 'QA part field', '1', 'qa', 'qa'),
  ('fb100000-0000-4000-8000-000000000002', 'qa_part_other', 'QA part other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fb200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-part-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-part-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-part-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-part-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fb200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-part-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(id, role_name, role_code, enabled, tenant_id, create_by, update_by) values
  ('fb400000-0000-4000-8000-000000000001', 'QA part owner', 'QA_PART_OWNER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000002', 'QA part manager', 'QA_PART_MANAGER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fb400000-0000-4000-8000-000000000003', 'QA part viewer', 'QA_PART_VIEWER', true, 'fb100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fb300000-0000-4000-8000-000000000001', 'qa-part-owner', 'QA Part Owner', 'qa-part-owner@example.invalid', '1', array['QA_PART_OWNER']::text[], 'fb200000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000002', 'qa-part-manager', 'QA Part Manager', 'qa-part-manager@example.invalid', '1', array['QA_PART_MANAGER']::text[], 'fb200000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000003', 'qa-part-viewer', 'QA Part Viewer', 'qa-part-viewer@example.invalid', '1', array['QA_PART_VIEWER']::text[], 'fb200000-0000-4000-8000-000000000003', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000004', 'qa-part-no-menu', 'QA Part No Menu', 'qa-part-no-menu@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000004', 'fb100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fb300000-0000-4000-8000-000000000005', 'qa-part-other', 'QA Part Other', 'qa-part-other@example.invalid', '1', array[]::text[], 'fb200000-0000-4000-8000-000000000005', 'fb100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(tenant_id, role_id, menu_id, permission, create_by, update_by)
select 'fb100000-0000-4000-8000-000000000001', role_row.id, menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_PART_OWNER', 'QA_PART_MANAGER')
  and menu_row.name in (
    'VehiclePartsManage', 'VehiclePartUsage:Add', 'VehiclePartUsage:View',
    'VehiclePartUsage:Edit', 'VehiclePartUsage:Delete'
  )
) or (
  role_row.role_code = 'QA_PART_VIEWER' and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fb100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'fb100000-0000-4000-8000-000000000001',
  'fb400000-0000-4000-8000-000000000002',
  resource_row.id, field_row.id,
  case field_row.field_key
    when 'supplierDetails' then 'masked'
    when 'traceabilityTag' then 'masked'
    when 'lifecycleLimits' then 'read'
    else 'masked'
  end,
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'fb100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.vehicle_part_usage';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fb500000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'QA-PART-001', 'QA-PART-VIN-001', 'truck', 'operating', 'pending', 'fb300000-0000-4000-8000-000000000001', 'qa-part-owner@example.invalid', 'qa-part-owner@example.invalid'),
  ('fb500000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000002', 'QA-PART-OTHER', 'QA-PART-VIN-OTHER', 'truck', 'operating', 'pending', 'fb300000-0000-4000-8000-000000000005', 'qa-part-other@example.invalid', 'qa-part-other@example.invalid');

insert into public.vehicle_supplier(id, tenant_id, supplier_name, contact_person, contact_phone) values
  ('fb700000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'SECRET-SUPPLIER', 'Secret Contact', '13800138000');

insert into public.vehicle_parts(
  id, tenant_id, part_name, part_code, category_id, brand, model, unit,
  supplier_id, supplier_contact, is_consumable, service_life, service_mileage
) values
  ('fb800000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'QA Brake Pad', 'QA-PART-001', null, 'QA Brand', 'QA Model', 'piece', 'fb700000-0000-4000-8000-000000000001', '13800138000', true, 3, 80000);

insert into public.vehicle_part_usage(
  id, tenant_id, vehicle_id, plate_no, company_name, part_id, part_type,
  part_name, part_code, category_id, category_name, brand, model, unit,
  supplier_id, supplier_name, supplier_contact, is_consumable,
  rfid_enabled, rfid_tag, enable_mode, enable_date, warranty_mode,
  warranty_mileage, warranty_duration, service_mileage_enabled, service_mileage,
  service_years_enabled, service_years, used_mileage, status, scrap_reason, remark,
  create_by, update_by
) values
  ('fb900000-0000-4000-8000-000000000001', 'fb100000-0000-4000-8000-000000000001', 'fb500000-0000-4000-8000-000000000001', 'QA-PART-001', 'QA Company', 'fb800000-0000-4000-8000-000000000001', 'original', 'QA Brake Pad', 'QA-PART-001', null, null, 'QA Brand', 'QA Model', 'piece', 'fb700000-0000-4000-8000-000000000001', 'SECRET-SUPPLIER', '13800138000', true, true, 'RFID-SECRET-001', 'date', '2026-01-01', 'self', 100000, 36, true, 80000, true, 3, 12000, 'normal', null, 'SECRET-NOTE', 'qa-part-owner@example.invalid', 'qa-part-owner@example.invalid'),
  ('fb900000-0000-4000-8000-000000000002', 'fb100000-0000-4000-8000-000000000002', 'fb500000-0000-4000-8000-000000000002', 'QA-PART-OTHER', 'Other Company', null, 'original', 'Other Brake Pad', 'OTHER-PART-001', null, null, 'Other Brand', 'Other Model', 'piece', null, 'OTHER-SUPPLIER', '13900139000', true, true, 'RFID-OTHER', 'date', '2026-01-01', 'self', 100000, 36, true, 80000, true, 3, 1000, 'normal', null, 'OTHER-NOTE', 'qa-part-other@example.invalid', 'qa-part-other@example.invalid');

do $qa$
begin
  if (select created_by_user_id from public.vehicle_part_usage where id = 'fb900000-0000-4000-8000-000000000001') <> 'fb300000-0000-4000-8000-000000000001' then
    raise exception 'vehicle part usage creator identity was not resolved';
  end if;
end;
$qa$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000001","email":"qa-part-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_list jsonb;
  v_created_id uuid;
  v_created jsonb;
begin
  v_list := public.vms_list_vehicle_part_usages_secure(p_plate_no => 'QA-PART-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'supplier_name' <> 'SECRET-SUPPLIER'
     or v_list->'records'->0->>'rfid_tag' <> 'RFID-SECRET-001'
     or (v_list->'records'->0->>'used_mileage')::numeric <> 12000
     or v_list->'records'->0->'field_access'->>'lifecycleLimits' <> 'edit'
     or (v_list->'records'->0->>'is_record_owner')::boolean is not true then
    raise exception 'vehicle part usage owner override failed';
  end if;

  v_created_id := public.vms_create_vehicle_part_usage_secure(jsonb_build_object(
    'vehicle_id', 'fb500000-0000-4000-8000-000000000001',
    'part_id', 'fb800000-0000-4000-8000-000000000001',
    'part_type', 'replacement',
    'rfid_enabled', false,
    'enable_mode', 'date',
    'enable_date', '2026-08-22',
    'warranty_mode', 'self',
    'warranty_duration', 12,
    'service_mileage_enabled', true,
    'service_mileage', 80000,
    'service_years_enabled', false,
    'used_mileage', 0,
    'status', 'normal'
  ));
  v_created := public.vms_get_vehicle_part_usage_secure(v_created_id);
  if (v_created->>'is_record_owner')::boolean is not true
     or v_created->>'part_name' <> 'QA Brake Pad' then
    raise exception 'secure vehicle part usage create lost creator identity or references';
  end if;
  if public.vms_delete_vehicle_part_usages_secure(array[v_created_id]) <> 1 then
    raise exception 'vehicle part usage owner delete failed';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000002","email":"qa-part-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_health jsonb;
begin
  v_list := public.vms_list_vehicle_part_usages_secure(p_plate_no => 'QA-PART-001');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'supplier_name' <> '***'
     or v_list->'records'->0->>'supplier_contact' <> '***'
     or v_list->'records'->0->>'rfid_tag' <> '***'
     or (v_list->'records'->0->>'used_mileage')::numeric <> 12000
     or v_list->'records'->0->>'remark' <> '***' then
    raise exception 'vehicle part usage field filtering failed';
  end if;
  if jsonb_array_length(public.vms_list_vehicle_part_usages_secure(
    p_rfid_tag => 'RFID-SECRET-001'
  )->'records') <> 0 then
    raise exception 'masked vehicle part RFID was filterable';
  end if;
  v_health := public.vms_get_vehicle_part_health_context_secure(
    'fb500000-0000-4000-8000-000000000001', 200
  );
  if jsonb_array_length(v_health) <> 1
     or (v_health->0->>'used_mileage')::numeric <> 12000 then
    raise exception 'vehicle part health context did not honor readable lifecycle data';
  end if;
  perform public.vms_update_vehicle_part_usage_secure(
    'fb900000-0000-4000-8000-000000000001', '{"quality_category":"qualified"}'::jsonb
  );
  begin
    perform public.vms_update_vehicle_part_usage_secure(
      'fb900000-0000-4000-8000-000000000001', '{"used_mileage":99999}'::jsonb
    );
    raise exception 'vehicle part lifecycle was editable without permission';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.vms_list_vehicle_part_usages_secure(p_purpose => 'export');
    raise exception 'vehicle part export unexpectedly bypassed missing button permission';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000003","email":"qa-part-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
begin
  v_list := public.vms_list_vehicle_part_usages_secure(
    p_vehicle_id => 'fb500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1
     or (v_list->'records'->0) ? 'supplier_name'
     or (v_list->'records'->0) ? 'rfid_tag'
     or (v_list->'records'->0) ? 'enable_date'
     or (v_list->'records'->0) ? 'used_mileage'
     or (v_list->'records'->0) ? 'remark' then
    raise exception 'vehicle query leaked protected part usage fields';
  end if;
  if jsonb_array_length(public.vms_get_vehicle_part_health_context_secure(
    'fb500000-0000-4000-8000-000000000001', 200
  )) <> 0 then
    raise exception 'vehicle part health context leaked hidden lifecycle data';
  end if;
  begin
    perform (select rfid_tag from public.vehicle_part_usage limit 1);
    raise exception 'direct vehicle part usage select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-000000000004","email":"qa-part-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fb200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_part_usages_secure();
    raise exception 'vehicle part usage list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.vehicle_part_usage(
      tenant_id, plate_no, part_name, part_code, part_type,
      service_mileage_enabled, service_mileage, created_by_user_id
    ) values (
      'fb100000-0000-4000-8000-000000000001', 'DIRECT', 'DIRECT', 'DIRECT', 'original',
      true, 1, 'fb300000-0000-4000-8000-000000000004'
    );
    raise exception 'direct vehicle part usage insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_part_usages_secure(integer,integer,uuid,text,text,text,text,uuid,text,text,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) or has_function_privilege(
    'anon', 'public.vms_get_vehicle_part_usage_secure(uuid)', 'execute'
  ) or has_function_privilege(
    'anon', 'public.vms_get_vehicle_part_health_context_secure(uuid,integer)', 'execute'
  ) then
    raise exception 'anon retained execute on secure vehicle part usage functions';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_part_usage', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_part_usage', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_part_usage', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_part_usage', 'delete') then
    raise exception 'authenticated retained direct vehicle part usage table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_part_usage_field_access_regression_passed' as result;
