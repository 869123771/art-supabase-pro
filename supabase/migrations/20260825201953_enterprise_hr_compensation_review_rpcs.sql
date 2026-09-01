-- Secure compensation review APIs and lifecycle state machine.

create or replace function app_private.hr_validate_compensation_review_budget(
  p_cycle_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_overrun record;
begin
  select
    coalesce(organization.organization_name, '未分配组织') as organization_name,
    coalesce(budget.budget_amount, 0) as budget_amount,
    coalesce(sum(greatest(item.proposed_base_amount - item.current_base_amount, 0)), 0) as used_amount
  into v_overrun
  from public.hr_compensation_review_item item
  left join public.sys_organization organization
    on organization.id = item.organization_id
   and organization.tenant_id = item.tenant_id
  left join public.hr_compensation_review_budget budget
    on budget.cycle_id = item.cycle_id
   and budget.tenant_id = item.tenant_id
   and budget.organization_id is not distinct from item.organization_id
  where item.cycle_id = p_cycle_id
    and item.status <> 'excluded'
  group by item.organization_id, organization.organization_name, budget.budget_amount
  having coalesce(sum(greatest(item.proposed_base_amount - item.current_base_amount, 0)), 0)
       > coalesce(budget.budget_amount, 0)
  order by
    coalesce(sum(greatest(item.proposed_base_amount - item.current_base_amount, 0)), 0)
      - coalesce(budget.budget_amount, 0) desc
  limit 1;

  if found then
    raise exception '% 调薪预算超支：预算 %，已建议 %',
      v_overrun.organization_name, v_overrun.budget_amount, v_overrun.used_amount;
  end if;
end;
$function$;

revoke all on function app_private.hr_validate_compensation_review_budget(uuid)
from public, anon, authenticated;

create or replace function public.hr_compensation_review_overview_secure(
  p_cycle_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle public.hr_compensation_review_cycle%rowtype;
  v_amount_access boolean;
  v_budget numeric(18, 2) := 0;
  v_used numeric(18, 2) := 0;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:View', null, false
  ) then
    raise exception '当前账号没有查看调薪复核的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_amount_access := app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:Amount:View', null, false
  );

  if p_cycle_id is not null then
    select * into v_cycle
    from public.hr_compensation_review_cycle cycle_row
    where cycle_row.id = p_cycle_id
      and (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id);
  else
    select * into v_cycle
    from public.hr_compensation_review_cycle cycle_row
    where (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id)
      and cycle_row.status <> 'cancelled'
    order by
      case cycle_row.status
        when 'open' then 1 when 'calibrating' then 2 when 'approved' then 3
        when 'draft' then 4 when 'effected' then 5 else 6
      end,
      cycle_row.effective_date desc,
      cycle_row.create_time desc
    limit 1;
  end if;

  if v_cycle.id is not null then
    select coalesce(sum(budget_amount), 0) into v_budget
    from public.hr_compensation_review_budget where cycle_id = v_cycle.id;

    select coalesce(sum(greatest(proposed_base_amount - current_base_amount, 0)), 0)
    into v_used
    from public.hr_compensation_review_item
    where cycle_id = v_cycle.id and status <> 'excluded';
  end if;

  return jsonb_build_object(
    'cycle_count', (
      select count(*) from public.hr_compensation_review_cycle cycle_row
      where (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id)
        and cycle_row.status <> 'cancelled'
    ),
    'amount_access', v_amount_access,
    'selected_cycle', case when v_cycle.id is null then null else jsonb_build_object(
      'id', v_cycle.id,
      'tenant_id', v_cycle.tenant_id,
      'cycle_code', v_cycle.cycle_code,
      'cycle_name', v_cycle.cycle_name,
      'review_year', v_cycle.review_year,
      'effective_date', v_cycle.effective_date,
      'recommendation_due_date', v_cycle.recommendation_due_date,
      'calibration_due_date', v_cycle.calibration_due_date,
      'scope_organization_id', v_cycle.scope_organization_id,
      'currency_code', v_cycle.currency_code,
      'default_budget_percent', v_cycle.default_budget_percent,
      'guideline_min_percent', v_cycle.guideline_min_percent,
      'guideline_max_percent', v_cycle.guideline_max_percent,
      'status', v_cycle.status,
      'description', v_cycle.description,
      'decision_note', v_cycle.decision_note
    ) end,
    'eligible_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item where cycle_id = v_cycle.id
    ) end,
    'pending_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'pending'
    ) end,
    'recommended_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'recommended'
    ) end,
    'calibrated_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status in ('calibrated', 'approved', 'effected')
    ) end,
    'approved_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status in ('approved', 'effected')
    ) end,
    'effected_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'effected'
    ) end,
    'excluded_count', case when v_cycle.id is null then 0 else (
      select count(*) from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'excluded'
    ) end,
    'out_of_guideline_count', case when v_cycle.id is null then 0 else (
      select count(*)
      from public.hr_compensation_review_item item
      where item.cycle_id = v_cycle.id
        and item.status <> 'excluded'
        and item.current_base_amount > 0
        and round((item.proposed_base_amount - item.current_base_amount) * 100
          / item.current_base_amount, 4)
          not between v_cycle.guideline_min_percent and v_cycle.guideline_max_percent
    ) end,
    'budget_amount', case when v_amount_access then v_budget else null end,
    'proposed_increase_amount', case when v_amount_access then v_used else null end,
    'budget_utilization', case
      when not v_amount_access then null
      when v_budget = 0 and v_used = 0 then 0
      when v_budget = 0 then 100
      else round(v_used * 100 / v_budget, 1)
    end
  );
