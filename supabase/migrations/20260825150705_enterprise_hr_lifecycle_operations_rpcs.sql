create or replace function public.hr_lifecycle_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:View', null, false) then
    raise exception '当前账号没有查看入转调离工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'active_case_count', (
      select count(*) from public.hr_lifecycle_case c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.execution_status in ('planning', 'in_progress', 'ready')
    ),
    'due_soon_case_count', (
      select count(*) from public.hr_lifecycle_case c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.execution_status in ('planning', 'in_progress')
        and c.planned_effective_date between current_date and current_date + 7
    ),
    'overdue_blocking_task_count', (
      select count(*) from public.hr_lifecycle_task t
      join public.hr_lifecycle_case c on c.id = t.lifecycle_case_id and c.tenant_id = t.tenant_id
      where (p_tenant_id is null or t.tenant_id = p_tenant_id)
        and c.execution_status in ('planning', 'in_progress')
        and t.blocking and t.status in ('pending', 'processing') and t.due_date < current_date
    ),
    'ready_case_count', (
      select count(*) from public.hr_lifecycle_case c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.execution_status = 'ready'
    ),
    'default_template_count', (
      select count(*) from public.hr_lifecycle_template t
      where (p_tenant_id is null or t.tenant_id = p_tenant_id)
        and t.status = 'active' and t.is_default
    ),
    'completion_rate', (
      select coalesce(round(100 * count(*) filter (where c.execution_status = 'completed')::numeric
        / nullif(count(*) filter (where c.execution_status in ('completed', 'cancelled')), 0), 1), 0)
      from public.hr_lifecycle_case c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.create_time >= now() - interval '90 days'
    )
  );
end
$function$;

