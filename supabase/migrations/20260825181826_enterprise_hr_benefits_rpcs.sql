-- Enterprise HR benefits administration controlled API.
-- Public wrappers are the only authenticated surface; all direct table access
-- remains denied. Every mutation checks a dedicated button permission.

create or replace function app_private.hr_benefit_amount_visible()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or app_private.has_permission('Hr:Benefits:Amount:View')
$function$;

revoke all on function app_private.hr_benefit_amount_visible()
  from public, anon, authenticated;

create or replace function app_private.hr_benefit_evidence_visible()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or app_private.has_permission('Hr:Benefits:Evidence:View')
$function$;

revoke all on function app_private.hr_benefit_evidence_visible()
  from public, anon, authenticated;

create or replace function app_private.hr_add_benefit_event(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_type text,
  p_from_status text,
  p_to_status text,
  p_summary text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.hr_benefit_event(
    tenant_id, entity_type, entity_id, event_type, from_status, to_status,
    summary, payload, actor_user_id, actor_name
  ) values (
    p_tenant_id, p_entity_type, p_entity_id, p_event_type,
    p_from_status, p_to_status, p_summary, coalesce(p_payload, '{}'::jsonb),
    auth.uid(), coalesce(auth.jwt() ->> 'email', auth.uid()::text)
  );
end
$function$;

revoke all on function app_private.hr_add_benefit_event(
  uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;

create or replace function public.hr_benefits_overview_secure(
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
  v_amount_visible boolean := app_private.hr_benefit_amount_visible();
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrBenefits', 'Hr:Benefits:View', null, false
  ) then
    raise exception '当前账号没有查看福利与参保的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'active_plan_count', (
      select count(*) from public.hr_benefit_plan plan
      where (p_tenant_id is null or plan.tenant_id = p_tenant_id)
        and plan.status = 'active'
        and plan.effective_from <= current_date
        and (plan.effective_to is null or plan.effective_to >= current_date)
    ),
    'active_enrollment_count', (
      select count(*) from public.hr_employee_benefit_enrollment enrollment
      where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
        and enrollment.status = 'active'
        and enrollment.coverage_from <= current_date
        and (enrollment.coverage_to is null or enrollment.coverage_to >= current_date)
    ),
    'pending_enrollment_count', (
      select count(*) from public.hr_employee_benefit_enrollment enrollment
      where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
        and enrollment.status = 'pending'
    ),
    'open_event_count', (
      select count(*) from public.hr_benefit_life_event event
      where (p_tenant_id is null or event.tenant_id = p_tenant_id)
        and event.status = 'open' and event.enrollment_window_end >= current_date
    ),
    'expiring_event_count', (
      select count(*) from public.hr_benefit_life_event event
      where (p_tenant_id is null or event.tenant_id = p_tenant_id)
        and event.status = 'open'
        and event.enrollment_window_end between current_date and current_date + 7
    ),
    'monthly_employee_contribution', case when v_amount_visible then (
      select coalesce(sum(enrollment.employee_contribution), 0)
      from public.hr_employee_benefit_enrollment enrollment
      where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
        and enrollment.status = 'active'
        and enrollment.coverage_from <= current_date
        and (enrollment.coverage_to is null or enrollment.coverage_to >= current_date)
    ) else null end,
    'monthly_employer_contribution', case when v_amount_visible then (
      select coalesce(sum(enrollment.employer_contribution), 0)
      from public.hr_employee_benefit_enrollment enrollment
      where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
        and enrollment.status = 'active'
        and enrollment.coverage_from <= current_date
        and (enrollment.coverage_to is null or enrollment.coverage_to >= current_date)
    ) else null end,
    'amount_visible', v_amount_visible
  );
end
$function$;