end;
$function$;

create or replace function public.hr_list_compensation_review_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_cycle_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_amount_access boolean;
  v_records jsonb := '[]'::jsonb;
  v_total integer := 0;
begin
  if p_kind not in ('cycle', 'item', 'budget') then
    raise exception '不支持的调薪复核记录类型';
  end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:View', null, false
  ) then
    raise exception '当前账号没有查看调薪复核的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_amount_access := app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:Amount:View', null, false
  );

  if p_kind = 'cycle' then
    select count(*)::integer into v_total
    from public.hr_compensation_review_cycle cycle_row
    left join public.sys_organization organization
      on organization.id = cycle_row.scope_organization_id
     and organization.tenant_id = cycle_row.tenant_id
    where (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id)
      and (p_status is null or p_status = '' or cycle_row.status = p_status)
      and (v_keyword is null or cycle_row.cycle_code ilike '%' || v_keyword || '%'
        or cycle_row.cycle_name ilike '%' || v_keyword || '%'
        or organization.organization_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by effective_date desc, create_time desc), '[]'::jsonb)
    into v_records
    from (
      select
        cycle_row.effective_date,
        cycle_row.create_time,
        jsonb_build_object(
          'id', cycle_row.id,
          'tenant_id', cycle_row.tenant_id,
          'cycle_code', cycle_row.cycle_code,
          'cycle_name', cycle_row.cycle_name,
          'review_year', cycle_row.review_year,
          'effective_date', cycle_row.effective_date,
          'recommendation_due_date', cycle_row.recommendation_due_date,
          'calibration_due_date', cycle_row.calibration_due_date,
          'scope_organization_id', cycle_row.scope_organization_id,
          'scope_organization_name', organization.organization_name,
          'currency_code', cycle_row.currency_code,
          'default_budget_percent', cycle_row.default_budget_percent,
          'guideline_min_percent', cycle_row.guideline_min_percent,
          'guideline_max_percent', cycle_row.guideline_max_percent,
          'status', cycle_row.status,
          'description', cycle_row.description,
          'decision_note', cycle_row.decision_note,
          'employee_count', (select count(*) from public.hr_compensation_review_item item where item.cycle_id = cycle_row.id),
          'pending_count', (select count(*) from public.hr_compensation_review_item item where item.cycle_id = cycle_row.id and item.status = 'pending'),
          'budget_amount', case when v_amount_access then (select coalesce(sum(budget_amount), 0) from public.hr_compensation_review_budget budget where budget.cycle_id = cycle_row.id) else to_jsonb('***'::text) end,
          'proposed_increase_amount', case when v_amount_access then (select coalesce(sum(greatest(proposed_base_amount - current_base_amount, 0)), 0) from public.hr_compensation_review_item item where item.cycle_id = cycle_row.id and item.status <> 'excluded') else to_jsonb('***'::text) end,
          'create_time', cycle_row.create_time,
          'update_time', cycle_row.update_time
        ) as row_data
      from public.hr_compensation_review_cycle cycle_row
      left join public.sys_organization organization
        on organization.id = cycle_row.scope_organization_id
       and organization.tenant_id = cycle_row.tenant_id
      where (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id)
        and (p_status is null or p_status = '' or cycle_row.status = p_status)
        and (v_keyword is null or cycle_row.cycle_code ilike '%' || v_keyword || '%'
          or cycle_row.cycle_name ilike '%' || v_keyword || '%'
          or organization.organization_name ilike '%' || v_keyword || '%')
      order by cycle_row.effective_date desc, cycle_row.create_time desc
      offset v_offset limit v_limit
    ) page;
  elsif p_kind = 'budget' then
    select count(*)::integer into v_total
    from public.hr_compensation_review_budget budget
    join public.hr_compensation_review_cycle cycle_row
      on cycle_row.id = budget.cycle_id and cycle_row.tenant_id = budget.tenant_id
    left join public.sys_organization organization
      on organization.id = budget.organization_id and organization.tenant_id = budget.tenant_id
    where (p_tenant_id is null or budget.tenant_id = p_tenant_id)
      and (p_cycle_id is null or budget.cycle_id = p_cycle_id)
      and (v_keyword is null or organization.organization_name ilike '%' || v_keyword || '%'
        or cycle_row.cycle_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by organization_name), '[]'::jsonb)
    into v_records
    from (
      select
        coalesce(organization.organization_name, '未分配组织') organization_name,
        jsonb_build_object(
          'id', budget.id,
          'tenant_id', budget.tenant_id,
          'cycle_id', budget.cycle_id,
          'cycle_name', cycle_row.cycle_name,
          'organization_id', budget.organization_id,
          'organization_name', coalesce(organization.organization_name, '未分配组织'),
          'budget_amount', case when v_amount_access then to_jsonb(budget.budget_amount) else to_jsonb('***'::text) end,
          'used_amount', case when v_amount_access then to_jsonb(coalesce(usage.used_amount, 0)) else to_jsonb('***'::text) end,
          'remaining_amount', case when v_amount_access then to_jsonb(budget.budget_amount - coalesce(usage.used_amount, 0)) else to_jsonb('***'::text) end,
          'utilization_percent', case when not v_amount_access then null when budget.budget_amount = 0 and coalesce(usage.used_amount, 0) = 0 then 0 when budget.budget_amount = 0 then 100 else round(coalesce(usage.used_amount, 0) * 100 / budget.budget_amount, 1) end,
          'employee_count', coalesce(usage.employee_count, 0),
          'source', budget.source,
          'note', budget.note,
          'cycle_status', cycle_row.status,
          'create_time', budget.create_time,
          'update_time', budget.update_time
        ) row_data
      from public.hr_compensation_review_budget budget
      join public.hr_compensation_review_cycle cycle_row
        on cycle_row.id = budget.cycle_id and cycle_row.tenant_id = budget.tenant_id
      left join public.sys_organization organization
        on organization.id = budget.organization_id and organization.tenant_id = budget.tenant_id
      left join lateral (
        select
          count(*)::integer employee_count,
          coalesce(sum(greatest(item.proposed_base_amount - item.current_base_amount, 0)), 0) used_amount
        from public.hr_compensation_review_item item
        where item.cycle_id = budget.cycle_id
          and item.organization_id is not distinct from budget.organization_id
          and item.status <> 'excluded'
      ) usage on true
      where (p_tenant_id is null or budget.tenant_id = p_tenant_id)
        and (p_cycle_id is null or budget.cycle_id = p_cycle_id)
        and (v_keyword is null or organization.organization_name ilike '%' || v_keyword || '%'
          or cycle_row.cycle_name ilike '%' || v_keyword || '%')
      order by coalesce(organization.organization_name, '未分配组织')
      offset v_offset limit v_limit
    ) page;
  else
    select count(*)::integer into v_total
    from public.hr_compensation_review_item item
    join public.hr_employee employee on employee.id = item.employee_id and employee.tenant_id = item.tenant_id
    left join public.sys_organization organization on organization.id = item.organization_id and organization.tenant_id = item.tenant_id
    where (p_tenant_id is null or item.tenant_id = p_tenant_id)
      and (p_cycle_id is null or item.cycle_id = p_cycle_id)
      and (p_status is null or p_status = '' or item.status = p_status)
      and (v_keyword is null or employee.employee_name ilike '%' || v_keyword || '%'
        or employee.employee_no ilike '%' || v_keyword || '%'
        or organization.organization_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by organization_name, employee_name), '[]'::jsonb)
    into v_records
    from (
      select
        coalesce(organization.organization_name, '未分配组织') organization_name,
        employee.employee_name,
        jsonb_build_object(
          'id', item.id,
          'tenant_id', item.tenant_id,
          'cycle_id', item.cycle_id,
          'cycle_name', cycle_row.cycle_name,
          'cycle_status', cycle_row.status,
          'employee_id', item.employee_id,
          'employee_no', employee.employee_no,
          'employee_name', employee.employee_name,
          'organization_id', item.organization_id,
          'organization_name', coalesce(organization.organization_name, '未分配组织'),
          'current_compensation_id', item.current_compensation_id,
          'current_grade_id', item.current_grade_id,
          'grade_name', grade.grade_name,
          'current_base_amount', case when v_amount_access then to_jsonb(item.current_base_amount) else to_jsonb('***'::text) end,
          'proposed_base_amount', case when v_amount_access then to_jsonb(item.proposed_base_amount) else to_jsonb('***'::text) end,
          'increase_amount', case when v_amount_access then to_jsonb(item.proposed_base_amount - item.current_base_amount) else to_jsonb('***'::text) end,
          'increase_percent', case when v_amount_access and item.current_base_amount > 0 then round((item.proposed_base_amount - item.current_base_amount) * 100 / item.current_base_amount, 2) else null end,
          'performance_level', item.performance_level,
          'status', item.status,
          'recommendation_reason', item.recommendation_reason,
          'recommended_by', item.recommended_by,
          'recommended_at', item.recommended_at,
          'calibration_note', item.calibration_note,
          'calibrated_by', item.calibrated_by,
          'calibrated_at', item.calibrated_at,
          'exclusion_reason', item.exclusion_reason,
          'new_compensation_id', item.new_compensation_id,
          'out_of_guideline', case when item.current_base_amount = 0 then false else round((item.proposed_base_amount - item.current_base_amount) * 100 / item.current_base_amount, 4) not between cycle_row.guideline_min_percent and cycle_row.guideline_max_percent end,
          'create_time', item.create_time,
          'update_time', item.update_time
        ) row_data
      from public.hr_compensation_review_item item
      join public.hr_compensation_review_cycle cycle_row on cycle_row.id = item.cycle_id and cycle_row.tenant_id = item.tenant_id
      join public.hr_employee employee on employee.id = item.employee_id and employee.tenant_id = item.tenant_id
      left join public.sys_organization organization on organization.id = item.organization_id and organization.tenant_id = item.tenant_id
      left join public.hr_grade grade on grade.id = item.current_grade_id and grade.tenant_id = item.tenant_id
      where (p_tenant_id is null or item.tenant_id = p_tenant_id)
        and (p_cycle_id is null or item.cycle_id = p_cycle_id)
        and (p_status is null or p_status = '' or item.status = p_status)
        and (v_keyword is null or employee.employee_name ilike '%' || v_keyword || '%'
          or employee.employee_no ilike '%' || v_keyword || '%'
          or organization.organization_name ilike '%' || v_keyword || '%')
      order by coalesce(organization.organization_name, '未分配组织'), employee.employee_name
      offset v_offset limit v_limit
    ) page;
  end if;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'amount_access', v_amount_access
  );
