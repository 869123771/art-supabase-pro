-- Add three read-only decision workspaces and a due-soon workflow SLA state.
-- Existing roles inherit access only when they already own the closest source page.

insert into public.sys_menu (
  id, parent_id, name, path, component, type, app_code, sort, meta,
  create_by, create_time, update_by, update_time
)
values
  (
    'c0de0000-0000-4000-8000-000000000303'::uuid,
    'c0de0000-0000-4000-8000-000000000300'::uuid,
    'HrTalentInventory', 'talent-inventory', '/hr/talent/talent-inventory', 'menu', 'hr', 3,
    '{"icon":"ri:team-line","title":"人才盘点","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'a1000000-0000-4000-8000-000000000036'::uuid,
    'a1000000-0000-4000-8000-000000000019'::uuid,
    'FinanceReceivableAging', 'receivable-aging', '/fms/receivable-aging/index', 'menu', 'fms', 12,
    '{"icon":"ri:hourglass-line","title":"应收账龄","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'b2000000-0000-4000-8000-000000000002'::uuid,
    '5cb6af14-977a-4a51-8e4d-107db0f1af2e'::uuid,
    'TmsRoutePerformance', 'route-performance', '/tms/route-performance', 'menu', 'tms', 10,
    '{"icon":"ri:road-map-line","title":"线路效能","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'c0de0000-0000-4000-8303-000000000001'::uuid,
    'c0de0000-0000-4000-8000-000000000303'::uuid,
    'Hr:TalentInventory:View', '', '', 'button', 'hr', 1,
    '{"icon":"","title":"查看人才盘点","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'a1000000-0000-4000-8036-000000000001'::uuid,
    'a1000000-0000-4000-8000-000000000036'::uuid,
    'FinanceReceivableAging:View', '', '', 'button', 'fms', 1,
    '{"icon":"","title":"查看应收账龄","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'b2000000-0000-4000-8100-000000000002'::uuid,
    'b2000000-0000-4000-8000-000000000002'::uuid,
    'TmsRoutePerformance:View', '', '', 'button', 'tms', 1,
    '{"icon":"","title":"查看线路效能","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  )
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, type = excluded.type, app_code = excluded.app_code,
  sort = excluded.sort, meta = excluded.meta, update_by = excluded.update_by, update_time = now();

with grants(source_menu_id, target_menu_id) as (
  values
    ('c0de0000-0000-4000-8000-000000000301'::uuid, 'c0de0000-0000-4000-8000-000000000303'::uuid),
    ('c0de0000-0000-4000-8000-000000000301'::uuid, 'c0de0000-0000-4000-8303-000000000001'::uuid),
    ('a1000000-0000-4000-8000-000000000003'::uuid, 'a1000000-0000-4000-8000-000000000036'::uuid),
    ('a1000000-0000-4000-8000-000000000003'::uuid, 'a1000000-0000-4000-8036-000000000001'::uuid),
    ('062a648a-494e-47ef-b2db-94620a565ca0'::uuid, 'b2000000-0000-4000-8000-000000000002'::uuid),
    ('062a648a-494e-47ef-b2db-94620a565ca0'::uuid, 'b2000000-0000-4000-8100-000000000002'::uuid)
)
insert into public.sys_role_menu (
  permission, create_by, create_time, role_id, menu_id, update_by, update_time, tenant_id
)
select source.permission, 'migration', now(), source.role_id, grants.target_menu_id,
  'migration', now(), source.tenant_id
from grants
join public.sys_role_menu source on source.menu_id = grants.source_menu_id
on conflict (role_id, menu_id) do update set
  permission = excluded.permission, update_by = excluded.update_by,
  update_time = now(), tenant_id = excluded.tenant_id;

insert into public.sys_dictionary (
  id, type_id, code, value, label, status, sort, tag_type, tenant_id,
  create_by, create_time, update_by, update_time, i18n_scope
)
select
  '7b280cc9-a576-46c8-bfe3-fc84c212af01'::uuid,
  type_row.id,
  'workflowSlaStatus_due_soon',
  'due_soon',
  '即将超时',
  '1',
  2,
  'warning',
  type_row.tenant_id,
  'migration', now(), 'migration', now(), '1'
from public.sys_dict_type type_row
where type_row.code = 'workflowSlaStatus'
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, value = excluded.value,
  label = excluded.label, status = excluded.status, sort = excluded.sort,
  tag_type = excluded.tag_type, tenant_id = excluded.tenant_id,
  update_by = excluded.update_by, update_time = now();

update public.sys_dictionary dictionary_row
set sort = 3, update_by = 'migration', update_time = now()
from public.sys_dict_type type_row
where dictionary_row.type_id = type_row.id
  and type_row.code = 'workflowSlaStatus'
  and dictionary_row.value = 'overdue';

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

  return jsonb_build_object(
    'generatedAt', now(),
    'records', coalesce((
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
      select jsonb_agg(jsonb_build_object(
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
        employee_row.employee_name, employee_row.id)
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
      ) competency on true
    ), '[]'::jsonb)
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
  return jsonb_build_object(
    'generatedAt', now(),
    'fieldAccess', v_access,
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_customer_statement_to_secure_json(
          to_jsonb(statement_row), base_row.created_by_user_id, null, v_access
        ) || jsonb_build_object('agingDays', greatest(current_date - statement_row.period_end, 0))
        order by statement_row.period_end, statement_row.id
      )
      from public.tms_customer_statement_summary statement_row
      join public.tms_customer_statement base_row on base_row.id = statement_row.id
        and base_row.tenant_id = statement_row.tenant_id
      where (v_is_platform_super or statement_row.tenant_id = v_tenant_id)
        and statement_row.status in ('pending_review', 'confirmed', 'partially_settled')
        and statement_row.outstanding_amount > 0
      limit 1000
    ), '[]'::jsonb)
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

  return jsonb_build_object(
    'generatedAt', now(),
    'periodDays', v_days,
    'records', coalesce((
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
      )
      select jsonb_agg(jsonb_build_object(
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
      ) order by completed_trips desc, delayed_active_trips desc, route_origin, route_destination)
      from aggregated
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.tms_get_route_performance_secure(integer) from public, anon;
grant execute on function public.tms_get_route_performance_secure(integer) to authenticated, service_role;

;
