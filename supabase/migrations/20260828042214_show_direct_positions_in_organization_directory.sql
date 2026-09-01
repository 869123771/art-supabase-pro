create or replace function public.hr_get_organization_position_directory_secure(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_employee_total bigint;
  v_employee_limit integer := 2000;
begin
  if not app_private.can_execute_business_action(
    'HrOrganizationPosition',
    'Hr:OrganizationPosition:View',
    null,
    false
  ) then
    raise exception 'Missing organization position directory view permission'
      using errcode = '42501';
  end if;

  select organization_row.tenant_id
  into v_target_tenant_id
  from public.sys_organization organization_row
  where organization_row.id = p_organization_id
    and organization_row.status = '1';

  if v_target_tenant_id is null
    or (
      not app_private.is_platform_super()
      and v_target_tenant_id <> v_current_tenant_id
    )
  then
    raise exception '组织不存在、已停用或超出当前租户范围' using errcode = '42501';
  end if;

  select count(*)
  into v_employee_total
  from public.hr_employee employee_row
  where employee_row.tenant_id = v_target_tenant_id
    and employee_row.organization_id = p_organization_id
    and employee_row.employment_status <> 'terminated';

  return (
    with position_records as (
      select
        position_row.id,
        position_row.tenant_id,
        position_row.position_code,
        position_row.position_name,
        position_row.position_kind,
        position_row.system_code,
        position_row.enabled,
        position_row.sort,
        position_row.description,
        (
          select count(*)
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_target_tenant_id
            and employee_row.organization_id = p_organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )::integer as employee_count
      from public.hr_position position_row
      where position_row.tenant_id = v_target_tenant_id
        and position_row.enabled
        and (
          position_row.organization_id = p_organization_id
          or exists (
            select 1
            from public.hr_employee employee_row
            where employee_row.tenant_id = v_target_tenant_id
              and employee_row.organization_id = p_organization_id
              and employee_row.position_id = position_row.id
              and employee_row.employment_status <> 'terminated'
          )
          or exists (
            select 1
            from public.hr_position_headcount headcount_row
            where headcount_row.tenant_id = v_target_tenant_id
              and headcount_row.organization_id = p_organization_id
              and headcount_row.position_id = position_row.id
              and headcount_row.enabled
              and headcount_row.effective_from <= current_date
              and (
                headcount_row.effective_to is null
                or headcount_row.effective_to >= current_date
              )
          )
        )
    ), employee_records as (
      select
        employee_row.id,
        employee_row.organization_id,
        employee_row.position_id,
        employee_row.employee_no,
        employee_row.employee_name,
        employee_row.avatar_url,
        employee_row.job_title,
        employee_row.employment_status,
        employee_row.employment_type,
        employee_row.hire_date
      from public.hr_employee employee_row
      where employee_row.tenant_id = v_target_tenant_id
        and employee_row.organization_id = p_organization_id
        and employee_row.employment_status <> 'terminated'
      order by employee_row.employee_name, employee_row.employee_no
      limit v_employee_limit
    )
    select jsonb_build_object(
      'positions', coalesce((
        select jsonb_agg(to_jsonb(position_records) order by sort, position_name, position_code)
        from position_records
      ), '[]'::jsonb),
      'employees', coalesce((
        select jsonb_agg(to_jsonb(employee_records) order by employee_name, employee_no)
        from employee_records
      ), '[]'::jsonb),
      'employee_total', v_employee_total,
      'truncated', v_employee_total > v_employee_limit
    )
  );
end;
$$;

revoke all on function public.hr_get_organization_position_directory_secure(uuid)
from public, anon;
grant execute on function public.hr_get_organization_position_directory_secure(uuid)
to authenticated, service_role;

comment on function public.hr_get_organization_position_directory_secure(uuid) is
  'Returns every enabled position owned by the selected organization, including positions with zero incumbents, plus legacy headcount/assignment-linked positions and direct employees.';

;
