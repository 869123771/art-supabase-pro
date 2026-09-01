create or replace function public.smis_list_risk_control_options_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:View')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Add')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Edit')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
  ) then
    raise exception '当前账号没有查看风险管控选项的权限' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'riskPoints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', point.id,
        'pointNo', point.point_no,
        'pointName', point.point_name,
        'riskType', point.risk_type,
        'siteName', site.site_name
      ) order by point.sort, point.point_no)
      from public.smis_risk_point point
      join public.smis_site site
        on site.tenant_id = point.tenant_id
       and site.id = point.site_id
      where point.tenant_id = v_tenant_id
        and point.status = 'enabled'
        and exists (
          select 1
          from public.smis_risk_item item
          where item.tenant_id = point.tenant_id
            and item.risk_point_id = point.id
            and item.status <> 'voided'
        )
    ), '[]'::jsonb),
    'duplicateConfigurations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', duplicate.id,
        'contentItem', duplicate.content_item,
        'repeatFrequency', duplicate.repeat_frequency,
        'frequencyUnit', duplicate.frequency_unit,
        'calendarType', duplicate.calendar_type,
        'calendarDays', to_jsonb(duplicate.calendar_days),
        'deadlineTime', duplicate.deadline_time,
        'displayLabel', concat(
          duplicate.content_item,
          ' · 每 ',
          duplicate.repeat_frequency,
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
        )
      ) order by duplicate.sort, duplicate.content_item)
      from public.smis_duplicate_configuration duplicate
      where duplicate.tenant_id = v_tenant_id
        and duplicate.status = 'enabled'
        and duplicate.repeat_enabled
    ), '[]'::jsonb)
  );
end
$$;

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
  ), filtered as (
    select *
    from records
    where (p_control_level is null or p_control_level = any(control_levels))
      and (p_control_status is null or control_status = p_control_status)
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
      'total', (select count(*) from filtered),
      'uncontrolled', (select count(*) from filtered where control_status = 'uncontrolled'),
      'active', (select count(*) from filtered where control_status = 'active'),
      'major', (select count(*) from filtered where level_code = 'major')
    )
  ) into v_result;

  return v_result;
end
$$;

create or replace function public.smis_save_risk_control_plan_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_control_start_at timestamptz,
  p_status text,
  p_control_description text,
  p_assignments jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_existing_id uuid;
  v_assignment jsonb;
  v_control_level text;
  v_employee_id uuid;
  v_duplicate_id uuid;
