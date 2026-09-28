begin;

insert into public.sys_tenant(
  id, tenant_code, tenant_name, status, create_by, update_by
) values (
  'f1100000-0000-4000-8000-000000000001',
  'qa_carrier_driver_field_access',
  'QA carrier driver field access',
  '1', 'qa', 'qa'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  'f1200000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'qa-owner-carrier@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f1200000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'qa-no-menu-carrier@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
),
(
  'f1200000-0000-4000-8000-000000000003',
  'authenticated', 'authenticated', 'qa-consumer-carrier@example.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.sys_role(
  id, role_name, role_code, enabled, tenant_id, create_by, update_by
) values (
  'f1400000-0000-4000-8000-000000000001',
  'QA carrier consumer', 'QA_CARRIER_CONSUMER', true,
  'f1100000-0000-4000-8000-000000000001', 'qa', 'qa'
);

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
) values
(
  'f1300000-0000-4000-8000-000000000001',
  'qa-carrier-owner', 'QA Carrier Owner', 'qa-owner-carrier@example.invalid', '1',
  array[]::text[], 'f1200000-0000-4000-8000-000000000001',
  'f1100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f1300000-0000-4000-8000-000000000002',
  'qa-carrier-no-menu', 'QA Carrier No Menu', 'qa-no-menu-carrier@example.invalid', '1',
  array[]::text[], 'f1200000-0000-4000-8000-000000000002',
  'f1100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
),
(
  'f1300000-0000-4000-8000-000000000003',
  'qa-carrier-consumer', 'QA Carrier Consumer', 'qa-consumer-carrier@example.invalid', '1',
  array['QA_CARRIER_CONSUMER']::text[], 'f1200000-0000-4000-8000-000000000003',
  'f1100000-0000-4000-8000-000000000001', '2', 'qa', 'qa'
);

insert into public.sys_role_menu(
  tenant_id, role_id, menu_id, permission, create_by, update_by
)
select
  'f1100000-0000-4000-8000-000000000001',
  'f1400000-0000-4000-8000-000000000001',
  menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_menu menu_row
where menu_row.name in ('TmsDriver', 'TmsCarrierDetail', 'TmsCarrierDetail:AiAnalyze');

insert into public.tms_carrier(
  id, carrier_code, company_name, carrier_type, enabled,
  driver_count, vehicle_count, contact_name, contact_phone,
  signed_contract, tenant_id, created_by_user_id, create_by, update_by
) values (
  'f1500000-0000-4000-8000-000000000001',
  'QA-CARRIER-001', 'QA carrier', 'contracted', true,
  0, 0, 'Secret contact', '13900001234',
  true, 'f1100000-0000-4000-8000-000000000001',
  'f1300000-0000-4000-8000-000000000001', 'qa', 'qa'
);

insert into public.tms_driver(
  id, carrier_id, driver_name, phone, gender, id_card_no,
  license_type, driver_type, enabled, tenant_id, created_by_user_id,
  create_by, update_by
) values (
  'f1600000-0000-4000-8000-000000000001',
  'f1500000-0000-4000-8000-000000000001',
  'QA driver', '13800005678', '1', '110101199001011234',
  'A2', 'primary', true,
  'f1100000-0000-4000-8000-000000000001',
  'f1300000-0000-4000-8000-000000000001', 'qa', 'qa'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"f1200000-0000-4000-8000-000000000002","email":"qa-no-menu-carrier@example.invalid","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'f1200000-0000-4000-8000-000000000002',
  true
);

do $qa$
begin
  begin
    perform public.tms_list_carrier_options_secure();
    raise exception 'carrier options unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform public.tms_list_driver_options_secure();
    raise exception 'driver options unexpectedly allowed without a consuming menu';
  exception when insufficient_privilege then
    null;
  end;
end;
$qa$;

select set_config(
  'request.jwt.claims',
  '{"sub":"f1200000-0000-4000-8000-000000000003","email":"qa-consumer-carrier@example.invalid","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'f1200000-0000-4000-8000-000000000003',
  true
);

do $qa$
declare
  v_carriers jsonb;
  v_drivers jsonb;
  v_context jsonb;
begin
  v_carriers := public.tms_list_carrier_options_secure();
  if jsonb_array_length(v_carriers) <> 1 then
    raise exception 'consumer menu did not allow the carrier option';
  end if;
  if (v_carriers->0) ? 'contact_phone' then
    raise exception 'hidden carrier phone leaked through the option endpoint';
  end if;
  if jsonb_array_length(public.tms_list_carrier_options_secure(
    null, false, '13900001234', null, 200
  )) <> 0 then
    raise exception 'hidden carrier phone remained searchable';
  end if;

  v_drivers := public.tms_list_driver_options_secure();
  if jsonb_array_length(v_drivers) <> 1 then
    raise exception 'consumer menu did not allow the driver option';
  end if;
  if (v_drivers->0) ? 'phone' then
    raise exception 'hidden driver phone leaked through the option endpoint';
  end if;
  if jsonb_array_length(public.tms_list_driver_options_secure(
    null, '13800005678', null, null, false, 200
  )) <> 0 then
    raise exception 'hidden driver phone remained searchable';
  end if;

  v_context := public.tms_get_carrier_performance_context_secure(
    'f1500000-0000-4000-8000-000000000001'
  );
  if v_context->'carrier'->>'company_name' <> 'QA carrier'
     or (v_context->>'driver_count')::integer <> 1
     or (v_context->>'vehicle_count')::integer <> 0 then
    raise exception 'carrier performance context is incomplete';
  end if;
  if (v_context->'carrier') ? 'contact_phone'
     or (v_context->'carrier') ? 'bank_account' then
    raise exception 'carrier performance context exposed sensitive fields';
  end if;
end;
$qa$;

reset role;
rollback;

select 'carrier_driver_field_access_regression_passed' as result;
