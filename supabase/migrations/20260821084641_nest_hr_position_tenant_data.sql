create or replace function public.hr_list_positions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_enabled boolean default null,
  p_tenant_id uuid default null
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

  v_limit := least(100, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  with filtered as materialized (
    select
      position_row.*,
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      (select count(*) from public.hr_employee employee_row
       where employee_row.position_id = position_row.id
         and employee_row.tenant_id = position_row.tenant_id) as employee_count
    from public.hr_position position_row
    join public.sys_tenant tenant_row on tenant_row.id = position_row.tenant_id
    where (p_tenant_id is null or position_row.tenant_id = p_tenant_id)
      and (p_enabled is null or position_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or position_row.description ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select * from filtered
    order by tenant_name, sort, position_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        (to_jsonb(paged) - 'tenant_code' - 'tenant_name') || jsonb_build_object(
          'tenant', jsonb_build_object(
            'id', paged.tenant_id,
            'tenant_code', paged.tenant_code,
            'tenant_name', paged.tenant_name
          )
        )
        order by tenant_name, sort, position_name
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.hr_list_positions_secure(integer, integer, text, boolean, uuid)
  from public, anon;
grant execute on function public.hr_list_positions_secure(integer, integer, text, boolean, uuid)
  to authenticated, service_role;

;
