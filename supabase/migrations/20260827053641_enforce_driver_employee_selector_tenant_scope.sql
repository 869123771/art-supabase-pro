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
as $function$
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
$function$;

;