end;
$function$;

create or replace function public.hr_list_compensation_review_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('cycle', 'organization') then raise exception '不支持的调薪选项类型'; end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:View', null, false
  ) then
    raise exception '当前账号没有查看调薪复核的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'cycle' then
    return (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', cycle_row.id,
        'tenant_id', cycle_row.tenant_id,
        'code', cycle_row.cycle_code,
        'name', cycle_row.cycle_name,
        'status', cycle_row.status,
        'effective_date', cycle_row.effective_date
      ) order by cycle_row.effective_date desc), '[]'::jsonb)
      from public.hr_compensation_review_cycle cycle_row
      where (p_tenant_id is null or cycle_row.tenant_id = p_tenant_id)
        and cycle_row.status <> 'cancelled'
    );
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', organization.id,
      'tenant_id', organization.tenant_id,
      'code', organization.organization_code,
      'name', organization.organization_name
    ) order by organization.sort, organization.organization_name), '[]'::jsonb)
    from public.sys_organization organization
    where (p_tenant_id is null or organization.tenant_id = p_tenant_id)
      and organization.status = '1'
  );
end;
$function$;

create or replace function public.hr_save_compensation_review_record_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle public.hr_compensation_review_cycle%rowtype;
  v_budget public.hr_compensation_review_budget%rowtype;
  v_item public.hr_compensation_review_item%rowtype;
  v_proposed numeric(18, 2);
  v_percent numeric(10, 4);
  v_reason text;
  v_note text;
  v_exclude boolean := coalesce((p_payload->>'exclude')::boolean, false);
  v_actor text := coalesce(app_private.current_user_email(), auth.uid()::text, 'system');