create or replace function public.hr_list_benefit_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_plan_type text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
  v_amount_visible boolean := app_private.hr_benefit_amount_visible();
  v_evidence_visible boolean := app_private.hr_benefit_evidence_visible();
  v_records jsonb;
  v_total bigint;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrBenefits', 'Hr:Benefits:View', null, false
  ) then
    raise exception '当前账号没有查看福利与参保的权限' using errcode = '42501';
  end if;
  if p_kind not in ('plan', 'enrollment', 'event') then
    raise exception '不支持的福利记录类型';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'plan' then
    with filtered as (
      select plan.*,
        (select count(*) from public.hr_benefit_option option
          where option.plan_id = plan.id and option.tenant_id = plan.tenant_id
            and option.enabled) as option_count,
        (select count(*) from public.hr_employee_benefit_enrollment enrollment
          where enrollment.plan_id = plan.id and enrollment.tenant_id = plan.tenant_id
            and enrollment.status = 'active') as active_enrollment_count
      from public.hr_benefit_plan plan
      where (p_tenant_id is null or plan.tenant_id = p_tenant_id)
        and (p_status is null or plan.status = p_status)
        and (p_plan_type is null or plan.plan_type = p_plan_type)
        and (v_keyword is null or plan.plan_code ilike '%' || v_keyword || '%'
          or plan.plan_name ilike '%' || v_keyword || '%'
          or coalesce(plan.provider_name, '') ilike '%' || v_keyword || '%')
    ), page as (
      select *, count(*) over() as total_count from filtered order by effective_from desc, plan_name, id
      offset v_from limit v_to - v_from + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id, 'tenant_id', page.tenant_id,
      'plan_code', page.plan_code, 'plan_name', page.plan_name,
      'plan_type', page.plan_type, 'provider_name', page.provider_name,
      'enrollment_method', page.enrollment_method, 'coverage_scope', page.coverage_scope,
      'currency_code', page.currency_code, 'effective_from', page.effective_from,
      'effective_to', page.effective_to, 'status', page.status,
      'description', page.description, 'option_count', page.option_count,
      'active_enrollment_count', page.active_enrollment_count,
      'create_time', page.create_time, 'update_time', page.update_time
    )), '[]'::jsonb), coalesce(max(page.total_count), 0)
    into v_records, v_total from page;
  elsif p_kind = 'enrollment' then
    with filtered as (
      select enrollment.*,
        employee.employee_no, employee.employee_name, employee.job_title,
        organization.organization_name, position.position_name,
        plan.plan_code, plan.plan_name, plan.plan_type,
        option.option_code, option.option_name, option.coverage_level,
        life_event.event_type as life_event_type, life_event.event_date,
        case
          when enrollment.status = 'active' and enrollment.coverage_to is not null
            and enrollment.coverage_to < current_date then 'expired'
          when enrollment.status = 'active' and enrollment.coverage_to is not null
            and enrollment.coverage_to <= current_date + 30 then 'expiring'
          else 'clear'
        end as due_status
      from public.hr_employee_benefit_enrollment enrollment
      join public.hr_employee employee on employee.id = enrollment.employee_id
        and employee.tenant_id = enrollment.tenant_id
      join public.hr_benefit_plan plan on plan.id = enrollment.plan_id
        and plan.tenant_id = enrollment.tenant_id
      join public.hr_benefit_option option on option.id = enrollment.option_id
        and option.tenant_id = enrollment.tenant_id
      left join public.hr_benefit_life_event life_event on life_event.id = enrollment.life_event_id
        and life_event.tenant_id = enrollment.tenant_id
      left join public.sys_organization organization on organization.id = employee.organization_id
      left join public.hr_position position on position.id = employee.position_id
        and position.tenant_id = employee.tenant_id
      where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
        and (p_status is null or enrollment.status = p_status)
        and (p_plan_type is null or plan.plan_type = p_plan_type)
        and (v_keyword is null or enrollment.enrollment_no ilike '%' || v_keyword || '%'
          or employee.employee_no ilike '%' || v_keyword || '%'
          or employee.employee_name ilike '%' || v_keyword || '%'
          or plan.plan_name ilike '%' || v_keyword || '%')
    ), page as (
      select *, count(*) over() as total_count from filtered order by coverage_from desc, enrollment_no, id
      offset v_from limit v_to - v_from + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id, 'tenant_id', page.tenant_id,
      'enrollment_no', page.enrollment_no, 'employee_id', page.employee_id,
      'employee', jsonb_build_object(
        'id', page.employee_id, 'employee_no', page.employee_no,
        'employee_name', page.employee_name, 'job_title', page.job_title,
        'organization_name', page.organization_name, 'position_name', page.position_name
      ),
      'plan_id', page.plan_id, 'plan', jsonb_build_object(
        'id', page.plan_id, 'plan_code', page.plan_code,
        'plan_name', page.plan_name, 'plan_type', page.plan_type
      ),
      'option_id', page.option_id, 'option', jsonb_build_object(
        'id', page.option_id, 'option_code', page.option_code,
        'option_name', page.option_name, 'coverage_level', page.coverage_level
      ),
      'life_event_id', page.life_event_id,
      'life_event', case when page.life_event_id is null then null else jsonb_build_object(
        'id', page.life_event_id, 'event_type', page.life_event_type,
        'event_date', page.event_date
      ) end,
      'coverage_from', page.coverage_from, 'coverage_to', page.coverage_to,
      'status', page.status, 'waiver_reason', page.waiver_reason,
      'employee_contribution', case when v_amount_visible then page.employee_contribution else null end,
      'employer_contribution', case when v_amount_visible then page.employer_contribution else null end,
      'currency_code', page.currency_code, 'payroll_sync_status', page.payroll_sync_status,
      'due_status', page.due_status, 'remark', page.remark,
      'approved_by', page.approved_by, 'approved_at', page.approved_at,
      'create_time', page.create_time, 'update_time', page.update_time
    )), '[]'::jsonb), coalesce(max(page.total_count), 0)
    into v_records, v_total from page;
  else
    with filtered as (
      select event.*, employee.employee_no, employee.employee_name,
        employee.job_title, organization.organization_name, position.position_name,
        case
          when event.status = 'open' and event.enrollment_window_end < current_date then 'expired'
          when event.status = 'open' and event.enrollment_window_end <= current_date + 7 then 'due_soon'
          else 'clear'
        end as due_status
      from public.hr_benefit_life_event event
      join public.hr_employee employee on employee.id = event.employee_id
        and employee.tenant_id = event.tenant_id
      left join public.sys_organization organization on organization.id = employee.organization_id
      left join public.hr_position position on position.id = employee.position_id
        and position.tenant_id = employee.tenant_id
      where (p_tenant_id is null or event.tenant_id = p_tenant_id)
        and (p_status is null or event.status = p_status)
        and (v_keyword is null or employee.employee_no ilike '%' || v_keyword || '%'
          or employee.employee_name ilike '%' || v_keyword || '%'
          or event.event_type ilike '%' || v_keyword || '%')
    ), page as (
      select *, count(*) over() as total_count from filtered order by event_date desc, id
      offset v_from limit v_to - v_from + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id, 'tenant_id', page.tenant_id,
      'employee_id', page.employee_id,
      'employee', jsonb_build_object(
        'id', page.employee_id, 'employee_no', page.employee_no,
        'employee_name', page.employee_name, 'job_title', page.job_title,
        'organization_name', page.organization_name, 'position_name', page.position_name
      ),
      'event_type', page.event_type, 'event_date', page.event_date,
      'enrollment_window_end', page.enrollment_window_end,
      'status', page.status,
      'evidence_urls', case when v_evidence_visible then page.evidence_urls else '[]'::jsonb end,
      'evidence_restricted', not v_evidence_visible,
      'remark', page.remark, 'processed_at', page.processed_at,
      'due_status', page.due_status, 'create_time', page.create_time,
      'update_time', page.update_time
    )), '[]'::jsonb), coalesce(max(page.total_count), 0)
    into v_records, v_total from page;
  end if;

  return jsonb_build_object('records', v_records, 'total', v_total,
    'amount_visible', v_amount_visible);
