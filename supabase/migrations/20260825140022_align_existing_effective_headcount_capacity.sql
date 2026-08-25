-- Existing tenants may already have effective headcount controls that predate the
-- workforce-planning module. Reconcile the operational position guard without
-- ever lowering it below the number of current incumbents.
with latest_control as (
  select distinct on (h.tenant_id, h.position_id)
    h.tenant_id,
    h.position_id,
    h.approved_count
  from public.hr_position_headcount h
  where h.enabled
    and h.effective_from <= current_date
    and (h.effective_to is null or h.effective_to >= current_date)
  order by h.tenant_id, h.position_id, h.effective_from desc, h.update_time desc
), incumbent as (
  select
    a.tenant_id,
    a.position_id,
    count(*)::integer as current_count
  from public.hr_employee_assignment a
  where a.primary_assignment
    and a.assignment_status <> 'ended'
    and a.effective_start <= current_date
    and (a.effective_end is null or a.effective_end >= current_date)
  group by a.tenant_id, a.position_id
)
update public.hr_position p
set headcount_limit = greatest(c.approved_count, coalesce(i.current_count, 0)),
    multiple_incumbents_allowed = p.multiple_incumbents_allowed
      or greatest(c.approved_count, coalesce(i.current_count, 0)) > 1,
    enabled = case
      when c.approved_count = 0 and coalesce(i.current_count, 0) = 0 then false
      else p.enabled
    end,
    update_time = now()
from latest_control c
left join incumbent i
  on i.tenant_id = c.tenant_id
 and i.position_id = c.position_id
where p.tenant_id = c.tenant_id
  and p.id = c.position_id
  and (
    p.headcount_limit is distinct from greatest(c.approved_count, coalesce(i.current_count, 0))
    or (c.approved_count = 0 and coalesce(i.current_count, 0) = 0 and p.enabled)
  );

-- Effective headcount is the reporting authority. The position limit remains the
-- assignment-time guard, with the fallback used only where no effective control
-- has been configured yet.
create or replace function public.hr_workforce_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrHeadcount', 'Hr:Headcount:View', null, false) then
    raise exception '当前账号没有查看人力规划的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_current_tenant; end if;

  with current_incumbents as (
    select a.tenant_id, a.position_id, count(*)::integer incumbent_count
    from public.hr_employee_assignment a
    where a.primary_assignment
      and a.assignment_status <> 'ended'
      and a.effective_start <= current_date
      and (a.effective_end is null or a.effective_end >= current_date)
      and (p_tenant_id is null or a.tenant_id = p_tenant_id)
    group by a.tenant_id, a.position_id
  ), current_control as (
    select distinct on (h.tenant_id, h.position_id)
      h.tenant_id, h.position_id, h.approved_count
    from public.hr_position_headcount h
    where h.enabled
      and h.effective_from <= current_date
      and (h.effective_to is null or h.effective_to >= current_date)
      and (p_tenant_id is null or h.tenant_id = p_tenant_id)
    order by h.tenant_id, h.position_id, h.effective_from desc, h.update_time desc
  ), capacity as (
    select p.tenant_id, p.id position_id,
      coalesce(c.approved_count, p.headcount_limit) operational_limit,
      coalesce(i.incumbent_count, 0) incumbent_count
    from public.hr_position p
    left join current_control c on c.tenant_id = p.tenant_id and c.position_id = p.id
    left join current_incumbents i on i.tenant_id = p.tenant_id and i.position_id = p.id
    where (p.enabled or c.position_id is not null)
      and (p_tenant_id is null or p.tenant_id = p_tenant_id)
  ), featured_plan as (
    select c.*
    from public.hr_workforce_plan_cycle c
    where (p_tenant_id is null or c.tenant_id = p_tenant_id)
    order by case c.status when 'active' then 1 when 'approved' then 2 when 'submitted' then 3 else 4 end,
      c.period_start desc, c.create_time desc
    limit 1
  ), bridge as (
    select coalesce(sum(l.baseline_count), 0)::integer baseline_count,
      coalesce(sum(l.planned_hires), 0)::integer planned_hires,
      coalesce(sum(l.planned_exits), 0)::integer planned_exits,
      coalesce(sum(l.target_count), 0)::integer target_count,
      coalesce(sum(l.planned_payroll), 0)::numeric planned_payroll
    from public.hr_workforce_plan_line l
    join featured_plan f on f.id = l.plan_id and f.tenant_id = l.tenant_id
  )
  select jsonb_build_object(
    'active_plan_count', (select count(*) from public.hr_workforce_plan_cycle c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status = 'active'),
    'pending_approval_count', (select count(*) from public.hr_workforce_plan_cycle c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status = 'submitted'),
    'operational_capacity', coalesce((select sum(operational_limit) from capacity), 0),
    'current_incumbent_count', coalesce((select sum(incumbent_count) from capacity), 0),
    'vacancy_count', coalesce((select sum(greatest(operational_limit - incumbent_count, 0)) from capacity), 0),
    'over_capacity_count', coalesce((select sum(greatest(incumbent_count - operational_limit, 0)) from capacity), 0),
    'featured_plan', case when (select id from featured_plan) is null then null else jsonb_build_object(
      'id', (select id from featured_plan),
      'plan_no', (select plan_no from featured_plan),
      'plan_name', (select plan_name from featured_plan),
      'status', (select status from featured_plan),
      'budget_amount', (select budget_amount from featured_plan),
      'currency_code', (select currency_code from featured_plan),
      'baseline_count', (select baseline_count from bridge),
      'planned_hires', (select planned_hires from bridge),
      'planned_exits', (select planned_exits from bridge),
      'target_count', (select target_count from bridge),
      'planned_payroll', (select planned_payroll from bridge),
      'budget_variance', case when (select budget_amount from featured_plan) is null then null
        else (select budget_amount from featured_plan) - (select planned_payroll from bridge) end
    ) end
  ) into v_result;
  return v_result;
end
$function$;
