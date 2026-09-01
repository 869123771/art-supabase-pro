-- Extend the second wave of operational decision workspaces for TMS, FMS, and HR.
-- All RPCs are read-only, permission-gated, tenant-scoped, and return bounded payloads.

create or replace function public.tms_get_capacity_planning_secure(p_days integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_days integer := coalesce(p_days, 14);
  v_active_fleet_count integer := 0;
  v_fleet_capacity_ton numeric := 0;
  v_current_assigned integer := 0;
  v_active_waybill_count integer := 0;
  v_unassigned_active_count integer := 0;
  v_backlog_count integer := 0;
  v_daily jsonb := '[]'::jsonb;
  v_backlog jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('TmsCapacityPlanning:View'), false) then
    raise exception 'Missing capacity planning view permission' using errcode = '42501';
  end if;
  if v_days not in (7, 14, 30) then
    raise exception 'Capacity planning period must be 7, 14, or 30 days' using errcode = '22023';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Capacity planning tenant is required' using errcode = '22023';
  end if;

  select count(*)::integer,
    round(coalesce(sum(coalesce(vehicle_row.approved_load_mass, 0)), 0), 2)
  into v_active_fleet_count, v_fleet_capacity_ton
  from public.vehicle_archive vehicle_row
  where (v_is_platform_super or vehicle_row.tenant_id = v_tenant_id)
    and vehicle_row.operation_status = 'operating'
    and vehicle_row.audit_status = 'approved';

  select count(*)::integer,
    count(distinct waybill_row.vehicle_id) filter (where waybill_row.vehicle_id is not null)::integer,
    count(*) filter (where waybill_row.vehicle_id is null)::integer
  into v_active_waybill_count, v_current_assigned, v_unassigned_active_count
  from public.tms_waybill waybill_row
  where (v_is_platform_super or waybill_row.tenant_id = v_tenant_id)
    and waybill_row.status = any(array['pending', 'accepted', 'loading', 'transporting', 'unloading']);

  with date_series as (
    select generate_series(current_date, current_date + (v_days - 1), interval '1 day')::date as plan_date
  ), scoped as (
    select waybill_row.*,
      coalesce(waybill_row.planned_load_time::date, waybill_row.create_time::date) as demand_date
    from public.tms_waybill waybill_row
    where (v_is_platform_super or waybill_row.tenant_id = v_tenant_id)
      and waybill_row.status <> 'cancelled'
      and coalesce(waybill_row.planned_load_time::date, waybill_row.create_time::date)
        between current_date and current_date + (v_days - 1)
  ), daily as (
    select date_row.plan_date,
      count(waybill_row.id)::integer as demand_trips,
      round(coalesce(sum(coalesce(waybill_row.cargo_weight_ton, 0)), 0), 2) as demand_ton,
      count(distinct waybill_row.vehicle_id) filter (where waybill_row.vehicle_id is not null)::integer
        as assigned_vehicles,
      count(waybill_row.id) filter (where waybill_row.vehicle_id is null)::integer
        as unassigned_trips
    from date_series date_row
    left join scoped waybill_row on waybill_row.demand_date = date_row.plan_date
    group by date_row.plan_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', daily.plan_date,
    'demandTrips', daily.demand_trips,
    'demandTon', daily.demand_ton,
    'assignedVehicles', daily.assigned_vehicles,
    'unassignedTrips', daily.unassigned_trips,
    'fleetCapacityTon', v_fleet_capacity_ton,
    'loadRate', case when v_fleet_capacity_ton <= 0 then null
      else round(daily.demand_ton * 100.0 / v_fleet_capacity_ton, 1) end
  ) order by daily.plan_date), '[]'::jsonb)
  into v_daily
  from daily;

  select count(*)::integer
  into v_backlog_count
  from public.tms_waybill waybill_row
  where (v_is_platform_super or waybill_row.tenant_id = v_tenant_id)
    and waybill_row.status = any(array['pending', 'accepted'])
    and waybill_row.vehicle_id is null;

  with bounded as (
    select waybill_row.id, waybill_row.waybill_no, waybill_row.status,
      waybill_row.origin_city, waybill_row.destination_city,
      waybill_row.planned_load_time, waybill_row.cargo_weight_ton,
      waybill_row.create_time
    from public.tms_waybill waybill_row
    where (v_is_platform_super or waybill_row.tenant_id = v_tenant_id)
      and waybill_row.status = any(array['pending', 'accepted'])
      and waybill_row.vehicle_id is null
    order by waybill_row.planned_load_time nulls first, waybill_row.create_time, waybill_row.id
    limit 100
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bounded.id,
    'waybillNo', bounded.waybill_no,
    'status', bounded.status,
    'originCity', bounded.origin_city,
    'destinationCity', bounded.destination_city,
    'plannedLoadTime', bounded.planned_load_time,
    'cargoWeightTon', bounded.cargo_weight_ton,
    'waitingHours', greatest(round(extract(epoch from (now() - bounded.create_time)) / 3600.0, 1), 0)
  ) order by bounded.planned_load_time nulls first, bounded.create_time, bounded.id), '[]'::jsonb)
  into v_backlog
  from bounded;

  return jsonb_build_object(
    'generatedAt', now(),
    'periodDays', v_days,
    'activeFleetCount', v_active_fleet_count,
    'fleetCapacityTon', v_fleet_capacity_ton,
    'activeWaybillCount', v_active_waybill_count,
    'assignedVehicleCount', v_current_assigned,
    'availableVehicleCount', greatest(v_active_fleet_count - v_current_assigned, 0),
    'unassignedActiveCount', v_unassigned_active_count,
    'backlogCount', v_backlog_count,
    'returnedBacklogCount', jsonb_array_length(v_backlog),
    'truncated', v_backlog_count > jsonb_array_length(v_backlog),
    'daily', v_daily,
    'backlog', v_backlog
  );