end
$function$;

create or replace function public.hr_benefit_plan_options_secure(
  p_plan_id uuid default null,
  p_tenant_id uuid default null,
  p_active_only boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_amount_visible boolean := app_private.hr_benefit_amount_visible();
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrBenefits', 'Hr:Benefits:View', null, false
  ) then
    raise exception '当前账号没有查看福利计划的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', option.id, 'tenant_id', option.tenant_id,
      'plan_id', option.plan_id, 'option_code', option.option_code,
      'option_name', option.option_name, 'coverage_level', option.coverage_level,
      'contribution_type', option.contribution_type,
      'employee_contribution', case when v_amount_visible then option.employee_contribution else null end,
      'employer_contribution', case when v_amount_visible then option.employer_contribution else null end,
      'employee_rate', case when v_amount_visible then option.employee_rate else null end,
      'employer_rate', case when v_amount_visible then option.employer_rate else null end,
      'pay_component_id', option.pay_component_id, 'enabled', option.enabled,
      'sort', option.sort, 'description', option.description,
      'plan', jsonb_build_object(
        'id', plan.id, 'plan_code', plan.plan_code, 'plan_name', plan.plan_name,
        'plan_type', plan.plan_type, 'currency_code', plan.currency_code,
        'status', plan.status
      )
    ) order by plan.plan_name, option.sort, option.option_name)
    from public.hr_benefit_option option
    join public.hr_benefit_plan plan on plan.id = option.plan_id
      and plan.tenant_id = option.tenant_id
    where (p_tenant_id is null or option.tenant_id = p_tenant_id)
      and (p_plan_id is null or option.plan_id = p_plan_id)
      and (not p_active_only or (option.enabled and plan.status = 'active'))
  ), '[]'::jsonb);
end
$function$;

