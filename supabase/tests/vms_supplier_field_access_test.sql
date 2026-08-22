begin;

insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by) values
  ('e7100000-0000-4000-8000-000000000001', 'qa_supplier_field', 'QA supplier field', '1', 'qa', 'qa'),
  ('e7100000-0000-4000-8000-000000000002', 'qa_supplier_other', 'QA supplier other', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e7200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-supplier-owner@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e7200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-supplier-manager@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e7200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-supplier-option@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e7200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-supplier-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('e7200000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'qa-supplier-other@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(id, role_name, role_code, enabled, tenant_id, create_by, update_by) values
  ('e7400000-0000-4000-8000-000000000001', 'QA supplier owner', 'QA_SUPPLIER_OWNER', true, 'e7100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('e7400000-0000-4000-8000-000000000002', 'QA supplier manager', 'QA_SUPPLIER_MANAGER', true, 'e7100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('e7400000-0000-4000-8000-000000000003', 'QA supplier option', 'QA_SUPPLIER_OPTION', true, 'e7100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
  ('e7300000-0000-4000-8000-000000000001', 'qa-supplier-owner', 'QA Supplier Owner', 'qa-supplier-owner@example.invalid', '1', array['QA_SUPPLIER_OWNER']::text[], 'e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('e7300000-0000-4000-8000-000000000002', 'qa-supplier-manager', 'QA Supplier Manager', 'qa-supplier-manager@example.invalid', '1', array['QA_SUPPLIER_MANAGER']::text[], 'e7200000-0000-4000-8000-000000000002', 'e7100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('e7300000-0000-4000-8000-000000000003', 'qa-supplier-option', 'QA Supplier Option', 'qa-supplier-option@example.invalid', '1', array['QA_SUPPLIER_OPTION']::text[], 'e7200000-0000-4000-8000-000000000003', 'e7100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('e7300000-0000-4000-8000-000000000004', 'qa-supplier-no-menu', 'QA Supplier No Menu', 'qa-supplier-no-menu@example.invalid', '1', array[]::text[], 'e7200000-0000-4000-8000-000000000004', 'e7100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'),
  ('e7300000-0000-4000-8000-000000000005', 'qa-supplier-other', 'QA Supplier Other', 'qa-supplier-other@example.invalid', '1', array[]::text[], 'e7200000-0000-4000-8000-000000000005', 'e7100000-0000-4000-8000-000000000002', '2', 'qa', 'qa');

insert into public.sys_role_menu(tenant_id, role_id, menu_id, permission, create_by, update_by)
select 'e7100000-0000-4000-8000-000000000001', role_row.id, menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
join public.sys_menu menu_row on (
  role_row.role_code in ('QA_SUPPLIER_OWNER', 'QA_SUPPLIER_MANAGER')
  and menu_row.name in (
    'Supplier', 'Supplier:Add', 'Supplier:Edit', 'Supplier:Delete',
    'Supplier:Import', 'Supplier:Export'
  )
) or (
  role_row.role_code = 'QA_SUPPLIER_OPTION' and menu_row.name = 'Parts'
)
where role_row.tenant_id = 'e7100000-0000-4000-8000-000000000001';

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  'e7100000-0000-4000-8000-000000000001',
  'e7400000-0000-4000-8000-000000000002',
  resource_row.id, field_row.id,
  case field_row.field_key
    when 'contactDetails' then 'masked'
    when 'addressDetails' then 'read'
    else 'hidden'
  end,
  'qa', 'qa'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.resource_id = resource_row.id and field_row.tenant_id = resource_row.tenant_id
where resource_row.tenant_id = 'e7100000-0000-4000-8000-000000000001'
  and resource_row.resource_key = 'vms.supplier';

insert into public.vehicle_supplier(
  id, tenant_id, supplier_name, contact_person, contact_phone,
  region, address_detail, remark, create_by, update_by
) values
  ('e7600000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', 'QA Secret Supplier', 'Secret Contact', '13800138000', '上海市/浦东新区', '秘密地址 100 号', 'SECRET-NOTE', 'qa-supplier-owner@example.invalid', 'qa-supplier-owner@example.invalid'),
  ('e7600000-0000-4000-8000-000000000002', 'e7100000-0000-4000-8000-000000000002', 'QA Other Supplier', 'Other Contact', '13900139000', '北京市', 'OTHER-ADDRESS', 'OTHER-NOTE', 'qa-supplier-other@example.invalid', 'qa-supplier-other@example.invalid');

do $qa$
begin
  if (select created_by_user_id from public.vehicle_supplier where id = 'e7600000-0000-4000-8000-000000000001')
       <> 'e7300000-0000-4000-8000-000000000001' then
    raise exception 'vehicle supplier creator identity was not resolved';
  end if;
end;
$qa$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e7200000-0000-4000-8000-000000000001","email":"qa-supplier-owner@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e7200000-0000-4000-8000-000000000001', true);

do $qa$
declare
  v_list jsonb;
  v_created_id uuid;
  v_imported_id uuid;
begin
  v_list := public.vms_list_vehicle_suppliers_secure(p_supplier_name => 'QA Secret');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'contact_person' <> 'Secret Contact'
     or v_list->'records'->0->>'contact_phone' <> '13800138000'
     or v_list->'records'->0->>'address_detail' <> '秘密地址 100 号'
     or v_list->'records'->0->>'remark' <> 'SECRET-NOTE'
     or v_list->'records'->0->'field_access'->>'contactDetails' <> 'edit'
     or (v_list->'records'->0->>'is_record_owner')::boolean is not true then
    raise exception 'vehicle supplier owner override failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_suppliers_secure(
    p_ids => array['e7600000-0000-4000-8000-000000000002'::uuid]
  )->'records') <> 0 then
    raise exception 'vehicle supplier list leaked another tenant';
  end if;

  v_created_id := public.vms_create_vehicle_supplier_secure(jsonb_build_object(
    'supplier_name', 'QA Created Supplier',
    'contact_person', 'Created Contact',
    'contact_phone', '13700137000',
    'region', '浙江省/杭州市',
    'address_detail', 'Created Address',
    'remark', 'Created Note'
  ));
  if jsonb_array_length(public.vms_list_vehicle_suppliers_secure(
    p_ids => array[v_created_id]
  )->'records') <> 1 then
    raise exception 'secure vehicle supplier create was not readable by its owner';
  end if;
  if public.vms_delete_vehicle_suppliers_secure(array[v_created_id]) <> 1 then
    raise exception 'secure vehicle supplier owner delete failed';
  end if;

  if public.vms_import_vehicle_suppliers_secure(jsonb_build_array(jsonb_build_object(
    'supplier_name', 'QA Imported Supplier',
    'contact_person', 'Imported Contact',
    'contact_phone', '13600136000'
  ))) <> 1 then
    raise exception 'secure vehicle supplier import failed';
  end if;
  v_imported_id := (public.vms_list_vehicle_suppliers_secure(
    p_supplier_name => 'QA Imported Supplier'
  )->'records'->0->>'id')::uuid;
  if public.vms_delete_vehicle_suppliers_secure(array[v_imported_id]) <> 1 then
    raise exception 'imported vehicle supplier cleanup failed';
  end if;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"e7200000-0000-4000-8000-000000000002","email":"qa-supplier-manager@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e7200000-0000-4000-8000-000000000002', true);

do $qa$
declare
  v_list jsonb;
  v_export jsonb;
  v_updated jsonb;
begin
  v_list := public.vms_list_vehicle_suppliers_secure(p_supplier_name => 'QA Secret');
  if jsonb_array_length(v_list->'records') <> 1
     or v_list->'records'->0->>'contact_person' <> '***'
     or v_list->'records'->0->>'contact_phone' <> '138****8000'
     or v_list->'records'->0->>'region' <> '上海市/浦东新区'
     or v_list->'records'->0->>'address_detail' <> '秘密地址 100 号'
     or (v_list->'records'->0) ? 'remark' then
    raise exception 'vehicle supplier field filtering failed';
  end if;

  if jsonb_array_length(public.vms_list_vehicle_suppliers_secure(
    p_contact_person => 'Secret Contact'
  )->'records') <> 0
     or jsonb_array_length(public.vms_list_vehicle_suppliers_secure(
       p_contact_phone => '13800138000'
     )->'records') <> 0 then
    raise exception 'masked vehicle supplier contacts were filterable';
  end if;

  v_export := public.vms_list_vehicle_suppliers_secure(
    p_supplier_name => 'QA Secret', p_purpose => 'export'
  );
  if v_export->'records'->0->>'contact_phone' <> '138****8000'
     or v_export->'records'->0->>'address_detail' <> '秘密地址 100 号'
     or (v_export->'records'->0) ? 'remark' then
    raise exception 'vehicle supplier export leaked protected fields';
  end if;

  v_updated := public.vms_update_vehicle_supplier_secure(
    'e7600000-0000-4000-8000-000000000001',
    '{"supplier_name":"QA Secret Supplier Updated"}'::jsonb
  );
  if v_updated->>'supplier_name' <> 'QA Secret Supplier Updated'
     or v_updated->>'update_by' <> 'qa-supplier-manager@example.invalid' then
    raise exception 'vehicle supplier non-sensitive update failed or lost operator identity';
  end if;

  begin
    perform public.vms_update_vehicle_supplier_secure(
      'e7600000-0000-4000-8000-000000000001',
      '{"contact_phone":"13500135000"}'::jsonb
    );
    raise exception 'vehicle supplier contact was editable without field permission';
  exception when insufficient_privilege then null;
  end;

  begin
    perform (select contact_phone from public.vehicle_supplier limit 1);
    raise exception 'direct vehicle supplier select unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"e7200000-0000-4000-8000-000000000003","email":"qa-supplier-option@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e7200000-0000-4000-8000-000000000003', true);

do $qa$
declare
  v_options jsonb;
begin
  v_options := public.vms_list_vehicle_suppliers_secure(
    p_ids => array[
      'e7600000-0000-4000-8000-000000000001'::uuid,
      'e7600000-0000-4000-8000-000000000002'::uuid
    ],
    p_purpose => 'options'
  );
  if jsonb_array_length(v_options->'records') <> 1
     or v_options->'records'->0->>'supplier_name' <> 'QA Secret Supplier Updated'
     or (v_options->'records'->0) ? 'contact_person'
     or (v_options->'records'->0) ? 'contact_phone'
     or (v_options->'records'->0) ? 'address_detail'
     or (v_options->'records'->0) ? 'remark' then
    raise exception 'vehicle supplier options leaked sensitive or cross-tenant data';
  end if;

  begin
    perform public.vms_list_vehicle_suppliers_secure();
    raise exception 'vehicle supplier list unexpectedly allowed through the Parts menu';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

select set_config('request.jwt.claims', '{"sub":"e7200000-0000-4000-8000-000000000004","email":"qa-supplier-no-menu@example.invalid","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e7200000-0000-4000-8000-000000000004', true);

do $qa$
begin
  begin
    perform public.vms_list_vehicle_suppliers_secure();
    raise exception 'vehicle supplier list unexpectedly allowed without its menu';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.vms_list_vehicle_suppliers_secure(p_purpose => 'options');
    raise exception 'vehicle supplier options unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.vehicle_supplier(
      tenant_id, supplier_name, created_by_user_id, create_by, update_by
    ) values (
      'e7100000-0000-4000-8000-000000000001', 'DIRECT',
      'e7300000-0000-4000-8000-000000000004',
      'qa-supplier-no-menu@example.invalid', 'qa-supplier-no-menu@example.invalid'
    );
    raise exception 'direct vehicle supplier insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$qa$;

reset role;

do $qa$
begin
  if has_function_privilege(
    'anon',
    'public.vms_list_vehicle_suppliers_secure(integer,integer,text,text,text,uuid[],text)',
    'execute'
  ) or has_function_privilege(
    'anon', 'public.vms_create_vehicle_supplier_secure(jsonb)', 'execute'
  ) then
    raise exception 'anon retained execute on secure vehicle supplier functions';
  end if;
  if has_table_privilege('authenticated', 'public.vehicle_supplier', 'select')
     or has_table_privilege('authenticated', 'public.vehicle_supplier', 'insert')
     or has_table_privilege('authenticated', 'public.vehicle_supplier', 'update')
     or has_table_privilege('authenticated', 'public.vehicle_supplier', 'delete') then
    raise exception 'authenticated retained direct vehicle supplier table privileges';
  end if;
end;
$qa$;

rollback;

select 'vms_supplier_field_access_regression_passed' as result;