end;
$function$;

revoke all on function public.tms_get_capacity_planning_secure(integer) from public, anon;
grant execute on function public.tms_get_capacity_planning_secure(integer) to authenticated, service_role;

comment on function public.tms_get_capacity_planning_secure(integer) is
  'Permission-gated tenant capacity planning workspace with a bounded backlog payload.';

create or replace function public.fms_get_financial_exception_center_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_posting_failed integer := 0;
  v_posting_pending integer := 0;
  v_bank_unmatched integer := 0;
  v_cost_pending_review integer := 0;
  v_overdue_receivable integer := 0;
  v_close_blocking integer := 0;
  v_total_issues integer := 0;
  v_issues jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('FinanceExceptionCenter:View'), false) then
    raise exception 'Missing financial exception center view permission' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Financial exception tenant is required' using errcode = '22023';
  end if;

  select count(*) filter (where event_row.status = 'failed')::integer,
    count(*) filter (where event_row.status = 'pending')::integer
  into v_posting_failed, v_posting_pending
  from public.fms_posting_event event_row
  where (v_is_platform_super or event_row.tenant_id = v_tenant_id);

  select count(*)::integer
  into v_bank_unmatched
  from public.fms_bank_statement_line line_row
  where (v_is_platform_super or line_row.tenant_id = v_tenant_id)
    and line_row.status not in ('matched', 'ignored');

  select count(*)::integer
  into v_cost_pending_review
  from public.tms_waybill_cost cost_row
  where (v_is_platform_super or cost_row.tenant_id = v_tenant_id)
    and cost_row.audit_status = 'pending_review';

  select count(*)::integer
  into v_overdue_receivable
  from public.tms_customer_statement_summary statement_row
  where (v_is_platform_super or statement_row.tenant_id = v_tenant_id)
    and statement_row.status in ('pending_review', 'confirmed', 'partially_settled')
    and statement_row.outstanding_amount > 0
    and statement_row.period_end < current_date;

  select count(*)::integer
  into v_close_blocking
  from public.fms_period_close_check check_row
  where (v_is_platform_super or check_row.tenant_id = v_tenant_id)
    and check_row.is_blocking
    and check_row.status <> 'passed'
    and check_row.checked_at >= now() - interval '90 days';

  v_total_issues := v_posting_failed + v_posting_pending + v_bank_unmatched
    + v_cost_pending_review + v_overdue_receivable + v_close_blocking;

  with issues as (
    select 'posting'::text as category,
      case when event_row.status = 'failed' then 'critical' else 'warning' end::text as severity,
      case when event_row.status = 'failed' then 1 else 2 end as severity_order,
      'posting:' || event_row.id::text as id,
      case when event_row.status = 'failed' then '自动入账失败' else '自动入账待处理' end as title,
      concat_ws(' · ', nullif(event_row.source_type, ''), nullif(event_row.source_no, '')) as description,
      event_row.source_no as source_no,
      event_row.create_time as occurred_at,
      '/fms/accounting/auto-posting'::text as route_path,
      '查看自动入账'::text as route_label
    from public.fms_posting_event event_row
    where (v_is_platform_super or event_row.tenant_id = v_tenant_id)
      and event_row.status in ('failed', 'pending')

    union all

    select 'bank'::text, 'warning'::text, 2,
      'bank:' || line_row.id::text,
      '银行流水尚未匹配',
      concat_ws(' · ', line_row.transaction_date::text, nullif(line_row.counterparty_name, '')),
      nullif(line_row.bank_reference, ''), line_row.create_time,
      '/fms/treasury/bank-reconciliation', '处理银行对账'
    from public.fms_bank_statement_line line_row
    where (v_is_platform_super or line_row.tenant_id = v_tenant_id)
      and line_row.status not in ('matched', 'ignored')

    union all

    select 'cost'::text, 'warning'::text, 2,
      'cost:' || cost_row.id::text,
      '运单费用待审核',
      concat_ws(' · ', nullif(cost_row.waybill_no_snapshot, ''), nullif(cost_row.cost_type, '')),
      nullif(cost_row.cost_no, ''), cost_row.create_time,
      '/fms/settlement/waybill-cost', '审核运单费用'
    from public.tms_waybill_cost cost_row
    where (v_is_platform_super or cost_row.tenant_id = v_tenant_id)
      and cost_row.audit_status = 'pending_review'

    union all

    select 'receivable'::text,
      case when current_date - statement_row.period_end > 90 then 'critical' else 'attention' end::text,
      case when current_date - statement_row.period_end > 90 then 1 else 3 end,
      'receivable:' || statement_row.id::text,
      '客户应收已逾期',
      concat_ws(' · ', nullif(statement_row.customer_name, ''),
        (current_date - statement_row.period_end)::text || ' 天'),
      statement_row.statement_no, statement_row.create_time,
      '/fms/settlement/receivable-aging', '查看应收账龄'
    from public.tms_customer_statement_summary statement_row
    where (v_is_platform_super or statement_row.tenant_id = v_tenant_id)
      and statement_row.status in ('pending_review', 'confirmed', 'partially_settled')
      and statement_row.outstanding_amount > 0
      and statement_row.period_end < current_date

    union all

    select 'close'::text, 'critical'::text, 1,
      'close:' || check_row.id::text,
      '月结检查存在阻断',
      concat_ws(' · ', nullif(check_row.check_name, ''), check_row.issue_count::text || ' 项'),
      check_row.check_code, check_row.checked_at,
      '/fms/specialized-accounting/period-close', '处理月结阻断'
    from public.fms_period_close_check check_row
    where (v_is_platform_super or check_row.tenant_id = v_tenant_id)
      and check_row.is_blocking
      and check_row.status <> 'passed'
      and check_row.checked_at >= now() - interval '90 days'
  ), bounded as (
    select * from issues
    order by severity_order, occurred_at desc nulls last, id
    limit 80
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bounded.id,
    'category', bounded.category,
    'severity', bounded.severity,
    'title', bounded.title,
    'description', bounded.description,
    'sourceNo', bounded.source_no,
    'occurredAt', bounded.occurred_at,
    'routePath', bounded.route_path,
    'routeLabel', bounded.route_label
  ) order by bounded.severity_order, bounded.occurred_at desc nulls last, bounded.id), '[]'::jsonb)
  into v_issues
  from bounded;

  return jsonb_build_object(
    'generatedAt', now(),
    'totalIssues', v_total_issues,
    'returnedIssues', jsonb_array_length(v_issues),
    'truncated', v_total_issues > jsonb_array_length(v_issues),
    'postingFailedCount', v_posting_failed,
    'postingPendingCount', v_posting_pending,
    'bankUnmatchedCount', v_bank_unmatched,
    'costPendingReviewCount', v_cost_pending_review,
    'overdueReceivableCount', v_overdue_receivable,
    'closeBlockingCount', v_close_blocking,
    'issues', v_issues
  );