create or replace function public.hr_get_benefit_detail_secure(
  p_kind text,
  p_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_amount_visible boolean := app_private.hr_benefit_amount_visible();
  v_evidence_visible boolean := app_private.hr_benefit_evidence_visible();
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrBenefits', 'Hr:Benefits:View', p_id, false
  ) then
    raise exception '当前账号没有查看福利详情的权限' using errcode = '42501';
  end if;
  if p_kind not in ('plan', 'enrollment', 'event') then raise exception '不支持的福利记录类型'; end if;

  if p_kind = 'plan' then
    select to_jsonb(plan) || jsonb_build_object(
      'options', coalesce((select jsonb_agg(
        to_jsonb(option) - 'employee_contribution' - 'employer_contribution'
          - 'employee_rate' - 'employer_rate'
        || case when v_amount_visible then jsonb_build_object(
          'employee_contribution', option.employee_contribution,
          'employer_contribution', option.employer_contribution,
          'employee_rate', option.employee_rate,
          'employer_rate', option.employer_rate
        ) else '{}'::jsonb end
        order by option.sort, option.option_name)
        from public.hr_benefit_option option
        where option.plan_id = plan.id and option.tenant_id = plan.tenant_id), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.create_time desc)
        from public.hr_benefit_event event
        where event.entity_type = 'plan' and event.entity_id = plan.id
          and event.tenant_id = plan.tenant_id), '[]'::jsonb),
      'amount_visible', v_amount_visible
    ) into v_result
    from public.hr_benefit_plan plan
    where plan.id = p_id
      and (app_private.is_platform_super() or plan.tenant_id = v_tenant_id);
  elsif p_kind = 'enrollment' then
    select (to_jsonb(enrollment) - 'employee_contribution' - 'employer_contribution')
      || case when v_amount_visible then jsonb_build_object(
        'employee_contribution', enrollment.employee_contribution,
        'employer_contribution', enrollment.employer_contribution
      ) else '{}'::jsonb end
      || jsonb_build_object(
        'employee', jsonb_build_object(
          'id', employee.id, 'employee_no', employee.employee_no,
          'employee_name', employee.employee_name, 'job_title', employee.job_title
        ),
        'plan', jsonb_build_object('id', plan.id, 'plan_code', plan.plan_code,
          'plan_name', plan.plan_name, 'plan_type', plan.plan_type),
        'option', jsonb_build_object('id', option.id, 'option_code', option.option_code,
          'option_name', option.option_name, 'coverage_level', option.coverage_level),
        'life_event', case when life_event.id is null then null else jsonb_build_object(
          'id', life_event.id, 'event_type', life_event.event_type,
          'event_date', life_event.event_date
        ) end,
        'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.create_time desc)
          from public.hr_benefit_event event
          where event.entity_type = 'enrollment' and event.entity_id = enrollment.id
            and event.tenant_id = enrollment.tenant_id), '[]'::jsonb),
        'amount_visible', v_amount_visible
      ) into v_result
    from public.hr_employee_benefit_enrollment enrollment
    join public.hr_employee employee on employee.id = enrollment.employee_id
      and employee.tenant_id = enrollment.tenant_id
    join public.hr_benefit_plan plan on plan.id = enrollment.plan_id
      and plan.tenant_id = enrollment.tenant_id
    join public.hr_benefit_option option on option.id = enrollment.option_id
      and option.tenant_id = enrollment.tenant_id
    left join public.hr_benefit_life_event life_event on life_event.id = enrollment.life_event_id
      and life_event.tenant_id = enrollment.tenant_id
    where enrollment.id = p_id
      and (app_private.is_platform_super() or enrollment.tenant_id = v_tenant_id);
  else
    select (to_jsonb(life_event) - 'evidence_urls')
      || jsonb_build_object(
      'evidence_urls', case when v_evidence_visible then life_event.evidence_urls else '[]'::jsonb end,
      'evidence_restricted', not v_evidence_visible,
      'employee', jsonb_build_object('id', employee.id, 'employee_no', employee.employee_no,
        'employee_name', employee.employee_name, 'job_title', employee.job_title),
      'enrollments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', enrollment.id, 'enrollment_no', enrollment.enrollment_no,
        'status', enrollment.status, 'plan_id', enrollment.plan_id,
        'plan_name', plan.plan_name, 'option_name', option.option_name
      ) order by enrollment.create_time desc)
        from public.hr_employee_benefit_enrollment enrollment
        join public.hr_benefit_plan plan on plan.id = enrollment.plan_id
          and plan.tenant_id = enrollment.tenant_id
        join public.hr_benefit_option option on option.id = enrollment.option_id
          and option.tenant_id = enrollment.tenant_id
        where enrollment.life_event_id = life_event.id
          and enrollment.tenant_id = life_event.tenant_id), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.create_time desc)
        from public.hr_benefit_event event
        where event.entity_type = 'life_event' and event.entity_id = life_event.id
          and event.tenant_id = life_event.tenant_id), '[]'::jsonb)
    ) into v_result
    from public.hr_benefit_life_event life_event
    join public.hr_employee employee on employee.id = life_event.employee_id
      and employee.tenant_id = life_event.tenant_id
    where life_event.id = p_id
      and (app_private.is_platform_super() or life_event.tenant_id = v_tenant_id);
  end if;

  if v_result is null then raise exception '福利记录不存在或无权查看' using errcode = '42501'; end if;
  return v_result;
end
$function$;

