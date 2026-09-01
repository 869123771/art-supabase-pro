-- Tenant-safe workflow bottleneck and approver workload analytics.

create index if not exists wf_task_tenant_create_time_idx
  on public.wf_task(tenant_id, create_time desc);

create or replace function app_private.get_workflow_bottleneck_analytics(
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

  with task_base as (
    select
      task.id,
      task.tenant_id,
      tenant.tenant_name,
      instance.definition_id,
      definition.name as definition_name,
      instance.business_type,
      task.node_key,
      task.node_name,
      task.assignee_user_id,
      task.assignee_name_snapshot,
      task.assignment_source,
      task.status,
      task.create_time,
      task.handled_at,
      task.due_at,
      greatest(
        extract(epoch from (coalesce(task.handled_at, now()) - task.create_time)) / 3600.0,
        0
      ) as elapsed_hours,
      (
        task.due_at is not null
        and (
          (task.handled_at is not null and task.handled_at > task.due_at)
          or (task.status = 'pending' and now() > task.due_at)
        )
      ) as is_sla_breached
    from public.wf_task task
    join public.wf_instance instance on instance.id = task.instance_id
    join public.wf_definition definition on definition.id = instance.definition_id
    join public.sys_tenant tenant on tenant.id = task.tenant_id
    where (v_is_platform_super or task.tenant_id = v_tenant_id)
      and task.create_time >= now() - make_interval(days => v_days)
  ), summary as (
    select
      count(*)::integer task_count,
      count(*) filter (where status = 'pending')::integer pending_count,
      count(*) filter (where status = 'pending' and is_sla_breached)::integer overdue_pending_count,
      count(*) filter (where handled_at is not null)::integer handled_count,
      count(*) filter (where due_at is not null)::integer sla_measured_count,
      count(*) filter (where is_sla_breached)::integer sla_breached_count,
      count(*) filter (where assignment_source = 'delegation')::integer delegated_count,
      count(*) filter (where assignment_source = 'transfer')::integer transferred_count,
      round(
        coalesce(avg(elapsed_hours) filter (where handled_at is not null), 0)::numeric,
        1
      ) as average_handle_hours,
      round(
        coalesce(
          percentile_cont(0.9) within group (order by elapsed_hours)
            filter (where handled_at is not null),
          0
        )::numeric,
        1
      ) as p90_handle_hours
    from task_base
  ), node_base as (
    select
      tenant_id,
      tenant_name,
      definition_id,
      definition_name,
      business_type,
      node_key,
      node_name,
      count(*)::integer task_count,
      count(*) filter (where status = 'pending')::integer pending_count,
      count(*) filter (where status = 'pending' and is_sla_breached)::integer overdue_pending_count,
      count(*) filter (where handled_at is not null)::integer handled_count,
      count(*) filter (where status = 'approved')::integer approved_count,
      count(*) filter (where status = 'rejected')::integer rejected_count,
      count(*) filter (where due_at is not null)::integer sla_measured_count,
      count(*) filter (where is_sla_breached)::integer sla_breached_count,
      round(
        coalesce(avg(elapsed_hours) filter (where handled_at is not null), 0)::numeric,
        1
      ) as average_handle_hours,
      round(
        coalesce(
          percentile_cont(0.9) within group (order by elapsed_hours)
            filter (where handled_at is not null),
          0
        )::numeric,
        1
      ) as p90_handle_hours
    from task_base
    group by
      tenant_id, tenant_name, definition_id, definition_name,
      business_type, node_key, node_name
  ), node_rows as (
    select
      node_base.*,
      case
        when sla_measured_count = 0 then 100::numeric
        else round(
          (sla_measured_count - sla_breached_count) * 100.0 / sla_measured_count,
          1
        )
      end as sla_compliance_rate
    from node_base
  ), node_stats as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'tenantId', tenant_id,
          'tenantName', tenant_name,
          'definitionId', definition_id,
          'definitionName', definition_name,
          'businessType', business_type,
          'nodeKey', node_key,
          'nodeName', node_name,
          'taskCount', task_count,
          'pendingCount', pending_count,
          'overduePendingCount', overdue_pending_count,
          'handledCount', handled_count,
          'approvedCount', approved_count,
          'rejectedCount', rejected_count,
          'slaMeasuredCount', sla_measured_count,
          'slaBreachedCount', sla_breached_count,
          'slaComplianceRate', sla_compliance_rate,
          'averageHandleHours', average_handle_hours,
          'p90HandleHours', p90_handle_hours,
          'riskLevel',
            case
              when overdue_pending_count > 0
                or (sla_measured_count >= 5 and sla_compliance_rate < 70) then 'critical'
              when pending_count >= 10
                or (sla_measured_count >= 5 and sla_compliance_rate < 90) then 'warning'
              else 'normal'
            end
        )
        order by
          overdue_pending_count desc,
          sla_breached_count desc,
          pending_count desc,
          p90_handle_hours desc,
          task_count desc,
          definition_name,
          node_name
      ),
      '[]'::jsonb
    ) as value
    from (
      select *
      from node_rows
      order by
        overdue_pending_count desc,
        sla_breached_count desc,
        pending_count desc,
        p90_handle_hours desc,
        task_count desc,
        definition_name,
        node_name
      limit 50
    ) ranked_nodes
  ), approver_base as (
    select
      tenant_id,
      tenant_name,
      assignee_user_id,
      max(assignee_name_snapshot) as assignee_name,
      count(*)::integer task_count,
      count(*) filter (where status = 'pending')::integer pending_count,
      count(*) filter (where status = 'pending' and is_sla_breached)::integer overdue_pending_count,
      count(*) filter (where handled_at is not null)::integer handled_count,
      count(*) filter (where status = 'approved')::integer approved_count,
      count(*) filter (where status = 'rejected')::integer rejected_count,
      count(*) filter (where due_at is not null)::integer sla_measured_count,
      count(*) filter (where is_sla_breached)::integer sla_breached_count,
      count(*) filter (where assignment_source = 'delegation')::integer delegated_count,
      count(*) filter (where assignment_source = 'transfer')::integer transferred_count,
      round(
        coalesce(avg(elapsed_hours) filter (where handled_at is not null), 0)::numeric,
        1
      ) as average_handle_hours,
      round(
        coalesce(
          percentile_cont(0.9) within group (order by elapsed_hours)
            filter (where handled_at is not null),
          0
        )::numeric,
        1
      ) as p90_handle_hours
    from task_base
    group by tenant_id, tenant_name, assignee_user_id
  ), approver_rows as (
    select
      approver_base.*,
      case
        when sla_measured_count = 0 then 100::numeric
        else round(
          (sla_measured_count - sla_breached_count) * 100.0 / sla_measured_count,
          1
        )
      end as sla_compliance_rate
    from approver_base
  ), approver_stats as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'tenantId', tenant_id,
          'tenantName', tenant_name,
          'assigneeUserId', assignee_user_id,
          'assigneeName', assignee_name,
          'taskCount', task_count,
          'pendingCount', pending_count,
          'overduePendingCount', overdue_pending_count,
          'handledCount', handled_count,
          'approvedCount', approved_count,
          'rejectedCount', rejected_count,
          'slaMeasuredCount', sla_measured_count,
          'slaBreachedCount', sla_breached_count,
          'slaComplianceRate', sla_compliance_rate,
          'delegatedCount', delegated_count,
          'transferredCount', transferred_count,
          'averageHandleHours', average_handle_hours,
          'p90HandleHours', p90_handle_hours,
          'riskLevel',
            case
              when overdue_pending_count > 0 then 'critical'
              when pending_count >= 10
                or (sla_measured_count >= 5 and sla_compliance_rate < 90) then 'warning'
              else 'normal'
            end
        )
        order by
          overdue_pending_count desc,
          pending_count desc,
          sla_breached_count desc,
          p90_handle_hours desc,
          task_count desc,
          assignee_name
      ),
      '[]'::jsonb
    ) as value
    from (
      select *
      from approver_rows
      order by
        overdue_pending_count desc,
        pending_count desc,
        sla_breached_count desc,
        p90_handle_hours desc,
        task_count desc,
        assignee_name
      limit 100
    ) ranked_approvers
  )
  select jsonb_build_object(
    'periodDays', v_days,
    'generatedAt', now(),
    'minimumSampleSize', 5,
    'summary', jsonb_build_object(
      'taskCount', summary.task_count,
      'pendingCount', summary.pending_count,
      'overduePendingCount', summary.overdue_pending_count,
      'handledCount', summary.handled_count,
      'slaMeasuredCount', summary.sla_measured_count,
      'slaBreachedCount', summary.sla_breached_count,
      'slaComplianceRate',
        case
          when summary.sla_measured_count = 0 then 100
          else round(
            (summary.sla_measured_count - summary.sla_breached_count)
              * 100.0 / summary.sla_measured_count,
            1
          )
        end,
      'delegatedCount', summary.delegated_count,
      'transferredCount', summary.transferred_count,
      'averageHandleHours', summary.average_handle_hours,
      'p90HandleHours', summary.p90_handle_hours
    ),
    'nodes', node_stats.value,
    'approvers', approver_stats.value
  )
  into v_result
  from summary cross join node_stats cross join approver_stats;

  return v_result;
end;
$function$;

create or replace function public.get_workflow_bottleneck_analytics(
  p_days integer default 30
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select app_private.get_workflow_bottleneck_analytics(p_days)
$function$;

revoke all on function app_private.get_workflow_bottleneck_analytics(integer)
  from public, anon, authenticated;
grant execute on function app_private.get_workflow_bottleneck_analytics(integer)
  to authenticated, service_role;

revoke all on function public.get_workflow_bottleneck_analytics(integer)
  from public, anon;
grant execute on function public.get_workflow_bottleneck_analytics(integer)
  to authenticated, service_role;

comment on function public.get_workflow_bottleneck_analytics(integer) is
  'Returns tenant-scoped workflow node bottlenecks and approver workload analytics.';

;