end;
$function$;

revoke all on function public.fms_get_financial_exception_center_secure() from public, anon;
grant execute on function public.fms_get_financial_exception_center_secure() to authenticated, service_role;

comment on function public.fms_get_financial_exception_center_secure() is
  'Permission-gated tenant financial exception center without sensitive amount fields.';

create or replace function public.hr_get_skill_matrix_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_record_limit constant integer := 1000;
  v_total_records integer := 0;
  v_modelled_employees integer := 0;
  v_assessed_employees integer := 0;
  v_ready_employees integer := 0;
  v_gap_employees integer := 0;
  v_unassessed_employees integer := 0;
  v_records jsonb := '[]'::jsonb;
  v_competencies jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce(app_private.has_permission('Hr:SkillMatrix:View'), false) then
    raise exception 'Missing skill matrix view permission' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception 'Skill matrix tenant is required' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_total_records
  from public.hr_employee employee_row
  where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
    and employee_row.employment_status <> 'terminated';

  with employee_scope as (
    select employee_row.id, employee_row.tenant_id, employee_row.employee_no,
      employee_row.employee_name, employee_row.job_title, employee_row.organization_id,
      employee_row.position_id, organization_row.organization_name, position_row.position_name
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
  ), employee_matrix as (
    select employee_row.*,
      coalesce(matrix.required_count, 0)::integer as required_count,
      coalesce(matrix.assessed_count, 0)::integer as assessed_count,
      coalesce(matrix.met_count, 0)::integer as met_count
    from employee_scope employee_row
    left join lateral (
      select count(*)::integer as required_count,
        count(employee_competency.id)::integer as assessed_count,
        count(*) filter (where
          case employee_competency.current_level
            when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2
            when 'basic' then 1 else 0 end
          >= case position_competency.required_level
            when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2
            when 'basic' then 1 else 0 end
        )::integer as met_count
      from public.hr_position_competency position_competency
      left join public.hr_employee_competency employee_competency
        on employee_competency.employee_id = employee_row.id
        and employee_competency.competency_id = position_competency.competency_id
        and employee_competency.tenant_id = employee_row.tenant_id
      where position_competency.position_id = employee_row.position_id
        and position_competency.tenant_id = employee_row.tenant_id
    ) matrix on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', employee_matrix.id,
      'employeeNo', employee_matrix.employee_no,
      'employeeName', employee_matrix.employee_name,
      'jobTitle', employee_matrix.job_title,
      'organizationName', employee_matrix.organization_name,
      'positionName', employee_matrix.position_name,
      'requiredCount', employee_matrix.required_count,
      'assessedCount', employee_matrix.assessed_count,
      'metCount', employee_matrix.met_count,
      'gapCount', greatest(employee_matrix.required_count - employee_matrix.met_count, 0),
      'unassessedCount', greatest(employee_matrix.required_count - employee_matrix.assessed_count, 0),
      'readinessRate', case when employee_matrix.required_count = 0 then null
        else round(employee_matrix.met_count * 100.0 / employee_matrix.required_count, 1) end
    ) order by greatest(employee_matrix.required_count - employee_matrix.met_count, 0) desc,
      employee_matrix.employee_name, employee_matrix.id), '[]'::jsonb),
    count(*) filter (where employee_matrix.required_count > 0)::integer,
    count(*) filter (where employee_matrix.assessed_count > 0)::integer,
    count(*) filter (where employee_matrix.required_count > 0
      and employee_matrix.met_count = employee_matrix.required_count)::integer,
    count(*) filter (where employee_matrix.required_count > employee_matrix.met_count)::integer,
    count(*) filter (where employee_matrix.required_count > 0
      and employee_matrix.assessed_count = 0)::integer
  into v_records, v_modelled_employees, v_assessed_employees, v_ready_employees,
    v_gap_employees, v_unassessed_employees
  from employee_matrix;

  with employee_scope as (
    select employee_row.id, employee_row.tenant_id, employee_row.position_id
    from public.hr_employee employee_row
    where (v_is_platform_super or employee_row.tenant_id = v_tenant_id)
      and employee_row.employment_status <> 'terminated'
    order by employee_row.tenant_id, employee_row.employee_name, employee_row.id
    limit v_record_limit
  ), competency_matrix as (
    select competency_row.id, competency_row.competency_code, competency_row.competency_name,
      coalesce(nullif(competency_row.category, ''), '未分类') as category,
      count(*)::integer as required_employees,
      count(employee_competency.id)::integer as assessed_employees,
      count(*) filter (where
        case employee_competency.current_level
          when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2
          when 'basic' then 1 else 0 end
        >= case position_competency.required_level
          when 'expert' then 4 when 'advanced' then 3 when 'intermediate' then 2
          when 'basic' then 1 else 0 end
      )::integer as met_employees,
      round(avg(position_competency.weight), 1) as average_weight
    from employee_scope employee_row
    join public.hr_position_competency position_competency
      on position_competency.position_id = employee_row.position_id
      and position_competency.tenant_id = employee_row.tenant_id
    join public.hr_competency competency_row
      on competency_row.id = position_competency.competency_id
      and competency_row.tenant_id = employee_row.tenant_id
    left join public.hr_employee_competency employee_competency
      on employee_competency.employee_id = employee_row.id
      and employee_competency.competency_id = competency_row.id
      and employee_competency.tenant_id = employee_row.tenant_id
    group by competency_row.id, competency_row.competency_code,
      competency_row.competency_name, competency_row.category
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', competency_matrix.id,
    'competencyCode', competency_matrix.competency_code,
    'competencyName', competency_matrix.competency_name,
    'category', competency_matrix.category,
    'requiredEmployees', competency_matrix.required_employees,
    'assessedEmployees', competency_matrix.assessed_employees,
    'metEmployees', competency_matrix.met_employees,
    'gapEmployees', greatest(competency_matrix.required_employees - competency_matrix.met_employees, 0),
    'unassessedEmployees', greatest(competency_matrix.required_employees - competency_matrix.assessed_employees, 0),
    'readinessRate', case when competency_matrix.required_employees = 0 then null
      else round(competency_matrix.met_employees * 100.0 / competency_matrix.required_employees, 1) end,
    'averageWeight', competency_matrix.average_weight
  ) order by greatest(competency_matrix.required_employees - competency_matrix.met_employees, 0) desc,
    competency_matrix.competency_name, competency_matrix.id), '[]'::jsonb)
  into v_competencies
  from competency_matrix;

  return jsonb_build_object(
    'generatedAt', now(),
    'totalRecords', v_total_records,
    'returnedRecords', jsonb_array_length(v_records),
    'truncated', v_total_records > jsonb_array_length(v_records),
    'employeeCount', jsonb_array_length(v_records),
    'modelledEmployeeCount', v_modelled_employees,
    'assessedEmployeeCount', v_assessed_employees,
    'readyEmployeeCount', v_ready_employees,
    'gapEmployeeCount', v_gap_employees,
    'unassessedEmployeeCount', v_unassessed_employees,
    'records', v_records,
    'competencies', v_competencies
  );