create or replace function public.hr_save_benefit_record_secure(
  p_kind text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_existing_status text;
  v_plan public.hr_benefit_plan;
  v_option public.hr_benefit_option;
  v_event public.hr_benefit_life_event;
  v_enrollment public.hr_employee_benefit_enrollment;
  v_plan_id uuid;
  v_option_id uuid;
  v_life_event_id uuid;
  v_employee_id uuid;
begin
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;
  if app_private.is_platform_super() and nullif(p_payload ->> 'tenant_id', '') is not null then
    v_tenant_id := (p_payload ->> 'tenant_id')::uuid;
  end if;

  if p_kind = 'plan' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Plan:Manage', v_id, false
    ) then raise exception '当前账号没有管理福利计划的权限' using errcode = '42501'; end if;
    if v_id is null then
      insert into public.hr_benefit_plan(
        tenant_id, plan_code, plan_name, plan_type, provider_name,
        enrollment_method, coverage_scope, currency_code,
        effective_from, effective_to, status, description
      ) values (
        v_tenant_id, btrim(p_payload ->> 'plan_code'), btrim(p_payload ->> 'plan_name'),
        p_payload ->> 'plan_type', nullif(btrim(p_payload ->> 'provider_name'), ''),
        coalesce(nullif(p_payload ->> 'enrollment_method', ''), 'election'),
        coalesce(nullif(p_payload ->> 'coverage_scope', ''), 'employee'),
        coalesce(nullif(p_payload ->> 'currency_code', ''), 'CNY'),
        (p_payload ->> 'effective_from')::date,
        nullif(p_payload ->> 'effective_to', '')::date,
        coalesce(nullif(p_payload ->> 'status', ''), 'draft'),
        nullif(btrim(p_payload ->> 'description'), '')
      ) returning * into v_plan;
      v_id := v_plan.id;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'plan', v_id,
        'created', null, v_plan.status, '创建福利计划');
    else
      select status into v_existing_status from public.hr_benefit_plan
        where id = v_id and tenant_id = v_tenant_id for update;
      if v_existing_status is null then raise exception '福利计划不存在或无权编辑'; end if;
      if v_existing_status not in ('draft', 'active') then
        raise exception '只有草稿或生效中的福利计划可以编辑';
      end if;
      update public.hr_benefit_plan set
        plan_code = btrim(p_payload ->> 'plan_code'),
        plan_name = btrim(p_payload ->> 'plan_name'),
        plan_type = p_payload ->> 'plan_type',
        provider_name = nullif(btrim(p_payload ->> 'provider_name'), ''),
        enrollment_method = p_payload ->> 'enrollment_method',
        coverage_scope = p_payload ->> 'coverage_scope',
        currency_code = p_payload ->> 'currency_code',
        effective_from = (p_payload ->> 'effective_from')::date,
        effective_to = nullif(p_payload ->> 'effective_to', '')::date,
        description = nullif(btrim(p_payload ->> 'description'), '')
      where id = v_id and tenant_id = v_tenant_id returning * into v_plan;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'plan', v_id,
        'updated', v_existing_status, v_existing_status, '更新福利计划资料');
    end if;
  elsif p_kind = 'option' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Plan:Manage', v_id, false
    ) then raise exception '当前账号没有管理福利方案的权限' using errcode = '42501'; end if;
    if not app_private.is_platform_super()
      and not app_private.has_permission('Hr:Benefits:Amount:Edit') then
      raise exception '当前账号没有维护福利缴费金额的权限' using errcode = '42501';
    end if;
    v_plan_id := (p_payload ->> 'plan_id')::uuid;
    if not exists (select 1 from public.hr_benefit_plan
      where id = v_plan_id and tenant_id = v_tenant_id and status in ('draft', 'active')) then
      raise exception '福利计划不存在、不可编辑或不属于当前租户';
    end if;
    if v_id is null then
      insert into public.hr_benefit_option(
        tenant_id, plan_id, option_code, option_name, coverage_level,
        contribution_type, employee_contribution, employer_contribution,
        employee_rate, employer_rate, pay_component_id, enabled, sort, description
      ) values (
        v_tenant_id, v_plan_id, btrim(p_payload ->> 'option_code'),
        btrim(p_payload ->> 'option_name'), p_payload ->> 'coverage_level',
        p_payload ->> 'contribution_type',
        coalesce(nullif(p_payload ->> 'employee_contribution', '')::numeric, 0),
        coalesce(nullif(p_payload ->> 'employer_contribution', '')::numeric, 0),
        nullif(p_payload ->> 'employee_rate', '')::numeric,
        nullif(p_payload ->> 'employer_rate', '')::numeric,
        nullif(p_payload ->> 'pay_component_id', '')::uuid,
        coalesce((p_payload ->> 'enabled')::boolean, true),
        coalesce((p_payload ->> 'sort')::integer, 0),
        nullif(btrim(p_payload ->> 'description'), '')
      ) returning * into v_option;
      v_id := v_option.id;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'plan', v_plan_id,
        'option_created', null, null, '新增福利覆盖方案',
        jsonb_build_object('option_id', v_id));
    else
      update public.hr_benefit_option set
        option_code = btrim(p_payload ->> 'option_code'),
        option_name = btrim(p_payload ->> 'option_name'),
        coverage_level = p_payload ->> 'coverage_level',
        contribution_type = p_payload ->> 'contribution_type',
        employee_contribution = coalesce(nullif(p_payload ->> 'employee_contribution', '')::numeric, 0),
        employer_contribution = coalesce(nullif(p_payload ->> 'employer_contribution', '')::numeric, 0),
        employee_rate = nullif(p_payload ->> 'employee_rate', '')::numeric,
        employer_rate = nullif(p_payload ->> 'employer_rate', '')::numeric,
        pay_component_id = nullif(p_payload ->> 'pay_component_id', '')::uuid,
        enabled = coalesce((p_payload ->> 'enabled')::boolean, true),
        sort = coalesce((p_payload ->> 'sort')::integer, 0),
        description = nullif(btrim(p_payload ->> 'description'), '')
      where id = v_id and tenant_id = v_tenant_id and plan_id = v_plan_id
      returning * into v_option;
      if v_option.id is null then raise exception '福利方案不存在或无权编辑'; end if;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'plan', v_plan_id,
        'option_updated', null, null, '更新福利覆盖方案',
        jsonb_build_object('option_id', v_id));
    end if;
  elsif p_kind = 'event' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Event:Manage', v_id, false
    ) then raise exception '当前账号没有管理福利人生事件的权限' using errcode = '42501'; end if;
    if v_id is null then
      insert into public.hr_benefit_life_event(
        tenant_id, employee_id, event_type, event_date,
        enrollment_window_end, status, evidence_urls, remark
      ) values (
        v_tenant_id, (p_payload ->> 'employee_id')::uuid,
        p_payload ->> 'event_type', (p_payload ->> 'event_date')::date,
        (p_payload ->> 'enrollment_window_end')::date, 'open',
        coalesce(p_payload -> 'evidence_urls', '[]'::jsonb),
        nullif(btrim(p_payload ->> 'remark'), '')
      ) returning * into v_event;
      v_id := v_event.id;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'life_event', v_id,
        'created', null, 'open', '创建福利人生事件');
    else
      select status into v_existing_status from public.hr_benefit_life_event
        where id = v_id and tenant_id = v_tenant_id for update;
      if v_existing_status is null then raise exception '人生事件不存在或无权编辑'; end if;
      if v_existing_status <> 'open' then raise exception '只有开放中的人生事件可以编辑'; end if;
      update public.hr_benefit_life_event set
        event_type = p_payload ->> 'event_type',
        event_date = (p_payload ->> 'event_date')::date,
        enrollment_window_end = (p_payload ->> 'enrollment_window_end')::date,
        evidence_urls = coalesce(p_payload -> 'evidence_urls', '[]'::jsonb),
        remark = nullif(btrim(p_payload ->> 'remark'), '')
      where id = v_id and tenant_id = v_tenant_id returning * into v_event;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'life_event', v_id,
        'updated', v_existing_status, v_existing_status, '更新福利人生事件');
    end if;
  elsif p_kind = 'enrollment' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Enrollment:Manage', v_id, false
    ) then raise exception '当前账号没有管理员工参保的权限' using errcode = '42501'; end if;
    if not app_private.is_platform_super()
      and not app_private.has_permission('Hr:Benefits:Amount:Edit') then
      raise exception '当前账号没有维护福利缴费金额的权限' using errcode = '42501';
    end if;
    v_plan_id := (p_payload ->> 'plan_id')::uuid;
    v_option_id := (p_payload ->> 'option_id')::uuid;
    v_life_event_id := nullif(p_payload ->> 'life_event_id', '')::uuid;
    v_employee_id := (p_payload ->> 'employee_id')::uuid;
    select option.* into v_option from public.hr_benefit_option option
      join public.hr_benefit_plan plan on plan.id = option.plan_id
        and plan.tenant_id = option.tenant_id
      where option.id = v_option_id and option.plan_id = v_plan_id
        and option.tenant_id = v_tenant_id and option.enabled
        and plan.status = 'active';
    if v_option.id is null then raise exception '福利计划或覆盖方案不可参保'; end if;
    if not exists (select 1 from public.hr_benefit_plan plan
      where plan.id = v_plan_id and plan.tenant_id = v_tenant_id
        and (p_payload ->> 'coverage_from')::date >= plan.effective_from
        and (plan.effective_to is null or (p_payload ->> 'coverage_from')::date <= plan.effective_to)) then
      raise exception '参保生效日期不在福利计划有效期内';
    end if;
    if v_life_event_id is not null and not exists (
      select 1 from public.hr_benefit_life_event event
      where event.id = v_life_event_id and event.tenant_id = v_tenant_id
        and event.employee_id = v_employee_id and event.status = 'open'
        and event.enrollment_window_end >= current_date
    ) then raise exception '人生事件不属于该员工、参保窗口已关闭或事件不可用'; end if;
    if v_id is null then
      insert into public.hr_employee_benefit_enrollment(
        tenant_id, employee_id, plan_id, option_id, life_event_id,
        enrollment_no, coverage_from, coverage_to, status, waiver_reason,
        employee_contribution, employer_contribution, currency_code,
        payroll_sync_status, remark
      ) values (
        v_tenant_id, v_employee_id, v_plan_id, v_option_id, v_life_event_id,
        coalesce(nullif(btrim(p_payload ->> 'enrollment_no'), ''),
          'BEN-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS')),
        (p_payload ->> 'coverage_from')::date,
        nullif(p_payload ->> 'coverage_to', '')::date, 'draft',
        nullif(btrim(p_payload ->> 'waiver_reason'), ''),
        coalesce(nullif(p_payload ->> 'employee_contribution', '')::numeric,
          v_option.employee_contribution),
        coalesce(nullif(p_payload ->> 'employer_contribution', '')::numeric,
          v_option.employer_contribution),
        coalesce(nullif(p_payload ->> 'currency_code', ''),
          (select currency_code from public.hr_benefit_plan where id = v_plan_id)),
        'not_ready', nullif(btrim(p_payload ->> 'remark'), '')
      ) returning * into v_enrollment;
      v_id := v_enrollment.id;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'enrollment', v_id,
        'created', null, 'draft', '创建员工参保草稿');
    else
      select status into v_existing_status from public.hr_employee_benefit_enrollment
        where id = v_id and tenant_id = v_tenant_id for update;
      if v_existing_status <> 'draft' then raise exception '只有草稿参保记录可以编辑'; end if;
      update public.hr_employee_benefit_enrollment set
        employee_id = v_employee_id,
        plan_id = v_plan_id, option_id = v_option_id,
        life_event_id = v_life_event_id,
        coverage_from = (p_payload ->> 'coverage_from')::date,
        coverage_to = nullif(p_payload ->> 'coverage_to', '')::date,
        waiver_reason = nullif(btrim(p_payload ->> 'waiver_reason'), ''),
        employee_contribution = coalesce(nullif(p_payload ->> 'employee_contribution', '')::numeric,
          v_option.employee_contribution),
        employer_contribution = coalesce(nullif(p_payload ->> 'employer_contribution', '')::numeric,
          v_option.employer_contribution),
        currency_code = coalesce(nullif(p_payload ->> 'currency_code', ''), currency_code),
        remark = nullif(btrim(p_payload ->> 'remark'), '')
      where id = v_id and tenant_id = v_tenant_id returning * into v_enrollment;
      if v_enrollment.id is null then raise exception '参保记录不存在或无权编辑'; end if;
      perform app_private.hr_add_benefit_event(v_tenant_id, 'enrollment', v_id,
        'updated', 'draft', 'draft', '更新员工参保草稿');
    end if;
  else
    raise exception '不支持的福利记录类型';
  end if;
  return v_id;
