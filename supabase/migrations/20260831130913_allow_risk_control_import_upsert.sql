-- The import button is an explicit controlled-write permission. Allow users who
-- hold it to upsert risk-control plans while keeping the same tenant and data
-- validation enforced for interactive add/edit operations.

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
  where plan.tenant_id = v_tenant_id and plan.risk_point_id = p_risk_point_id;

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
    select 1 from public.smis_risk_point point
    where point.tenant_id = v_tenant_id
      and point.id = p_risk_point_id
      and point.status = 'enabled'
      and exists (
        select 1
        from public.smis_risk_item item
        join public.smis_risk_evaluation evaluation
          on evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
        where item.tenant_id = point.tenant_id
          and item.risk_point_id = point.id
          and item.status <> 'voided'
      )
  ) then
    raise exception '风险点未完成定量评价，不能配置分级管控' using errcode = '22023';
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
      tenant_id, risk_point_id, control_start_at, status, control_description
    ) values (
      v_tenant_id, p_risk_point_id, coalesce(p_control_start_at, now()),
      coalesce(p_status, 'active'), nullif(btrim(coalesce(p_control_description, '')), '')
    ) returning id into v_id;
  else
    update public.smis_risk_control_plan
    set control_start_at = coalesce(p_control_start_at, control_start_at),
        status = coalesce(p_status, status),
        control_description = nullif(btrim(coalesce(p_control_description, '')), '')
    where id = v_id and tenant_id = v_tenant_id and risk_point_id = p_risk_point_id
    returning id into v_id;
    if v_id is null then
      raise exception '风险管控配置不存在或不属于当前风险点' using errcode = 'P0002';
    end if;
  end if;

  update public.smis_risk_control_assignment
  set status = 'inactive'
  where tenant_id = v_tenant_id and plan_id = v_id;

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
      select 1 from public.hr_employee employee
      where employee.tenant_id = v_tenant_id
        and employee.id = v_employee_id
        and employee.employment_status = 'active'
    ) then
      raise exception '管控责任人不存在、已离职或不属于当前租户' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.smis_duplicate_configuration duplicate
      where duplicate.tenant_id = v_tenant_id
        and duplicate.id = v_duplicate_id
        and duplicate.status = 'enabled'
        and duplicate.repeat_enabled
    ) then
      raise exception '管控频率不存在、已停用或未启用重复规则' using errcode = '22023';
    end if;

    insert into public.smis_risk_control_assignment(
      tenant_id, plan_id, control_level, responsible_employee_id,
      duplicate_configuration_id, control_measure, status, sort
    ) values (
      v_tenant_id, v_id, v_control_level, v_employee_id, v_duplicate_id,
      nullif(btrim(coalesce(v_assignment->>'control_measure', '')), ''),
      'active', greatest(coalesce((v_assignment->>'sort')::integer, 0), 0)
    )
    on conflict (tenant_id, plan_id, control_level)
    do update set
      responsible_employee_id = excluded.responsible_employee_id,
      duplicate_configuration_id = excluded.duplicate_configuration_id,
      control_measure = excluded.control_measure,
      status = 'active',
      sort = excluded.sort;
  end loop;

  perform app_private.smis_generate_due_risk_inspection_tasks(v_tenant_id, now() + interval '1 day');
  return v_id;
end;
$$;

;
