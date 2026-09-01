-- Enterprise People Analytics: tenant-scoped, privacy-thresholded workforce insights.
-- The RPC intentionally returns aggregates only. It never exposes employee or
-- assignment identifiers and suppresses organization cohorts below five people.

create index if not exists hr_employee_tenant_hire_date_idx
  on public.hr_employee(tenant_id, hire_date)
  where hire_date is not null;

create index if not exists hr_employee_tenant_leave_date_idx
  on public.hr_employee(tenant_id, leave_date)
  where leave_date is not null;

create index if not exists hr_employee_assignment_tenant_effective_period_idx
  on public.hr_employee_assignment(tenant_id, effective_start, effective_end)
  where primary_assignment;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000210'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrPeopleAnalytics', 'people-analytics', '/hr/operations/people-analytics',
  jsonb_build_object(
    'title', '人力分析',
    'icon', 'ri:line-chart-line',
    'is_hide', false,
    'is_enable', true,
    'keep_alive', true,
    'roles', jsonb_build_array()
  ),
  10, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8210-000000000001'::uuid,
  'c0de0000-0000-4000-8000-000000000210'::uuid,
  'Hr:PeopleAnalytics:View', '', '',
  jsonb_build_object(
    'title', '查看人力分析',
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ),
  1, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

-- Preserve the existing HR operations role model: roles that can enter the
-- operations folder receive this read-only, threshold-protected workspace.
insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select folder_grant.role_id, target.menu_id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu folder_grant
join public.sys_role role on role.id = folder_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8000-000000000210'::uuid),
  ('c0de0000-0000-4000-8210-000000000001'::uuid)
) target(menu_id)
where folder_grant.menu_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
on conflict (role_id, menu_id) do nothing;

