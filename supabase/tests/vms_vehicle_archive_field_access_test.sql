begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values
(
  'f2100000-0000-4000-8000-000000000001',
  'qa_vehicle_field_access', 'QA vehicle field access', '1', 'qa', 'qa'
),
(
  'f2100000-0000-4000-8000-000000000002',
  'qa_vehicle_field_access_other', 'QA vehicle field access other', '1', 'qa', 'qa'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'f2200000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'qa-vehicle-owner@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f2200000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'qa-vehicle-manager@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f2200000-0000-4000-8000-000000000003',
  'authenticated', 'authenticated', 'qa-vehicle-viewer@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f2200000-0000-4000-8000-000000000004',
  'authenticated', 'authenticated', 'qa-vehicle-no-menu@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f2200000-0000-4000-8000-000000000005',
  'authenticated', 'authenticated', 'qa-vehicle-other@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values
(
  'f2400000-0000-4000-8000-000000000001',
  'QA vehicle owner', 'QA_VEHICLE_OWNER', true,
  'f2100000-0000-4000-8000-000000000001', 'qa', 'qa'
),
(
  'f2400000-0000-4000-8000-000000000002',
  'QA vehicle manager', 'QA_VEHICLE_MANAGER', true,
  'f2100000-0000-4000-8000-000000000001', 'qa', 'qa'
),
(
  'f2400000-0000-4000-8000-000000000003',
  'QA vehicle viewer', 'QA_VEHICLE_VIEWER', true,
  'f2100000-0000-4000-8000-000000000001', 'qa', 'qa'
);

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
(
  'f2300000-0000-4000-8000-000000000001',
  'qa-vehicle-owner', 'QA Vehicle Owner', 'qa-vehicle-owner@example.invalid', '1',
  array['QA_VEHICLE_OWNER']::text[], 'f2200000-0000-4000-8000-000000000001',
  'f2100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f2300000-0000-4000-8000-000000000002',
  'qa-vehicle-manager', 'QA Vehicle Manager', 'qa-vehicle-manager@example.invalid', '1',
  array['QA_VEHICLE_MANAGER']::text[], 'f2200000-0000-4000-8000-000000000002',
  'f2100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f2300000-0000-4000-8000-000000000003',
  'qa-vehicle-viewer', 'QA Vehicle Viewer', 'qa-vehicle-viewer@example.invalid', '1',
  array['QA_VEHICLE_VIEWER']::text[], 'f2200000-0000-4000-8000-000000000003',
  'f2100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f2300000-0000-4000-8000-000000000004',
  'qa-vehicle-no-menu', 'QA Vehicle No Menu', 'qa-vehicle-no-menu@example.invalid', '1',
  array[]::text[], 'f2200000-0000-4000-8000-000000000004',
  'f2100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f2300000-0000-4000-8000-000000000005',
  'qa-vehicle-other', 'QA Vehicle Other', 'qa-vehicle-other@example.invalid', '1',
  array[]::text[], 'f2200000-0000-4000-8000-000000000005',
  'f2100000-0000-4000-8000-000000000002', '2', 'qa', 'qa'
);

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'f2100000-0000-4000-8000-000000000001',
  role_row.id,
  menu_row.id,
  '{}'::jsonb,
  'qa',
  'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_VEHICLE_OWNER', 'QA_VEHICLE_MANAGER')
  and menu_row.name in (
    'VehicleArchiveManage', 'VehicleArchive:Add', 'VehicleArchive:Edit',
    'VehicleArchive:View', 'VehicleArchive:Delete'
  )
) or (
  role_row.role_code = 'QA_VEHICLE_VIEWER'
  and menu_row.name in ('VehicleQuery', 'VehicleQuery:View')
)
where role_row.tenant_id = 'f2100000-0000-4000-8000-000000000001';

