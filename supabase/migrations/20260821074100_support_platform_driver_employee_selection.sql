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
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      organization_row.organization_code,
      organization_row.organization_name
    from public.hr_employee employee_row
    join public.sys_tenant tenant_row
      on tenant_row.id = employee_row.tenant_id
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
     and organization_row.tenant_id = employee_row.tenant_id
    where (app_private.is_platform_super() or employee_row.tenant_id = v_tenant_id)
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
          'tenant_id', (paged.employee_row).tenant_id,
          'tenant', jsonb_build_object(
            'id', (paged.employee_row).tenant_id,
            'tenant_code', paged.tenant_code,
            'tenant_name', paged.tenant_name
          ),
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
  from public, anon;
grant execute on function public.tms_list_driver_employee_options_secure(integer, integer, text)
  to authenticated, service_role;

create or replace function public.tms_create_driver_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_input public.tms_driver%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false) then
    raise exception 'Missing driver create permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_driver_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_driver, p_payload);

  if app_private.is_platform_super() then
    if v_input.employee_id is not null then
      select employee_row.tenant_id
      into v_tenant_id
      from public.hr_employee employee_row
      where employee_row.id = v_input.employee_id;
    else
      select carrier_row.tenant_id
      into v_tenant_id
      from public.tms_carrier carrier_row
      where carrier_row.id = v_input.carrier_id;
    end if;
  else
    v_tenant_id := app_private.current_user_tenant_id();
  end if;

  if v_tenant_id is null then
    raise exception '无法确定司机所属租户，请重新选择员工或承运商';
  end if;

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

revoke all on function public.tms_create_driver_secure(jsonb) from public, anon;
grant execute on function public.tms_create_driver_secure(jsonb) to authenticated, service_role;

;
