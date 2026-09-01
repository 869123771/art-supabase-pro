-- Provide a position-specific organization navigator and apply its selected
-- organization scope inside the paginated position query.

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

  if v_target_tenant_id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', organization_row.id,
        'tenant_id', organization_row.tenant_id,
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
      order by organization_row.sort, organization_row.organization_name
    )
    from public.sys_organization organization_row
    where organization_row.tenant_id = v_target_tenant_id
      and organization_row.status = '1'
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.hr_list_position_organization_scope_secure(uuid)
  from public, anon;
grant execute on function public.hr_list_position_organization_scope_secure(uuid)
  to authenticated, service_role;

drop function if exists public.hr_list_positions_secure(
  integer,
  integer,
  text,
  boolean,
  uuid
);

create function public.hr_list_positions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_enabled boolean default null,
  p_tenant_id uuid default null,
  p_organization_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false) then
    raise exception 'Missing position view permission' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then
    p_tenant_id := v_tenant_id;
  end if;

  v_limit := least(
    2000,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.*,
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      organization_row.organization_code,
      organization_row.organization_name,
      profile_row.job_code,
      profile_row.job_name,
      grade_row.grade_code,
      grade_row.grade_name,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.position_id = position_row.id
          and employee_row.tenant_id = position_row.tenant_id
          and employee_row.employment_status <> 'terminated'
      ) as employee_count
    from public.hr_position position_row
    join public.sys_tenant tenant_row on tenant_row.id = position_row.tenant_id
    left join public.sys_organization organization_row
      on organization_row.id = position_row.organization_id
     and organization_row.tenant_id = position_row.tenant_id
    join public.hr_job_profile profile_row
      on profile_row.id = position_row.job_profile_id
     and profile_row.tenant_id = position_row.tenant_id
    left join public.hr_grade grade_row
      on grade_row.id = position_row.grade_id
     and grade_row.tenant_id = position_row.tenant_id
    where (p_tenant_id is null or position_row.tenant_id = p_tenant_id)
      and (
        coalesce(cardinality(p_organization_ids), 0) = 0
        or position_row.organization_id = any(p_organization_ids)
      )
      and (p_enabled is null or position_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or profile_row.job_name ilike '%' || btrim(p_keyword) || '%'
        or organization_row.organization_name ilike '%' || btrim(p_keyword) || '%'
        or position_row.description ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select *
    from filtered
    order by tenant_name, sort, position_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        (to_jsonb(paged)
          - 'tenant_code' - 'tenant_name'
          - 'organization_code' - 'organization_name'
          - 'job_code' - 'job_name' - 'grade_code' - 'grade_name')
        || jsonb_build_object(
          'tenant', jsonb_build_object(
            'id', paged.tenant_id,
            'tenant_code', paged.tenant_code,
            'tenant_name', paged.tenant_name
          ),
          'organization', case
            when paged.organization_id is null then null
            else jsonb_build_object(
              'id', paged.organization_id,
              'organization_code', paged.organization_code,
              'organization_name', paged.organization_name
            )
          end,
          'job_profile', jsonb_build_object(
            'id', paged.job_profile_id,
            'job_code', paged.job_code,
            'job_name', paged.job_name
          ),
          'grade', case
            when paged.grade_id is null then null
            else jsonb_build_object(
              'id', paged.grade_id,
              'grade_code', paged.grade_code,
              'grade_name', paged.grade_name
            )
          end
        )
        order by paged.tenant_name, paged.sort, paged.position_name
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.hr_list_positions_secure(
  integer,
  integer,
  text,
  boolean,
  uuid,
  uuid[]
) from public, anon;
grant execute on function public.hr_list_positions_secure(
  integer,
  integer,
  text,
  boolean,
  uuid,
  uuid[]
) to authenticated, service_role;

;
