-- Bound decision-workspace payloads so large tenants cannot return unbounded JSON arrays.
-- The existing signatures and record shapes remain compatible; capacity metadata is additive.

create or replace function public.hr_get_talent_inventory_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_record_limit constant integer := 1000;
  v_total_records bigint := 0;
  v_records jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('Hr:TalentInventory:View'), false) then
    raise exception 'Missing talent inventory view permission' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Talent inventory tenant is required' using errcode = '22023';
  end if;

  select count(*)
  into v_total_records
  from public.hr_employee employee_row
  where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
    and employee_row.employment_status <> 'terminated';

  with employee_scope as (
    select employee_row.id, employee_row.employee_no, employee_row.employee_name,
      employee_row.job_title, employee_row.organization_id, employee_row.position_id,
      employee_row.tenant_id, organization_row.organization_name, position_row.position_name
    from public.hr_employee employee_row
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
      and organization_row.tenant_id = employee_row.tenant_id
    left join public.hr_position position_row
      on position_row.id = employee_row.position_id
      and position_row.tenant_id = employee_row.tenant_id
    where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
      and employee_row.employment_status <> 'terminated'
    order by employee_row.tenant_id, employee_row.employee_name, employee_row.id
    limit v_record_limit
  ), latest_review as (
    select distinct on (review_row.employee_id)
      review_row.employee_id, review_row.total_score, review_row.performance_level,
      cycle_row.cycle_name
    from public.hr_performance_review review_row
    join public.hr_performance_cycle cycle_row on cycle_row.id = review_row.cycle_id
    join employee_scope employee_row on employee_row.id = review_row.employee_id
      and employee_row.tenant_id = review_row.tenant_id
    where review_row.status in ('confirmed', 'completed')
    order by review_row.employee_id, cycle_row.end_date desc,
      review_row.confirmed_at desc nulls last, review_row.id desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', employee_row.id,
    'employeeNo', employee_row.employee_no,
    'employeeName', employee_row.employee_name,
    'jobTitle', employee_row.job_title,
    'organizationName', employee_row.organization_name,
    'positionName', employee_row.position_name,
    'performanceLevel', review_row.performance_level,
    'totalScore', review_row.total_score,
    'cycleName', review_row.cycle_name,
    'competencyTotal', coalesce(competency.total_count, 0),
    'competencyMet', coalesce(competency.met_count, 0),
    'competencyGapCount', coalesce(competency.total_count - competency.met_count, 0),
    'readinessRate', case when coalesce(competency.total_count, 0) = 0 then null
      else round(competency.met_count * 100.0 / competency.total_count, 1) end
  ) order by coalesce(competency.total_count - competency.met_count, 0) desc,
    employee_row.employee_name, employee_row.id), '[]'::jsonb)
  into v_records
  from employee_scope employee_row
  left join latest_review review_row on review_row.employee_id = employee_row.id
  left join lateral (
    select count(*)::integer as total_count,
      count(*) filter (where
        case employee_competency.current_level
          when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2 when 'basic' then 1 else 0 end
        >= case position_competency.required_level
          when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2 when 'basic' then 1 else 0 end
      )::integer as met_count
    from public.hr_position_competency position_competency
    left join public.hr_employee_competency employee_competency
      on employee_competency.employee_id = employee_row.id
      and employee_competency.competency_id = position_competency.competency_id
      and employee_competency.tenant_id = employee_row.tenant_id
    where position_competency.position_id = employee_row.position_id
      and position_competency.tenant_id = employee_row.tenant_id
  ) competency on true;

  return jsonb_build_object(
    'generatedAt', now(),
    'records', v_records,
    'totalRecords', v_total_records,
    'returnedRecords', jsonb_array_length(v_records),
    'truncated', v_total_records > jsonb_array_length(v_records)
  );
end;
$$;

revoke all on function public.hr_get_talent_inventory_secure() from public, anon;
grant execute on function public.hr_get_talent_inventory_secure() to authenticated, service_role;

create or replace function public.fms_get_receivable_aging_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_access jsonb;
  v_record_limit constant integer := 1000;
  v_total_records bigint := 0;
  v_records jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('FinanceReceivableAging:View'), false) then
    raise exception 'Missing receivable aging view permission' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Receivable aging tenant is required' using errcode = '22023';
  end if;

  v_access := app_private.field_access_map('tms.customer_statement', null);

  select count(*)
  into v_total_records
  from public.tms_customer_statement_summary statement_row
  join public.tms_customer_statement base_row on base_row.id = statement_row.id
    and base_row.tenant_id = statement_row.tenant_id
  where (v_is_platform_super or statement_row.tenant_id = v_tenant_id)
    and statement_row.status in ('pending_review', 'confirmed', 'partially_settled')
    and statement_row.outstanding_amount > 0;

  with bounded as (
    select statement_row.*, base_row.created_by_user_id as base_created_by_user_id
    from public.tms_customer_statement_summary statement_row
    join public.tms_customer_statement base_row on base_row.id = statement_row.id
      and base_row.tenant_id = statement_row.tenant_id
    where (v_is_platform_super or statement_row.tenant_id = v_tenant_id)
      and statement_row.status in ('pending_review', 'confirmed', 'partially_settled')
      and statement_row.outstanding_amount > 0
    order by statement_row.period_end, statement_row.id
    limit v_record_limit
  )
  select coalesce(jsonb_agg(
    app_private.tms_customer_statement_to_secure_json(
      to_jsonb(statement_row) - 'base_created_by_user_id',
      statement_row.base_created_by_user_id,
      null,
      v_access
    ) || jsonb_build_object('agingDays', greatest(current_date - statement_row.period_end, 0))
    order by statement_row.period_end, statement_row.id
  ), '[]'::jsonb)
  into v_records
  from bounded statement_row;

  return jsonb_build_object(
    'generatedAt', now(),
    'fieldAccess', v_access,
    'records', v_records,
    'totalRecords', v_total_records,
    'returnedRecords', jsonb_array_length(v_records),
    'truncated', v_total_records > jsonb_array_length(v_records)
  );
