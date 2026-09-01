alter table public.tms_driver
  add column if not exists employee_id uuid;

comment on column public.tms_driver.employee_id is
  '可选关联的HR员工档案；仅记录司机建档来源，不自动同步覆盖司机运营资料';

alter table public.tms_driver
  drop constraint if exists tms_driver_employee_tenant_fkey;

alter table public.tms_driver
  add constraint tms_driver_employee_tenant_fkey
  foreign key (employee_id, tenant_id)
  references public.hr_employee(id, tenant_id)
  on delete restrict;

create unique index if not exists tms_driver_employee_tenant_unique
  on public.tms_driver(employee_id, tenant_id)
  where employee_id is not null;

create or replace function app_private.assert_tms_driver_employee_scope(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_driver_id uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_employee_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.hr_employee employee_row
    where employee_row.id = p_employee_id
      and employee_row.tenant_id = p_tenant_id
      and employee_row.employment_status in ('probation', 'active')
  ) then
    raise exception '所选员工不在当前租户，或已不处于在职状态';
  end if;

  if exists (
    select 1
    from public.tms_driver driver_row
    where driver_row.employee_id = p_employee_id
      and driver_row.tenant_id = p_tenant_id
      and (p_driver_id is null or driver_row.id <> p_driver_id)
  ) then
    raise exception '所选员工已建立司机档案，请勿重复新增';
  end if;
end;
$$;

revoke all on function app_private.assert_tms_driver_employee_scope(uuid, uuid, uuid)
  from public;

create or replace function app_private.assert_tms_driver_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Driver payload must be a JSON object';
  end if;

  select array_agg(key order by key)
  into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'employee_id', 'carrier_id', 'driver_name', 'phone', 'gender', 'id_card_no',
    'license_type', 'driver_type', 'license_expire_date', 'home_address',
    'emergency_contact_name', 'emergency_contact_phone', 'enabled',
    'id_card_front_url', 'id_card_back_url', 'driver_license_front_url',
    'driver_license_back_url', 'remark'
  ]::text[]);

  if v_invalid_keys is not null then
    raise exception 'Driver payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function public.tms_list_driver_employee_options_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_limit integer;
  v_result jsonb;
