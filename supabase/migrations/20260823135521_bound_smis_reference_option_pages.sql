-- Bound tenant-scoped SMIS reference selectors so one request cannot create an
-- unbounded employee or supplier payload.

create or replace function public.smis_list_employee_reference_options(
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns table (
  id uuid,
  employee_no text,
  employee_name text,
  organization_name text,
  job_title text,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 9), greatest(coalesce(p_from, 0), 0));
begin
  if app_private.smis_current_user_id() is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:View') then
    raise exception 'Missing permission: SmisCatalog:View';
  end if;
  if v_to - v_from + 1 > 100 then
    raise exception 'Reference option page size must not exceed 100';
  end if;

  return query
  with filtered as (
    select
      employee_row.id,
      employee_row.employee_no,
      employee_row.employee_name,
      organization_row.organization_name,
      employee_row.job_title
    from public.hr_employee employee_row
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
     and organization_row.tenant_id = employee_row.tenant_id
    where employee_row.tenant_id = v_tenant_id
      and employee_row.employment_status = any(array['probation', 'active']::text[])
      and (
        v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or coalesce(employee_row.job_title, '') ilike '%' || v_keyword || '%'
        or coalesce(organization_row.organization_name, '') ilike '%' || v_keyword || '%'
      )
  ), counted as (
    select filtered.*, count(*) over() as total_count
    from filtered
  )
  select counted.id, counted.employee_no, counted.employee_name,
         counted.organization_name, counted.job_title, counted.total_count
  from counted
  order by counted.employee_no, counted.employee_name
  offset v_from
  limit greatest(v_to - v_from + 1, 1);
end;
$$;

revoke all on function public.smis_list_employee_reference_options(text, integer, integer)
  from public, anon;
grant execute on function public.smis_list_employee_reference_options(text, integer, integer)
  to authenticated, service_role;

create or replace function public.smis_list_supplier_reference_options(
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns table (
  id uuid,
  supplier_code text,
  supplier_name text,
  contact_name text,
  contact_phone text,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 9), greatest(coalesce(p_from, 0), 0));
begin
  if app_private.smis_current_user_id() is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:View') then
    raise exception 'Missing permission: SmisCatalog:View';
  end if;
  if v_to - v_from + 1 > 100 then
    raise exception 'Reference option page size must not exceed 100';
  end if;

  return query
  with filtered as (
    select
      supplier_row.id,
      'SUP-' || upper(left(replace(supplier_row.id::text, '-', ''), 8)) as supplier_code,
      supplier_row.supplier_name::text,
      supplier_row.contact_person::text as contact_name,
      supplier_row.contact_phone::text
    from public.vehicle_supplier supplier_row
    where supplier_row.tenant_id = v_tenant_id
      and (
        v_keyword is null
        or supplier_row.supplier_name ilike '%' || v_keyword || '%'
        or coalesce(supplier_row.contact_person, '') ilike '%' || v_keyword || '%'
        or coalesce(supplier_row.contact_phone, '') ilike '%' || v_keyword || '%'
      )
  ), counted as (
    select filtered.*, count(*) over() as total_count
    from filtered
  )
  select counted.id, counted.supplier_code, counted.supplier_name,
         counted.contact_name, counted.contact_phone, counted.total_count
  from counted
  order by counted.supplier_name
  offset v_from
  limit greatest(v_to - v_from + 1, 1);
end;
$$;

revoke all on function public.smis_list_supplier_reference_options(text, integer, integer)
  from public, anon;
grant execute on function public.smis_list_supplier_reference_options(text, integer, integer)
  to authenticated, service_role;

;
