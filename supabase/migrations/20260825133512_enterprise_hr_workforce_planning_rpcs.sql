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
    where a.primary_assignment and a.effective_end is null and a.assignment_status <> 'ended'
      and (p_tenant_id is null or a.tenant_id = p_tenant_id)
    group by a.tenant_id, a.position_id
  ), capacity as (
    select p.tenant_id, p.id position_id, p.headcount_limit,
      coalesce(i.incumbent_count, 0) incumbent_count
    from public.hr_position p
    left join current_incumbents i on i.tenant_id = p.tenant_id and i.position_id = p.id
    where p.enabled and (p_tenant_id is null or p.tenant_id = p_tenant_id)
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
    'operational_capacity', coalesce((select sum(headcount_limit) from capacity), 0),
    'current_incumbent_count', coalesce((select sum(incumbent_count) from capacity), 0),
    'vacancy_count', coalesce((select sum(greatest(headcount_limit - incumbent_count, 0)) from capacity), 0),
    'over_capacity_count', coalesce((select sum(greatest(incumbent_count - headcount_limit, 0)) from capacity), 0),
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

create or replace function public.hr_list_workforce_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_plan_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('cycle', 'line', 'effective') then raise exception '不支持的人力规划记录类型'; end if;
  if not app_private.can_execute_business_action('HrHeadcount', 'Hr:Headcount:View', null, false) then
    raise exception '当前账号没有查看人力规划的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_current_tenant; end if;

  if p_kind = 'cycle' then
    with filtered as materialized (
      select c.*, t.tenant_name,
        e.employee_no owner_no, e.employee_name owner_name,
        coalesce(x.line_count, 0) line_count,
        coalesce(x.baseline_count, 0) baseline_count,
        coalesce(x.planned_hires, 0) planned_hires,
        coalesce(x.planned_exits, 0) planned_exits,
        coalesce(x.target_count, 0) target_count,
        coalesce(x.planned_payroll, 0) planned_payroll
      from public.hr_workforce_plan_cycle c
      join public.sys_tenant t on t.id = c.tenant_id
      left join public.hr_employee e on e.id = c.owner_employee_id and e.tenant_id = c.tenant_id
      left join lateral (
        select count(*)::integer line_count, coalesce(sum(l.baseline_count),0)::integer baseline_count,
          coalesce(sum(l.planned_hires),0)::integer planned_hires,
          coalesce(sum(l.planned_exits),0)::integer planned_exits,
          coalesce(sum(l.target_count),0)::integer target_count,
          coalesce(sum(l.planned_payroll),0)::numeric planned_payroll
        from public.hr_workforce_plan_line l where l.plan_id = c.id and l.tenant_id = c.tenant_id
      ) x on true
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and (p_status is null or c.status = p_status)
        and (v_keyword is null or c.plan_no ilike '%' || v_keyword || '%'
          or c.plan_name ilike '%' || v_keyword || '%' or e.employee_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by period_start desc, create_time desc offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'tenant_name' - 'owner_no' - 'owner_name') || jsonb_build_object(
          'tenant', jsonb_build_object('id', tenant_id, 'name', tenant_name),
          'owner', case when owner_employee_id is null then null else jsonb_build_object(
            'id', owner_employee_id, 'code', owner_no, 'name', owner_name
          ) end
        ) order by period_start desc, create_time desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'line' then
    with incumbent as (
      select a.tenant_id, a.position_id, count(*)::integer current_count
      from public.hr_employee_assignment a
      where a.primary_assignment and a.effective_end is null and a.assignment_status <> 'ended'
      group by a.tenant_id, a.position_id
    ), requisitions as (
      select r.tenant_id, r.position_id,
        count(*) filter (where r.status not in ('completed','cancelled','rejected'))::integer requisition_count,
        coalesce(sum(greatest(r.opening_count - r.hired_count, 0))
          filter (where r.status not in ('completed','cancelled','rejected')), 0)::integer recruiting_count
      from public.hr_recruitment_requisition r group by r.tenant_id, r.position_id
    ), filtered as materialized (
      select l.*, c.plan_no, c.plan_name, c.status plan_status, c.period_start, c.period_end,
        o.organization_code org_code, o.organization_name org_name, p.position_code, p.position_name,
        coalesce(i.current_count, 0) current_count,
        coalesce(r.requisition_count, 0) requisition_count,
        coalesce(r.recruiting_count, 0) recruiting_count,
        l.target_count - coalesce(i.current_count, 0) forecast_gap
      from public.hr_workforce_plan_line l
      join public.hr_workforce_plan_cycle c on c.id = l.plan_id and c.tenant_id = l.tenant_id
      join public.sys_organization o on o.id = l.organization_id and o.tenant_id = l.tenant_id
      join public.hr_position p on p.id = l.position_id and p.tenant_id = l.tenant_id
      left join incumbent i on i.tenant_id = l.tenant_id and i.position_id = l.position_id
      left join requisitions r on r.tenant_id = l.tenant_id and r.position_id = l.position_id
      where (p_tenant_id is null or l.tenant_id = p_tenant_id)
        and (p_plan_id is null or l.plan_id = p_plan_id)
        and (p_status is null or l.priority = p_status)
        and (v_keyword is null or c.plan_no ilike '%' || v_keyword || '%'
          or c.plan_name ilike '%' || v_keyword || '%' or o.organization_name ilike '%' || v_keyword || '%'
          or p.position_code ilike '%' || v_keyword || '%' or p.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by
        case priority when 'critical' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
        demand_date nulls last, position_name offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'plan_no' - 'plan_name' - 'org_code' - 'org_name' - 'position_code' - 'position_name')
        || jsonb_build_object(
          'plan', jsonb_build_object('id', plan_id, 'code', plan_no, 'name', plan_name, 'status', plan_status),
          'organization', jsonb_build_object('id', organization_id, 'code', org_code, 'name', org_name),
          'position', jsonb_build_object('id', position_id, 'code', position_code, 'name', position_name)
        )
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  with incumbent as (
    select a.tenant_id, a.position_id, count(*)::integer current_count
    from public.hr_employee_assignment a
    where a.primary_assignment and a.effective_end is null and a.assignment_status <> 'ended'
    group by a.tenant_id, a.position_id
  ), latest_control as (
    select distinct on (h.tenant_id, h.position_id) h.*
    from public.hr_position_headcount h
    where h.enabled and h.effective_from <= current_date
      and (h.effective_to is null or h.effective_to >= current_date)
    order by h.tenant_id, h.position_id, h.effective_from desc, h.update_time desc
  ), filtered as materialized (
    select coalesce(h.id, p.id) id, p.tenant_id, p.organization_id, p.id position_id,
      coalesce(h.approved_count, p.headcount_limit) approved_count,
      h.effective_from, h.effective_to, coalesce(h.enabled, true) enabled, h.remark,
      h.source_plan_line_id, o.organization_code org_code, o.organization_name org_name,
      p.position_code, p.position_name,
      coalesce(i.current_count, 0) current_count,
      coalesce(h.approved_count, p.headcount_limit) - coalesce(i.current_count, 0) vacancy_count,
      h.create_by, h.create_time, h.update_by, h.update_time
    from public.hr_position p
    join public.sys_organization o on o.id = p.organization_id and o.tenant_id = p.tenant_id
    left join latest_control h on h.tenant_id = p.tenant_id and h.position_id = p.id
    left join incumbent i on i.tenant_id = p.tenant_id and i.position_id = p.id
    where (p_tenant_id is null or p.tenant_id = p_tenant_id)
      and (p_status is null or (p_status = 'vacant' and coalesce(h.approved_count,p.headcount_limit) > coalesce(i.current_count,0))
        or (p_status = 'full' and coalesce(h.approved_count,p.headcount_limit) = coalesce(i.current_count,0))
        or (p_status = 'over' and coalesce(h.approved_count,p.headcount_limit) < coalesce(i.current_count,0)))
      and (v_keyword is null or o.organization_name ilike '%' || v_keyword || '%'
        or p.position_code ilike '%' || v_keyword || '%' or p.position_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by vacancy_count desc, org_name, position_name offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged) - 'org_code' - 'org_name' - 'position_code' - 'position_name')
      || jsonb_build_object(
        'organization', jsonb_build_object('id', organization_id, 'code', org_code, 'name', org_name),
        'position', jsonb_build_object('id', position_id, 'code', position_code, 'name', position_name)
      )
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records','[]'::jsonb,'total',0));
end
$function$;

create or replace function public.hr_list_workforce_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('plan', 'organization', 'position') then raise exception '不支持的人力规划选项类型'; end if;
  if not app_private.can_execute_business_action('HrHeadcount', 'Hr:Headcount:View', null, false) then
    raise exception '当前账号没有查看人力规划的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_current_tenant; end if;

  if p_kind = 'plan' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'code', c.plan_no, 'name', c.plan_name,
      'status', c.status, 'period_start', c.period_start, 'period_end', c.period_end
    ) order by c.period_start desc), '[]'::jsonb)
    from public.hr_workforce_plan_cycle c
    where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status <> 'cancelled');
  end if;
  if p_kind = 'organization' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id, 'tenant_id', o.tenant_id, 'code', o.organization_code, 'name', o.organization_name
    ) order by o.sort, o.organization_name), '[]'::jsonb)
    from public.sys_organization o
    where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = '1');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'tenant_id', p.tenant_id, 'organization_id', p.organization_id,
    'code', p.position_code, 'name', p.position_name, 'headcount_limit', p.headcount_limit,
    'current_count', coalesce(i.current_count,0)
  ) order by p.position_name), '[]'::jsonb)
  from public.hr_position p
  left join lateral (
    select count(*)::integer current_count from public.hr_employee_assignment a
    where a.tenant_id = p.tenant_id and a.position_id = p.id and a.primary_assignment
      and a.effective_end is null and a.assignment_status <> 'ended'
  ) i on true
  where (p_tenant_id is null or p.tenant_id = p_tenant_id) and p.enabled);