begin
  if p_kind not in ('cycle', 'budget', 'item') then raise exception '不支持的调薪复核记录类型'; end if;
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;

  if p_kind = 'cycle' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Cycle:Manage', null, false
    ) then raise exception '当前账号没有管理调薪周期的权限' using errcode = '42501'; end if;
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Amount:Edit', null, false
    ) then raise exception '当前账号没有编辑调薪金额的权限' using errcode = '42501'; end if;

    if p_id is not null then
      select * into v_cycle from public.hr_compensation_review_cycle
      where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
      if not found then raise exception '调薪周期不存在'; end if;
      if v_cycle.status <> 'draft' then raise exception '只有草稿周期可以修改'; end if;
      v_tenant_id := v_cycle.tenant_id;
    elsif app_private.is_platform_super() and nullif(p_payload->>'tenant_id', '') is not null then
      v_tenant_id := (p_payload->>'tenant_id')::uuid;
    end if;

    if nullif(btrim(p_payload->>'cycle_code'), '') is null
      or nullif(btrim(p_payload->>'cycle_name'), '') is null then
      raise exception '周期编码和名称不能为空';
    end if;

    if p_id is null then
      insert into public.hr_compensation_review_cycle(
        tenant_id, cycle_code, cycle_name, review_year, effective_date,
        recommendation_due_date, calibration_due_date, scope_organization_id,
        currency_code, default_budget_percent, guideline_min_percent,
        guideline_max_percent, status, description
      ) values (
        v_tenant_id,
        upper(btrim(p_payload->>'cycle_code')),
        btrim(p_payload->>'cycle_name'),
        (p_payload->>'review_year')::integer,
        (p_payload->>'effective_date')::date,
        (p_payload->>'recommendation_due_date')::date,
        (p_payload->>'calibration_due_date')::date,
        nullif(p_payload->>'scope_organization_id', '')::uuid,
        upper(coalesce(nullif(p_payload->>'currency_code', ''), 'CNY')),
        coalesce(nullif(p_payload->>'default_budget_percent', '')::numeric, 5),
        coalesce(nullif(p_payload->>'guideline_min_percent', '')::numeric, 0),
        coalesce(nullif(p_payload->>'guideline_max_percent', '')::numeric, 10),
        'draft',
        nullif(btrim(p_payload->>'description'), '')
      ) returning * into v_cycle;
    else
      update public.hr_compensation_review_cycle set
        cycle_code = upper(btrim(p_payload->>'cycle_code')),
        cycle_name = btrim(p_payload->>'cycle_name'),
        review_year = (p_payload->>'review_year')::integer,
        effective_date = (p_payload->>'effective_date')::date,
        recommendation_due_date = (p_payload->>'recommendation_due_date')::date,
        calibration_due_date = (p_payload->>'calibration_due_date')::date,
        scope_organization_id = nullif(p_payload->>'scope_organization_id', '')::uuid,
        currency_code = upper(coalesce(nullif(p_payload->>'currency_code', ''), 'CNY')),
        default_budget_percent = coalesce(nullif(p_payload->>'default_budget_percent', '')::numeric, 5),
        guideline_min_percent = coalesce(nullif(p_payload->>'guideline_min_percent', '')::numeric, 0),
        guideline_max_percent = coalesce(nullif(p_payload->>'guideline_max_percent', '')::numeric, 10),
        description = nullif(btrim(p_payload->>'description'), '')
      where id = p_id returning * into v_cycle;
    end if;
    return v_cycle.id;
  end if;

  if p_kind = 'budget' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Budget:Manage', null, false
    ) or not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Amount:Edit', null, false
    ) then raise exception '当前账号没有维护调薪预算的权限' using errcode = '42501'; end if;

    select * into v_cycle from public.hr_compensation_review_cycle
    where id = (p_payload->>'cycle_id')::uuid
      and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '调薪周期不存在'; end if;
    if v_cycle.status not in ('draft', 'open') then raise exception '当前阶段不能调整预算'; end if;
    v_tenant_id := v_cycle.tenant_id;

    if p_id is null then
      insert into public.hr_compensation_review_budget(
        tenant_id, cycle_id, organization_id, budget_amount, source, note
      ) values (
        v_tenant_id, v_cycle.id, nullif(p_payload->>'organization_id', '')::uuid,
        (p_payload->>'budget_amount')::numeric, 'manual', nullif(btrim(p_payload->>'note'), '')
      ) returning * into v_budget;
    else
      select * into v_budget from public.hr_compensation_review_budget
      where id = p_id and cycle_id = v_cycle.id and tenant_id = v_tenant_id for update;
      if not found then raise exception '组织预算不存在'; end if;
      update public.hr_compensation_review_budget set
        budget_amount = (p_payload->>'budget_amount')::numeric,
        source = 'manual',
        note = nullif(btrim(p_payload->>'note'), '')
      where id = p_id returning * into v_budget;
    end if;
    return v_budget.id;
  end if;

  if not app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:Amount:Edit', null, false
  ) then raise exception '当前账号没有编辑调薪金额的权限' using errcode = '42501'; end if;

  select item.* into v_item
  from public.hr_compensation_review_item item
  where item.id = p_id and (app_private.is_platform_super() or item.tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '员工调薪复核项不存在'; end if;
  select * into v_cycle from public.hr_compensation_review_cycle
  where id = v_item.cycle_id and tenant_id = v_item.tenant_id for update;

  if v_cycle.status = 'open' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Recommend', null, false
    ) then raise exception '当前账号没有提交调薪建议的权限' using errcode = '42501'; end if;
  elsif v_cycle.status = 'calibrating' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Calibrate', null, false
    ) then raise exception '当前账号没有执行调薪校准的权限' using errcode = '42501'; end if;
  else
    raise exception '当前阶段不能修改员工调薪建议';
  end if;

  if v_exclude then
    v_reason := nullif(btrim(p_payload->>'exclusion_reason'), '');
    if v_reason is null then raise exception '排除员工必须填写原因'; end if;
    update public.hr_compensation_review_item set
      status = 'excluded', exclusion_reason = v_reason,
      recommendation_reason = null, calibration_note = null
    where id = v_item.id;
    return v_item.id;
  end if;

  v_proposed := nullif(p_payload->>'proposed_base_amount', '')::numeric;
  if v_proposed is null or v_proposed < 0 then raise exception '建议基本工资必须为非负金额'; end if;
  v_reason := nullif(btrim(p_payload->>'recommendation_reason'), '');
  v_note := nullif(btrim(p_payload->>'calibration_note'), '');
  v_percent := case when v_item.current_base_amount = 0 then 0
    else round((v_proposed - v_item.current_base_amount) * 100 / v_item.current_base_amount, 4) end;

  if v_proposed <> v_item.current_base_amount and v_reason is null then
    raise exception '发生调薪时必须填写建议依据';
  end if;
  if (v_percent < v_cycle.guideline_min_percent or v_percent > v_cycle.guideline_max_percent)
    and coalesce(v_note, v_reason) is null then
    raise exception '超出调薪指引时必须填写例外依据';
  end if;

  if v_cycle.status = 'open' then
    update public.hr_compensation_review_item set
      proposed_base_amount = v_proposed,
      status = 'recommended',
      recommendation_reason = v_reason,
      recommended_by = v_actor,
      recommended_at = now(),
      exclusion_reason = null
    where id = v_item.id;
  else
    update public.hr_compensation_review_item set
      proposed_base_amount = v_proposed,
      status = 'calibrated',
      recommendation_reason = coalesce(v_reason, recommendation_reason),
      calibration_note = v_note,
      calibrated_by = v_actor,
      calibrated_at = now(),
      exclusion_reason = null
    where id = v_item.id;
  end if;
  return v_item.id;