end
$function$;

create or replace function public.hr_transition_benefit_record_secure(
  p_kind text,
  p_id uuid,
  p_action text,
  p_comment text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_plan public.hr_benefit_plan;
  v_enrollment public.hr_employee_benefit_enrollment;
  v_event public.hr_benefit_life_event;
begin
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;

  if p_kind = 'plan' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Plan:Manage', p_id, false
    ) then raise exception '当前账号没有管理福利计划的权限' using errcode = '42501'; end if;
    select * into v_plan from public.hr_benefit_plan
      where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if v_plan.id is null then raise exception '福利计划不存在或无权处理'; end if;
    if p_action = 'activate' and v_plan.status = 'draft' then
      if not exists (select 1 from public.hr_benefit_option
        where plan_id = p_id and tenant_id = v_plan.tenant_id and enabled) then
        raise exception '至少维护一个启用的覆盖方案后才能生效';
      end if;
      update public.hr_benefit_plan set status = 'active' where id = p_id;
      perform app_private.hr_add_benefit_event(v_plan.tenant_id, 'plan', p_id,
        'activated', v_plan.status, 'active', '福利计划已生效');
    elsif p_action = 'deactivate' and v_plan.status = 'active' then
      update public.hr_benefit_plan set status = 'inactive' where id = p_id;
      perform app_private.hr_add_benefit_event(v_plan.tenant_id, 'plan', p_id,
        'deactivated', v_plan.status, 'inactive', '福利计划已停用');
    elsif p_action = 'reactivate' and v_plan.status = 'inactive' then
      update public.hr_benefit_plan set status = 'active' where id = p_id;
      perform app_private.hr_add_benefit_event(v_plan.tenant_id, 'plan', p_id,
        'reactivated', v_plan.status, 'active', '福利计划已重新生效');
    elsif p_action = 'cancel' and v_plan.status = 'draft' then
      update public.hr_benefit_plan set status = 'cancelled' where id = p_id;
      perform app_private.hr_add_benefit_event(v_plan.tenant_id, 'plan', p_id,
        'cancelled', v_plan.status, 'cancelled', '福利计划草稿已取消');
    else raise exception '当前状态不允许执行该计划动作'; end if;
  elsif p_kind = 'enrollment' then
    select * into v_enrollment from public.hr_employee_benefit_enrollment
      where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if v_enrollment.id is null then raise exception '参保记录不存在或无权处理'; end if;
    if p_action = 'submit' then
      if not app_private.can_execute_business_action(
        'HrBenefits', 'Hr:Benefits:Enrollment:Manage', p_id, false
      ) or v_enrollment.status <> 'draft' then raise exception '当前参保记录不能提交审核'; end if;
      if exists (select 1 from public.hr_employee_benefit_enrollment existing
        where existing.tenant_id = v_enrollment.tenant_id
          and existing.employee_id = v_enrollment.employee_id
          and existing.plan_id = v_enrollment.plan_id
          and existing.id <> v_enrollment.id
          and existing.status in ('pending', 'active')) then
        raise exception '该员工在此福利计划下已有待审核或生效中的参保记录';
      end if;
      update public.hr_employee_benefit_enrollment set status = 'pending'
        where id = p_id;
      perform app_private.hr_add_benefit_event(v_enrollment.tenant_id, 'enrollment', p_id,
        'submitted', 'draft', 'pending', '提交参保审核');
    elsif p_action = 'approve' then
      if not app_private.can_execute_business_action(
        'HrBenefits', 'Hr:Benefits:Approve', p_id, false
      ) or v_enrollment.status <> 'pending' then raise exception '当前参保记录不能审核生效'; end if;
      update public.hr_employee_benefit_enrollment set status = 'active',
        payroll_sync_status = 'ready', approved_by = coalesce(auth.jwt() ->> 'email', auth.uid()::text),
        approved_at = now() where id = p_id;
      if v_enrollment.life_event_id is not null then
        update public.hr_benefit_life_event set status = 'processed', processed_at = now()
          where id = v_enrollment.life_event_id and status = 'open';
      end if;
      perform app_private.hr_add_benefit_event(v_enrollment.tenant_id, 'enrollment', p_id,
        'approved', 'pending', 'active', '参保审核通过并生成薪资输入资格');
    elsif p_action = 'reject' then
      if not app_private.can_execute_business_action(
        'HrBenefits', 'Hr:Benefits:Approve', p_id, false
      ) or v_enrollment.status <> 'pending' or nullif(btrim(p_comment), '') is null then
        raise exception '驳回待审核参保记录时必须填写原因';
      end if;
      update public.hr_employee_benefit_enrollment set status = 'draft'
        where id = p_id;
      perform app_private.hr_add_benefit_event(v_enrollment.tenant_id, 'enrollment', p_id,
        'rejected', 'pending', 'draft', '参保审核已驳回',
        jsonb_build_object('comment', btrim(p_comment)));
    elsif p_action = 'end' then
      if not app_private.can_execute_business_action(
        'HrBenefits', 'Hr:Benefits:Enrollment:Manage', p_id, false
      ) or v_enrollment.status <> 'active' then raise exception '只有生效中的参保可以终止'; end if;
      update public.hr_employee_benefit_enrollment set status = 'ended',
        coverage_to = coalesce(coverage_to, current_date), payroll_sync_status = 'stopped',
        ended_at = now() where id = p_id;
      perform app_private.hr_add_benefit_event(v_enrollment.tenant_id, 'enrollment', p_id,
        'ended', 'active', 'ended', '员工福利保障已终止',
        jsonb_build_object('comment', nullif(btrim(p_comment), '')));
    elsif p_action = 'cancel' and v_enrollment.status = 'draft' then
      if not app_private.can_execute_business_action(
        'HrBenefits', 'Hr:Benefits:Enrollment:Manage', p_id, false
      ) then raise exception '当前账号没有取消参保草稿的权限'; end if;
      update public.hr_employee_benefit_enrollment set status = 'cancelled',
        payroll_sync_status = 'stopped' where id = p_id;
      perform app_private.hr_add_benefit_event(v_enrollment.tenant_id, 'enrollment', p_id,
        'cancelled', 'draft', 'cancelled', '参保草稿已取消');
    else raise exception '当前状态不允许执行该参保动作'; end if;
  elsif p_kind = 'event' then
    if not app_private.can_execute_business_action(
      'HrBenefits', 'Hr:Benefits:Event:Manage', p_id, false
    ) then raise exception '当前账号没有管理福利人生事件的权限' using errcode = '42501'; end if;
    select * into v_event from public.hr_benefit_life_event
      where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if v_event.id is null then raise exception '人生事件不存在或无权处理'; end if;
    if p_action = 'process' and v_event.status = 'open' then
      update public.hr_benefit_life_event set status = 'processed', processed_at = now()
        where id = p_id;
      perform app_private.hr_add_benefit_event(v_event.tenant_id, 'life_event', p_id,
        'processed', 'open', 'processed', '人生事件已处理');
    elsif p_action = 'cancel' and v_event.status = 'open' then
      update public.hr_benefit_life_event set status = 'cancelled' where id = p_id;
      perform app_private.hr_add_benefit_event(v_event.tenant_id, 'life_event', p_id,
        'cancelled', 'open', 'cancelled', '人生事件已取消');
    else raise exception '当前状态不允许执行该人生事件动作'; end if;
  else raise exception '不支持的福利记录类型'; end if;
  return true;
