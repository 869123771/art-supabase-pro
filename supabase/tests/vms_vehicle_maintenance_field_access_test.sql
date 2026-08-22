begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
  ('fc100000-0000-4000-8000-000000000001', 'qa_maintenance_field', 'QA maintenance field', '1', 'qa', 'qa'),
  ('fc100000-0000-4000-8000-000000000002', 'qa_maintenance_other', 'QA maintenance other', '1', 'qa', 'qa');

update public.sys_document_number_rule
set auto_enabled = false
where tenant_id = 'fc100000-0000-4000-8000-000000000001'
  and rule_key = 'vehicle.maintenance';

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('fc200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-maintenance-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fc200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-maintenance-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fc200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-maintenance-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fc200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-maintenance-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('fc200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-maintenance-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
  ('fc400000-0000-4000-8000-000000000001', 'QA maintenance owner', 'QA_MAINTENANCE_OWNER', true, 'fc100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fc400000-0000-4000-8000-000000000002', 'QA maintenance manager', 'QA_MAINTENANCE_MANAGER', true, 'fc100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('fc400000-0000-4000-8000-000000000003', 'QA maintenance viewer', 'QA_MAINTENANCE_VIEWER', true, 'fc100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('fc300000-0000-4000-8000-000000000001', 'qa-maintenance-owner', 'QA Maintenance Owner', 'qa-maintenance-owner@example.invalid', '1', array['QA_MAINTENANCE_OWNER']::text[], 'fc200000-0000-4000-8000-000000000001', 'fc100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fc300000-0000-4000-8000-000000000002', 'qa-maintenance-manager', 'QA Maintenance Manager', 'qa-maintenance-manager@example.invalid', '1', array['QA_MAINTENANCE_MANAGER']::text[], 'fc200000-0000-4000-8000-000000000002', 'fc100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fc300000-0000-4000-8000-000000000003', 'qa-maintenance-viewer', 'QA Maintenance Viewer', 'qa-maintenance-viewer@example.invalid', '1', array['QA_MAINTENANCE_VIEWER']::text[], 'fc200000-0000-4000-8000-000000000003', 'fc100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fc300000-0000-4000-8000-000000000004', 'qa-maintenance-no-menu', 'QA Maintenance No Menu', 'qa-maintenance-no-menu@example.invalid', '1', array[]::text[], 'fc200000-0000-4000-8000-000000000004', 'fc100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('fc300000-0000-4000-8000-000000000005', 'qa-maintenance-other', 'QA Maintenance Other', 'qa-maintenance-other@example.invalid', '1', array[]::text[], 'fc200000-0000-4000-8000-000000000005', 'fc100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'fc100000-0000-4000-8000-000000000001', role_row.id, menu_row.id,
  '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_MAINTENANCE_OWNER', 'QA_MAINTENANCE_MANAGER')
  and menu_row.name in (
    'VehicleMaintenance', 'VehicleMaintenance:Add', 'VehicleMaintenance:Edit',
    'VehicleMaintenance:View', 'VehicleMaintenance:Delete', 'VehicleMaintenance:Export'
  )
) or (
  role_row.role_code = 'QA_MAINTENANCE_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'fc100000-0000-4000-8000-000000000001';

insert into public.vehicle_archive(
  id, tenant_id, plate_no, vin, vehicle_type, operation_status, audit_status,
  created_by_user_id, create_by, update_by
) values
  ('fc500000-0000-4000-8000-000000000001', 'fc100000-0000-4000-8000-000000000001', 'QA-MNT-001', 'QA-MNT-VIN-001', 'truck', 'operating', 'pending', 'fc300000-0000-4000-8000-000000000001', 'qa-maintenance-owner@example.invalid', 'qa-maintenance-owner@example.invalid'),
  ('fc500000-0000-4000-8000-000000000002', 'fc100000-0000-4000-8000-000000000002', 'QA-MNT-OTHER', 'QA-MNT-VIN-OTHER', 'truck', 'operating', 'pending', 'fc300000-0000-4000-8000-000000000005', 'qa-maintenance-other@example.invalid', 'qa-maintenance-other@example.invalid');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fc200000-0000-4000-8000-000000000001","email":"qa-maintenance-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fc200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_id uuid;
  v_detail jsonb;
begin
  v_id := public.vms_create_vehicle_maintenance_secure(jsonb_build_object(
    'vehicle_id', 'fc500000-0000-4000-8000-000000000001',
    'maintenance_no', 'MAINTENANCE-SECRET-001',
    'maintenance_type', 'repair',
    'initiator', 'Owner',
    'start_time', '2026-08-22 09:00:00+08',
    'end_time', '2026-08-22 18:00:00+08',
    'cost_amount', 2680.50,
    'workshop', 'QA workshop',
    'external_repair', true,
    'remark', 'safe remark',
    'items', jsonb_build_array(jsonb_build_object(
      'item_name', 'brake repair', 'part_name', 'brake pad', 'total_amount', 1800
    )),
    'attachments', jsonb_build_array(jsonb_build_object(
      'name', 'invoice.pdf', 'url', 'https://example.invalid/invoice.pdf'
    ))
  ));
  v_detail := public.vms_get_vehicle_maintenance_secure(v_id);
  if v_detail->>'maintenance_no' <> 'MAINTENANCE-SECRET-001'
     or (v_detail->>'cost_amount')::numeric <> 2680.50
     or jsonb_array_length(v_detail->'items') <> 1
     or v_detail->'field_access'->>'totalCost' <> 'edit'
     or (v_detail->>'is_record_owner')::boolean is not true then
    raise exception 'maintenance owner override failed';
  end if;

  perform public.vms_update_vehicle_maintenance_secure(
    v_id, jsonb_build_object('cost_amount', 2880.50)
  );
  if (public.vms_get_vehicle_maintenance_secure(v_id)->>'cost_amount')::numeric <> 2880.50 then
    raise exception 'maintenance owner could not update protected cost';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fc200000-0000-4000-8000-000000000003","email":"qa-maintenance-viewer@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fc200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
  v_context jsonb;
begin
  v_list := public.vms_list_vehicle_maintenance_secure(
    p_from => 0, p_to => 9, p_vehicle_id => 'fc500000-0000-4000-8000-000000000001'
  );
  if jsonb_array_length(v_list->'records') <> 1 then
    raise exception 'vehicle query did not return maintenance lifecycle data';
  end if;
  if (v_list->'records'->0) ? 'maintenance_no'
     or (v_list->'records'->0) ? 'cost_amount'
     or (v_list->'records'->0) ? 'items'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'hidden maintenance fields leaked through list';
  end if;

  v_list := public.vms_list_vehicle_maintenance_secure(
    p_maintenance_no => 'MAINTENANCE-SECRET-001'
  );
  if jsonb_array_length(v_list->'records') <> 0 then
    raise exception 'hidden maintenance number remained searchable';
  end if;

  v_context := public.vms_get_vehicle_maintenance_health_context_secure(
    p_vehicle_id => 'fc500000-0000-4000-8000-000000000001', p_limit => 10
  );
  if jsonb_array_length(v_context) <> 1
     or (v_context->0) ? 'maintenance_no'
     or (v_context->0) ? 'cost_amount'
     or (v_context->0) ? 'items'
     or (v_context->0) ? 'remark' then
    raise exception 'maintenance AI context leaked protected fields';
  end if;

  begin
    perform (select maintenance_no from public.vehicle_maintenance_record limit 1);
    raise exception 'direct maintenance select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fc200000-0000-4000-8000-000000000002","email":"qa-maintenance-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fc200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_id uuid;
begin
  v_id := (
    public.vms_list_vehicle_maintenance_secure(
      p_from => 0, p_to => 9, p_plate_no => 'QA-MNT-001'
    )->'records'->0->>'id'
  )::uuid;
  perform public.vms_update_vehicle_maintenance_secure(v_id, jsonb_build_object('remark', 'safe manager update'));

  begin
    perform public.vms_update_vehicle_maintenance_secure(v_id, jsonb_build_object('cost_amount', 1));
    raise exception 'manager unexpectedly updated hidden maintenance cost';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_maintenance_secure(
      v_id, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('item_name', 'leak')))
    );
    raise exception 'manager unexpectedly updated hidden maintenance items';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_maintenance_secure(
      v_id, jsonb_build_object('vehicle_id', 'fc500000-0000-4000-8000-000000000002')
    );
    raise exception 'cross-tenant maintenance vehicle reference unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"fc200000-0000-4000-8000-000000000004","email":"qa-maintenance-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'fc200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_maintenance_secure();
    raise exception 'maintenance list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.vehicle_maintenance_record set remark = 'direct leak';
    raise exception 'direct maintenance update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_maintenance_secure(integer,integer,uuid,text,text,text,text,timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on secure maintenance list';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_maintenance_record', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_maintenance_record', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_maintenance_record', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_maintenance_record', 'delete') then
    raise exception 'authenticated retained direct maintenance table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_maintenance_field_access_regression_passed' as result;