begin
  select plan.id into v_existing_id
  from public.smis_risk_control_plan plan
  where plan.tenant_id = v_tenant_id
    and plan.risk_point_id = p_risk_point_id;

  if p_id is null and v_existing_id is null and not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:Add')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Import')
  ) then
    raise exception '当前账号没有新增风险管控配置的权限' using errcode = '42501';
  end if;

  if coalesce(p_id, v_existing_id) is not null and not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:Edit')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Import')
  ) then
    raise exception '当前账号没有编辑风险管控配置的权限' using errcode = '42501';
  end if;

  if coalesce(p_status, 'active') not in ('active', 'suspended') then
    raise exception '管控状态无效' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_assignments, '[]'::jsonb)) = 0 then
    raise exception '请至少配置一个管控层级' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.smis_risk_point point
    where point.tenant_id = v_tenant_id
      and point.id = p_risk_point_id
      and point.status = 'enabled'
      and exists (
        select 1
        from public.smis_risk_item item
        where item.tenant_id = point.tenant_id
          and item.risk_point_id = point.id
          and item.status <> 'voided'
      )
  ) then
    raise exception '风险点尚未维护有效危险源，不能配置分级管控' using errcode = '22023';
  end if;

  if (
    select count(*) <> count(distinct item->>'control_level')
    from jsonb_array_elements(p_assignments) item
  ) then
    raise exception '同一管控层级不能重复配置' using errcode = '23505';
  end if;

  v_id := coalesce(p_id, v_existing_id);

  if v_id is null then
    insert into public.smis_risk_control_plan(
      tenant_id,
      risk_point_id,
      control_start_at,
      status,
      control_description
    ) values (
      v_tenant_id,
      p_risk_point_id,
      coalesce(p_control_start_at, now()),
      coalesce(p_status, 'active'),
      nullif(btrim(coalesce(p_control_description, '')), '')
    ) returning id into v_id;
  else
    update public.smis_risk_control_plan
    set control_start_at = coalesce(p_control_start_at, control_start_at),
        status = coalesce(p_status, status),
        control_description = nullif(btrim(coalesce(p_control_description, '')), '')
    where id = v_id
      and tenant_id = v_tenant_id
      and risk_point_id = p_risk_point_id
    returning id into v_id;

    if v_id is null then
      raise exception '风险管控配置不存在或不属于当前风险点' using errcode = 'P0002';
    end if;
  end if;

  update public.smis_risk_control_assignment
  set status = 'inactive'
  where tenant_id = v_tenant_id
    and plan_id = v_id;

  for v_assignment in select * from jsonb_array_elements(p_assignments)
  loop
    v_control_level := v_assignment->>'control_level';
    begin
      v_employee_id := (v_assignment->>'responsible_employee_id')::uuid;
      v_duplicate_id := (v_assignment->>'duplicate_configuration_id')::uuid;
    exception when others then
      raise exception '管控责任人或管控频率格式无效' using errcode = '22023';
    end;

    if v_control_level not in ('company', 'department', 'team', 'position') then
      raise exception '管控层级无效' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from public.hr_employee employee
      where employee.tenant_id = v_tenant_id
        and employee.id = v_employee_id
        and employee.employment_status = 'active'
    ) then
      raise exception '管控责任人不存在、已离职或不属于当前租户' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from public.smis_duplicate_configuration duplicate
      where duplicate.tenant_id = v_tenant_id
        and duplicate.id = v_duplicate_id
        and duplicate.status = 'enabled'
        and duplicate.repeat_enabled
    ) then
      raise exception '管控频率不存在、已停用或未启用重复规则' using errcode = '22023';
    end if;

    insert into public.smis_risk_control_assignment(
      tenant_id,
      plan_id,
      control_level,
      responsible_employee_id,
      duplicate_configuration_id,
      control_measure,
      status,
      sort
    ) values (
      v_tenant_id,
      v_id,
      v_control_level,
      v_employee_id,
      v_duplicate_id,
      nullif(btrim(coalesce(v_assignment->>'control_measure', '')), ''),
      'active',
      greatest(coalesce((v_assignment->>'sort')::integer, 0), 0)
    )
    on conflict (tenant_id, plan_id, control_level)
    do update set
      responsible_employee_id = excluded.responsible_employee_id,
      duplicate_configuration_id = excluded.duplicate_configuration_id,
      control_measure = excluded.control_measure,
      status = 'active',
      sort = excluded.sort;
  end loop;

  perform app_private.smis_generate_due_risk_inspection_tasks(
    v_tenant_id,
    now() + interval '1 day'
  );

  return v_id;
end
$$;

update public.sys_menu
set meta = jsonb_set(
      coalesce(meta, '{}'::jsonb),
      '{icon}',
      to_jsonb(case name
        when 'SmisDualControlSafetyRiskList' then 'ri:file-list-3-line'
        when 'SmisDualControlRiskClassificationControl' then 'ri:git-merge-line'
        when 'SmisDualControlRiskListSummary' then 'ri:bar-chart-box-line'
        when 'SmisDualControlRiskInspectionTask' then 'ri:task-line'
      end),
      true
    ),
    update_by = 'migration',
    update_time = now()
where type = 'menu'
  and name in (
    'SmisDualControlSafetyRiskList',
    'SmisDualControlRiskClassificationControl',
    'SmisDualControlRiskListSummary',
    'SmisDualControlRiskInspectionTask'
  )
  and coalesce(meta->>'icon', '') = '';

;