begin
  if not (
    app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false)
    or app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Edit', null, false)
  ) then
    raise exception 'Missing driver create or edit permission' using errcode = '42501';
  end if;

  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_access := app_private.field_access_map('tms.driver', null);
  v_limit := least(
    100,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      employee_row,
      organization_row.organization_code,
      organization_row.organization_name
    from public.hr_employee employee_row
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
     and organization_row.tenant_id = employee_row.tenant_id
    where employee_row.tenant_id = v_tenant_id
      and employee_row.employment_status in ('probation', 'active')
      and not exists (
        select 1
        from public.tms_driver driver_row
        where driver_row.employee_id = employee_row.id
          and driver_row.tenant_id = employee_row.tenant_id
      )
      and (
        nullif(btrim(p_keyword), '') is null
        or employee_row.employee_no ilike '%' || btrim(p_keyword) || '%'
        or employee_row.employee_name ilike '%' || btrim(p_keyword) || '%'
        or employee_row.job_title ilike '%' || btrim(p_keyword) || '%'
        or organization_row.organization_name ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select *
    from filtered
    order by (filtered.employee_row).employee_name, (filtered.employee_row).employee_no
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', (paged.employee_row).id,
          'employee_no', (paged.employee_row).employee_no,
          'employee_name', (paged.employee_row).employee_name,
          'organization_id', (paged.employee_row).organization_id,
          'organization', case
            when paged.organization_name is null then null
            else jsonb_build_object(
              'id', (paged.employee_row).organization_id,
              'organization_code', paged.organization_code,
              'organization_name', paged.organization_name
            )
          end,
          'job_title', (paged.employee_row).job_title,
          'employment_status', (paged.employee_row).employment_status,
          'gender', (paged.employee_row).gender,
          'phone', case
            when coalesce(v_access->>'contactPhone', 'hidden') = 'edit'
              then (paged.employee_row).phone
            else null
          end,
          'id_card_no', case
            when coalesce(v_access->>'idCardNo', 'hidden') = 'edit'
              then (paged.employee_row).id_card_no
            else null
          end,
          'home_address', case
            when coalesce(v_access->>'homeAddress', 'hidden') = 'edit'
              then (paged.employee_row).home_address
            else null
          end,
          'emergency_contact_name', case
            when coalesce(v_access->>'emergencyContact', 'hidden') = 'edit'
              then (paged.employee_row).emergency_contact_name
            else null
          end,
          'emergency_contact_phone', case
            when coalesce(v_access->>'emergencyContact', 'hidden') = 'edit'
              then (paged.employee_row).emergency_contact_phone
            else null
          end
        )
        order by (paged.employee_row).employee_name, (paged.employee_row).employee_no
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.tms_list_driver_employee_options_secure(integer, integer, text)
  from public;
grant execute on function public.tms_list_driver_employee_options_secure(integer, integer, text)
  to authenticated, service_role;

create or replace function public.tms_create_driver_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_driver%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false) then
    raise exception 'Missing driver create permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_driver_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_driver, p_payload);
  perform app_private.assert_tms_driver_carrier_scope(v_tenant_id, v_input.carrier_id);
  perform app_private.assert_tms_driver_employee_scope(v_tenant_id, v_input.employee_id, null);

  insert into public.tms_driver (
    employee_id, carrier_id, driver_name, phone, gender, id_card_no, license_type,
    driver_type, license_expire_date, home_address, emergency_contact_name,
    emergency_contact_phone, enabled, id_card_front_url, id_card_back_url,
    driver_license_front_url, driver_license_back_url, remark, tenant_id
  ) values (
    v_input.employee_id, v_input.carrier_id, v_input.driver_name, v_input.phone,
    v_input.gender, v_input.id_card_no, v_input.license_type,
    coalesce(v_input.driver_type, 'primary'), v_input.license_expire_date,
    v_input.home_address, v_input.emergency_contact_name,
    v_input.emergency_contact_phone, coalesce(v_input.enabled, true),
    v_input.id_card_front_url, v_input.id_card_back_url, v_input.driver_license_front_url,
    v_input.driver_license_back_url, v_input.remark, v_tenant_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.tms_update_driver_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_driver%rowtype;
  v_candidate public.tms_driver%rowtype;
  v_updated public.tms_driver%rowtype;
begin
  select * into v_old
  from public.tms_driver driver_row
  where driver_row.id = p_id
    and (app_private.is_platform_super() or driver_row.tenant_id = app_private.current_user_tenant_id())
  for update;

  if not found then
    raise exception 'Driver not found or access denied';
  end if;

  if not app_private.can_execute_business_action(
    'TmsDriver', 'TmsDriver:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing driver edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_driver_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_driver_carrier_scope(v_old.tenant_id, v_candidate.carrier_id);
  perform app_private.assert_tms_driver_employee_scope(
    v_old.tenant_id,
    v_candidate.employee_id,
    v_old.id
  );

  if v_candidate.phone is distinct from v_old.phone
     and app_private.resolve_field_access(
       'tms.driver', 'contactPhone', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver phone' using errcode = '42501';
  end if;
  if v_candidate.id_card_no is distinct from v_old.id_card_no
     and app_private.resolve_field_access(
       'tms.driver', 'idCardNo', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver identity number' using errcode = '42501';
  end if;
  if v_candidate.home_address is distinct from v_old.home_address
     and app_private.resolve_field_access(
       'tms.driver', 'homeAddress', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver home address' using errcode = '42501';
  end if;
  if (v_candidate.emergency_contact_name, v_candidate.emergency_contact_phone)
     is distinct from (v_old.emergency_contact_name, v_old.emergency_contact_phone)
     and app_private.resolve_field_access(
       'tms.driver', 'emergencyContact', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver emergency contact' using errcode = '42501';
  end if;
  if (v_candidate.id_card_front_url, v_candidate.id_card_back_url,
      v_candidate.driver_license_front_url, v_candidate.driver_license_back_url)
     is distinct from (v_old.id_card_front_url, v_old.id_card_back_url,
      v_old.driver_license_front_url, v_old.driver_license_back_url)
     and app_private.resolve_field_access(
       'tms.driver', 'identityDocuments', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver identity documents' using errcode = '42501';
  end if;

  update public.tms_driver set
    employee_id = v_candidate.employee_id,
    carrier_id = v_candidate.carrier_id,
    driver_name = v_candidate.driver_name,
    phone = v_candidate.phone,
    gender = v_candidate.gender,
    id_card_no = v_candidate.id_card_no,
    license_type = v_candidate.license_type,
    driver_type = v_candidate.driver_type,
    license_expire_date = v_candidate.license_expire_date,
    home_address = v_candidate.home_address,
    emergency_contact_name = v_candidate.emergency_contact_name,
    emergency_contact_phone = v_candidate.emergency_contact_phone,
    enabled = v_candidate.enabled,
    id_card_front_url = v_candidate.id_card_front_url,
    id_card_back_url = v_candidate.id_card_back_url,
    driver_license_front_url = v_candidate.driver_license_front_url,
    driver_license_back_url = v_candidate.driver_license_back_url,
    remark = v_candidate.remark
  where id = v_old.id
  returning * into v_updated;

  return app_private.tms_driver_with_relations_to_secure_json(v_updated);
end;
$$;

;