create or replace function public.hr_people_analytics_overview_secure(
  p_as_of_date date default current_date,
  p_period_months integer default 12,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_tenant_id uuid;
  v_as_of date := least(coalesce(p_as_of_date, current_date), current_date);
  v_months integer := least(36, greatest(coalesce(p_period_months, 12), 3));
  v_period_start date;
  v_opening_date date;
  v_privacy_threshold constant integer := 5;
  v_result jsonb;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPeopleAnalytics', 'Hr:PeopleAnalytics:View', null, false
  ) then
    raise exception '当前账号没有查看人力分析的权限' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    v_tenant_id := coalesce(p_tenant_id, v_current_tenant);
  else
    v_tenant_id := v_current_tenant;
  end if;

  if v_tenant_id is null then
    raise exception '当前账号缺少有效租户上下文' using errcode = '22023';
  end if;

  v_period_start := (date_trunc('month', v_as_of)::date - (v_months - 1) * interval '1 month')::date;
  v_opening_date := v_period_start - 1;

  with recursive
  month_axis as (
    select generate_series(
      date_trunc('month', v_period_start)::date,
      date_trunc('month', v_as_of)::date,
      interval '1 month'
    )::date as month_start
  ),
  month_points as (
    select month_start,
      least((month_start + interval '1 month - 1 day')::date, v_as_of) as month_end
    from month_axis
  ),
  opening_population as (
    select assignment.employee_id, assignment.fte
    from public.hr_employee_assignment assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.primary_assignment
      and assignment.effective_start <= v_opening_date
      and (assignment.effective_end is null or assignment.effective_end >= v_opening_date)
  ),
  closing_population as (
    select assignment.employee_id, assignment.organization_id, assignment.position_id,
      assignment.fte, assignment.effective_start,
      employee.hire_date, employee.employment_type
    from public.hr_employee_assignment assignment
    join public.hr_employee employee
      on employee.id = assignment.employee_id and employee.tenant_id = assignment.tenant_id
    where assignment.tenant_id = v_tenant_id
      and assignment.primary_assignment
      and assignment.effective_start <= v_as_of
      and (assignment.effective_end is null or assignment.effective_end >= v_as_of)
  ),
  flow_summary as (
    select
      count(*) filter (
        where employee.hire_date between v_period_start and v_as_of
      )::integer as hires,
      count(*) filter (
        where employee.leave_date between v_period_start and v_as_of
      )::integer as exits
    from public.hr_employee employee
    where employee.tenant_id = v_tenant_id
  ),
  monthly_flow as (
    select point.month_start, point.month_end,
      (select count(*)::integer
       from public.hr_employee_assignment assignment
       where assignment.tenant_id = v_tenant_id
         and assignment.primary_assignment
         and assignment.effective_start <= point.month_end
         and (assignment.effective_end is null or assignment.effective_end >= point.month_end)
      ) as headcount,
      (select count(*)::integer
       from public.hr_employee employee
       where employee.tenant_id = v_tenant_id
         and employee.hire_date between point.month_start and point.month_end
      ) as hires,
      (select count(*)::integer
       from public.hr_employee employee
       where employee.tenant_id = v_tenant_id
         and employee.leave_date between point.month_start and point.month_end
      ) as exits
    from month_points point
  ),
  organization_raw as (
    select organization.organization_name as name,
      count(*)::integer as headcount,
      round(sum(population.fte), 2) as fte
    from closing_population population
    join public.sys_organization organization
      on organization.id = population.organization_id and organization.tenant_id = v_tenant_id
    group by organization.id, organization.organization_name
  ),
  organization_safe as (
    select name, headcount, fte, false as protected
    from organization_raw
    where headcount >= v_privacy_threshold
    union all
    select '其他受保护组织', sum(headcount)::integer, round(sum(fte), 2), true
    from organization_raw
    where headcount < v_privacy_threshold
    having sum(headcount) > 0
  ),
  employment_raw as (
    select coalesce(nullif(btrim(employment_type), ''), 'unknown') as key,
      count(*)::integer as headcount
    from closing_population
    group by coalesce(nullif(btrim(employment_type), ''), 'unknown')
  ),
  employment_safe as (
    select key, headcount, false as protected
    from employment_raw
    where headcount >= v_privacy_threshold
    union all
    select 'protected', sum(headcount)::integer, true
    from employment_raw
    where headcount < v_privacy_threshold
    having sum(headcount) > 0
  ),
  tenure_buckets as (
    select bucket_key, bucket_label, sort,
      count(population.employee_id)::integer as headcount
    from (values
      ('under_1', '1 年以内', 1, 0::numeric, 1::numeric),
      ('year_1_3', '1–3 年', 2, 1::numeric, 3::numeric),
      ('year_3_5', '3–5 年', 3, 3::numeric, 5::numeric),
      ('year_5_10', '5–10 年', 4, 5::numeric, 10::numeric),
      ('year_10_plus', '10 年以上', 5, 10::numeric, null::numeric)
    ) bucket(bucket_key, bucket_label, sort, min_years, max_years)
    left join closing_population population
      on population.hire_date is not null
      and (v_as_of - population.hire_date) / 365.25 >= bucket.min_years
      and (bucket.max_years is null or (v_as_of - population.hire_date) / 365.25 < bucket.max_years)
    group by bucket_key, bucket_label, sort
  ),
  data_quality as (
    select * from (values
      ('hire_date', '入职日期',
        (select count(*) from closing_population where hire_date is not null)::integer),
      ('organization', '组织归属',
        (select count(*) from closing_population where organization_id is not null)::integer),
      ('position', '岗位归属',
        (select count(*) from closing_population where position_id is not null)::integer),
      ('employment_type', '用工类型',
        (select count(*) from closing_population where nullif(btrim(employment_type), '') is not null)::integer)
    ) quality(key, label, complete_count)
  ),
  totals as (
    select
      (select count(*)::integer from opening_population) as opening_headcount,
      (select count(*)::integer from closing_population) as ending_headcount,
      (select coalesce(round(sum(fte), 2), 0) from closing_population) as ending_fte,
      (select hires from flow_summary) as hires,
      (select exits from flow_summary) as exits,
      (select coalesce(round(avg((v_as_of - hire_date) / 365.25), 1), 0)
       from closing_population where hire_date is not null) as average_tenure_years
  )
  select jsonb_build_object(
    'as_of_date', v_as_of,
    'period_start_date', v_period_start,
    'period_months', v_months,
    'privacy_threshold', v_privacy_threshold,
    'generated_at', now(),
    'overview', jsonb_build_object(
      'opening_headcount', totals.opening_headcount,
      'ending_headcount', totals.ending_headcount,
      'ending_fte', totals.ending_fte,
      'hires', totals.hires,
      'exits', totals.exits,
      'net_change', totals.ending_headcount - totals.opening_headcount,
      'turnover_rate', case
        when (totals.opening_headcount + totals.ending_headcount) = 0 then 0
        else round(100.0 * totals.exits /
          ((totals.opening_headcount + totals.ending_headcount) / 2.0), 1)
      end,
      'average_tenure_years', totals.average_tenure_years,
      'data_completeness_rate', case when totals.ending_headcount = 0 then 0 else (
        select round(100.0 * sum(complete_count) /
          (totals.ending_headcount * count(*)), 1) from data_quality
      ) end
    ),
    'flow_trend', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', to_char(month_start, 'YYYY-MM'),
        'headcount', headcount,
        'hires', hires,
        'exits', exits
      ) order by month_start)
      from monthly_flow
    ), '[]'::jsonb),
    'organization_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', name,
        'headcount', headcount,
        'fte', fte,
        'share', case when totals.ending_headcount = 0 then 0
          else round(100.0 * headcount / totals.ending_headcount, 1) end,
        'protected', protected
      ) order by protected, headcount desc, name)
      from organization_safe
    ), '[]'::jsonb),
    'employment_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', key,
        'headcount', headcount,
        'share', case when totals.ending_headcount = 0 then 0
          else round(100.0 * headcount / totals.ending_headcount, 1) end,
        'protected', protected
      ) order by protected, headcount desc, key)
      from employment_safe
    ), '[]'::jsonb),
    'tenure_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', bucket_key,
        'label', bucket_label,
        'headcount', headcount,
        'share', case when totals.ending_headcount = 0 then 0
          else round(100.0 * headcount / totals.ending_headcount, 1) end
      ) order by sort)
      from tenure_buckets
    ), '[]'::jsonb),
    'data_quality', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', key,
        'label', label,
        'complete_count', complete_count,
        'total_count', totals.ending_headcount,
        'rate', case when totals.ending_headcount = 0 then 0
          else round(100.0 * complete_count / totals.ending_headcount, 1) end
      ) order by key)
      from data_quality
    ), '[]'::jsonb)
  ) into v_result
  from totals;

  return v_result;
end
$function$;

revoke all on function public.hr_people_analytics_overview_secure(date, integer, uuid)
  from public, anon;
grant execute on function public.hr_people_analytics_overview_secure(date, integer, uuid)
  to authenticated;

;
