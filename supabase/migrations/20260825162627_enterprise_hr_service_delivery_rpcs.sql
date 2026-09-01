create or replace function app_private.hr_current_employee_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.hr_employee_id
  from public.sys_user u
  where u.id = app_private.current_app_user_id()
    and u.status = '1'
  limit 1
$function$;

revoke all on function app_private.hr_current_employee_id() from public, anon, authenticated;

create or replace function app_private.hr_service_case_visible(
  p_tenant_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or (
      p_tenant_id = app_private.current_user_tenant_id()
      and (
        app_private.has_permission('Hr:SelfService:Manage')
        or p_employee_id = app_private.hr_current_employee_id()
      )
    )
$function$;

revoke all on function app_private.hr_service_case_visible(uuid, uuid)
  from public, anon, authenticated;

create or replace function app_private.hr_add_service_event(
  p_request public.hr_self_service_request,
  p_event_type text,
  p_from_status text,
  p_to_status text,
  p_comment text default null,
  p_event_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.hr_service_request_event(
    tenant_id, request_id, event_type, from_status, to_status,
    actor_employee_id, comment, event_data
  ) values (
    p_request.tenant_id, p_request.id, p_event_type, p_from_status, p_to_status,
    app_private.hr_current_employee_id(), nullif(btrim(p_comment), ''), coalesce(p_event_data, '{}'::jsonb)
  );
end
$function$;

revoke all on function app_private.hr_add_service_event(
  public.hr_self_service_request, text, text, text, text, jsonb
) from public, anon, authenticated;

create or replace function public.hr_service_delivery_overview_secure(
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
  v_employee_id uuid := app_private.hr_current_employee_id();
  v_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Manage');
begin
  if not app_private.can_execute_business_action(
    'HrSelfService', 'Hr:SelfService:View', null, false
  ) then
    raise exception '当前账号没有查看员工服务中心的权限' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then
    p_tenant_id := v_tenant_id;
  end if;

  return jsonb_build_object(
    'available_service_count', (
      select count(*) from public.hr_service_catalog service
      where (p_tenant_id is null or service.tenant_id = p_tenant_id)
        and service.enabled
    ),
    'open_request_count', (
      select count(*) from public.hr_self_service_request request
      where (p_tenant_id is null or request.tenant_id = p_tenant_id)
        and (v_manage or request.employee_id = v_employee_id)
        and request.status in ('submitted', 'assigned', 'in_progress', 'waiting_employee')
    ),
    'sla_risk_count', (
      select count(*) from public.hr_self_service_request request
      where (p_tenant_id is null or request.tenant_id = p_tenant_id)
        and (v_manage or request.employee_id = v_employee_id)
        and request.status in ('submitted', 'assigned', 'in_progress', 'waiting_employee')
        and request.resolution_due_at is not null
        and request.resolution_due_at <= now() + interval '4 hours'
    ),
    'unassigned_count', (
      select count(*) from public.hr_self_service_request request
      where v_manage
        and (p_tenant_id is null or request.tenant_id = p_tenant_id)
        and request.status = 'submitted'
        and request.assigned_employee_id is null
    ),
    'resolved_month_count', (
      select count(*) from public.hr_self_service_request request
      where (p_tenant_id is null or request.tenant_id = p_tenant_id)
        and (v_manage or request.employee_id = v_employee_id)
        and request.resolved_at >= date_trunc('month', now())
    ),
    'response_on_time_rate', (
      select coalesce(round(
        100 * count(*) filter (
          where request.first_responded_at is not null
            and request.first_response_due_at is not null
            and request.first_responded_at <= request.first_response_due_at
        )::numeric / nullif(count(*) filter (where request.first_responded_at is not null), 0), 1
      ), 0)
      from public.hr_self_service_request request
      where (p_tenant_id is null or request.tenant_id = p_tenant_id)
        and (v_manage or request.employee_id = v_employee_id)
        and request.create_time >= date_trunc('month', now())
    ),
    'manager_view', v_manage
  );
end
$function$;

create or replace function public.hr_list_service_delivery_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_category text default null,
  p_scope text default 'mine',
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
  v_employee_id uuid := app_private.hr_current_employee_id();
  v_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Manage');
  v_catalog_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Catalog:Manage');
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    500,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('service', 'request') then
    raise exception '不支持的员工服务记录类型';
  end if;
  if not app_private.can_execute_business_action(
    'HrSelfService', 'Hr:SelfService:View', null, false
  ) then
    raise exception '当前账号没有查看员工服务中心的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then
    p_tenant_id := v_tenant_id;
  end if;

  if p_kind = 'service' then
    with filtered as materialized (
      select service.*,
        (select count(*) from public.hr_self_service_request request
          where request.service_id = service.id and request.tenant_id = service.tenant_id
        ) as request_count
      from public.hr_service_catalog service
      where (p_tenant_id is null or service.tenant_id = p_tenant_id)
        and (v_catalog_manage or service.enabled)
        and (p_status is null or service.enabled = (p_status = 'enabled'))
        and (p_category is null or service.category = p_category)
        and (
          v_keyword is null
          or service.service_code ilike '%' || v_keyword || '%'
          or service.service_name ilike '%' || v_keyword || '%'
          or service.description ilike '%' || v_keyword || '%'
          or service.routing_group ilike '%' || v_keyword || '%'
        )
    ), paged as (
      select * from filtered
      order by enabled desc, sort, service_name
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(paged) order by enabled desc, sort, service_name), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  with filtered as materialized (
    select request.*,
      service.service_code,
      service.service_name,
      service.category as service_category,
      service.routing_group,
      requester.employee_no as requester_code,
      requester.employee_name as requester_name,
      requester.job_title as requester_job_title,
      assignee.employee_no as assignee_code,
      assignee.employee_name as assignee_name,
      case
        when request.status not in ('submitted', 'assigned', 'in_progress', 'waiting_employee')
          or request.resolution_due_at is null then 'clear'
        when request.resolution_due_at < now() then 'breached'
        when request.resolution_due_at <= now() + interval '4 hours' then 'at_risk'
        else 'on_track'
      end as sla_status
    from public.hr_self_service_request request
    left join public.hr_service_catalog service
      on service.id = request.service_id and service.tenant_id = request.tenant_id
    join public.hr_employee requester
      on requester.id = request.employee_id and requester.tenant_id = request.tenant_id
    left join public.hr_employee assignee
      on assignee.id = request.assigned_employee_id and assignee.tenant_id = request.tenant_id
    where (p_tenant_id is null or request.tenant_id = p_tenant_id)
      and (v_manage and p_scope = 'team' or request.employee_id = v_employee_id)
      and (p_status is null or request.status = p_status)
      and (p_category is null or service.category = p_category)
      and (
        v_keyword is null
        or request.request_no ilike '%' || v_keyword || '%'
        or request.title ilike '%' || v_keyword || '%'
        or request.reason ilike '%' || v_keyword || '%'
        or service.service_name ilike '%' || v_keyword || '%'
        or requester.employee_no ilike '%' || v_keyword || '%'
        or requester.employee_name ilike '%' || v_keyword || '%'
      )
  ), paged as (
    select * from filtered
    order by
      case when sla_status = 'breached' then 0 when sla_status = 'at_risk' then 1 else 2 end,
      last_activity_at desc
    offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged)
        - 'service_code' - 'service_name' - 'service_category' - 'routing_group'
        - 'requester_code' - 'requester_name' - 'requester_job_title'
        - 'assignee_code' - 'assignee_name')
      || jsonb_build_object(
        'service', case when service_id is null then null else jsonb_build_object(
          'id', service_id, 'code', service_code, 'name', service_name,
          'category', service_category, 'routing_group', routing_group
        ) end,
        'requester', jsonb_build_object(
          'id', employee_id, 'code', requester_code, 'name', requester_name,
          'job_title', requester_job_title
        ),
        'assignee', case when assigned_employee_id is null then null else jsonb_build_object(
          'id', assigned_employee_id, 'code', assignee_code, 'name', assignee_name
        ) end
      )
      order by
        case when sla_status = 'breached' then 0 when sla_status = 'at_risk' then 1 else 2 end,
        last_activity_at desc
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_get_service_request_detail_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_request public.hr_self_service_request;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'HrSelfService', 'Hr:SelfService:View', null, false
  ) then
    raise exception '当前账号没有查看员工服务中心的权限' using errcode = '42501';
  end if;

  select * into v_request from public.hr_self_service_request where id = p_id;
  if not found or not app_private.hr_service_case_visible(
    v_request.tenant_id, v_request.employee_id
  ) then
    raise exception '员工服务工单不存在或无权查看' using errcode = '42501';
  end if;

  select to_jsonb(request)
    || jsonb_build_object(
      'service', case when service.id is null then null else jsonb_build_object(
        'id', service.id, 'code', service.service_code, 'name', service.service_name,
        'category', service.category, 'routing_group', service.routing_group
      ) end,
      'requester', jsonb_build_object(
        'id', requester.id, 'code', requester.employee_no,
        'name', requester.employee_name, 'job_title', requester.job_title
      ),
      'assignee', case when assignee.id is null then null else jsonb_build_object(
        'id', assignee.id, 'code', assignee.employee_no, 'name', assignee.employee_name
      ) end,
      'events', coalesce((
        select jsonb_agg(
          to_jsonb(event) || jsonb_build_object(
            'actor', case when actor.id is null then null else jsonb_build_object(
              'id', actor.id, 'code', actor.employee_no, 'name', actor.employee_name
            ) end
          ) order by event.create_time desc
        )
        from public.hr_service_request_event event
        left join public.hr_employee actor
          on actor.id = event.actor_employee_id and actor.tenant_id = event.tenant_id
        where event.request_id = request.id and event.tenant_id = request.tenant_id
      ), '[]'::jsonb)
    ) into v_result
  from public.hr_self_service_request request
  left join public.hr_service_catalog service
    on service.id = request.service_id and service.tenant_id = request.tenant_id
  join public.hr_employee requester
    on requester.id = request.employee_id and requester.tenant_id = request.tenant_id
  left join public.hr_employee assignee
    on assignee.id = request.assigned_employee_id and assignee.tenant_id = request.tenant_id
  where request.id = p_id;

  return v_result;
end
$function$;

create or replace function public.hr_save_service_catalog_secure(
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record public.hr_service_catalog;
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'HrSelfService', 'Hr:SelfService:Catalog:Manage', null, false
  ) then
    raise exception '当前账号没有维护员工服务目录的权限' using errcode = '42501';
  end if;
  if app_private.is_platform_super() then
    v_tenant_id := coalesce(nullif(p_payload->>'tenant_id', '')::uuid, v_tenant_id);
  end if;

  if nullif(btrim(p_payload->>'service_code'), '') is null
    or nullif(btrim(p_payload->>'service_name'), '') is null
    or nullif(btrim(p_payload->>'category'), '') is null then
    raise exception '服务编码、服务名称和服务类别不能为空';
  end if;

  if p_id is null then
    insert into public.hr_service_catalog(
      tenant_id, service_code, service_name, category, description, service_mode,
      route_path, routing_group, first_response_hours, resolution_hours, enabled, sort
    ) values (
      v_tenant_id, upper(btrim(p_payload->>'service_code')), btrim(p_payload->>'service_name'),
      p_payload->>'category', nullif(btrim(p_payload->>'description'), ''),
      coalesce(nullif(p_payload->>'service_mode', ''), 'case'),
      nullif(btrim(p_payload->>'route_path'), ''), nullif(btrim(p_payload->>'routing_group'), ''),
      coalesce((p_payload->>'first_response_hours')::integer, 8),
      coalesce((p_payload->>'resolution_hours')::integer, 40),
      coalesce((p_payload->>'enabled')::boolean, true),
      coalesce((p_payload->>'sort')::integer, 0)
    ) returning * into v_record;
  else
    select * into v_record from public.hr_service_catalog where id = p_id for update;
    if not found or (
      not app_private.is_platform_super() and v_record.tenant_id <> v_tenant_id
    ) then
      raise exception '员工服务目录记录不存在或无权维护' using errcode = '42501';
    end if;
    update public.hr_service_catalog
    set service_code = upper(btrim(p_payload->>'service_code')),
        service_name = btrim(p_payload->>'service_name'),
        category = p_payload->>'category',
        description = nullif(btrim(p_payload->>'description'), ''),
        service_mode = coalesce(nullif(p_payload->>'service_mode', ''), 'case'),
        route_path = nullif(btrim(p_payload->>'route_path'), ''),
        routing_group = nullif(btrim(p_payload->>'routing_group'), ''),
        first_response_hours = coalesce((p_payload->>'first_response_hours')::integer, 8),
        resolution_hours = coalesce((p_payload->>'resolution_hours')::integer, 40),
        enabled = coalesce((p_payload->>'enabled')::boolean, true),
        sort = coalesce((p_payload->>'sort')::integer, 0)
    where id = p_id returning * into v_record;
  end if;
  return v_record.id;
exception
  when unique_violation then
    raise exception '同一租户下服务编码不能重复';
end
$function$;

create or replace function public.hr_save_service_request_secure(
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record public.hr_self_service_request;
  v_service public.hr_service_catalog;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_employee_id uuid := app_private.hr_current_employee_id();
  v_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Manage');
begin
  if p_id is null then
    if not app_private.can_execute_business_action(
      'HrSelfService', 'Hr:SelfService:Add', null, false
    ) then
      raise exception '当前账号没有创建员工服务工单的权限' using errcode = '42501';
    end if;
    if app_private.is_platform_super() then
      v_tenant_id := coalesce(nullif(p_payload->>'tenant_id', '')::uuid, v_tenant_id);
    end if;
    if v_manage and nullif(p_payload->>'employee_id', '') is not null then
      v_employee_id := (p_payload->>'employee_id')::uuid;
    end if;
  else
    if not app_private.can_execute_business_action(
      'HrSelfService', 'Hr:SelfService:Edit', null, false
    ) then
      raise exception '当前账号没有编辑员工服务工单的权限' using errcode = '42501';
    end if;
    select * into v_record from public.hr_self_service_request where id = p_id for update;
    if not found or not app_private.hr_service_case_visible(
      v_record.tenant_id, v_record.employee_id
    ) then
      raise exception '员工服务工单不存在或无权编辑' using errcode = '42501';
    end if;
    if v_record.status <> 'draft' then
      raise exception '仅草稿工单可以编辑';
    end if;
    v_tenant_id := v_record.tenant_id;
    v_employee_id := v_record.employee_id;
  end if;

  if v_employee_id is null then
    raise exception '当前账号未关联员工档案，无法创建服务工单';
  end if;
  if nullif(p_payload->>'service_id', '') is null
    or nullif(btrim(p_payload->>'request_no'), '') is null
    or nullif(btrim(p_payload->>'title'), '') is null
    or nullif(btrim(p_payload->>'reason'), '') is null then
    raise exception '服务项目、工单编号、主题和问题说明不能为空';
  end if;

  select * into v_service from public.hr_service_catalog
  where id = (p_payload->>'service_id')::uuid and tenant_id = v_tenant_id and enabled;
  if not found then raise exception '所选员工服务不存在或已停用'; end if;
  if v_service.service_mode <> 'case' then raise exception '跳转型服务不能创建工单'; end if;

  if p_id is null then
    insert into public.hr_self_service_request(
      tenant_id, request_no, employee_id, request_type, title, reason, request_data,
      status, service_id, priority, channel, attachment_urls, last_activity_at
    ) values (
      v_tenant_id, btrim(p_payload->>'request_no'), v_employee_id, v_service.category,
      btrim(p_payload->>'title'), btrim(p_payload->>'reason'), '{}'::jsonb,
      'draft', v_service.id, coalesce(nullif(p_payload->>'priority', ''), 'normal'),
      case when v_manage then coalesce(nullif(p_payload->>'channel', ''), 'agent')
        else 'self_service' end,
      coalesce(p_payload->'attachment_urls', '[]'::jsonb), now()
    ) returning * into v_record;
    perform app_private.hr_add_service_event(
      v_record, 'created', null, 'draft', '创建服务工单',
      jsonb_build_object('service_id', v_service.id)
    );
  else
    update public.hr_self_service_request
    set service_id = v_service.id,
        request_type = v_service.category,
        request_no = btrim(p_payload->>'request_no'),
        title = btrim(p_payload->>'title'),
        reason = btrim(p_payload->>'reason'),
        priority = coalesce(nullif(p_payload->>'priority', ''), 'normal'),
        channel = case when v_manage then coalesce(nullif(p_payload->>'channel', ''), channel)
          else channel end,
        attachment_urls = coalesce(p_payload->'attachment_urls', '[]'::jsonb),
        last_activity_at = now()
    where id = p_id returning * into v_record;
    perform app_private.hr_add_service_event(v_record, 'updated', 'draft', 'draft', '更新工单信息');
  end if;

  return v_record.id;
exception
  when unique_violation then
    raise exception '员工服务工单编号不能重复';
end
$function$;

create or replace function public.hr_transition_service_request_secure(
  p_id uuid,
  p_action text,
  p_assignee_employee_id uuid default null,
  p_comment text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record public.hr_self_service_request;
  v_service public.hr_service_catalog;
  v_old_status text;
  v_new_status text;
  v_event_type text;
  v_comment text := nullif(btrim(p_comment), '');
  v_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Manage');
  v_own boolean;
begin
  select * into v_record from public.hr_self_service_request where id = p_id for update;
  if not found or not app_private.hr_service_case_visible(
    v_record.tenant_id, v_record.employee_id
  ) then
    raise exception '员工服务工单不存在或无权处理' using errcode = '42501';
  end if;
  v_own := v_record.employee_id = app_private.hr_current_employee_id();
  v_old_status := v_record.status;

  if p_action = 'submit' then
    if not (v_own or v_manage) or not app_private.has_permission('Hr:SelfService:Submit') then
      raise exception '当前账号没有提交员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status <> 'draft' then raise exception '仅草稿工单可以提交'; end if;
    select * into v_service from public.hr_service_catalog
      where id = v_record.service_id and tenant_id = v_record.tenant_id and enabled;
    if not found or v_service.service_mode <> 'case' then raise exception '服务项目不可受理'; end if;
    v_new_status := 'submitted'; v_event_type := 'submitted';
    update public.hr_self_service_request
    set status = v_new_status,
        first_response_due_at = now() + make_interval(hours => v_service.first_response_hours),
        resolution_due_at = now() + make_interval(hours => v_service.resolution_hours),
        last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'assign' then
    if not app_private.has_permission('Hr:SelfService:Assign') then
      raise exception '当前账号没有分派员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status not in ('submitted', 'assigned') then raise exception '当前状态不能分派'; end if;
    if p_assignee_employee_id is null or not exists(
      select 1 from public.hr_employee employee
      where employee.id = p_assignee_employee_id and employee.tenant_id = v_record.tenant_id
        and employee.employment_status <> 'terminated'
    ) then raise exception '请选择同租户的有效处理人'; end if;
    v_new_status := 'assigned'; v_event_type := 'assigned';
    update public.hr_self_service_request
    set status = v_new_status, assigned_employee_id = p_assignee_employee_id,
        last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'start' then
    if not app_private.has_permission('Hr:SelfService:Resolve') then
      raise exception '当前账号没有处理员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status not in ('submitted', 'assigned') then raise exception '当前状态不能开始处理'; end if;
    v_new_status := 'in_progress'; v_event_type := 'started';
    update public.hr_self_service_request
    set status = v_new_status,
        assigned_employee_id = coalesce(assigned_employee_id, app_private.hr_current_employee_id()),
        first_responded_at = coalesce(first_responded_at, now()),
        last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'wait' then
    if not app_private.has_permission('Hr:SelfService:Resolve') then
      raise exception '当前账号没有处理员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status <> 'in_progress' then raise exception '仅处理中工单可以等待员工补充'; end if;
    if v_comment is null then raise exception '请说明需要员工补充的材料或信息'; end if;
    v_new_status := 'waiting_employee'; v_event_type := 'waiting';
    update public.hr_self_service_request
    set status = v_new_status, waiting_started_at = now(), waiting_reason = v_comment,
        last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'resume' then
    if not (v_own or app_private.has_permission('Hr:SelfService:Resolve')) then
      raise exception '当前账号没有恢复员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status <> 'waiting_employee' then raise exception '当前工单不在等待员工补充状态'; end if;
    v_new_status := 'in_progress'; v_event_type := 'resumed';
    update public.hr_self_service_request
    set status = v_new_status,
        resolution_due_at = case when resolution_due_at is null then null
          else resolution_due_at + (now() - waiting_started_at) end,
        waiting_started_at = null, waiting_reason = null, last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'resolve' then
    if not app_private.has_permission('Hr:SelfService:Resolve') then
      raise exception '当前账号没有解决员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status not in ('assigned', 'in_progress') then raise exception '当前状态不能标记为已解决'; end if;
    if v_comment is null then raise exception '请填写可供员工确认的解决结果'; end if;
    v_new_status := 'resolved'; v_event_type := 'resolved';
    update public.hr_self_service_request
    set status = v_new_status, resolution = v_comment, resolved_at = now(),
        first_responded_at = coalesce(first_responded_at, now()),
        waiting_started_at = null, waiting_reason = null, last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'close' then
    if not (v_own or app_private.has_permission('Hr:SelfService:Resolve')) then
      raise exception '当前账号没有关闭员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status <> 'resolved' then raise exception '仅已解决工单可以关闭'; end if;
    v_new_status := 'closed'; v_event_type := 'closed';
    update public.hr_self_service_request
    set status = v_new_status, closed_at = now(), last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'reopen' then
    if not (v_own or app_private.has_permission('Hr:SelfService:Resolve')) then
      raise exception '当前账号没有重开员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status not in ('resolved', 'closed') then raise exception '仅已解决或已关闭工单可以重开'; end if;
    if v_comment is null then raise exception '请说明重新打开工单的原因'; end if;
    v_new_status := 'in_progress'; v_event_type := 'reopened';
    update public.hr_self_service_request
    set status = v_new_status, resolution = null, resolved_at = null, closed_at = null,
        reopen_count = reopen_count + 1,
        resolution_due_at = greatest(coalesce(resolution_due_at, now()), now()) + interval '8 hours',
        last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'cancel' then
    if not (v_own or v_manage) or not app_private.has_permission('Hr:SelfService:Submit') then
      raise exception '当前账号没有取消员工服务工单的权限' using errcode = '42501';
    end if;
    if v_old_status not in ('draft', 'submitted') then raise exception '当前状态不能取消'; end if;
    v_new_status := 'cancelled'; v_event_type := 'cancelled';
    update public.hr_self_service_request
    set status = v_new_status, last_activity_at = now()
    where id = p_id returning * into v_record;
  elsif p_action = 'comment' then
    if v_comment is null then raise exception '请输入沟通内容'; end if;
    v_new_status := v_old_status; v_event_type := 'commented';
    update public.hr_self_service_request set last_activity_at = now()
      where id = p_id returning * into v_record;
  else
    raise exception '不支持的员工服务工单动作';
  end if;

  perform app_private.hr_add_service_event(
    v_record, v_event_type, v_old_status, v_new_status, v_comment,
    case when p_assignee_employee_id is null then '{}'::jsonb
      else jsonb_build_object('assignee_employee_id', p_assignee_employee_id) end
  );
end
$function$;

create or replace function public.hr_delete_service_request_secure(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_record public.hr_self_service_request;
  v_manage boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:SelfService:Manage');
begin
  if not app_private.can_execute_business_action(
    'HrSelfService', 'Hr:SelfService:Delete', null, false
  ) then
    raise exception '当前账号没有删除员工服务工单的权限' using errcode = '42501';
  end if;
  select * into v_record from public.hr_self_service_request where id = p_id for update;
  if not found or not app_private.hr_service_case_visible(
    v_record.tenant_id, v_record.employee_id
  ) then
    raise exception '员工服务工单不存在或无权删除' using errcode = '42501';
  end if;
  if v_record.status <> 'draft' then raise exception '仅草稿工单可以删除'; end if;
  if not (v_manage or v_record.employee_id = app_private.hr_current_employee_id()) then
    raise exception '只能删除本人草稿工单' using errcode = '42501';
  end if;
  delete from public.hr_self_service_request where id = p_id;
end
$function$;

revoke all on function public.hr_service_delivery_overview_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.hr_list_service_delivery_records_secure(
  text, integer, integer, text, text, text, text, uuid
) from public, anon, authenticated;
revoke all on function public.hr_get_service_request_detail_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.hr_save_service_catalog_secure(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.hr_save_service_request_secure(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.hr_transition_service_request_secure(uuid, text, uuid, text)
  from public, anon, authenticated;
revoke all on function public.hr_delete_service_request_secure(uuid)
  from public, anon, authenticated;

grant execute on function public.hr_service_delivery_overview_secure(uuid) to authenticated;
grant execute on function public.hr_list_service_delivery_records_secure(
  text, integer, integer, text, text, text, text, uuid
) to authenticated;
grant execute on function public.hr_get_service_request_detail_secure(uuid) to authenticated;
grant execute on function public.hr_save_service_catalog_secure(uuid, jsonb) to authenticated;
grant execute on function public.hr_save_service_request_secure(uuid, jsonb) to authenticated;
grant execute on function public.hr_transition_service_request_secure(uuid, text, uuid, text)
  to authenticated;
grant execute on function public.hr_delete_service_request_secure(uuid) to authenticated;

;
