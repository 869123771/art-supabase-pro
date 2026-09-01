create or replace function public.hr_list_position_organization_scope_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target_tenant_id uuid;
begin
  if not app_private.can_execute_business_action(
    'HrPosition',
    'Hr:Position:View',
    null,
    false
  ) then
    raise exception 'Missing position view permission' using errcode = '42501';
  end if;

  v_target_tenant_id := case
    when app_private.is_platform_super() then p_tenant_id
    else app_private.current_user_tenant_id()
  end;

  if not app_private.is_platform_super() and v_target_tenant_id is null then
    raise exception 'Position tenant is required' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', organization_row.id,
        'tenant_id', organization_row.tenant_id,
        'tenant', jsonb_build_object(
          'tenant_code', tenant_row.tenant_code,
          'tenant_name', tenant_row.tenant_name
        ),
        'parent_id', organization_row.parent_id,
        'organization_code', organization_row.organization_code,
        'organization_name', organization_row.organization_name,
        'organization_type', organization_row.organization_type,
        'status', organization_row.status,
        'sort', organization_row.sort,
        'is_system', organization_row.is_system,
        'scope_count', (
          select count(*)
          from public.hr_position position_row
          where position_row.tenant_id = organization_row.tenant_id
            and position_row.organization_id = organization_row.id
        )
      )
      order by tenant_row.tenant_name, organization_row.sort, organization_row.organization_name
    )
    from public.sys_organization organization_row
    join public.sys_tenant tenant_row on tenant_row.id = organization_row.tenant_id
    where (v_target_tenant_id is null or organization_row.tenant_id = v_target_tenant_id)
      and organization_row.status = '1'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.hr_list_employee_organization_scope_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target_tenant_id uuid;
begin
  perform app_private.assert_hr_employee_readable();

  v_target_tenant_id := case
    when app_private.is_platform_super() then p_tenant_id
    else app_private.current_user_tenant_id()
  end;

  if not app_private.is_platform_super() and v_target_tenant_id is null then
    raise exception 'Employee tenant is required' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', organization_row.id,
        'tenant_id', organization_row.tenant_id,
        'tenant', jsonb_build_object(
          'tenant_code', tenant_row.tenant_code,
          'tenant_name', tenant_row.tenant_name
        ),
        'parent_id', organization_row.parent_id,
        'organization_code', organization_row.organization_code,
        'organization_name', organization_row.organization_name,
        'organization_type', organization_row.organization_type,
        'status', organization_row.status,
        'sort', organization_row.sort,
        'is_system', organization_row.is_system,
        'scope_count', (
          select count(*)
          from public.hr_employee employee_row
          where employee_row.tenant_id = organization_row.tenant_id
            and employee_row.organization_id = organization_row.id
        )
      )
      order by tenant_row.tenant_name, organization_row.sort, organization_row.organization_name
    )
    from public.sys_organization organization_row
    join public.sys_tenant tenant_row on tenant_row.id = organization_row.tenant_id
    where (v_target_tenant_id is null or organization_row.tenant_id = v_target_tenant_id)
      and organization_row.status = '1'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.hr_list_employees_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_tenant_id uuid default null,
  p_organization_ids uuid[] default null,
  p_organization_unassigned boolean default false,
  p_employment_status text default null,
  p_employment_type text default null,
  p_keyword text default null,
  p_hire_start date default null,
  p_hire_end date default null,
  p_record_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_current_user_id uuid := app_private.current_app_user_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    1000
  );
  v_keyword text := nullif(btrim(p_keyword), '');
  v_contact_access text := app_private.resolve_field_access(
    'hr.employee', 'contactDetails', null
  );
  v_identity_access text := app_private.resolve_field_access(
    'hr.employee', 'identityDetails', null
  );
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_hr_employee_readable();

  v_target_tenant_id := case
    when app_private.is_platform_super() then p_tenant_id
    else v_tenant_id
  end;

  if not app_private.is_platform_super() and v_target_tenant_id is null then
    raise exception 'Employee tenant is required' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.hr_employee employee_row
  where (v_target_tenant_id is null or employee_row.tenant_id = v_target_tenant_id)
    and (p_record_id is null or employee_row.id = p_record_id)
    and (
      not coalesce(p_organization_unassigned, false)
      or employee_row.organization_id is null
    )
    and (
      coalesce(p_organization_unassigned, false)
      or p_organization_ids is null
      or employee_row.organization_id = any(p_organization_ids)
    )
    and (p_employment_status is null or employee_row.employment_status = p_employment_status)
    and (p_employment_type is null or employee_row.employment_type = p_employment_type)
    and (p_hire_start is null or employee_row.hire_date >= p_hire_start)
    and (p_hire_end is null or employee_row.hire_date <= p_hire_end)
    and (
      v_keyword is null
      or employee_row.employee_no ilike '%' || v_keyword || '%'
      or employee_row.employee_name ilike '%' || v_keyword || '%'
      or employee_row.job_title ilike '%' || v_keyword || '%'
      or (
        (
          employee_row.created_by_user_id = v_current_user_id
          or v_contact_access in ('read', 'edit')
        )
        and (
          employee_row.phone ilike '%' || v_keyword || '%'
          or employee_row.email ilike '%' || v_keyword || '%'
        )
      )
      or (
        (
          employee_row.created_by_user_id = v_current_user_id
          or v_identity_access in ('read', 'edit')
        )
        and employee_row.id_card_no ilike '%' || v_keyword || '%'
      )
    );

  for v_row in
    select employee_row.id, employee_row.created_by_user_id
    from public.hr_employee employee_row
    where (v_target_tenant_id is null or employee_row.tenant_id = v_target_tenant_id)
      and (p_record_id is null or employee_row.id = p_record_id)
      and (
        not coalesce(p_organization_unassigned, false)
        or employee_row.organization_id is null
      )
      and (
        coalesce(p_organization_unassigned, false)
        or p_organization_ids is null
        or employee_row.organization_id = any(p_organization_ids)
      )
      and (p_employment_status is null or employee_row.employment_status = p_employment_status)
      and (p_employment_type is null or employee_row.employment_type = p_employment_type)
      and (p_hire_start is null or employee_row.hire_date >= p_hire_start)
      and (p_hire_end is null or employee_row.hire_date <= p_hire_end)
      and (
        v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or employee_row.job_title ilike '%' || v_keyword || '%'
        or (
          (
            employee_row.created_by_user_id = v_current_user_id
            or v_contact_access in ('read', 'edit')
          )
          and (
            employee_row.phone ilike '%' || v_keyword || '%'
            or employee_row.email ilike '%' || v_keyword || '%'
          )
        )
        or (
          (
            employee_row.created_by_user_id = v_current_user_id
            or v_identity_access in ('read', 'edit')
          )
          and employee_row.id_card_no ilike '%' || v_keyword || '%'
        )
      )
    order by
      employee_row.tenant_id,
      employee_row.employment_status,
      employee_row.hire_date desc nulls last,
      employee_row.create_time desc,
      employee_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.hr_employee_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('hr.employee', null)
  );
end;
$$;

;
