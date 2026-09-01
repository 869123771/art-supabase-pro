-- Align secure accident dashboard RPCs with the actual SMIS dashboard menu name.

create or replace function public.smis_list_open_accident_cases_secure(
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 2000);
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  if not app_private.can_access_business_menu('SmisSafetyDashboard') then
    raise exception 'Missing SMIS dashboard access' using errcode = '42501';
  end if;
  select count(*) into v_total
  from public.smis_accident_case case_row
  where case_row.tenant_id = v_tenant_id
    and case_row.status not in ('closed', 'cancelled');

  for v_row in
    select case_row.id, case_row.created_by_user_id
    from public.smis_accident_case case_row
    where case_row.tenant_id = v_tenant_id
      and case_row.status not in ('closed', 'cancelled')
    order by case_row.occurred_at desc, case_row.id
    limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.smis_accident_case_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;
  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('smis.accident_case', null)
  );
end;
$$;

create or replace function public.smis_get_accident_risk_counts_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_access_business_menu('SmisSafetyDashboard') then
    raise exception 'Missing SMIS dashboard access' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'open_accidents', (
      select count(*) from public.smis_accident_case case_row
      where case_row.tenant_id = v_tenant_id
        and case_row.status not in ('closed', 'cancelled')
    ),
    'major_accidents', (
      select count(*) from public.smis_accident_case case_row
      where case_row.tenant_id = v_tenant_id
        and case_row.status not in ('closed', 'cancelled')
        and case_row.severity in ('major', 'critical')
    )
  );
end;
$$;

revoke all on function public.smis_list_open_accident_cases_secure(integer)
  from public, anon;
revoke all on function public.smis_get_accident_risk_counts_secure()
  from public, anon;
grant execute on function public.smis_list_open_accident_cases_secure(integer)
  to authenticated, service_role;
grant execute on function public.smis_get_accident_risk_counts_secure()
  to authenticated, service_role;

;