end;
$$;

revoke all on function public.fms_get_receivable_aging_secure() from public, anon;
grant execute on function public.fms_get_receivable_aging_secure() to authenticated, service_role;

create or replace function public.tms_get_route_performance_secure(p_days integer default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_days integer := coalesce(p_days, 90);
  v_record_limit constant integer := 500;
  v_total_records bigint := 0;
  v_records jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('TmsRoutePerformance:View'), false) then
    raise exception 'Missing route performance view permission' using errcode = '42501';
  end if;
  if v_days < 7 or v_days > 365 then
    raise exception 'Route performance period must be between 7 and 365 days' using errcode = '22023';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Route performance tenant is required' using errcode = '22023';
  end if;

  with scoped as (
    select waybill_row.*,
      coalesce(nullif(btrim(waybill_row.origin_city), ''), '未标注') as route_origin,
      coalesce(nullif(btrim(waybill_row.destination_city), ''), '未标注') as route_destination
    from public.tms_waybill waybill_row
    where (v_is_platform_super or waybill_row.tenant_id = v_tenant_id)
      and (
        waybill_row.completed_at >= now() - make_interval(days => v_days)
        or waybill_row.status = any(array['pending','accepted','loading','transporting','unloading'])
      )
  ), aggregated as (
    select route_origin, route_destination,
      count(*) filter (where completed_at >= now() - make_interval(days => v_days))::integer as completed_trips,
      count(*) filter (where completed_at >= now() - make_interval(days => v_days)
        and planned_unload_time is not null)::integer as scheduled_trips,
      count(*) filter (where completed_at >= now() - make_interval(days => v_days)
        and planned_unload_time is not null and completed_at <= planned_unload_time)::integer as on_time_trips,
      round(avg(extract(epoch from (completed_at - departed_at)) / 3600.0)
        filter (where completed_at >= now() - make_interval(days => v_days)
          and departed_at is not null and completed_at >= departed_at), 1) as average_duration_hours,
      round(avg(extract(epoch from (completed_at - planned_unload_time)) / 3600.0)
        filter (where completed_at >= now() - make_interval(days => v_days)
          and planned_unload_time is not null and completed_at > planned_unload_time), 1) as average_delay_hours,
      round(coalesce(sum(cargo_weight_ton) filter
        (where completed_at >= now() - make_interval(days => v_days)), 0), 2) as cargo_weight_ton,
      count(*) filter (where status = any(array['pending','accepted','loading','transporting','unloading']))::integer as active_trips,
      count(*) filter (where status = any(array['pending','accepted','loading','transporting','unloading'])
        and planned_unload_time is not null and planned_unload_time < now())::integer as delayed_active_trips
    from scoped
    group by route_origin, route_destination
  ), ranked as (
    select aggregated.*, count(*) over() as total_records
    from aggregated
  ), bounded as (
    select *
    from ranked
    order by completed_trips desc, delayed_active_trips desc, route_origin, route_destination
    limit v_record_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', md5(route_origin || '→' || route_destination),
    'originCity', route_origin,
    'destinationCity', route_destination,
    'completedTrips', completed_trips,
    'scheduledTrips', scheduled_trips,
    'onTimeTrips', on_time_trips,
    'onTimeRate', case when scheduled_trips = 0 then null
      else round(on_time_trips * 100.0 / scheduled_trips, 1) end,
    'averageDurationHours', average_duration_hours,
    'averageDelayHours', average_delay_hours,
    'cargoWeightTon', cargo_weight_ton,
    'activeTrips', active_trips,
    'delayedActiveTrips', delayed_active_trips
  ) order by completed_trips desc, delayed_active_trips desc, route_origin, route_destination), '[]'::jsonb),
    coalesce(max(total_records), 0)
  into v_records, v_total_records
  from bounded;

  return jsonb_build_object(
    'generatedAt', now(),
    'periodDays', v_days,
    'records', v_records,
    'totalRecords', v_total_records,
    'returnedRecords', jsonb_array_length(v_records),
    'truncated', v_total_records > jsonb_array_length(v_records)
  );
end;
$$;

revoke all on function public.tms_get_route_performance_secure(integer) from public, anon;
grant execute on function public.tms_get_route_performance_secure(integer) to authenticated, service_role;

;