end;
$function$;

revoke all on function public.hr_get_skill_matrix_secure() from public, anon;
grant execute on function public.hr_get_skill_matrix_secure() to authenticated, service_role;

comment on function public.hr_get_skill_matrix_secure() is
  'Permission-gated tenant skill matrix with bounded employee and competency summaries.';

do $block$
declare
  v_parent_id uuid;
  v_page_id uuid;
begin
  select id into v_parent_id from public.sys_menu
  where name = 'TmsTransportation' and type = 'menu' and app_code = 'tms' limit 1;

  select id into v_page_id from public.sys_menu
  where name = 'TmsCapacityPlanning' and type = 'menu' limit 1;
  if v_page_id is null then
    v_page_id := gen_random_uuid();
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      v_page_id, v_parent_id, 'TmsCapacityPlanning', 'capacity-planning',
      '/tms/capacity-planning', 'menu', 'tms', 11,
      '{"icon":"ri:truck-line","title":"运力容量中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  else
    update public.sys_menu set parent_id = v_parent_id, path = 'capacity-planning',
      component = '/tms/capacity-planning', app_code = 'tms', sort = 11,
      meta = '{"icon":"ri:truck-line","title":"运力容量中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      update_by = 'migration', update_time = now()
    where id = v_page_id;
  end if;

  if not exists (select 1 from public.sys_menu where name = 'TmsCapacityPlanning:View') then
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      gen_random_uuid(), v_page_id, 'TmsCapacityPlanning:View', '', '', 'button', 'tms', 1,
      '{"icon":"","title":"查看运力容量","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  end if;
