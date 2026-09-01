-- Tenant-safe workflow analytics used by the operations report.

create or replace function app_private.get_workflow_operational_analytics(
  p_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 7), 365);
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_result jsonb;
begin
  if (select auth.uid()) is null or v_tenant_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;

  with base as (
    select
      instance.id,
      instance.business_type,
      instance.status,
      instance.started_at,
      instance.finished_at,
      exists (
        select 1
        from public.wf_task task
        where task.instance_id = instance.id
          and task.status = 'pending'
          and task.due_at < now()
      ) as is_overdue,
      case
        when instance.finished_at is not null
          then extract(epoch from (instance.finished_at - instance.started_at)) / 3600.0
        else null
      end as duration_hours
    from public.wf_instance instance
    where (v_is_platform_super or instance.tenant_id = v_tenant_id)
      and instance.started_at >= now() - make_interval(days => v_days)
  ), summary as (
    select
      count(*)::integer total_count,
      count(*) filter (where status = 'running')::integer running_count,
      count(*) filter (where status = 'approved')::integer approved_count,
      count(*) filter (where status = 'rejected')::integer rejected_count,
      count(*) filter (where status in ('withdrawn','cancelled'))::integer interrupted_count,
      count(*) filter (where is_overdue)::integer overdue_count,
      round(coalesce(avg(duration_hours) filter (where duration_hours is not null), 0)::numeric, 1)
        average_duration_hours
    from base
  ), business_rows as (
    select
      business_type,
      count(*)::integer total_count,
      count(*) filter (where status = 'running')::integer running_count,
      count(*) filter (where status = 'approved')::integer approved_count,
      count(*) filter (where status = 'rejected')::integer rejected_count,
      count(*) filter (where status in ('withdrawn','cancelled'))::integer interrupted_count,
      count(*) filter (where is_overdue)::integer overdue_count,
      round(coalesce(avg(duration_hours) filter (where duration_hours is not null), 0)::numeric, 1)
        average_duration_hours
    from base
    group by business_type
  ), business_stats as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'businessType', business_type,
          'totalCount', total_count,
          'runningCount', running_count,
          'approvedCount', approved_count,
          'rejectedCount', rejected_count,
          'interruptedCount', interrupted_count,
          'overdueCount', overdue_count,
          'averageDurationHours', average_duration_hours,
          'approvalRate',
            case when approved_count + rejected_count = 0 then 0
              else round(approved_count * 100.0 / (approved_count + rejected_count), 1) end
        )
        order by total_count desc, business_type
      ),
      '[]'::jsonb
    ) value
    from business_rows
  ), report_days as (
    select generate_series(
      current_date - (v_days - 1),
      current_date,
      interval '1 day'
    )::date as report_date
  ), daily_rows as (
    select
      report_days.report_date,
      count(base.id)::integer started_count,
      count(base.id) filter (where base.status = 'approved')::integer approved_count,
      count(base.id) filter (where base.status = 'rejected')::integer rejected_count
    from report_days
    left join base on base.started_at::date = report_days.report_date
    group by report_days.report_date
    order by report_days.report_date
  ), daily_stats as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'date', report_date,
          'startedCount', started_count,
          'approvedCount', approved_count,
          'rejectedCount', rejected_count
        )
        order by report_date
      ),
      '[]'::jsonb
    ) value
    from daily_rows
  )
  select jsonb_build_object(
    'periodDays', v_days,
    'generatedAt', now(),
    'summary', jsonb_build_object(
      'totalCount', summary.total_count,
      'runningCount', summary.running_count,
      'approvedCount', summary.approved_count,
      'rejectedCount', summary.rejected_count,
      'interruptedCount', summary.interrupted_count,
      'overdueCount', summary.overdue_count,
      'averageDurationHours', summary.average_duration_hours
    ),
    'businessTypes', business_stats.value,
    'daily', daily_stats.value
  )
  into v_result
  from summary cross join business_stats cross join daily_stats;

  return v_result;
end;
$function$;

create or replace function public.get_workflow_operational_analytics(
  p_days integer default 30
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select app_private.get_workflow_operational_analytics(p_days)
$function$;

revoke all on function app_private.get_workflow_operational_analytics(integer)
  from public, anon, authenticated;
grant execute on function app_private.get_workflow_operational_analytics(integer)
  to authenticated, service_role;

revoke all on function public.get_workflow_operational_analytics(integer)
  from public, anon;
grant execute on function public.get_workflow_operational_analytics(integer)
  to authenticated, service_role;

;