create or replace function public.hr_list_lifecycle_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_case_id uuid default null,
  p_template_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('case', 'task', 'template', 'template_task') then
    raise exception '不支持的生命周期记录类型';
  end if;
  if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:View', null, false) then
    raise exception '当前账号没有查看入转调离工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'case' then
    with filtered as materialized (
      select c.*, e.employee_no, e.employee_name,
        o.organization_code, o.organization_name,
        p.position_code, p.position_name,
        template.template_code, template.template_name,
        owner.employee_no owner_no, owner.employee_name owner_name,
        buddy.employee_no buddy_no, buddy.employee_name buddy_name,
        coalesce(task_stats.task_count, 0) task_count,
        coalesce(task_stats.closed_count, 0) closed_task_count,
        coalesce(task_stats.open_blocking_count, 0) open_blocking_task_count,
        coalesce(task_stats.overdue_count, 0) overdue_task_count
      from public.hr_lifecycle_case c
      join public.hr_employee e on e.id = c.employee_id and e.tenant_id = c.tenant_id
      left join public.sys_organization o on o.id = c.organization_id and o.tenant_id = c.tenant_id
      left join public.hr_position p on p.id = c.position_id and p.tenant_id = c.tenant_id
      left join public.hr_lifecycle_template template on template.id = c.template_id and template.tenant_id = c.tenant_id
      left join public.hr_employee owner on owner.id = c.owner_employee_id and owner.tenant_id = c.tenant_id
      left join public.hr_employee buddy on buddy.id = c.buddy_employee_id and buddy.tenant_id = c.tenant_id
      left join lateral (
        select count(*)::integer task_count,
          count(*) filter (where t.status in ('completed', 'skipped'))::integer closed_count,
          count(*) filter (where t.blocking and t.status in ('pending', 'processing'))::integer open_blocking_count,
          count(*) filter (where t.status in ('pending', 'processing') and t.due_date < current_date)::integer overdue_count
        from public.hr_lifecycle_task t
        where t.lifecycle_case_id = c.id and t.tenant_id = c.tenant_id
      ) task_stats on true
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and (p_status is null or c.execution_status = p_status)
        and (v_keyword is null or c.case_no ilike '%' || v_keyword || '%'
          or e.employee_no ilike '%' || v_keyword || '%'
          or e.employee_name ilike '%' || v_keyword || '%'
          or o.organization_name ilike '%' || v_keyword || '%'
          or p.position_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered
      order by case when execution_status in ('planning', 'in_progress', 'ready') then 0 else 1 end,
        planned_effective_date, create_time desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'employee_no' - 'employee_name' - 'organization_code' - 'organization_name'
          - 'position_code' - 'position_name' - 'template_code' - 'template_name'
          - 'owner_no' - 'owner_name' - 'buddy_no' - 'buddy_name')
        || jsonb_build_object(
          'employee', jsonb_build_object('id', employee_id, 'code', employee_no, 'name', employee_name),
          'organization', case when organization_id is null then null else jsonb_build_object('id', organization_id, 'code', organization_code, 'name', organization_name) end,
          'position', case when position_id is null then null else jsonb_build_object('id', position_id, 'code', position_code, 'name', position_name) end,
          'template', case when template_id is null then null else jsonb_build_object('id', template_id, 'code', template_code, 'name', template_name) end,
          'owner', case when owner_employee_id is null then null else jsonb_build_object('id', owner_employee_id, 'code', owner_no, 'name', owner_name) end,
          'buddy', case when buddy_employee_id is null then null else jsonb_build_object('id', buddy_employee_id, 'code', buddy_no, 'name', buddy_name) end
        )
        order by case when execution_status in ('planning', 'in_progress', 'ready') then 0 else 1 end,
          planned_effective_date, create_time desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'task' then
    with filtered as materialized (
      select t.*, c.case_no, c.case_type, c.execution_status, c.employee_id,
        e.employee_no, e.employee_name, owner.employee_no owner_no, owner.employee_name owner_name
      from public.hr_lifecycle_task t
      join public.hr_lifecycle_case c on c.id = t.lifecycle_case_id and c.tenant_id = t.tenant_id
      join public.hr_employee e on e.id = c.employee_id and e.tenant_id = c.tenant_id
      left join public.hr_employee owner on owner.id = t.owner_employee_id and owner.tenant_id = t.tenant_id
      where (p_tenant_id is null or t.tenant_id = p_tenant_id)
        and (p_case_id is null or t.lifecycle_case_id = p_case_id)
        and (p_status is null or t.status = p_status)
        and (v_keyword is null or t.task_name ilike '%' || v_keyword || '%'
          or t.description ilike '%' || v_keyword || '%'
          or c.case_no ilike '%' || v_keyword || '%'
          or e.employee_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered
      order by case when status in ('pending', 'processing') then 0 else 1 end,
        due_date nulls last, sort, task_name
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'case_no' - 'case_type' - 'execution_status' - 'employee_id'
          - 'employee_no' - 'employee_name' - 'owner_no' - 'owner_name')
        || jsonb_build_object(
          'case', jsonb_build_object('id', lifecycle_case_id, 'code', case_no, 'name', employee_name,
            'case_type', case_type, 'execution_status', execution_status, 'employee_id', employee_id),
          'employee', jsonb_build_object('id', employee_id, 'code', employee_no, 'name', employee_name),
          'owner', case when owner_employee_id is null then null else jsonb_build_object('id', owner_employee_id, 'code', owner_no, 'name', owner_name) end
        )
        order by case when status in ('pending', 'processing') then 0 else 1 end,
          due_date nulls last, sort, task_name
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'template' then
    with filtered as materialized (
      select t.*,
        (select count(*) from public.hr_lifecycle_template_task task
          where task.template_id = t.id and task.tenant_id = t.tenant_id) task_count,
        (select count(*) from public.hr_lifecycle_case c
          where c.template_id = t.id and c.tenant_id = t.tenant_id) usage_count
      from public.hr_lifecycle_template t
      where (p_tenant_id is null or t.tenant_id = p_tenant_id)
        and (p_status is null or t.status = p_status)
        and (v_keyword is null or t.template_code ilike '%' || v_keyword || '%'
          or t.template_name ilike '%' || v_keyword || '%'
          or t.description ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by is_default desc, case_type, template_name
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(paged) order by is_default desc, case_type, template_name), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  with filtered as materialized (
    select task.*, template.template_code, template.template_name, template.case_type, template.status template_status
    from public.hr_lifecycle_template_task task
    join public.hr_lifecycle_template template on template.id = task.template_id and template.tenant_id = task.tenant_id
    where (p_tenant_id is null or task.tenant_id = p_tenant_id)
      and (p_template_id is null or task.template_id = p_template_id)
      and (v_keyword is null or task.task_name ilike '%' || v_keyword || '%'
        or task.description ilike '%' || v_keyword || '%'
        or template.template_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by template_name, sort, task_name offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged) - 'template_code' - 'template_name' - 'case_type' - 'template_status')
      || jsonb_build_object('template', jsonb_build_object(
        'id', template_id, 'code', template_code, 'name', template_name,
        'case_type', case_type, 'status', template_status
      )) order by template_name, sort, task_name
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_list_lifecycle_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('case', 'template', 'employee', 'organization', 'position', 'handoff') then
    raise exception '不支持的生命周期选项类型';
  end if;
  if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:View', null, false) then
    raise exception '当前账号没有查看生命周期选项的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'case' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'code', c.case_no, 'name', e.employee_name,
      'status', c.execution_status, 'case_type', c.case_type, 'employee_id', c.employee_id
    ) order by c.planned_effective_date desc)
    from public.hr_lifecycle_case c
    join public.hr_employee e on e.id = c.employee_id and e.tenant_id = c.tenant_id
    where (p_tenant_id is null or c.tenant_id = p_tenant_id)
      and c.execution_status in ('planning', 'in_progress', 'ready')), '[]'::jsonb);
  end if;
  if p_kind = 'template' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'tenant_id', t.tenant_id, 'code', t.template_code, 'name', t.template_name,
      'status', t.status, 'case_type', t.case_type
    ) order by t.case_type, t.is_default desc, t.template_name)
    from public.hr_lifecycle_template t
    where (p_tenant_id is null or t.tenant_id = p_tenant_id) and t.status = 'active'), '[]'::jsonb);
  end if;
  if p_kind = 'employee' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'tenant_id', e.tenant_id, 'code', e.employee_no, 'name', e.employee_name,
      'organization_id', e.organization_id, 'position_id', e.position_id, 'status', e.employment_status
    ) order by e.employee_no)
    from public.hr_employee e
    where (p_tenant_id is null or e.tenant_id = p_tenant_id)
      and e.employment_status <> 'terminated'), '[]'::jsonb);
  end if;
  if p_kind = 'organization' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'tenant_id', o.tenant_id, 'code', o.organization_code, 'name', o.organization_name,
      'status', o.status
    ) order by o.organization_code)
    from public.sys_organization o
    where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = '1'), '[]'::jsonb);
  end if;
  if p_kind = 'position' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'tenant_id', p.tenant_id, 'code', p.position_code, 'name', p.position_name,
      'organization_id', p.organization_id, 'status', p.status
    ) order by p.position_code)
    from public.hr_position p
    where (p_tenant_id is null or p.tenant_id = p_tenant_id) and p.status = '1'), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', h.id, 'tenant_id', h.tenant_id, 'code', c.candidate_no, 'name', e.employee_name,
    'status', h.status, 'employee_id', h.onboard_employee_id,
    'organization_id', h.organization_id, 'position_id', h.position_id
  ) order by h.completed_at desc)
  from public.hr_recruitment_handoff h
  join public.hr_candidate c on c.id = h.candidate_id and c.tenant_id = h.tenant_id
  join public.hr_employee e on e.id = h.onboard_employee_id and e.tenant_id = h.tenant_id
  where (p_tenant_id is null or h.tenant_id = p_tenant_id)
    and h.status = 'completed'
    and not exists (select 1 from public.hr_lifecycle_case lifecycle
      where lifecycle.tenant_id = h.tenant_id
        and lifecycle.source_type = 'recruitment_handoff' and lifecycle.source_id = h.id)), '[]'::jsonb);
