create or replace function public.smis_list_positions_secure(
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_is_platform_super boolean := app_private.is_platform_super();
  v_tenant_id uuid;
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionSafetyResponsibility',
    'SmisPositionSafetyResponsibility:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position safety responsibility view permission'
      using errcode = '42501';
  end if;

  v_tenant_id := case
    when p_organization_id is not null
      then app_private.resolve_organization_tenant_id(p_organization_id)
    when v_is_platform_super then null
    else app_private.current_user_tenant_id()
  end;

  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.id,
      position_row.tenant_id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = position_row.tenant_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
          and (
            p_organization_id is null
            or employee_row.organization_id = p_organization_id
          )
      )::integer as employee_count
    from public.hr_position position_row
    where (v_tenant_id is null or position_row.tenant_id = v_tenant_id)
      and position_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(position_row.description, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        p_organization_id is null
        or position_row.organization_id = p_organization_id
        or exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = position_row.tenant_id
            and headcount_row.position_id = position_row.id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.enabled
            and headcount_row.effective_from <= current_date
            and (
              headcount_row.effective_to is null
              or headcount_row.effective_to >= current_date
            )
        )
        or exists (
          select 1
          from public.hr_employee employee_row
          where employee_row.tenant_id = position_row.tenant_id
            and employee_row.position_id = position_row.id
            and employee_row.organization_id = p_organization_id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_safety_responsibility responsibility_row
          where responsibility_row.tenant_id = position_row.tenant_id
            and responsibility_row.position_id = position_row.id
            and responsibility_row.organization_id = p_organization_id
        )
      )
  ), paged as (
    select *
    from filtered
    order by tenant_id, sort, position_name, position_code
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(paged) order by tenant_id, sort, position_name, position_code)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.smis_list_risk_positions_secure(
  p_organization_id uuid,
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionRiskList',
    'SmisPositionRiskList:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position risk list view permission'
      using errcode = '42501';
  end if;

  v_tenant_id := app_private.resolve_organization_tenant_id(p_organization_id);
  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.id,
      position_row.tenant_id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = position_row.tenant_id
          and employee_row.organization_id = p_organization_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
      )::integer as employee_count,
      (
        select count(*)
        from public.smis_position_risk_control risk_row
        where risk_row.tenant_id = position_row.tenant_id
          and risk_row.organization_id = p_organization_id
          and risk_row.position_id = position_row.id
      )::integer as control_count
    from public.hr_position position_row
    where position_row.tenant_id = v_tenant_id
      and position_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(position_row.description, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        position_row.organization_id = p_organization_id
        or exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = position_row.tenant_id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.position_id = position_row.id
            and headcount_row.enabled
            and headcount_row.effective_from <= current_date
            and (
              headcount_row.effective_to is null
              or headcount_row.effective_to >= current_date
            )
        )
        or exists (
          select 1
          from public.hr_employee employee_row
          where employee_row.tenant_id = position_row.tenant_id
            and employee_row.organization_id = p_organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_risk_control risk_row
          where risk_row.tenant_id = position_row.tenant_id
            and risk_row.organization_id = p_organization_id
            and risk_row.position_id = position_row.id
        )
      )
  ), paged as (
    select *
    from filtered
    order by sort, position_name, position_code
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(paged) order by sort, position_name, position_code)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

;
