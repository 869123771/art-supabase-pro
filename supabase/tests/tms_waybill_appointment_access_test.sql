-- Execute the whole file as one transaction. Every fixture and appointment is rolled back.
begin;

insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by)
values
  ('f8100000-0000-4000-8000-000000000001', 'qa_tms_appointment_a', 'QA appointment tenant A', '1', 'qa', 'qa'),
  ('f8100000-0000-4000-8000-000000000002', 'qa_tms_appointment_b', 'QA appointment tenant B', '1', 'qa', 'qa');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('f8200000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'qa-appointment-a@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('f8200000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'qa-appointment-b@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('f8200000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'qa-appointment-no-menu@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('f8200000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'qa-appointment-viewer@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.sys_role(id, role_name, role_code, enabled, tenant_id, create_by, update_by)
values
  ('f8400000-0000-4000-8000-000000000001', 'QA appointment A', 'QA_APPOINTMENT_A', true, 'f8100000-0000-4000-8000-000000000001', 'qa', 'qa'),
  ('f8400000-0000-4000-8000-000000000002', 'QA appointment B', 'QA_APPOINTMENT_B', true, 'f8100000-0000-4000-8000-000000000002', 'qa', 'qa'),
  ('f8400000-0000-4000-8000-000000000003', 'QA appointment viewer', 'QA_APPOINTMENT_VIEWER', true, 'f8100000-0000-4000-8000-000000000001', 'qa', 'qa');

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, account_identity_type, create_by, update_by
)
values
  ('f8300000-0000-4000-8000-000000000001', 'qa-appointment-a', 'QA appointment A', 'qa-appointment-a@example.invalid', '1', array['QA_APPOINTMENT_A']::text[], 'f8200000-0000-4000-8000-000000000001', 'f8100000-0000-4000-8000-000000000001', '2', 'external', 'qa', 'qa'),
  ('f8300000-0000-4000-8000-000000000002', 'qa-appointment-b', 'QA appointment B', 'qa-appointment-b@example.invalid', '1', array['QA_APPOINTMENT_B']::text[], 'f8200000-0000-4000-8000-000000000002', 'f8100000-0000-4000-8000-000000000002', '2', 'external', 'qa', 'qa'),
  ('f8300000-0000-4000-8000-000000000003', 'qa-appointment-no-menu', 'QA appointment without menu', 'qa-appointment-no-menu@example.invalid', '1', array[]::text[], 'f8200000-0000-4000-8000-000000000003', 'f8100000-0000-4000-8000-000000000001', '2', 'external', 'qa', 'qa'),
  ('f8300000-0000-4000-8000-000000000004', 'qa-appointment-viewer', 'QA appointment viewer', 'qa-appointment-viewer@example.invalid', '1', array['QA_APPOINTMENT_VIEWER']::text[], 'f8200000-0000-4000-8000-000000000004', 'f8100000-0000-4000-8000-000000000001', '2', 'external', 'qa', 'qa');

insert into public.sys_role_menu(tenant_id, role_id, menu_id, permission, create_by, update_by)
select role_row.tenant_id, role_row.id, menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_role role_row
cross join public.sys_menu menu_row
where role_row.role_code in ('QA_APPOINTMENT_A', 'QA_APPOINTMENT_B')
  and (menu_row.name = 'TmsPickupAppointment' or menu_row.name like 'TmsPickupAppointment:%'
    or menu_row.name = 'TmsDeliveryAppointment' or menu_row.name like 'TmsDeliveryAppointment:%');

insert into public.sys_role_menu(tenant_id, role_id, menu_id, permission, create_by, update_by)
select 'f8100000-0000-4000-8000-000000000001', 'f8400000-0000-4000-8000-000000000003', menu_row.id, '{}'::jsonb, 'qa', 'qa'
from public.sys_menu menu_row
where menu_row.name in ('TmsPickupAppointment', 'TmsDeliveryAppointment');

insert into public.tms_order(
  id, tenant_id, order_no, origin_station, destination_station, delivery_method,
  shipping_contact_name, shipping_contact_phone, shipping_address_detail,
  receiving_contact_name, receiving_contact_phone, receiving_address_detail,
  payment_method, created_by_user_id
)
values
  ('f8500000-0000-4000-8000-000000000001', 'f8100000-0000-4000-8000-000000000001', 'QA-APPOINTMENT-ORDER-A', 'A origin', 'A destination', 'delivery', 'A shipper', '13800000001', 'A shipper address', 'A receiver', '13800000002', 'A receiver address', 'cash', 'f8300000-0000-4000-8000-000000000001'),
  ('f8500000-0000-4000-8000-000000000002', 'f8100000-0000-4000-8000-000000000002', 'QA-APPOINTMENT-ORDER-B', 'B origin', 'B destination', 'delivery', 'B shipper', '13800000003', 'B shipper address', 'B receiver', '13800000004', 'B receiver address', 'cash', 'f8300000-0000-4000-8000-000000000002');

insert into public.tms_waybill(
  id, tenant_id, waybill_no, order_id, execution_kind, origin_city, destination_city,
  shipper_address, receiver_address, cargo_name, created_by_user_id
)
values
  ('f8600000-0000-4000-8000-000000000001', 'f8100000-0000-4000-8000-000000000001', 'QA-APPOINTMENT-A-1', 'f8500000-0000-4000-8000-000000000001', 'split', 'A origin', 'A destination', 'A shipper address', 'A receiver address', 'QA cargo', 'f8300000-0000-4000-8000-000000000001'),
  ('f8600000-0000-4000-8000-000000000002', 'f8100000-0000-4000-8000-000000000001', 'QA-APPOINTMENT-A-2', 'f8500000-0000-4000-8000-000000000001', 'split', 'A origin', 'A destination', 'A shipper address', 'A receiver address', 'QA cargo', 'f8300000-0000-4000-8000-000000000001'),
  ('f8600000-0000-4000-8000-000000000003', 'f8100000-0000-4000-8000-000000000002', 'QA-APPOINTMENT-B-1', 'f8500000-0000-4000-8000-000000000002', 'single', 'B origin', 'B destination', 'B shipper address', 'B receiver address', 'QA cargo', 'f8300000-0000-4000-8000-000000000002');

insert into public.tms_waybill_order_allocation(
  tenant_id, waybill_id, order_id, quantity, weight_kg, volume_m3
)
values
  ('f8100000-0000-4000-8000-000000000001', 'f8600000-0000-4000-8000-000000000001', 'f8500000-0000-4000-8000-000000000001', 1, 100, 1),
  ('f8100000-0000-4000-8000-000000000001', 'f8600000-0000-4000-8000-000000000002', 'f8500000-0000-4000-8000-000000000001', 1, 100, 1),
  ('f8100000-0000-4000-8000-000000000002', 'f8600000-0000-4000-8000-000000000003', 'f8500000-0000-4000-8000-000000000002', 1, 100, 1);

set local role authenticated;

do $qa$
declare
  v_pickup uuid;
  v_delivery uuid;
  v_children jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"f8200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f8200000-0000-4000-8000-000000000001', true);

  v_children := public.tms_list_appointment_candidates_secure('f8600000-0000-4000-8000-000000000001');
  if jsonb_array_length(v_children) <> 2 then
    raise exception 'sibling selection did not return exactly two tenant-local waybills';
  end if;

  begin
    perform public.tms_save_waybill_appointment_secure(jsonb_build_object(
      'kind', 'pickup', 'anchor_waybill_id', 'f8600000-0000-4000-8000-000000000001',
      'selected_waybill_ids', jsonb_build_array('f8600000-0000-4000-8000-000000000001', 'f8600000-0000-4000-8000-000000000003'),
      'driver_name', 'QA driver', 'driver_phone', '13800000000', 'plate_no', 'QA12345',
      'scheduled_at', now()
    ));
    raise exception 'cross-tenant child was accepted';
  exception when invalid_parameter_value then null;
  end;

  v_pickup := public.tms_save_waybill_appointment_secure(jsonb_build_object(
    'kind', 'pickup', 'anchor_waybill_id', 'f8600000-0000-4000-8000-000000000001',
    'selected_waybill_ids', jsonb_build_array('f8600000-0000-4000-8000-000000000001', 'f8600000-0000-4000-8000-000000000002'),
    'driver_name', 'QA driver', 'driver_phone', '13800000000', 'plate_no', 'QA12345',
    'scheduled_at', now()
  ));
  if jsonb_array_length(public.tms_list_waybill_appointments_secure('pickup', array['f8600000-0000-4000-8000-000000000002']::uuid[])) <> 1
    or not ('f8600000-0000-4000-8000-000000000002' = any(public.tms_filter_appointment_waybill_ids_secure('pickup', 'confirming')))
    or jsonb_array_length(public.tms_list_waybill_appointments_secure('pickup', array['f8600000-0000-4000-8000-000000000003']::uuid[])) <> 0 then
    raise exception 'appointment read or status filter escaped its selected child / tenant scope';
  end if;

  perform set_config('request.jwt.claims', '{"sub":"f8200000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f8200000-0000-4000-8000-000000000003', true);
  begin
    perform public.tms_list_waybill_appointments_secure('pickup', array['f8600000-0000-4000-8000-000000000001']::uuid[]);
    raise exception 'user without the appointment menu could read appointments';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.tms_delete_waybill_appointment_secure(v_pickup);
    raise exception 'user without delete permission removed an appointment';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', '{"sub":"f8200000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f8200000-0000-4000-8000-000000000004', true);
  if public.tms_list_waybill_appointments_secure('pickup', array['f8600000-0000-4000-8000-000000000001']::uuid[])->0->>'driverPhone' is not null then
    raise exception 'viewer received the private driver phone';
  end if;
  begin
    perform public.tms_change_waybill_appointment_status_secure(v_pickup, 'confirm');
    raise exception 'read-only viewer confirmed an appointment';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.tms_waybill_appointment where id = v_pickup;
    raise exception 'authenticated role directly selected from the appointment table';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', '{"sub":"f8200000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f8200000-0000-4000-8000-000000000002', true);
  if jsonb_array_length(public.tms_list_waybill_appointments_secure('pickup', array['f8600000-0000-4000-8000-000000000001']::uuid[])) <> 0 then
    raise exception 'tenant B could read tenant A appointment';
  end if;
  begin
    perform public.tms_change_waybill_appointment_status_secure(v_pickup, 'confirm');
    raise exception 'tenant B changed tenant A appointment';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', '{"sub":"f8200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f8200000-0000-4000-8000-000000000001', true);
  perform public.tms_change_waybill_appointment_status_secure(v_pickup, 'confirm');
  perform public.tms_record_waybill_appointment_arrival_secure(v_pickup, jsonb_build_object(
    'arrival_plate_no', 'QA12345', 'arrived_at', now(),
    'loading_started_at', now() + interval '10 minutes',
    'loading_finished_at', now() + interval '20 minutes',
    'departed_at', now() + interval '30 minutes'
  ));
  perform public.tms_change_waybill_appointment_status_secure(v_pickup, 'complete');
  if not ('f8600000-0000-4000-8000-000000000001' = any(public.tms_filter_appointment_waybill_ids_secure('pickup', 'completed'))) then
    raise exception 'completed pickup was absent from status filter';
  end if;
  begin
    perform public.tms_delete_waybill_appointment_secure(v_pickup);
    raise exception 'completed pickup was deleted';
  exception when invalid_parameter_value then null;
  end;

  v_delivery := public.tms_save_waybill_appointment_secure(jsonb_build_object(
    'kind', 'delivery', 'anchor_waybill_id', 'f8600000-0000-4000-8000-000000000001',
    'selected_waybill_ids', jsonb_build_array('f8600000-0000-4000-8000-000000000001'),
    'driver_name', 'QA driver', 'driver_phone', '13800000000', 'plate_no', 'QA12345',
    'scheduled_at', now()
  ));
  perform public.tms_change_waybill_appointment_status_secure(v_delivery, 'confirm');
  begin
    perform public.tms_record_waybill_appointment_arrival_secure(v_delivery, jsonb_build_object('arrived_at', now()));
    raise exception 'delivery arrival without a dock was accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.tms_record_waybill_appointment_arrival_secure(v_delivery, jsonb_build_object('arrived_at', now(), 'dock_name', 'QA dock 1'));
  perform public.tms_change_waybill_appointment_status_secure(v_delivery, 'complete');
end;
$qa$;

reset role;
rollback;

select 'tms_waybill_appointment_access_regression_passed' as result;