end
$function$;

create or replace function public.hr_save_lifecycle_record_secure(
  p_kind text,
  p_id uuid,
  p_payload jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_tenant_id uuid;
  v_permission text := case when p_id is null then 'Hr:Lifecycle:Add' else 'Hr:Lifecycle:Edit' end;
  v_id uuid;
  v_case public.hr_lifecycle_case;
  v_template public.hr_lifecycle_template;
  v_handoff public.hr_recruitment_handoff;
  v_case_type text := nullif(p_payload ->> 'case_type', '');
  v_template_id uuid := nullif(p_payload ->> 'template_id', '')::uuid;
  v_handoff_id uuid := nullif(p_payload ->> 'handoff_id', '')::uuid;
  v_planned_date date := nullif(p_payload ->> 'planned_effective_date', '')::date;
begin
  if p_kind not in ('case', 'task', 'template', 'template_task') then raise exception '不支持的生命周期记录类型'; end if;
  if p_kind in ('template', 'template_task') then v_permission := 'Hr:Lifecycle:ManageTemplate'; end if;
  if not app_private.can_execute_business_action('HrLifecycle', v_permission, null, false) then
    raise exception '当前账号没有保存生命周期记录的权限' using errcode = '42501';
  end if;
  v_tenant_id := case when app_private.is_platform_super()
    then coalesce(nullif(p_payload ->> 'tenant_id', '')::uuid, v_current_tenant)
    else v_current_tenant end;

  if p_kind = 'case' then
    if v_planned_date is null then raise exception '计划生效日期不能为空'; end if;
    if v_handoff_id is not null then
      select * into v_handoff from public.hr_recruitment_handoff h
      where h.id = v_handoff_id and h.tenant_id = v_tenant_id and h.status = 'completed';
      if not found then raise exception '招聘交接不存在、未完成或不属于当前租户'; end if;
      v_case_type := 'onboarding';
    end if;
    if v_case_type not in ('onboarding', 'regularization', 'transfer', 'offboarding') then
      raise exception '事项类型无效';
    end if;
    if v_template_id is null then
      select t.id into v_template_id from public.hr_lifecycle_template t
      where t.tenant_id = v_tenant_id and t.case_type = v_case_type
        and t.status = 'active' and t.is_default
      order by t.update_time desc limit 1;
    end if;
    if v_template_id is not null then
      select * into v_template from public.hr_lifecycle_template t
      where t.id = v_template_id and t.tenant_id = v_tenant_id
        and t.case_type = v_case_type and t.status = 'active';
      if not found then raise exception '所选标准任务包不可用或与事项类型不匹配'; end if;
    end if;

    if p_id is null then
      insert into public.hr_lifecycle_case(
        tenant_id, case_no, employee_id, case_type, planned_effective_date, status,
        template_id, source_type, source_id, organization_id, position_id,
        owner_employee_id, buddy_employee_id, priority, execution_status, remark
      ) values (
        v_tenant_id,
        coalesce(nullif(btrim(p_payload ->> 'case_no'), ''), 'LC' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS')),
        coalesce(v_handoff.onboard_employee_id, nullif(p_payload ->> 'employee_id', '')::uuid),
        v_case_type, v_planned_date, 'draft', v_template_id,
        case when v_handoff_id is null then null else 'recruitment_handoff' end, v_handoff_id,
        coalesce(v_handoff.organization_id, nullif(p_payload ->> 'organization_id', '')::uuid),
        coalesce(v_handoff.position_id, nullif(p_payload ->> 'position_id', '')::uuid),
        coalesce(v_handoff.owner_employee_id, nullif(p_payload ->> 'owner_employee_id', '')::uuid),
        coalesce(v_handoff.buddy_employee_id, nullif(p_payload ->> 'buddy_employee_id', '')::uuid),
        coalesce(nullif(p_payload ->> 'priority', ''), 'normal'), 'planning',
        nullif(btrim(p_payload ->> 'remark'), '')
      ) returning id into v_id;
      if v_template_id is not null then
        insert into public.hr_lifecycle_task(
          tenant_id, lifecycle_case_id, template_task_id, task_type, task_name, description,
          owner_role, due_date, required, blocking, evidence_required, status, sort
        )
        select v_tenant_id, v_id, task.id, task.task_type, task.task_name, task.description,
          task.owner_role, v_planned_date + task.due_offset_days,
          task.required, task.blocking, task.evidence_required, 'pending', task.sort
        from public.hr_lifecycle_template_task task
        where task.template_id = v_template_id and task.tenant_id = v_tenant_id;
      end if;
      return v_id;
    end if;

    select * into v_case from public.hr_lifecycle_case c
    where c.id = p_id and c.tenant_id = v_tenant_id for update;
    if not found then raise exception '生命周期事项不存在或无权编辑'; end if;
    if v_case.execution_status <> 'planning' or v_case.status not in ('draft', 'rejected') then
      raise exception '只有待规划的草稿或已驳回事项可以编辑';
    end if;
    if v_handoff_id is distinct from v_case.source_id and v_case.source_id is not null then
      raise exception '已接收的招聘交接来源不能更换';
    end if;
    if v_template_id is distinct from v_case.template_id then
      delete from public.hr_lifecycle_task t
      where t.lifecycle_case_id = v_case.id and t.tenant_id = v_tenant_id
        and t.template_task_id is not null and t.status = 'pending';
    end if;
    update public.hr_lifecycle_case set
      case_no = coalesce(nullif(btrim(p_payload ->> 'case_no'), ''), case_no),
      employee_id = coalesce(v_handoff.onboard_employee_id, nullif(p_payload ->> 'employee_id', '')::uuid, employee_id),
      case_type = v_case_type, planned_effective_date = v_planned_date, template_id = v_template_id,
      organization_id = coalesce(v_handoff.organization_id, nullif(p_payload ->> 'organization_id', '')::uuid),
      position_id = coalesce(v_handoff.position_id, nullif(p_payload ->> 'position_id', '')::uuid),
      owner_employee_id = coalesce(v_handoff.owner_employee_id, nullif(p_payload ->> 'owner_employee_id', '')::uuid),
      buddy_employee_id = coalesce(v_handoff.buddy_employee_id, nullif(p_payload ->> 'buddy_employee_id', '')::uuid),
      priority = coalesce(nullif(p_payload ->> 'priority', ''), priority),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = p_id;
    if v_template_id is distinct from v_case.template_id and v_template_id is not null then
      insert into public.hr_lifecycle_task(
        tenant_id, lifecycle_case_id, template_task_id, task_type, task_name, description,
        owner_role, due_date, required, blocking, evidence_required, status, sort
      )
      select v_tenant_id, p_id, task.id, task.task_type, task.task_name, task.description,
        task.owner_role, v_planned_date + task.due_offset_days,
        task.required, task.blocking, task.evidence_required, 'pending', task.sort
      from public.hr_lifecycle_template_task task
      where task.template_id = v_template_id and task.tenant_id = v_tenant_id;
    end if;
    return p_id;
  end if;

  if p_kind = 'task' then
    select c.* into v_case from public.hr_lifecycle_case c
    where c.id = nullif(p_payload ->> 'lifecycle_case_id', '')::uuid and c.tenant_id = v_tenant_id;
    if not found or v_case.execution_status in ('ready', 'completed', 'cancelled') then
      raise exception '所选事项不存在或已不允许维护任务';
    end if;
    if nullif(p_payload ->> 'due_date', '') is null then raise exception '任务截止日期不能为空'; end if;
    if p_id is null then
      insert into public.hr_lifecycle_task(
        tenant_id, lifecycle_case_id, task_type, task_name, description, owner_employee_id,
        owner_role, due_date, required, blocking, evidence_required, status, sort
      ) values (
        v_tenant_id, v_case.id, p_payload ->> 'task_type', btrim(p_payload ->> 'task_name'),
        nullif(btrim(p_payload ->> 'description'), ''), nullif(p_payload ->> 'owner_employee_id', '')::uuid,
        coalesce(nullif(p_payload ->> 'owner_role', ''), 'hr'), (p_payload ->> 'due_date')::date,
        coalesce((p_payload ->> 'required')::boolean, true),
        coalesce((p_payload ->> 'blocking')::boolean, true),
        coalesce((p_payload ->> 'evidence_required')::boolean, false), 'pending',
        coalesce((p_payload ->> 'sort')::integer, 0)
      ) returning id into v_id;
      return v_id;
    end if;
    update public.hr_lifecycle_task set
      lifecycle_case_id = v_case.id, task_type = p_payload ->> 'task_type',
      task_name = btrim(p_payload ->> 'task_name'), description = nullif(btrim(p_payload ->> 'description'), ''),
      owner_employee_id = nullif(p_payload ->> 'owner_employee_id', '')::uuid,
      owner_role = coalesce(nullif(p_payload ->> 'owner_role', ''), owner_role),
      due_date = (p_payload ->> 'due_date')::date,
      required = coalesce((p_payload ->> 'required')::boolean, required),
      blocking = coalesce((p_payload ->> 'blocking')::boolean, blocking),
      evidence_required = coalesce((p_payload ->> 'evidence_required')::boolean, evidence_required),
      sort = coalesce((p_payload ->> 'sort')::integer, sort)
    where id = p_id and tenant_id = v_tenant_id and status in ('pending', 'processing')
    returning id into v_id;
    if v_id is null then raise exception '任务不存在、已关闭或无权编辑'; end if;
    return v_id;
  end if;

  if p_kind = 'template' then
    if p_id is null then
      insert into public.hr_lifecycle_template(
        tenant_id, template_code, template_name, case_type, status, is_default, description
      ) values (
        v_tenant_id, btrim(p_payload ->> 'template_code'), btrim(p_payload ->> 'template_name'),
        p_payload ->> 'case_type', 'draft', coalesce((p_payload ->> 'is_default')::boolean, false),
        nullif(btrim(p_payload ->> 'description'), '')
      ) returning id into v_id;
      return v_id;
    end if;
    update public.hr_lifecycle_template set
      template_code = btrim(p_payload ->> 'template_code'),
      template_name = btrim(p_payload ->> 'template_name'),
      case_type = p_payload ->> 'case_type',
      is_default = coalesce((p_payload ->> 'is_default')::boolean, is_default),
      description = nullif(btrim(p_payload ->> 'description'), '')
    where id = p_id and tenant_id = v_tenant_id and status in ('draft', 'inactive')
    returning * into v_template;
    if not found then raise exception '任务包不存在、已启用或无权编辑'; end if;
    return p_id;
  end if;

  select template.* into v_template from public.hr_lifecycle_template template
  where template.id = nullif(p_payload ->> 'template_id', '')::uuid
    and template.tenant_id = v_tenant_id and template.status in ('draft', 'inactive');
  if not found then raise exception '只有草稿或停用任务包可以维护模板任务'; end if;
  if p_id is null then
    insert into public.hr_lifecycle_template_task(
      tenant_id, template_id, task_type, task_name, description, owner_role,
      due_offset_days, required, blocking, evidence_required, sort
    ) values (
      v_tenant_id, v_template.id, p_payload ->> 'task_type', btrim(p_payload ->> 'task_name'),
      nullif(btrim(p_payload ->> 'description'), ''), coalesce(nullif(p_payload ->> 'owner_role', ''), 'hr'),
      coalesce((p_payload ->> 'due_offset_days')::integer, 0),
      coalesce((p_payload ->> 'required')::boolean, true),
      coalesce((p_payload ->> 'blocking')::boolean, true),
      coalesce((p_payload ->> 'evidence_required')::boolean, false),
      coalesce((p_payload ->> 'sort')::integer, 0)
    ) returning id into v_id;
    return v_id;
  end if;
  update public.hr_lifecycle_template_task set
    template_id = v_template.id, task_type = p_payload ->> 'task_type',
    task_name = btrim(p_payload ->> 'task_name'), description = nullif(btrim(p_payload ->> 'description'), ''),
    owner_role = coalesce(nullif(p_payload ->> 'owner_role', ''), owner_role),
    due_offset_days = coalesce((p_payload ->> 'due_offset_days')::integer, due_offset_days),
    required = coalesce((p_payload ->> 'required')::boolean, required),
    blocking = coalesce((p_payload ->> 'blocking')::boolean, blocking),
    evidence_required = coalesce((p_payload ->> 'evidence_required')::boolean, evidence_required),
    sort = coalesce((p_payload ->> 'sort')::integer, sort)
  where id = p_id and tenant_id = v_tenant_id returning id into v_id;
  if v_id is null then raise exception '模板任务不存在或无权编辑'; end if;
  return v_id;
end
$function$;

create or replace function public.hr_transition_lifecycle_case_secure(
  p_id uuid,
  p_action text,
  p_comment text default null,
  p_effective_date date default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_case public.hr_lifecycle_case;
  v_open_blocking integer;
  v_open_required integer;
  v_permission text := case when p_action = 'complete' then 'Hr:Lifecycle:CompleteCase' else 'Hr:Lifecycle:Start' end;
begin
  if p_action not in ('start', 'ready', 'complete', 'cancel') then raise exception '不支持的事项动作'; end if;
  if not app_private.can_execute_business_action('HrLifecycle', v_permission, null, false) then
    raise exception '当前账号没有推进生命周期事项的权限' using errcode = '42501';
  end if;
  select * into v_case from public.hr_lifecycle_case c
  where c.id = p_id and (app_private.is_platform_super() or c.tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '生命周期事项不存在或无权操作'; end if;

  if p_action = 'start' then
    if v_case.execution_status <> 'planning' or v_case.status not in ('approved', 'effective') then
      raise exception '只有审批通过且待规划的事项可以启动';
    end if;
    if not exists (select 1 from public.hr_lifecycle_task t where t.lifecycle_case_id = v_case.id) then
      raise exception '事项至少需要一项执行任务';
    end if;
    update public.hr_lifecycle_case set execution_status = 'in_progress', started_at = now()
    where id = v_case.id;
    return;
  end if;
  if p_action = 'ready' then
    if v_case.execution_status <> 'in_progress' then raise exception '只有执行中的事项可以校验就绪'; end if;
    select count(*) into v_open_blocking from public.hr_lifecycle_task t
    where t.lifecycle_case_id = v_case.id and t.blocking and t.status in ('pending', 'processing');
    if v_open_blocking > 0 then raise exception '仍有 % 项阻断任务未完成', v_open_blocking; end if;
    update public.hr_lifecycle_case set execution_status = 'ready', ready_at = now() where id = v_case.id;
    return;
  end if;
  if p_action = 'complete' then
    if v_case.execution_status <> 'ready' then raise exception '只有已就绪事项可以办结'; end if;
    select count(*) into v_open_required from public.hr_lifecycle_task t
    where t.lifecycle_case_id = v_case.id and t.required and t.status in ('pending', 'processing');
    if v_open_required > 0 then raise exception '仍有 % 项必办任务未完成', v_open_required; end if;
    update public.hr_lifecycle_case set status = 'effective', execution_status = 'completed',
      actual_effective_date = coalesce(p_effective_date, planned_effective_date),
      completed_at = now(), completed_by = auth.uid()::text,
      remark = coalesce(nullif(btrim(p_comment), ''), remark)
    where id = v_case.id;
    return;
  end if;
  if v_case.execution_status in ('completed', 'cancelled') then raise exception '已结束事项不能取消'; end if;
  if nullif(btrim(p_comment), '') is null then raise exception '取消事项必须填写原因'; end if;
  update public.hr_lifecycle_case set status = 'cancelled', execution_status = 'cancelled',
    cancelled_at = now(), cancellation_reason = btrim(p_comment)
  where id = v_case.id;
  update public.hr_lifecycle_task set status = 'cancelled'
  where lifecycle_case_id = v_case.id and status in ('pending', 'processing');
end
$function$;

create or replace function public.hr_transition_lifecycle_task_secure(
  p_id uuid,
  p_action text,
  p_note text default null,
  p_evidence_url text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_task public.hr_lifecycle_task;
  v_case public.hr_lifecycle_case;
  v_permission text := case when p_action = 'waive' then 'Hr:Lifecycle:WaiveTask' else 'Hr:Lifecycle:CompleteTask' end;
begin
  if p_action not in ('start', 'complete', 'waive', 'reopen') then raise exception '不支持的任务动作'; end if;
  if not app_private.can_execute_business_action('HrLifecycle', v_permission, null, false) then
    raise exception '当前账号没有处理生命周期任务的权限' using errcode = '42501';
  end if;
  select * into v_task from public.hr_lifecycle_task t
  where t.id = p_id and (app_private.is_platform_super() or t.tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '生命周期任务不存在或无权操作'; end if;
  select * into v_case from public.hr_lifecycle_case c
  where c.id = v_task.lifecycle_case_id and c.tenant_id = v_task.tenant_id;
  if v_case.execution_status not in ('planning', 'in_progress') then
    raise exception '当前事项状态不允许处理任务';
  end if;
  if p_action in ('start', 'complete') and v_task.dependency_task_id is not null and exists (
    select 1 from public.hr_lifecycle_task dependency
    where dependency.id = v_task.dependency_task_id and dependency.status not in ('completed', 'skipped')
  ) then raise exception '前置任务尚未完成'; end if;
  if p_action = 'start' then
    if v_task.status <> 'pending' then raise exception '只有待处理任务可以开始'; end if;
    update public.hr_lifecycle_task set status = 'processing', started_at = now() where id = v_task.id;
    return;
  end if;
  if p_action = 'complete' then
    if v_task.status not in ('pending', 'processing') then raise exception '当前任务不能完成'; end if;
    if v_task.evidence_required and nullif(btrim(p_note), '') is null and nullif(btrim(p_evidence_url), '') is null then
      raise exception '该任务要求填写完成证据或证据链接';
    end if;
    update public.hr_lifecycle_task set status = 'completed', completed_at = now(),
      completed_by = auth.uid()::text, completion_note = nullif(btrim(p_note), ''),
      evidence_note = nullif(btrim(p_note), ''), evidence_url = nullif(btrim(p_evidence_url), ''),
      waived_at = null, waived_by = null, waiver_reason = null
    where id = v_task.id;
    return;
  end if;
  if p_action = 'waive' then
    if v_task.status not in ('pending', 'processing') then raise exception '当前任务不能豁免'; end if;
    if nullif(btrim(p_note), '') is null then raise exception '豁免任务必须填写原因'; end if;
    update public.hr_lifecycle_task set status = 'skipped', waived_at = now(),
      waived_by = auth.uid()::text, waiver_reason = btrim(p_note),
      completed_at = now(), completed_by = auth.uid()::text, completion_note = btrim(p_note)
    where id = v_task.id;
    return;
  end if;
  if v_task.status not in ('completed', 'skipped') then raise exception '只有已关闭任务可以重新打开'; end if;
  update public.hr_lifecycle_task set status = 'pending', started_at = null,
    completed_at = null, completed_by = null, completion_note = null,
    evidence_note = null, evidence_url = null, waived_at = null, waived_by = null, waiver_reason = null
  where id = v_task.id;
end
$function$;

create or replace function public.hr_transition_lifecycle_template_secure(
  p_id uuid,
  p_action text
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_template public.hr_lifecycle_template;
begin
  if p_action not in ('activate', 'deactivate') then raise exception '不支持的任务包动作'; end if;
  if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:ManageTemplate', null, false) then
    raise exception '当前账号没有管理标准任务包的权限' using errcode = '42501';
  end if;
  select * into v_template from public.hr_lifecycle_template t
  where t.id = p_id and (app_private.is_platform_super() or t.tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '标准任务包不存在或无权操作'; end if;
  if p_action = 'activate' then
    if v_template.status = 'active' then return; end if;
    if not exists (select 1 from public.hr_lifecycle_template_task task where task.template_id = v_template.id) then
      raise exception '任务包至少需要一项模板任务';
    end if;
    if v_template.is_default then
      update public.hr_lifecycle_template set is_default = false
      where tenant_id = v_template.tenant_id and case_type = v_template.case_type
        and id <> v_template.id and status = 'active' and is_default;
    end if;
    update public.hr_lifecycle_template set status = 'active' where id = v_template.id;
  else
    if v_template.status <> 'active' then raise exception '只有启用任务包可以停用'; end if;
    update public.hr_lifecycle_template set status = 'inactive', is_default = false where id = v_template.id;
  end if;
end
$function$;

create or replace function public.hr_delete_lifecycle_record_secure(p_kind text, p_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_deleted integer;
begin
  if p_kind not in ('case', 'task', 'template', 'template_task') then raise exception '不支持的生命周期记录类型'; end if;
  if p_kind in ('template', 'template_task') then
    if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:ManageTemplate', null, false) then
      raise exception '当前账号没有删除标准任务包的权限' using errcode = '42501';
    end if;
  elsif not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:Delete', null, false) then
    raise exception '当前账号没有删除生命周期记录的权限' using errcode = '42501';
  end if;
  if p_kind = 'case' then
    delete from public.hr_lifecycle_case c where c.id = p_id
      and (app_private.is_platform_super() or c.tenant_id = v_tenant_id)
      and c.status in ('draft', 'rejected') and c.execution_status = 'planning';
  elsif p_kind = 'task' then
    delete from public.hr_lifecycle_task t where t.id = p_id
      and (app_private.is_platform_super() or t.tenant_id = v_tenant_id) and t.status = 'pending';
  elsif p_kind = 'template' then
    delete from public.hr_lifecycle_template t where t.id = p_id
      and (app_private.is_platform_super() or t.tenant_id = v_tenant_id)
      and t.status in ('draft', 'inactive')
      and not exists (select 1 from public.hr_lifecycle_case c where c.template_id = t.id);
  else
    delete from public.hr_lifecycle_template_task task where task.id = p_id
      and (app_private.is_platform_super() or task.tenant_id = v_tenant_id)
      and exists (select 1 from public.hr_lifecycle_template template
        where template.id = task.template_id and template.status in ('draft', 'inactive'));
  end if;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then raise exception '记录不存在、状态不允许删除或仍被业务引用'; end if;
end
$function$;

revoke all on function public.hr_lifecycle_overview_secure(uuid) from public, anon, authenticated;
revoke all on function public.hr_list_lifecycle_records_secure(text,integer,integer,text,text,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.hr_list_lifecycle_options_secure(text,uuid) from public, anon, authenticated;
revoke all on function public.hr_save_lifecycle_record_secure(text,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.hr_transition_lifecycle_case_secure(uuid,text,text,date) from public, anon, authenticated;
revoke all on function public.hr_transition_lifecycle_task_secure(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.hr_transition_lifecycle_template_secure(uuid,text) from public, anon, authenticated;
revoke all on function public.hr_delete_lifecycle_record_secure(text,uuid) from public, anon, authenticated;

grant execute on function public.hr_lifecycle_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_lifecycle_records_secure(text,integer,integer,text,text,uuid,uuid,uuid) to authenticated, service_role;
grant execute on function public.hr_list_lifecycle_options_secure(text,uuid) to authenticated, service_role;
grant execute on function public.hr_save_lifecycle_record_secure(text,uuid,jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_lifecycle_case_secure(uuid,text,text,date) to authenticated, service_role;
grant execute on function public.hr_transition_lifecycle_task_secure(uuid,text,text,text) to authenticated, service_role;
grant execute on function public.hr_transition_lifecycle_template_secure(uuid,text) to authenticated, service_role;
grant execute on function public.hr_delete_lifecycle_record_secure(text,uuid) to authenticated, service_role;