end
$function$;

create or replace function public.hr_save_workforce_record_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_permission text;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle public.hr_workforce_plan_cycle%rowtype;
  v_line public.hr_workforce_plan_line%rowtype;
  v_position public.hr_position%rowtype;
  v_baseline integer;
  v_effective public.hr_position_headcount%rowtype;
begin
  if p_kind not in ('cycle','line','effective') then raise exception '不支持的人力规划记录类型'; end if;
  v_permission := case when p_id is null then 'Hr:Headcount:Add' else 'Hr:Headcount:Edit' end;
  if not app_private.can_execute_business_action('HrHeadcount', v_permission, null, false) then
    raise exception '当前账号没有维护人力规划的权限' using errcode = '42501';
  end if;
  if app_private.is_platform_super() and nullif(p_payload->>'tenant_id','') is not null then
    v_tenant_id := (p_payload->>'tenant_id')::uuid;
  end if;
  if v_tenant_id is null then raise exception '缺少所属租户'; end if;

  if p_kind = 'cycle' then
    if p_id is not null then
      select * into v_cycle from public.hr_workforce_plan_cycle where id = p_id for update;
      if not found then raise exception '人力规划周期不存在'; end if;
      if not app_private.is_platform_super() and v_cycle.tenant_id <> v_tenant_id then raise exception '无权维护其他租户数据'; end if;
      if v_cycle.status <> 'draft' then raise exception '仅草稿规划可以编辑'; end if;
      update public.hr_workforce_plan_cycle set
        plan_no = btrim(p_payload->>'plan_no'), plan_name = btrim(p_payload->>'plan_name'),
        scenario = coalesce(nullif(p_payload->>'scenario',''), scenario),
        period_start = (p_payload->>'period_start')::date,
        period_end = (p_payload->>'period_end')::date,
        baseline_date = coalesce(nullif(p_payload->>'baseline_date','')::date, baseline_date),
        owner_employee_id = nullif(p_payload->>'owner_employee_id','')::uuid,
        budget_amount = nullif(p_payload->>'budget_amount','')::numeric,
        currency_code = coalesce(nullif(upper(p_payload->>'currency_code'),''), currency_code),
        objective = nullif(btrim(p_payload->>'objective'),''),
        assumptions = nullif(btrim(p_payload->>'assumptions'),''),
        remark = nullif(btrim(p_payload->>'remark'),'')
      where id = p_id returning * into v_cycle;
      return v_cycle.id;
    end if;
    insert into public.hr_workforce_plan_cycle(
      tenant_id, plan_no, plan_name, scenario, period_start, period_end, baseline_date,
      owner_employee_id, budget_amount, currency_code, objective, assumptions, remark
    ) values (
      v_tenant_id, btrim(p_payload->>'plan_no'), btrim(p_payload->>'plan_name'),
      coalesce(nullif(p_payload->>'scenario',''),'baseline'),
      (p_payload->>'period_start')::date, (p_payload->>'period_end')::date,
      coalesce(nullif(p_payload->>'baseline_date','')::date,current_date),
      nullif(p_payload->>'owner_employee_id','')::uuid,
      nullif(p_payload->>'budget_amount','')::numeric,
      coalesce(nullif(upper(p_payload->>'currency_code'),''),'CNY'),
      nullif(btrim(p_payload->>'objective'),''), nullif(btrim(p_payload->>'assumptions'),''),
      nullif(btrim(p_payload->>'remark'),'')
    ) returning * into v_cycle;
    return v_cycle.id;
  end if;

  if p_kind = 'line' then
    select * into v_cycle from public.hr_workforce_plan_cycle
    where id = (p_payload->>'plan_id')::uuid for update;
    if not found then raise exception '所属人力规划周期不存在'; end if;
    if not app_private.is_platform_super() and v_cycle.tenant_id <> v_tenant_id then raise exception '无权维护其他租户数据'; end if;
    if v_cycle.status <> 'draft' then raise exception '仅草稿规划可以维护岗位需求'; end if;
    v_tenant_id := v_cycle.tenant_id;
    select * into v_position from public.hr_position
    where id = (p_payload->>'position_id')::uuid and tenant_id = v_tenant_id;
    if not found or not v_position.enabled then raise exception '所选岗位不存在或已停用'; end if;
    if v_position.organization_id <> (p_payload->>'organization_id')::uuid then
      raise exception '岗位与组织不匹配';
    end if;
    select count(*)::integer into v_baseline from public.hr_employee_assignment a
    where a.tenant_id = v_tenant_id and a.position_id = v_position.id and a.primary_assignment
      and a.effective_end is null and a.assignment_status <> 'ended';
    if nullif(p_payload->>'demand_date','') is not null
      and (p_payload->>'demand_date')::date not between v_cycle.period_start and v_cycle.period_end then
      raise exception '需求日期必须位于规划周期内';
    end if;

    if p_id is not null then
      select * into v_line from public.hr_workforce_plan_line where id = p_id for update;
      if not found or v_line.plan_id <> v_cycle.id then raise exception '人力规划岗位需求不存在'; end if;
      update public.hr_workforce_plan_line set
        organization_id = (p_payload->>'organization_id')::uuid,
        position_id = v_position.id,
        baseline_count = case when v_line.position_id = v_position.id then v_line.baseline_count else v_baseline end,
        planned_hires = coalesce((p_payload->>'planned_hires')::integer,0),
        planned_exits = coalesce((p_payload->>'planned_exits')::integer,0),
        annual_cost_per_head = nullif(p_payload->>'annual_cost_per_head','')::numeric,
        demand_date = nullif(p_payload->>'demand_date','')::date,
        priority = coalesce(nullif(p_payload->>'priority',''),'normal'),
        rationale = btrim(p_payload->>'rationale'),
        assumptions = nullif(btrim(p_payload->>'assumptions'),'')
      where id = p_id returning * into v_line;
      return v_line.id;
    end if;
    insert into public.hr_workforce_plan_line(
      tenant_id, plan_id, organization_id, position_id, baseline_count, planned_hires,
      planned_exits, annual_cost_per_head, demand_date, priority, rationale, assumptions
    ) values (
      v_tenant_id, v_cycle.id, (p_payload->>'organization_id')::uuid, v_position.id, v_baseline,
      coalesce((p_payload->>'planned_hires')::integer,0), coalesce((p_payload->>'planned_exits')::integer,0),
      nullif(p_payload->>'annual_cost_per_head','')::numeric,
      nullif(p_payload->>'demand_date','')::date, coalesce(nullif(p_payload->>'priority',''),'normal'),
      btrim(p_payload->>'rationale'), nullif(btrim(p_payload->>'assumptions'),'')
    ) returning * into v_line;
    return v_line.id;
  end if;

  select * into v_position from public.hr_position
  where id = (p_payload->>'position_id')::uuid and tenant_id = v_tenant_id;
  if not found then raise exception '岗位不存在'; end if;
  if v_position.organization_id <> (p_payload->>'organization_id')::uuid then raise exception '岗位与组织不匹配'; end if;
  if exists (
    select 1 from public.hr_position_headcount h
    where h.tenant_id = v_tenant_id and h.position_id = v_position.id and h.enabled
      and h.id <> coalesce(p_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and daterange(h.effective_from, coalesce(h.effective_to,'infinity'::date),'[]')
        && daterange((p_payload->>'effective_from')::date,
          coalesce(nullif(p_payload->>'effective_to','')::date,'infinity'::date),'[]')
  ) then raise exception '该岗位在所选期间已有有效编制记录'; end if;
  if p_id is null then
    insert into public.hr_position_headcount(
      tenant_id, organization_id, position_id, approved_count, effective_from, effective_to, enabled, remark
    ) values (
      v_tenant_id, (p_payload->>'organization_id')::uuid, v_position.id,
      (p_payload->>'approved_count')::integer, (p_payload->>'effective_from')::date,
      nullif(p_payload->>'effective_to','')::date,
      coalesce((p_payload->>'enabled')::boolean,true), nullif(btrim(p_payload->>'remark'),'')
    ) returning * into v_effective;
  else
    update public.hr_position_headcount set
      organization_id = (p_payload->>'organization_id')::uuid,
      position_id = v_position.id, approved_count = (p_payload->>'approved_count')::integer,
      effective_from = (p_payload->>'effective_from')::date,
      effective_to = nullif(p_payload->>'effective_to','')::date,
      enabled = coalesce((p_payload->>'enabled')::boolean,true),
      remark = nullif(btrim(p_payload->>'remark'),'')
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    returning * into v_effective;
    if not found then raise exception '有效编制记录不存在'; end if;
  end if;
  if v_effective.enabled and v_effective.effective_from <= current_date
    and (v_effective.effective_to is null or v_effective.effective_to >= current_date) then
    if v_effective.approved_count = 0 then
      update public.hr_position set enabled = false where id = v_position.id;
    else
      update public.hr_position set headcount_limit = v_effective.approved_count,
        multiple_incumbents_allowed = multiple_incumbents_allowed or v_effective.approved_count > 1
      where id = v_position.id;
    end if;
  end if;
  return v_effective.id;
end
$function$;

create or replace function public.hr_transition_workforce_plan_secure(
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_cycle public.hr_workforce_plan_cycle%rowtype;
  v_permission text;
  v_line record;
  v_incumbents integer;
begin
  v_permission := case
    when p_action in ('submit','cancel') then 'Hr:Headcount:Submit'
    when p_action in ('approve','return') then 'Hr:Headcount:Approve'
    when p_action = 'activate' then 'Hr:Headcount:Activate'
    when p_action = 'close' then 'Hr:Headcount:Close'
    else null end;
  if v_permission is null then raise exception '不支持的人力规划状态操作'; end if;
  if not app_private.can_execute_business_action('HrHeadcount', v_permission, null, false) then
    raise exception '当前账号没有执行该人力规划操作的权限' using errcode = '42501';
  end if;
  select * into v_cycle from public.hr_workforce_plan_cycle where id = p_id for update;
  if not found then raise exception '人力规划周期不存在'; end if;
  if not app_private.is_platform_super() and v_cycle.tenant_id <> app_private.current_user_tenant_id() then
    raise exception '无权操作其他租户的人力规划';
  end if;

  if p_action = 'submit' then
    if v_cycle.status <> 'draft' then raise exception '仅草稿规划可以提交'; end if;
    if not exists (select 1 from public.hr_workforce_plan_line where plan_id = p_id) then
      raise exception '至少维护一条岗位需求后才能提交';
    end if;
    if exists (
      select 1 from public.hr_workforce_plan_line l
      join public.hr_workforce_plan_cycle other_cycle on other_cycle.id <> v_cycle.id
        and other_cycle.tenant_id = l.tenant_id and other_cycle.status in ('approved','active')
        and daterange(other_cycle.period_start,other_cycle.period_end,'[]')
          && daterange(v_cycle.period_start,v_cycle.period_end,'[]')
      join public.hr_workforce_plan_line other_line on other_line.plan_id = other_cycle.id
        and other_line.position_id = l.position_id
      where l.plan_id = v_cycle.id
    ) then raise exception '规划周期与已批准或执行中的同岗位计划重叠'; end if;
    update public.hr_workforce_plan_cycle set status='submitted', remark=coalesce(nullif(btrim(p_comment),''),remark)
    where id=p_id;
    return true;
  end if;
  if p_action = 'return' then
    if v_cycle.status <> 'submitted' then raise exception '仅待审批规划可以退回'; end if;
    if nullif(btrim(p_comment),'') is null then raise exception '退回时必须填写原因'; end if;
    update public.hr_workforce_plan_cycle set status='draft', remark=btrim(p_comment) where id=p_id;
    return true;
  end if;
  if p_action = 'cancel' then
    if v_cycle.status not in ('draft','submitted') then raise exception '当前状态不能取消'; end if;
    if nullif(btrim(p_comment),'') is null then raise exception '取消时必须填写原因'; end if;
    update public.hr_workforce_plan_cycle set status='cancelled', remark=btrim(p_comment) where id=p_id;
    return true;
  end if;
  if p_action = 'approve' then
    if v_cycle.status <> 'submitted' then raise exception '仅待审批规划可以批准'; end if;
    update public.hr_workforce_plan_cycle set status='approved',
      approved_by=coalesce(public.get_app_user_display_name(),app_private.current_user_email(),'system'),
      approved_at=now(), remark=coalesce(nullif(btrim(p_comment),''),remark)
    where id=p_id;
    return true;
  end if;
  if p_action = 'activate' then
    if v_cycle.status <> 'approved' then raise exception '仅已批准规划可以启用'; end if;
    if current_date < v_cycle.period_start then raise exception '规划尚未到生效日期'; end if;
    if current_date > v_cycle.period_end then raise exception '规划周期已经结束'; end if;
    for v_line in select * from public.hr_workforce_plan_line where plan_id=p_id for update loop
      select count(*)::integer into v_incumbents from public.hr_employee_assignment a
      where a.tenant_id=v_line.tenant_id and a.position_id=v_line.position_id and a.primary_assignment
        and a.effective_end is null and a.assignment_status <> 'ended';
      if v_line.target_count < v_incumbents then
        raise exception '岗位目标编制 % 低于当前在岗 %，请先完成调配或修订计划', v_line.target_count, v_incumbents;
      end if;
      insert into public.hr_position_headcount(
        tenant_id, organization_id, position_id, approved_count, effective_from, effective_to,
        enabled, remark, source_plan_line_id
      ) values (
        v_line.tenant_id, v_line.organization_id, v_line.position_id, v_line.target_count,
        v_cycle.period_start, v_cycle.period_end, true,
        '由人力规划 ' || v_cycle.plan_no || ' 启用', v_line.id
      ) on conflict (tenant_id, organization_id, position_id, effective_from) do update set
        approved_count=excluded.approved_count, effective_to=excluded.effective_to, enabled=true,
        remark=excluded.remark, source_plan_line_id=excluded.source_plan_line_id;
      if v_line.target_count = 0 then
        update public.hr_position set enabled=false where id=v_line.position_id and tenant_id=v_line.tenant_id;
      else
        update public.hr_position set headcount_limit=v_line.target_count,
          multiple_incumbents_allowed=multiple_incumbents_allowed or v_line.target_count > 1
        where id=v_line.position_id and tenant_id=v_line.tenant_id;
      end if;
    end loop;
    update public.hr_workforce_plan_cycle set status='active',activated_at=now(),
      remark=coalesce(nullif(btrim(p_comment),''),remark) where id=p_id;
    return true;
  end if;
  if v_cycle.status <> 'active' then raise exception '仅执行中的规划可以关闭'; end if;
  if current_date < v_cycle.period_end and nullif(btrim(p_comment),'') is null then
    raise exception '提前关闭规划必须填写原因';
  end if;
  update public.hr_workforce_plan_cycle set status='closed',closed_at=now(),
    remark=coalesce(nullif(btrim(p_comment),''),remark) where id=p_id;
  return true;
end
$function$;

create or replace function public.hr_delete_workforce_record_secure(p_kind text, p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid;
  v_status text;
begin
  if p_kind not in ('cycle','line','effective') then raise exception '不支持的人力规划记录类型'; end if;
  if not app_private.can_execute_business_action('HrHeadcount', 'Hr:Headcount:Delete', null, false) then
    raise exception '当前账号没有删除人力规划记录的权限' using errcode = '42501';
  end if;
  if p_kind = 'cycle' then
    select tenant_id,status into v_tenant_id,v_status from public.hr_workforce_plan_cycle where id=p_id;
    if not found then raise exception '人力规划周期不存在'; end if;
    if v_status <> 'draft' then raise exception '仅草稿规划可以删除'; end if;
    if not app_private.is_platform_super() and v_tenant_id <> app_private.current_user_tenant_id() then raise exception '无权删除其他租户数据'; end if;
    delete from public.hr_workforce_plan_cycle where id=p_id;
    return true;
  end if;
  if p_kind = 'line' then
    select l.tenant_id,c.status into v_tenant_id,v_status
    from public.hr_workforce_plan_line l join public.hr_workforce_plan_cycle c on c.id=l.plan_id
    where l.id=p_id;
    if not found then raise exception '岗位需求不存在'; end if;
    if v_status <> 'draft' then raise exception '仅草稿规划的岗位需求可以删除'; end if;
    if not app_private.is_platform_super() and v_tenant_id <> app_private.current_user_tenant_id() then raise exception '无权删除其他租户数据'; end if;
    delete from public.hr_workforce_plan_line where id=p_id;
    return true;
  end if;
  select tenant_id into v_tenant_id from public.hr_position_headcount where id=p_id
    and source_plan_line_id is null and effective_from > current_date;
  if not found then raise exception '仅可删除尚未生效且非规划启用产生的编制记录'; end if;
  if not app_private.is_platform_super() and v_tenant_id <> app_private.current_user_tenant_id() then raise exception '无权删除其他租户数据'; end if;
  delete from public.hr_position_headcount where id=p_id;
  return true;
end
$function$;

revoke execute on function public.hr_workforce_overview_secure(uuid) from public, anon;
revoke execute on function public.hr_list_workforce_records_secure(text,integer,integer,text,text,uuid,uuid) from public, anon;
revoke execute on function public.hr_list_workforce_options_secure(text,uuid) from public, anon;
revoke execute on function public.hr_save_workforce_record_secure(text,uuid,jsonb) from public, anon;
revoke execute on function public.hr_transition_workforce_plan_secure(uuid,text,text) from public, anon;
revoke execute on function public.hr_delete_workforce_record_secure(text,uuid) from public, anon;

grant execute on function public.hr_workforce_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_workforce_records_secure(text,integer,integer,text,text,uuid,uuid) to authenticated, service_role;
grant execute on function public.hr_list_workforce_options_secure(text,uuid) to authenticated, service_role;
grant execute on function public.hr_save_workforce_record_secure(text,uuid,jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_workforce_plan_secure(uuid,text,text) to authenticated, service_role;
grant execute on function public.hr_delete_workforce_record_secure(text,uuid) to authenticated, service_role;