insert into public.tms_carrier(
  id, carrier_code, company_name, carrier_type, enabled,
  driver_count, vehicle_count, signed_contract, tenant_id,
  created_by_user_id, create_by, update_by
) values
(
  'f2500000-0000-4000-8000-000000000001',
  'QA-VEHICLE-CARRIER', 'QA vehicle carrier', 'contracted', true,
  0, 0, true, 'f2100000-0000-4000-8000-000000000001',
  'f2300000-0000-4000-8000-000000000001', 'qa', 'qa'
),
(
  'f2500000-0000-4000-8000-000000000002',
  'QA-OTHER-CARRIER', 'QA other carrier', 'contracted', true,
  0, 0, true, 'f2100000-0000-4000-8000-000000000002',
  'f2300000-0000-4000-8000-000000000005', 'qa', 'qa'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f2200000-0000-4000-8000-000000000001","email":"qa-vehicle-owner@example.invalid","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', 'f2200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_id uuid;
  v_detail jsonb;
begin
  v_id := public.vms_create_vehicle_archive_secure(jsonb_build_object(
    'plate_no', 'QA-VMS-001',
    'vehicle_type', 'truck',
    'vin', 'QA-SECRET-VIN-0001',
    'carrier_id', 'f2500000-0000-4000-8000-000000000001',
    'owner_name', 'QA secret owner',
    'owner_phone', '13800001111',
    'id_card_no', '110101199001011234',
    'mailing_address', 'QA secret address',
    'operation_route', 'QA secret route',
    'terminal_phone', '13900002222',
    'attachments', jsonb_build_array(jsonb_build_object(
      'name', 'secret.pdf', 'url', 'https://example.invalid/secret.pdf'
    ))
  ));
  if v_id is null then raise exception 'secure vehicle create did not return an id'; end if;
  v_detail := public.vms_get_vehicle_archive_secure(v_id);
  if v_detail->>'vin' <> 'QA-SECRET-VIN-0001'
     or v_detail->>'owner_phone' <> '13800001111'
     or v_detail->'field_access'->>'vehicleIdentifiers' <> 'edit'
     or (v_detail->>'is_record_owner')::boolean is not true then
    raise exception 'record owner override did not return editable sensitive fields';
  end if;

  perform public.vms_update_vehicle_archive_secure(
    v_id, jsonb_build_object('vin', 'QA-OWNER-UPDATED-VIN')
  );
  if public.vms_get_vehicle_archive_secure(v_id)->>'vin' <> 'QA-OWNER-UPDATED-VIN' then
    raise exception 'record owner could not update a protected vehicle field';
  end if;
  if jsonb_array_length(public.vms_list_vehicle_archives_secure(
    p_from => 0, p_to => 9, p_vin => 'QA-OWNER-UPDATED-VIN'
  )->'records') <> 1 then
    raise exception 'record owner could not search an owned vehicle identifier';
  end if;
  if public.vms_list_vehicle_archive_options_secure(
    p_ids => array[v_id]
  )->0->>'vin' <> 'QA-OWNER-UPDATED-VIN' then
    raise exception 'record owner vehicle option omitted the owned identifier';
  end if;
end;
$qa$;

select set_config(
  'request.jwt.claims',
  '{"sub":"f2200000-0000-4000-8000-000000000003","email":"qa-vehicle-viewer@example.invalid","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', 'f2200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_list jsonb;
  v_detail jsonb;
  v_id uuid;
begin
  select vehicle_row.id into v_id
  from public.vehicle_archive vehicle_row
  where vehicle_row.plate_no = 'QA-VMS-001';

  v_list := public.vms_list_vehicle_archives_secure(
    p_from => 0, p_to => 9, p_record_id => v_id
  );
  if jsonb_array_length(v_list->'records') <> 1 then
    raise exception 'vehicle query menu did not return the tenant vehicle';
  end if;
  if (v_list->'records'->0) ? 'vin'
     or (v_list->'records'->0) ? 'owner_phone'
     or (v_list->'records'->0) ? 'attachments' then
    raise exception 'hidden vehicle fields leaked through the list endpoint';
  end if;

  v_detail := public.vms_get_vehicle_archive_secure(v_id);
  if v_detail ? 'vin' or v_detail ? 'id_card_no' or v_detail ? 'operation_route' then
    raise exception 'hidden vehicle fields leaked through the detail endpoint';
  end if;

  v_list := public.vms_list_vehicle_archives_secure(
    p_from => 0, p_to => 9, p_vin => 'QA-OWNER-UPDATED-VIN'
  );
  if jsonb_array_length(v_list->'records') <> 0 then
    raise exception 'hidden vehicle VIN remained searchable';
  end if;

  begin
    perform (select vehicle_row.vin from public.vehicle_archive vehicle_row limit 1);
    raise exception 'direct VIN select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.vehicle_archive set remark = 'direct write leak' where id = v_id;
    raise exception 'direct vehicle update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config(
  'request.jwt.claims',
  '{"sub":"f2200000-0000-4000-8000-000000000002","email":"qa-vehicle-manager@example.invalid","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', 'f2200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_id uuid;
  v_updated jsonb;
begin
  select vehicle_row.id into v_id
  from public.vehicle_archive vehicle_row
  where vehicle_row.plate_no = 'QA-VMS-001';

  v_updated := public.vms_update_vehicle_archive_secure(
    v_id, jsonb_build_object('remark', 'manager safe update')
  );
  if v_updated->>'remark' <> 'manager safe update' then
    raise exception 'authorized manager could not update a non-sensitive field';
  end if;

  begin
    perform public.vms_update_vehicle_archive_secure(
      v_id, jsonb_build_object('vin', 'QA-MANAGER-LEAK')
    );
    raise exception 'manager unexpectedly updated a hidden vehicle identifier';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_update_vehicle_archive_secure(
      v_id,
      jsonb_build_object('carrier_id', 'f2500000-0000-4000-8000-000000000002')
    );
    raise exception 'cross-tenant vehicle carrier reference unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  if (public.vms_get_vehicle_archive_delete_preview_secure(v_id)->>'related_total')::integer <> 0 then
    raise exception 'vehicle delete preview returned unexpected dependencies';
  end if;
end;
$qa$;

select set_config(
  'request.jwt.claims',
  '{"sub":"f2200000-0000-4000-8000-000000000004","email":"qa-vehicle-no-menu@example.invalid","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', 'f2200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  if (select count(*) from public.vehicle_archive) <> 0 then
    raise exception 'vehicle RLS exposed rows to a user without a consuming menu';
  end if;

  begin
    perform public.vms_list_vehicle_archive_options_secure();
    raise exception 'vehicle options unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.vms_list_vehicle_archives_secure();
    raise exception 'vehicle list unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon', 'public.vms_list_vehicle_archives_secure(integer,integer,uuid,uuid,text,text,text,text,text,text,text,text[],timestamptz,timestamptz,uuid[],text)',
    'execute'
  ) then
    raise exception 'anon retained execute on the secure vehicle list';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_archive', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_archive', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_archive', 'delete') then
    raise exception 'authenticated retained direct vehicle write privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_vehicle_archive_field_access_regression_passed' as result;
