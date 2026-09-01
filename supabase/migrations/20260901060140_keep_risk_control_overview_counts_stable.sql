create or replace function public.smis_list_risk_control_points_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_risk_type text default null,
  p_control_level text default null,
  p_control_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.has_permission('SmisDualControlRiskClassificationControl:View') then
    raise exception '当前账号没有查看风险分级管控的权限' using errcode = '42501';
  end if;

  with records as (
    select
      point.id as risk_point_id,
      point.point_no,
      point.point_name,
      point.risk_type,
      site.site_name,
      plan.id as plan_id,
      plan.control_start_at,
      plan.control_description,
      coalesce(plan.status, 'uncontrolled') as control_status,
      coalesce(evaluated_risk.level_code, 'unidentified') as level_code,
      coalesce(evaluated_risk.level_name, '待评价') as level_name,
      coalesce(evaluated_risk.level_color, '#94A3B8') as level_color,
      hazard.accident_types,
      coalesce(assignment.assignments, '[]'::jsonb) as assignments,
      coalesce(assignment.control_levels, '{}'::text[]) as control_levels,
      coalesce(assignment.responsible_names, '') as responsible_names,
      coalesce(assignment.task_count, 0) as task_count,
      greatest(point.update_time, coalesce(plan.update_time, point.update_time)) as updated_at
    from public.smis_risk_point point
    join public.smis_site site
      on site.tenant_id = point.tenant_id
     and site.id = point.site_id
    left join public.smis_risk_control_plan plan
      on plan.tenant_id = point.tenant_id
     and plan.risk_point_id = point.id
    join lateral (
      select
        coalesce(
          array_agg(distinct accident_type) filter (where accident_type is not null),
          '{}'::text[]
        ) as accident_types
      from public.smis_risk_item item
      left join lateral unnest(item.accident_types) accident_type on true
      where item.tenant_id = point.tenant_id
        and item.risk_point_id = point.id
        and item.status <> 'voided'
      having count(distinct item.id) > 0
    ) hazard on true
    left join lateral (
      select
        level.level_code,
        level.level_name,
        level.color as level_color
      from public.smis_risk_item item
      join public.smis_risk_evaluation evaluation
        on evaluation.tenant_id = item.tenant_id
       and evaluation.risk_item_id = item.id
      join public.smis_risk_assessment_level level
        on level.tenant_id = evaluation.tenant_id
       and level.id = evaluation.risk_level_id
      where item.tenant_id = point.tenant_id
        and item.risk_point_id = point.id
        and item.status <> 'voided'
      order by level.sort
      limit 1
    ) evaluated_risk on true
    left join lateral (
      select
        jsonb_agg(jsonb_build_object(
          'id', control_assignment.id,
          'controlLevel', control_assignment.control_level,
          'responsibleEmployeeId', employee.id,
          'responsibleEmployeeNo', employee.employee_no,
          'responsibleEmployeeName', employee.employee_name,
          'responsibleOrganizationId', employee.organization_id,
          'responsibleOrganizationName', employee_organization.organization_name,
          'duplicateConfigurationId', duplicate.id,
          'frequencyLabel', concat(
            '每 ', duplicate.repeat_frequency,
            case duplicate.frequency_unit
              when 'shift' then '班'
              when 'day' then '日'
              when 'week' then '周'
              when 'month' then '月'
              when 'quarter' then '季'
              when 'year' then '年'
              when 'ten_day' then '旬'
              else duplicate.frequency_unit
            end
          ),
          'controlMeasure', control_assignment.control_measure,
          'sort', control_assignment.sort
        ) order by control_assignment.sort, control_assignment.control_level) as assignments,
        array_agg(control_assignment.control_level order by control_assignment.sort) as control_levels,
        string_agg(distinct employee.employee_name, '、') as responsible_names,
        sum((
          select count(*)
          from public.smis_risk_inspection_task task
          where task.tenant_id = control_assignment.tenant_id
            and task.assignment_id = control_assignment.id
        ))::integer as task_count
      from public.smis_risk_control_assignment control_assignment
      join public.hr_employee employee
        on employee.tenant_id = control_assignment.tenant_id
       and employee.id = control_assignment.responsible_employee_id
      left join public.sys_organization employee_organization
        on employee_organization.tenant_id = employee.tenant_id
       and employee_organization.id = employee.organization_id
      join public.smis_duplicate_configuration duplicate
        on duplicate.tenant_id = control_assignment.tenant_id
       and duplicate.id = control_assignment.duplicate_configuration_id
      where control_assignment.tenant_id = plan.tenant_id
        and control_assignment.plan_id = plan.id
        and control_assignment.status = 'active'
    ) assignment on true
    where point.tenant_id = v_tenant_id
      and point.status = 'enabled'
      and (
        p_keyword is null
        or btrim(p_keyword) = ''
        or point.point_no ilike '%' || btrim(p_keyword) || '%'
        or point.point_name ilike '%' || btrim(p_keyword) || '%'
      )
      and (p_risk_type is null or point.risk_type = p_risk_type)
  ), status_scope as (
    select *
    from records
    where p_control_level is null or p_control_level = any(control_levels)
  ), filtered as (
    select *
    from status_scope
    where p_control_status is null or control_status = p_control_status
  ), paged as (
    select *
    from filtered
    order by updated_at desc, point_no
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'riskPointId', risk_point_id,
        'riskPointNo', point_no,
        'riskPointName', point_name,
        'riskPointType', risk_type,
        'siteName', site_name,
        'riskLevelCode', level_code,
        'riskLevelName', level_name,
        'riskLevelColor', level_color,
        'accidentTypes', to_jsonb(accident_types),
        'planId', plan_id,
        'controlStartAt', control_start_at,
        'controlDescription', control_description,
        'controlStatus', control_status,
        'controlLevels', to_jsonb(control_levels),
        'responsibleNames', responsible_names,
        'taskCount', task_count,
        'assignments', assignments
      ) order by updated_at desc, point_no)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from status_scope),
      'uncontrolled', (select count(*) from status_scope where control_status = 'uncontrolled'),
      'active', (select count(*) from status_scope where control_status = 'active'),
      'major', (select count(*) from status_scope where level_code = 'major')
    )
  ) into v_result;

  return v_result;
end
$$;

;