end;
$function$;

create or replace function public.hr_transition_compensation_review_cycle_secure(
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle public.hr_compensation_review_cycle%rowtype;
  v_item public.hr_compensation_review_item%rowtype;
  v_new_compensation_id uuid;
  v_actor text := coalesce(app_private.current_user_email(), auth.uid()::text, 'system');
  v_inserted integer := 0;
begin
  if p_action not in ('open', 'calibrate', 'approve', 'effect', 'cancel') then
    raise exception '不支持的调薪复核动作';
  end if;
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;

  select * into v_cycle from public.hr_compensation_review_cycle
  where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
  if not found then raise exception '调薪周期不存在'; end if;

  if p_action in ('open', 'cancel') then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Cycle:Manage', null, false
    ) then raise exception '当前账号没有管理调薪周期的权限' using errcode = '42501'; end if;
  elsif p_action = 'calibrate' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Calibrate', null, false
    ) then raise exception '当前账号没有执行调薪校准的权限' using errcode = '42501'; end if;
  elsif p_action = 'approve' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Approve', null, false
    ) then raise exception '当前账号没有批准调薪结果的权限' using errcode = '42501'; end if;
  else
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Effect', null, false
    ) then raise exception '当前账号没有批量生效调薪的权限' using errcode = '42501'; end if;
  end if;

  if p_action = 'open' then
    if v_cycle.status <> 'draft' then raise exception '只有草稿周期可以开放建议'; end if;
    if v_cycle.recommendation_due_date < current_date then raise exception '建议截止日期不能早于当前业务日期'; end if;

    insert into public.hr_compensation_review_item(
      tenant_id, cycle_id, employee_id, organization_id, current_compensation_id,
      current_grade_id, current_base_amount, proposed_base_amount, performance_level, status
    )
    select
      v_cycle.tenant_id,
      v_cycle.id,
      employee.id,
      coalesce(assignment.organization_id, employee.organization_id),
      compensation.id,
      coalesce(assignment.grade_id, compensation.grade_id),
      compensation.base_amount,
      compensation.base_amount,
      performance.performance_level,
      'pending'
    from public.hr_employee employee
    join lateral (
      select compensation_row.*
      from public.hr_employee_compensation compensation_row
      where compensation_row.tenant_id = employee.tenant_id
        and compensation_row.employee_id = employee.id
        and compensation_row.status = 'approved'
        and compensation_row.currency_code = v_cycle.currency_code
        and compensation_row.effective_from <= current_date
        and coalesce(compensation_row.effective_to, 'infinity'::date) >= current_date
      order by compensation_row.effective_from desc
      limit 1
    ) compensation on true
    left join lateral (
      select assignment_row.*
      from public.hr_employee_assignment assignment_row
      where assignment_row.tenant_id = employee.tenant_id
        and assignment_row.employee_id = employee.id
        and assignment_row.primary_assignment
        and assignment_row.effective_start <= current_date
        and coalesce(assignment_row.effective_end, 'infinity'::date) >= current_date
      order by assignment_row.effective_start desc
      limit 1
    ) assignment on true
    left join lateral (
      select review.performance_level
      from public.hr_performance_review review
      where review.tenant_id = employee.tenant_id
        and review.employee_id = employee.id
        and review.status = 'completed'
      order by review.completed_at desc nulls last, review.update_time desc
      limit 1
    ) performance on true
    where employee.tenant_id = v_cycle.tenant_id
      and employee.employment_status in ('probation', 'active', 'leave')
      and (v_cycle.scope_organization_id is null
        or coalesce(assignment.organization_id, employee.organization_id) = v_cycle.scope_organization_id)
      and not exists (
        select 1
        from public.hr_compensation_review_item existing_item
        join public.hr_compensation_review_cycle existing_cycle
          on existing_cycle.id = existing_item.cycle_id
         and existing_cycle.tenant_id = existing_item.tenant_id
        where existing_item.tenant_id = employee.tenant_id
          and existing_item.employee_id = employee.id
          and existing_cycle.effective_date = v_cycle.effective_date
          and existing_cycle.id <> v_cycle.id
          and existing_cycle.status not in ('cancelled', 'effected')
      )
    on conflict (cycle_id, employee_id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 and not exists (
      select 1 from public.hr_compensation_review_item where cycle_id = v_cycle.id
    ) then raise exception '当前范围没有已生效薪酬的在职员工可进入复核'; end if;

    insert into public.hr_compensation_review_budget(
      tenant_id, cycle_id, organization_id, budget_amount, source, note
    )
    select
      item.tenant_id,
      item.cycle_id,
      item.organization_id,
      round(sum(item.current_base_amount) * v_cycle.default_budget_percent / 100, 2),
      'auto',
      '按周期默认预算率自动生成'
    from public.hr_compensation_review_item item
    where item.cycle_id = v_cycle.id
    group by item.tenant_id, item.cycle_id, item.organization_id
    on conflict (cycle_id, organization_id) do update set
      budget_amount = case
        when public.hr_compensation_review_budget.source = 'auto' then excluded.budget_amount
        else public.hr_compensation_review_budget.budget_amount
      end,
      note = case
        when public.hr_compensation_review_budget.source = 'auto' then excluded.note
        else public.hr_compensation_review_budget.note
      end;

    update public.hr_compensation_review_cycle
    set status = 'open', opened_at = now() where id = v_cycle.id;
    return true;
  end if;

  if p_action = 'calibrate' then
    if v_cycle.status <> 'open' then raise exception '只有建议开放中的周期可以进入校准'; end if;
    if exists (
      select 1 from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'pending'
    ) then raise exception '仍有员工未提交调薪建议或排除说明'; end if;
    perform app_private.hr_validate_compensation_review_budget(v_cycle.id);
    update public.hr_compensation_review_item set
      status = 'calibrated',
      calibrated_by = coalesce(calibrated_by, v_actor),
      calibrated_at = coalesce(calibrated_at, now())
    where cycle_id = v_cycle.id and status = 'recommended';
    update public.hr_compensation_review_cycle set status = 'calibrating' where id = v_cycle.id;
    return true;
  end if;

  if p_action = 'approve' then
    if v_cycle.status <> 'calibrating' then raise exception '只有校准中的周期可以批准'; end if;
    if nullif(btrim(p_comment), '') is null then raise exception '批准调薪必须填写审批结论'; end if;
    if exists (
      select 1 from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status not in ('calibrated', 'excluded')
    ) then raise exception '仍有员工尚未完成校准'; end if;
    perform app_private.hr_validate_compensation_review_budget(v_cycle.id);
    update public.hr_compensation_review_item set
      status = 'approved', approved_by = v_actor, approved_at = now()
    where cycle_id = v_cycle.id and status = 'calibrated';
    update public.hr_compensation_review_cycle set
      status = 'approved', decision_note = btrim(p_comment), approved_at = now()
    where id = v_cycle.id;
    return true;
  end if;

  if p_action = 'effect' then
    if v_cycle.status <> 'approved' then raise exception '只有已批准周期可以批量生效'; end if;
    if v_cycle.effective_date > current_date then
      raise exception '调薪生效日尚未到达，不能提前写入员工薪酬历史';
    end if;
    perform app_private.hr_validate_compensation_review_budget(v_cycle.id);

    for v_item in
      select * from public.hr_compensation_review_item
      where cycle_id = v_cycle.id and status = 'approved'
      order by employee_id
      for update
    loop
      if v_item.proposed_base_amount = v_item.current_base_amount then
        update public.hr_compensation_review_item set status = 'effected'
        where id = v_item.id;
        continue;
      end if;

      if exists (
        select 1 from public.hr_employee_compensation existing_compensation
        where existing_compensation.tenant_id = v_item.tenant_id
          and existing_compensation.employee_id = v_item.employee_id
          and existing_compensation.status = 'approved'
          and existing_compensation.id <> v_item.current_compensation_id
          and existing_compensation.effective_from <= v_cycle.effective_date
          and coalesce(existing_compensation.effective_to, 'infinity'::date) >= v_cycle.effective_date
      ) then raise exception '员工 % 在生效日已有其他薪酬版本，请刷新周期快照后再处理', v_item.employee_id; end if;

      perform 1 from public.hr_employee_compensation current_compensation
      where current_compensation.id = v_item.current_compensation_id
        and current_compensation.tenant_id = v_item.tenant_id
        and current_compensation.employee_id = v_item.employee_id
        and current_compensation.status = 'approved'
        and current_compensation.base_amount = v_item.current_base_amount
        and current_compensation.effective_from < v_cycle.effective_date
        and coalesce(current_compensation.effective_to, 'infinity'::date) >= v_cycle.effective_date
      for update;
      if not found then raise exception '员工 % 的当前薪酬已发生变化，本次调薪不能自动生效', v_item.employee_id; end if;

      update public.hr_employee_compensation
      set effective_to = v_cycle.effective_date - 1
      where id = v_item.current_compensation_id;

      insert into public.hr_employee_compensation(
        tenant_id, employee_id, plan_id, grade_id, base_amount, currency_code,
        pay_frequency, effective_from, effective_to, status, change_reason,
        source_review_item_id, approved_by, approved_at
      )
      select
        current_compensation.tenant_id,
        current_compensation.employee_id,
        current_compensation.plan_id,
        current_compensation.grade_id,
        v_item.proposed_base_amount,
        current_compensation.currency_code,
        current_compensation.pay_frequency,
        v_cycle.effective_date,
        null,
        'approved',
        '调薪复核：' || v_cycle.cycle_name,
        v_item.id,
        v_actor,
        now()
      from public.hr_employee_compensation current_compensation
      where current_compensation.id = v_item.current_compensation_id
      returning id into v_new_compensation_id;

      insert into public.hr_employee_compensation_item(
        tenant_id, compensation_id, component_id, amount, rate, source
      )
      select
        current_item.tenant_id,
        v_new_compensation_id,
        current_item.component_id,
        current_item.amount,
        current_item.rate,
        current_item.source
      from public.hr_employee_compensation_item current_item
      where current_item.compensation_id = v_item.current_compensation_id;

      update public.hr_compensation_review_item set
        status = 'effected', new_compensation_id = v_new_compensation_id
      where id = v_item.id;
    end loop;

    update public.hr_compensation_review_cycle
    set status = 'effected', effected_at = now(),
      decision_note = concat_ws(E'\n', decision_note, nullif(btrim(p_comment), ''))
    where id = v_cycle.id;
    return true;
  end if;

  if v_cycle.status not in ('draft', 'open') then raise exception '当前阶段不能取消调薪周期'; end if;
  if nullif(btrim(p_comment), '') is null then raise exception '取消周期必须填写原因'; end if;
  update public.hr_compensation_review_item set
    status = 'excluded', exclusion_reason = '周期取消：' || btrim(p_comment)
  where cycle_id = v_cycle.id and status <> 'excluded';
  update public.hr_compensation_review_cycle set
    status = 'cancelled', decision_note = btrim(p_comment)
  where id = v_cycle.id;
  return true;
end;
$function$;

create or replace function public.hr_delete_compensation_review_record_secure(
  p_kind text,
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cycle_status text;
begin
  if p_kind not in ('cycle', 'budget') then raise exception '不支持删除该类调薪复核记录'; end if;
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;

  if p_kind = 'cycle' then
    if not app_private.can_execute_business_action(
      'HrCompensationReview', 'Hr:CompensationReview:Cycle:Manage', null, false
    ) then raise exception '当前账号没有管理调薪周期的权限' using errcode = '42501'; end if;
    select status into v_cycle_status from public.hr_compensation_review_cycle
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '调薪周期不存在'; end if;
    if v_cycle_status <> 'draft' then raise exception '只有草稿周期可以删除'; end if;
    delete from public.hr_compensation_review_cycle where id = p_id;
    return true;
  end if;

  if not app_private.can_execute_business_action(
    'HrCompensationReview', 'Hr:CompensationReview:Budget:Manage', null, false
  ) then raise exception '当前账号没有管理调薪预算的权限' using errcode = '42501'; end if;
  select cycle_row.status into v_cycle_status
  from public.hr_compensation_review_budget budget
  join public.hr_compensation_review_cycle cycle_row
    on cycle_row.id = budget.cycle_id and cycle_row.tenant_id = budget.tenant_id
  where budget.id = p_id and (app_private.is_platform_super() or budget.tenant_id = v_tenant_id)
  for update of budget;
  if not found then raise exception '组织预算不存在'; end if;
  if v_cycle_status not in ('draft', 'open') then raise exception '当前阶段不能删除组织预算'; end if;
  delete from public.hr_compensation_review_budget where id = p_id;
  return true;
end;
$function$;

revoke all on function public.hr_compensation_review_overview_secure(uuid, uuid)
from public, anon;
revoke all on function public.hr_list_compensation_review_records_secure(text, integer, integer, text, text, uuid, uuid)
from public, anon;
revoke all on function public.hr_list_compensation_review_options_secure(text, uuid)
from public, anon;
revoke all on function public.hr_save_compensation_review_record_secure(text, uuid, jsonb)
from public, anon;
revoke all on function public.hr_transition_compensation_review_cycle_secure(uuid, text, text)
from public, anon;
revoke all on function public.hr_delete_compensation_review_record_secure(text, uuid)
from public, anon;

grant execute on function public.hr_compensation_review_overview_secure(uuid, uuid)
to authenticated, service_role;
grant execute on function public.hr_list_compensation_review_records_secure(text, integer, integer, text, text, uuid, uuid)
to authenticated, service_role;
grant execute on function public.hr_list_compensation_review_options_secure(text, uuid)
to authenticated, service_role;
grant execute on function public.hr_save_compensation_review_record_secure(text, uuid, jsonb)
to authenticated, service_role;
grant execute on function public.hr_transition_compensation_review_cycle_secure(uuid, text, text)
to authenticated, service_role;
grant execute on function public.hr_delete_compensation_review_record_secure(text, uuid)
to authenticated, service_role;


;