end
$function$;

create or replace function public.hr_benefit_payroll_inputs_secure(
  p_payroll_month date,
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
  v_month_start date := date_trunc('month', p_payroll_month)::date;
  v_month_end date := (date_trunc('month', p_payroll_month) + interval '1 month - 1 day')::date;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrBenefits', 'Hr:Benefits:Payroll:Export', null, false
  ) then raise exception '当前账号没有导出福利薪资输入的权限' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return coalesce((select jsonb_agg(jsonb_build_object(
    'enrollment_id', enrollment.id, 'enrollment_no', enrollment.enrollment_no,
    'tenant_id', enrollment.tenant_id, 'employee_id', enrollment.employee_id,
    'employee_no', employee.employee_no, 'employee_name', employee.employee_name,
    'plan_id', plan.id, 'plan_code', plan.plan_code, 'plan_name', plan.plan_name,
    'plan_type', plan.plan_type, 'option_id', option.id,
    'option_code', option.option_code, 'option_name', option.option_name,
    'pay_component_id', option.pay_component_id,
    'employee_contribution', enrollment.employee_contribution,
    'employer_contribution', enrollment.employer_contribution,
    'currency_code', enrollment.currency_code,
    'coverage_from', enrollment.coverage_from, 'coverage_to', enrollment.coverage_to
  ) order by employee.employee_no, plan.plan_code)
  from public.hr_employee_benefit_enrollment enrollment
  join public.hr_employee employee on employee.id = enrollment.employee_id
    and employee.tenant_id = enrollment.tenant_id
  join public.hr_benefit_plan plan on plan.id = enrollment.plan_id
    and plan.tenant_id = enrollment.tenant_id
  join public.hr_benefit_option option on option.id = enrollment.option_id
    and option.tenant_id = enrollment.tenant_id
  where (p_tenant_id is null or enrollment.tenant_id = p_tenant_id)
    and enrollment.status = 'active'
    and enrollment.payroll_sync_status in ('ready', 'exported')
    and enrollment.coverage_from <= v_month_end
    and (enrollment.coverage_to is null or enrollment.coverage_to >= v_month_start)), '[]'::jsonb);