end;
$block$;

do $block$
declare
  v_parent_id uuid;
  v_page_id uuid;
begin
  select id into v_parent_id from public.sys_menu
  where name = 'FinanceCenter' and type = 'menu' and app_code = 'fms' limit 1;

  select id into v_page_id from public.sys_menu
  where name = 'FinanceExceptionCenter' and type = 'menu' limit 1;
  if v_page_id is null then
    v_page_id := gen_random_uuid();
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      v_page_id, v_parent_id, 'FinanceExceptionCenter', 'exception-center',
      '/fms/exception-center', 'menu', 'fms', 6,
      '{"icon":"ri:alarm-warning-line","title":"财务异常中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  else
    update public.sys_menu set parent_id = v_parent_id, path = 'exception-center',
      component = '/fms/exception-center', app_code = 'fms', sort = 6,
      meta = '{"icon":"ri:alarm-warning-line","title":"财务异常中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      update_by = 'migration', update_time = now()
    where id = v_page_id;
  end if;

  if not exists (select 1 from public.sys_menu where name = 'FinanceExceptionCenter:View') then
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      gen_random_uuid(), v_page_id, 'FinanceExceptionCenter:View', '', '', 'button', 'fms', 1,
      '{"icon":"","title":"查看财务异常","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  end if;
