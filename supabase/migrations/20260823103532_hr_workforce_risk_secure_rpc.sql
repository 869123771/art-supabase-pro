create or replace function public.hr_get_workforce_risk_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
begin
  if not coalesce(app_private.has_permission('Hr:WorkforceRisk:View'), false) then
    raise exception 'Missing workforce risk view permission' using errcode = '42501';
  end if;

  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Workforce risk tenant is required' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'activeEmployeeCount', (
      select count(*)
      from public.hr_employee employee_row
      where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
        and employee_row.employment_status = 'active'
    ),
    'probationEmployees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scoped.id,
        'employeeNo', scoped.employee_no,
        'employeeName', scoped.employee_name,
        'probationEndDate', scoped.probation_end_date
      ) order by scoped.probation_end_date, scoped.id)
      from (
        select employee_row.id, employee_row.employee_no, employee_row.employee_name,
          employee_row.probation_end_date
        from public.hr_employee employee_row
        where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
          and employee_row.employment_status = 'probation'
          and employee_row.probation_end_date is not null
          and employee_row.probation_end_date <= current_date + 30
        order by employee_row.probation_end_date, employee_row.id
        limit 1000
      ) scoped
    ), '[]'::jsonb),
    'contracts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scoped.id,
        'contractNo', scoped.contract_no,
        'endDate', scoped.end_date,
        'employee', jsonb_build_object(
          'id', scoped.employee_id,
          'employeeNo', scoped.employee_no,
          'employeeName', scoped.employee_name
        )
      ) order by scoped.end_date, scoped.id)
      from (
        select contract_row.id, contract_row.contract_no, contract_row.end_date,
          employee_row.id as employee_id, employee_row.employee_no, employee_row.employee_name
        from public.hr_employee_contract contract_row
        left join public.hr_employee employee_row
          on employee_row.id = contract_row.employee_id
          and employee_row.tenant_id = contract_row.tenant_id
        where (v_is_platform_super or contract_row.tenant_id = v_tenant_id)
          and contract_row.contract_status = 'active'
          and contract_row.end_date is not null
          and contract_row.end_date <= current_date + 60
        order by contract_row.end_date, contract_row.id
        limit 1000
      ) scoped
    ), '[]'::jsonb),
    'qualifications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scoped.id,
        'qualificationName', scoped.qualification_name,
        'expiryDate', scoped.expiry_date,
        'employee', jsonb_build_object(
          'id', scoped.employee_id,
          'employeeNo', scoped.employee_no,
          'employeeName', scoped.employee_name
        )
      ) order by scoped.expiry_date, scoped.id)
      from (
        select qualification_row.id, qualification_row.qualification_name,
          qualification_row.expiry_date, employee_row.id as employee_id,
          employee_row.employee_no, employee_row.employee_name
        from public.hr_employee_qualification qualification_row
        left join public.hr_employee employee_row
          on employee_row.id = qualification_row.employee_id
          and employee_row.tenant_id = qualification_row.tenant_id
        where (v_is_platform_super or qualification_row.tenant_id = v_tenant_id)
          and qualification_row.status = 'valid'
          and qualification_row.expiry_date is not null
          and qualification_row.expiry_date <= current_date + 60
        order by qualification_row.expiry_date, qualification_row.id
        limit 1000
      ) scoped
    ), '[]'::jsonb),
    'headcounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', scoped.id,
        'approvedCount', scoped.approved_count,
        'occupiedCount', scoped.occupied_count,
        'vacancyCount', greatest(scoped.approved_count - scoped.occupied_count, 0),
        'enabled', scoped.enabled,
        'organization', jsonb_build_object(
          'id', scoped.organization_id,
          'organizationCode', scoped.organization_code,
          'organizationName', scoped.organization_name
        ),
        'position', jsonb_build_object(
          'id', scoped.position_id,
          'positionCode', scoped.position_code,
          'positionName', scoped.position_name
        )
      ) order by scoped.organization_name, scoped.position_name, scoped.id)
      from (
        select headcount_row.id, headcount_row.organization_id, headcount_row.position_id,
          headcount_row.approved_count, headcount_row.enabled,
          organization_row.organization_code, organization_row.organization_name,
          position_row.position_code, position_row.position_name,
          (
            select count(*)::integer
            from public.hr_employee employee_row
            where employee_row.tenant_id = headcount_row.tenant_id
              and employee_row.organization_id = headcount_row.organization_id
              and employee_row.position_id = headcount_row.position_id
              and employee_row.employment_status <> 'terminated'
          ) as occupied_count
        from public.hr_position_headcount headcount_row
        left join public.sys_organization organization_row
          on organization_row.id = headcount_row.organization_id
          and organization_row.tenant_id = headcount_row.tenant_id
        left join public.hr_position position_row
          on position_row.id = headcount_row.position_id
          and position_row.tenant_id = headcount_row.tenant_id
        where (v_is_platform_super or headcount_row.tenant_id = v_tenant_id)
          and headcount_row.enabled
          and headcount_row.effective_from <= current_date
          and (headcount_row.effective_to is null or headcount_row.effective_to >= current_date)
        order by organization_row.organization_name, position_row.position_name, headcount_row.id
        limit 1000
      ) scoped
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.hr_get_workforce_risk_secure() from public, anon;
grant execute on function public.hr_get_workforce_risk_secure() to authenticated, service_role;

;