end
$function$;

revoke all on function public.hr_benefits_overview_secure(uuid) from public, anon;
revoke all on function public.hr_list_benefit_records_secure(text,integer,integer,text,text,text,uuid) from public, anon;
revoke all on function public.hr_benefit_plan_options_secure(uuid,uuid,boolean) from public, anon;
revoke all on function public.hr_get_benefit_detail_secure(text,uuid) from public, anon;
revoke all on function public.hr_save_benefit_record_secure(text,jsonb) from public, anon;
revoke all on function public.hr_transition_benefit_record_secure(text,uuid,text,text) from public, anon;
revoke all on function public.hr_benefit_payroll_inputs_secure(date,uuid) from public, anon;

grant execute on function public.hr_benefits_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_benefit_records_secure(text,integer,integer,text,text,text,uuid) to authenticated, service_role;
grant execute on function public.hr_benefit_plan_options_secure(uuid,uuid,boolean) to authenticated, service_role;
grant execute on function public.hr_get_benefit_detail_secure(text,uuid) to authenticated, service_role;
grant execute on function public.hr_save_benefit_record_secure(text,jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_benefit_record_secure(text,uuid,text,text) to authenticated, service_role;
grant execute on function public.hr_benefit_payroll_inputs_secure(date,uuid) to authenticated, service_role;

;