end;
$block$;

do $block$
declare
  v_parent_id uuid;
  v_page_id uuid;
begin
  select id into v_parent_id from public.sys_menu
  where name = 'HrTalent' and type = 'menu' and app_code = 'hr' limit 1;

  select id into v_page_id from public.sys_menu
  where name = 'HrSkillMatrix' and type = 'menu' limit 1;
  if v_page_id is null then
    v_page_id := gen_random_uuid();
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      v_page_id, v_parent_id, 'HrSkillMatrix', 'skill-matrix',
      '/hr/talent/skill-matrix', 'menu', 'hr', 4,
      '{"icon":"ri:grid-line","title":"技能矩阵","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  else
    update public.sys_menu set parent_id = v_parent_id, path = 'skill-matrix',
      component = '/hr/talent/skill-matrix', app_code = 'hr', sort = 4,
      meta = '{"icon":"ri:grid-line","title":"技能矩阵","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
      update_by = 'migration', update_time = now()
    where id = v_page_id;
  end if;

  if not exists (select 1 from public.sys_menu where name = 'Hr:SkillMatrix:View') then
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta,
      create_by, create_time, update_by, update_time
    ) values (
      gen_random_uuid(), v_page_id, 'Hr:SkillMatrix:View', '', '', 'button', 'hr', 1,
      '{"icon":"","title":"查看技能矩阵","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
      'migration', now(), 'migration', now()
    );
  end if;
end;
$block$;

with grant_pairs(source_name, target_name) as (
  values
    ('TmsRoutePerformance', 'TmsCapacityPlanning'),
    ('TmsRoutePerformance', 'TmsCapacityPlanning:View'),
    ('FinanceWorkbench', 'FinanceExceptionCenter'),
    ('FinanceWorkbench', 'FinanceExceptionCenter:View'),
    ('HrTalentInventory', 'HrSkillMatrix'),
    ('HrTalentInventory', 'Hr:SkillMatrix:View')
), resolved as (
  select source_menu.id as source_menu_id, target_menu.id as target_menu_id
  from grant_pairs
  join public.sys_menu source_menu on source_menu.name = grant_pairs.source_name
  join public.sys_menu target_menu on target_menu.name = grant_pairs.target_name
)
insert into public.sys_role_menu (
  permission, create_by, create_time, role_id, menu_id, update_by, update_time, tenant_id
)
select source.permission, 'migration', now(), source.role_id, resolved.target_menu_id,
  'migration', now(), source.tenant_id
from resolved
join public.sys_role_menu source on source.menu_id = resolved.source_menu_id
on conflict (role_id, menu_id) do update set
  permission = excluded.permission,
  update_by = excluded.update_by,
  update_time = now(),
  tenant_id = excluded.tenant_id;

;
