create or replace function public.smis_emergency_drill_report_secure(
  p_start_date date default null,
  p_end_date date default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_rows jsonb;
  v_outstanding jsonb;
  v_overview jsonb;
begin
  if not app_private.has_permission('SmisEmergencyDrillReport:View') then
    raise exception '当前账号无权查看应急演练报表';
  end if;
  if p_start_date is not null and p_end_date is not null and p_start_date > p_end_date then
    raise exception '开始日期不能晚于结束日期';
  end if;
  v_tenant := app_private.current_user_tenant_id();

  with filtered_plans as (
    select p.id, p.plan_no, p.drill_name, p.applicable_organization_id,
      p.plan_category, p.plan_level, p.plan_end_date, p.status,
      r.id as record_id, r.actual_start_date, r.actual_end_date, org.organization_name
    from public.smis_emergency_drill_plan p
    join public.sys_organization org
      on org.id = p.applicable_organization_id and org.tenant_id = p.tenant_id
    left join public.smis_emergency_drill_record r
      on r.drill_plan_id = p.id and r.tenant_id = p.tenant_id and r.status = 'submitted'
    where p.tenant_id = v_tenant
      and (p_start_date is null or coalesce(r.actual_start_date, p.plan_end_date) >= p_start_date)
      and (p_end_date is null or coalesce(r.actual_start_date, p.plan_end_date) <= p_end_date)
      and (p_organization_id is null or p.applicable_organization_id = p_organization_id)
  ), grouped as (
    select applicable_organization_id, organization_name, plan_category, plan_level,
      count(*)::integer as plan_count,
      count(*) filter (where record_id is not null)::integer as completed_count,
      count(*) filter (where record_id is not null)::integer as drill_count,
      count(*) filter (where record_id is not null and actual_start_date > plan_end_date)::integer as late_count,
      case
        when count(*) filter (where record_id is not null) > 1 then
          round(
            (max(actual_start_date) - min(actual_start_date))::numeric
            / (count(*) filter (where record_id is not null) - 1),
            1
          )
        else null
      end as average_interval_days
    from filtered_plans
    group by applicable_organization_id, organization_name, plan_category, plan_level
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organizationId', applicable_organization_id,
        'organizationName', organization_name,
        'planCategory', plan_category,
        'planLevel', plan_level,
        'planCount', plan_count,
        'completedCount', completed_count,
        'sprintRate', case
          when plan_count > 0 then round(completed_count::numeric * 100 / plan_count, 1)
          else 0
        end,
        'drillCount', drill_count,
        'lateCount', late_count,
        'averageIntervalDays', average_interval_days
      )
      order by organization_name, plan_category, plan_level
    ),
    '[]'::jsonb
  )
  into v_rows
  from grouped;

  with filtered_plans as (
    select p.id, p.plan_no, p.drill_name, p.applicable_organization_id,
      p.plan_category, p.plan_level, p.plan_end_date, p.status,
      r.id as record_id, org.organization_name
    from public.smis_emergency_drill_plan p
    join public.sys_organization org
      on org.id = p.applicable_organization_id and org.tenant_id = p.tenant_id
    left join public.smis_emergency_drill_record r
      on r.drill_plan_id = p.id and r.tenant_id = p.tenant_id and r.status = 'submitted'
    where p.tenant_id = v_tenant
      and (p_start_date is null or coalesce(r.actual_start_date, p.plan_end_date) >= p_start_date)
      and (p_end_date is null or coalesce(r.actual_start_date, p.plan_end_date) <= p_end_date)
      and (p_organization_id is null or p.applicable_organization_id = p_organization_id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'planNo', plan_no,
        'drillName', drill_name,
        'organizationName', organization_name,
        'planCategory', plan_category,
        'planLevel', plan_level,
        'planEndDate', plan_end_date,
        'warningStatus', case when plan_end_date <= current_date + 3 then 'warning' else 'normal' end
      )
      order by plan_end_date, plan_no
    ),
    '[]'::jsonb
  )
  into v_outstanding
  from filtered_plans
  where status = 'planned' and record_id is null;

  with filtered_plans as (
    select p.status, p.plan_end_date, r.id as record_id, r.actual_start_date
    from public.smis_emergency_drill_plan p
    left join public.smis_emergency_drill_record r
      on r.drill_plan_id = p.id and r.tenant_id = p.tenant_id and r.status = 'submitted'
    where p.tenant_id = v_tenant
      and (p_start_date is null or coalesce(r.actual_start_date, p.plan_end_date) >= p_start_date)
      and (p_end_date is null or coalesce(r.actual_start_date, p.plan_end_date) <= p_end_date)
      and (p_organization_id is null or p.applicable_organization_id = p_organization_id)
  )
  select jsonb_build_object(
    'planCount', count(*),
    'completedCount', count(*) filter (where record_id is not null),
    'outstandingCount', count(*) filter (where status = 'planned' and record_id is null),
    'warningCount', count(*) filter (
      where status = 'planned' and record_id is null and plan_end_date <= current_date + 3
    ),
    'lateCount', count(*) filter (
      where record_id is not null and actual_start_date > plan_end_date
    )
  )
  into v_overview
  from filtered_plans;

  return jsonb_build_object('overview', v_overview, 'rows', v_rows, 'outstanding', v_outstanding);
end
$$;

revoke all on function public.smis_emergency_drill_report_secure(date, date, uuid)
  from public, anon;
grant execute on function public.smis_emergency_drill_report_secure(date, date, uuid)
  to authenticated;

do $$
declare
  v_parent_id uuid;
  v_button_id uuid;
  v_app_code text;
begin
  select id, app_code
  into v_parent_id, v_app_code
  from public.sys_menu
  where name = 'SmisEmergencyDrillReport' and type = 'menu'
  order by create_time
  limit 1;

  if v_parent_id is null then
    raise exception '未找到应急演练报表菜单';
  end if;

  select id
  into v_button_id
  from public.sys_menu
  where parent_id = v_parent_id
    and name = 'SmisEmergencyDrillReport:Export'
    and type = 'button'
  limit 1;

  if v_button_id is null then
    v_button_id := gen_random_uuid();
    insert into public.sys_menu (
      id, parent_id, name, path, component, type, app_code, sort, meta, create_by, update_by
    ) values (
      v_button_id, v_parent_id, 'SmisEmergencyDrillReport:Export', '', '', 'button',
      v_app_code, 2,
      jsonb_build_object(
        'title', '导出',
        'roles', jsonb_build_array(),
        'is_hide', true,
        'is_enable', true
      ),
      'migration', 'migration'
    );
  end if;

  insert into public.sys_role_menu (
    id, role_id, menu_id, tenant_id, permission, create_by, update_by
  )
  select gen_random_uuid(), role_menu.role_id, v_button_id, role_menu.tenant_id,
    '{}'::jsonb, 'migration', 'migration'
  from public.sys_role_menu role_menu
  where role_menu.menu_id = v_parent_id
  on conflict (role_id, menu_id) do nothing;
end
$$;;
