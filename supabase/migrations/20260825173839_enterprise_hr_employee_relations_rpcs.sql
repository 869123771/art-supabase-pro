create or replace function app_private.hr_employee_relation_case_visible(
  p_tenant_id uuid,
  p_subject_employee_id uuid,
  p_reporter_employee_id uuid,
  p_owner_employee_id uuid
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
        p_subject_employee_id = app_private.hr_current_employee_id()
        or p_reporter_employee_id = app_private.hr_current_employee_id()
        or p_owner_employee_id = app_private.hr_current_employee_id()
        or app_private.has_permission('Hr:EmployeeRelations:Assign')
        or app_private.has_permission('Hr:EmployeeRelations:Investigate')
        or app_private.has_permission('Hr:EmployeeRelations:Resolve')
        or app_private.has_permission('Hr:EmployeeRelations:Close')
        or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View')
      )
    )
$function$;

revoke all on function app_private.hr_employee_relation_case_visible(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;

create or replace function app_private.hr_add_employee_relation_event(
  p_case public.hr_employee_relation_case,
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
  insert into public.hr_employee_relation_event(
    tenant_id, case_id, event_type, from_status, to_status,
    actor_employee_id, comment, event_data
  ) values (
    p_case.tenant_id, p_case.id, p_event_type, p_from_status, p_to_status,
    app_private.hr_current_employee_id(), nullif(btrim(p_comment), ''),
    coalesce(p_event_data, '{}'::jsonb)
  );
end
$function$;

revoke all on function app_private.hr_add_employee_relation_event(
  public.hr_employee_relation_case, text, text, text, text, jsonb
) from public, anon, authenticated;

create or replace function public.hr_employee_relations_overview_secure(
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
  v_sensitive boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View');
begin
  if not app_private.can_execute_business_action(
    'HrEmployeeRelations', 'Hr:EmployeeRelations:View', null, false
  ) then
    raise exception '当前账号没有查看员工关系案件的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'open_case_count', (
      select count(*) from public.hr_employee_relation_case relation_case
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and relation_case.status in ('reported', 'triaged', 'investigating', 'action_required')
    ),
    'critical_case_count', (
      select count(*) from public.hr_employee_relation_case relation_case
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and relation_case.status in ('reported', 'triaged', 'investigating', 'action_required')
        and relation_case.severity = 'critical'
    ),
    'unassigned_case_count', (
      select count(*) from public.hr_employee_relation_case relation_case
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and relation_case.status = 'reported' and relation_case.owner_employee_id is null
    ),
    'overdue_case_count', (
      select count(*) from public.hr_employee_relation_case relation_case
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and relation_case.status in ('triaged', 'investigating', 'action_required')
        and relation_case.target_resolution_date < current_date
    ),
    'overdue_action_count', (
      select count(*)
      from public.hr_employee_relation_action action
      join public.hr_employee_relation_case relation_case
        on relation_case.id = action.case_id and relation_case.tenant_id = action.tenant_id
      where (p_tenant_id is null or action.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and action.status in ('planned', 'in_progress') and action.due_date < current_date
    ),
    'resolved_month_count', (
      select count(*) from public.hr_employee_relation_case relation_case
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and relation_case.resolved_at >= date_trunc('month', now())
    ),
    'sensitive_access', v_sensitive
  );
end
$function$;

create or replace function public.hr_list_employee_relations_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_case_type text default null,
  p_severity text default null,
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
  v_sensitive boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View');
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('case', 'action') then
    raise exception '不支持的员工关系记录类型';
  end if;
  if not app_private.can_execute_business_action(
    'HrEmployeeRelations', 'Hr:EmployeeRelations:View', null, false
  ) then
    raise exception '当前账号没有查看员工关系案件的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'case' then
    with filtered as materialized (
      select relation_case.*,
        case when v_sensitive then relation_case.title else '受限员工关系案件' end as safe_title,
        jsonb_build_object(
          'id', subject.id, 'employee_no', subject.employee_no,
          'employee_name', subject.employee_name, 'job_title', subject.job_title,
          'organization_name', organization.organization_name,
          'position_name', position.position_name
        ) as subject_employee,
        case when owner.id is null then null else jsonb_build_object(
          'id', owner.id, 'employee_no', owner.employee_no,
          'employee_name', owner.employee_name, 'job_title', owner.job_title
        ) end as owner_employee,
        case when not v_sensitive or relation_case.anonymous_report or reporter.id is null then null
          else jsonb_build_object(
            'id', reporter.id, 'employee_no', reporter.employee_no,
            'employee_name', reporter.employee_name, 'job_title', reporter.job_title
          ) end as reporter_employee,
        (select count(*) from public.hr_employee_relation_action action
          where action.case_id = relation_case.id and action.tenant_id = relation_case.tenant_id
            and action.status in ('planned', 'in_progress')) as open_action_count,
        case
          when relation_case.status not in ('triaged', 'investigating', 'action_required')
            or relation_case.target_resolution_date is null then 'clear'
          when relation_case.target_resolution_date < current_date then 'overdue'
          when relation_case.target_resolution_date <= current_date + 7 then 'due_soon'
          else 'on_track'
        end as due_status
      from public.hr_employee_relation_case relation_case
      join public.hr_employee subject
        on subject.id = relation_case.subject_employee_id
        and subject.tenant_id = relation_case.tenant_id
      left join public.sys_organization organization on organization.id = subject.organization_id
      left join public.hr_position position on position.id = subject.position_id
      left join public.hr_employee owner
        on owner.id = relation_case.owner_employee_id and owner.tenant_id = relation_case.tenant_id
      left join public.hr_employee reporter
        on reporter.id = relation_case.reporter_employee_id
        and reporter.tenant_id = relation_case.tenant_id
      where (p_tenant_id is null or relation_case.tenant_id = p_tenant_id)
        and app_private.hr_employee_relation_case_visible(
          relation_case.tenant_id, relation_case.subject_employee_id,
          relation_case.reporter_employee_id, relation_case.owner_employee_id
        )
        and (p_status is null or relation_case.status = p_status)
        and (p_case_type is null or relation_case.case_type = p_case_type)
        and (p_severity is null or relation_case.severity = p_severity)
        and (
          v_keyword is null
          or relation_case.case_no ilike '%' || v_keyword || '%'
          or (v_sensitive and relation_case.title ilike '%' || v_keyword || '%')
          or subject.employee_no ilike '%' || v_keyword || '%'
          or subject.employee_name ilike '%' || v_keyword || '%'
          or owner.employee_name ilike '%' || v_keyword || '%'
        )
    ), paged as (
      select * from filtered
      order by
        case due_status when 'overdue' then 0 when 'due_soon' then 1 else 2 end,
        case severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,
        update_time desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged)
          - 'title' - 'allegation_summary' - 'findings_summary' - 'resolution_summary'
          - 'attachment_urls' - 'reporter_employee_id')
        || jsonb_build_object('title', paged.safe_title)
        order by
          case paged.due_status when 'overdue' then 0 when 'due_soon' then 1 else 2 end,
          case paged.severity when 'critical' then 0 when 'high' then 1
            when 'medium' then 2 else 3 end,
          paged.update_time desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  with filtered as materialized (
    select action.*,
      case when v_sensitive then action.title else '受限处置行动' end as safe_title,
      jsonb_build_object(
        'id', relation_case.id, 'case_no', relation_case.case_no,
        'title', case when v_sensitive then relation_case.title else '受限员工关系案件' end,
        'case_type', relation_case.case_type, 'status', relation_case.status,
        'severity', relation_case.severity
      ) as relation_case,
      jsonb_build_object(
        'id', owner.id, 'employee_no', owner.employee_no,
        'employee_name', owner.employee_name, 'job_title', owner.job_title
      ) as owner_employee,
      case
        when action.status not in ('planned', 'in_progress') then 'clear'
        when action.due_date < current_date then 'overdue'
        when action.due_date <= current_date + 7 then 'due_soon'
        else 'on_track'
      end as due_status
    from public.hr_employee_relation_action action
    join public.hr_employee_relation_case relation_case
      on relation_case.id = action.case_id and relation_case.tenant_id = action.tenant_id
    join public.hr_employee owner
      on owner.id = action.owner_employee_id and owner.tenant_id = action.tenant_id
    where (p_tenant_id is null or action.tenant_id = p_tenant_id)
      and app_private.hr_employee_relation_case_visible(
        relation_case.tenant_id, relation_case.subject_employee_id,
        relation_case.reporter_employee_id, relation_case.owner_employee_id
      )
      and (p_status is null or action.status = p_status)
      and (p_case_type is null or relation_case.case_type = p_case_type)
      and (p_severity is null or relation_case.severity = p_severity)
      and (
        v_keyword is null
        or relation_case.case_no ilike '%' || v_keyword || '%'
        or (v_sensitive and action.title ilike '%' || v_keyword || '%')
        or owner.employee_no ilike '%' || v_keyword || '%'
        or owner.employee_name ilike '%' || v_keyword || '%'
      )
  ), paged as (
    select * from filtered
    order by case due_status when 'overdue' then 0 when 'due_soon' then 1 else 2 end,
      due_date, update_time desc
    offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged) - 'title' - 'completion_note' - 'remark')
        || jsonb_build_object('title', paged.safe_title)
      order by case paged.due_status when 'overdue' then 0
        when 'due_soon' then 1 else 2 end, paged.due_date, paged.update_time desc
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_get_employee_relation_case_detail_secure(
  p_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_case public.hr_employee_relation_case;
  v_result jsonb;
  v_sensitive boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View');
begin
  if not app_private.can_execute_business_action(
    'HrEmployeeRelations', 'Hr:EmployeeRelations:View', p_id, false
  ) then
    raise exception '当前账号没有查看员工关系案件的权限' using errcode = '42501';
  end if;
  select * into v_case from public.hr_employee_relation_case where id = p_id;
  if v_case.id is null or not app_private.hr_employee_relation_case_visible(
    v_case.tenant_id, v_case.subject_employee_id, v_case.reporter_employee_id,
    v_case.owner_employee_id
  ) then
    raise exception '员工关系案件不存在或无权查看' using errcode = '42501';
  end if;

  select (to_jsonb(v_case)
      - case when v_sensitive then '__none__' else 'allegation_summary' end
      - case when v_sensitive then '__none__' else 'findings_summary' end
      - case when v_sensitive then '__none__' else 'resolution_summary' end
      - case when v_sensitive then '__none__' else 'attachment_urls' end
      - case when v_sensitive then '__none__' else 'reporter_employee_id' end)
    || jsonb_build_object(
      'title', case when v_sensitive then v_case.title else '受限员工关系案件' end,
      'sensitive_restricted', not v_sensitive,
      'subject_employee', jsonb_build_object(
        'id', subject.id, 'employee_no', subject.employee_no,
        'employee_name', subject.employee_name, 'job_title', subject.job_title,
        'organization_name', organization.organization_name,
        'position_name', position.position_name
      ),
      'owner_employee', case when owner.id is null then null else jsonb_build_object(
        'id', owner.id, 'employee_no', owner.employee_no,
        'employee_name', owner.employee_name, 'job_title', owner.job_title
      ) end,
      'reporter_employee', case when not v_sensitive or v_case.anonymous_report
          or reporter.id is null then null else jsonb_build_object(
        'id', reporter.id, 'employee_no', reporter.employee_no,
        'employee_name', reporter.employee_name, 'job_title', reporter.job_title
      ) end,
      'actions', coalesce((
        select jsonb_agg(
          (to_jsonb(action)
            - case when v_sensitive then '__none__' else 'title' end
            - case when v_sensitive then '__none__' else 'completion_note' end
            - case when v_sensitive then '__none__' else 'remark' end)
          || jsonb_build_object(
            'title', case when v_sensitive then action.title else '受限处置行动' end,
            'owner_employee', jsonb_build_object(
              'id', action_owner.id, 'employee_no', action_owner.employee_no,
              'employee_name', action_owner.employee_name, 'job_title', action_owner.job_title
            )
          ) order by action.due_date, action.create_time
        )
        from public.hr_employee_relation_action action
        join public.hr_employee action_owner
          on action_owner.id = action.owner_employee_id
          and action_owner.tenant_id = action.tenant_id
        where action.case_id = v_case.id and action.tenant_id = v_case.tenant_id
      ), '[]'::jsonb),
      'events', coalesce((
        select jsonb_agg(
          (to_jsonb(event) - case when v_sensitive then '__none__' else 'comment' end)
          || jsonb_build_object(
            'actor', case when actor.id is null then null else jsonb_build_object(
              'id', actor.id, 'employee_no', actor.employee_no,
              'employee_name', actor.employee_name, 'job_title', actor.job_title
            ) end
          ) order by event.create_time desc
        )
        from public.hr_employee_relation_event event
        left join public.hr_employee actor
          on actor.id = event.actor_employee_id and actor.tenant_id = event.tenant_id
        where event.case_id = v_case.id and event.tenant_id = v_case.tenant_id
      ), '[]'::jsonb)
    ) into v_result
  from public.hr_employee subject
  left join public.sys_organization organization on organization.id = subject.organization_id
  left join public.hr_position position on position.id = subject.position_id
  left join public.hr_employee owner
    on owner.id = v_case.owner_employee_id and owner.tenant_id = v_case.tenant_id
  left join public.hr_employee reporter
    on reporter.id = v_case.reporter_employee_id and reporter.tenant_id = v_case.tenant_id
  where subject.id = v_case.subject_employee_id and subject.tenant_id = v_case.tenant_id;
  return v_result;
end
$function$;

create or replace function public.hr_save_employee_relations_record_secure(
  p_kind text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_tenant_id uuid := coalesce(nullif(p_payload->>'tenant_id', '')::uuid,
    app_private.current_user_tenant_id());
  v_case public.hr_employee_relation_case;
  v_before public.hr_employee_relation_case;
  v_action public.hr_employee_relation_action;
  v_case_no text;
begin
  if p_kind not in ('case', 'action') then
    raise exception '不支持的员工关系记录类型';
  end if;
  if not app_private.is_platform_super() then
    v_tenant_id := app_private.current_user_tenant_id();
  end if;

  if p_kind = 'case' then
    if v_id is null then
      if not app_private.can_execute_business_action(
        'HrEmployeeRelations', 'Hr:EmployeeRelations:Add', null, false
      ) then
        raise exception '当前账号没有新建员工关系案件的权限' using errcode = '42501';
      end if;
      v_case_no := nullif(btrim(p_payload->>'case_no'), '');
      if v_case_no is null or upper(v_case_no) = 'AUTO' then
        v_case_no := 'ERC' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS');
      end if;
      insert into public.hr_employee_relation_case(
        tenant_id, case_no, case_type, title, subject_employee_id,
        reporter_employee_id, anonymous_report, source, severity,
        confidentiality_level, status, allegation_summary, attachment_urls,
        external_reference, remark
      ) values (
        v_tenant_id, v_case_no, p_payload->>'case_type', btrim(p_payload->>'title'),
        (p_payload->>'subject_employee_id')::uuid,
        case when coalesce((p_payload->>'anonymous_report')::boolean, false) then null
          else nullif(p_payload->>'reporter_employee_id', '')::uuid end,
        coalesce((p_payload->>'anonymous_report')::boolean, false),
        coalesce(nullif(p_payload->>'source', ''), 'hr'),
        coalesce(nullif(p_payload->>'severity', ''), 'medium'),
        coalesce(nullif(p_payload->>'confidentiality_level', ''), 'restricted'),
        'draft', btrim(p_payload->>'allegation_summary'),
        coalesce(p_payload->'attachment_urls', '[]'::jsonb),
        nullif(btrim(p_payload->>'external_reference'), ''),
        nullif(btrim(p_payload->>'remark'), '')
      ) returning * into v_case;
      perform app_private.hr_add_employee_relation_event(
        v_case, 'created', null, 'draft', '创建员工关系案件草稿'
      );
      return v_case.id;
    end if;

    if not app_private.can_execute_business_action(
      'HrEmployeeRelations', 'Hr:EmployeeRelations:Edit', v_id, false
    ) then
      raise exception '当前账号没有编辑员工关系案件的权限' using errcode = '42501';
    end if;
    select * into v_before from public.hr_employee_relation_case where id = v_id for update;
    if v_before.id is null or v_before.tenant_id <> v_tenant_id then
      raise exception '员工关系案件不存在或无权编辑';
    end if;
    if v_before.status not in ('draft', 'reported') then
      raise exception '案件完成分级后，核心资料只能通过受控动作更新';
    end if;
    update public.hr_employee_relation_case set
      case_type = p_payload->>'case_type',
      title = btrim(p_payload->>'title'),
      subject_employee_id = (p_payload->>'subject_employee_id')::uuid,
      reporter_employee_id = case
        when coalesce((p_payload->>'anonymous_report')::boolean, false) then null
        else nullif(p_payload->>'reporter_employee_id', '')::uuid end,
      anonymous_report = coalesce((p_payload->>'anonymous_report')::boolean, false),
      source = p_payload->>'source', severity = p_payload->>'severity',
      confidentiality_level = p_payload->>'confidentiality_level',
      allegation_summary = btrim(p_payload->>'allegation_summary'),
      attachment_urls = coalesce(p_payload->'attachment_urls', '[]'::jsonb),
      external_reference = nullif(btrim(p_payload->>'external_reference'), ''),
      remark = nullif(btrim(p_payload->>'remark'), '')
    where id = v_before.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'updated', v_before.status, v_case.status, '更新案件基础资料'
    );
    return v_case.id;
  end if;

  if not app_private.can_execute_business_action(
    'HrEmployeeRelations', 'Hr:EmployeeRelations:Action:Manage', v_id, false
  ) then
    raise exception '当前账号没有管理员工关系处置行动的权限' using errcode = '42501';
  end if;
  select * into v_case from public.hr_employee_relation_case
    where id = (p_payload->>'case_id')::uuid;
  if v_case.id is null or v_case.tenant_id <> v_tenant_id
    or v_case.status not in ('investigating', 'action_required') then
    raise exception '只有调查中或待处置案件可以维护处置行动';
  end if;
  if v_id is null then
    insert into public.hr_employee_relation_action(
      tenant_id, case_id, action_type, title, owner_employee_id, due_date, status, remark
    ) values (
      v_tenant_id, v_case.id, p_payload->>'action_type', btrim(p_payload->>'title'),
      (p_payload->>'owner_employee_id')::uuid, (p_payload->>'due_date')::date,
      'planned', nullif(btrim(p_payload->>'remark'), '')
    ) returning * into v_action;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'action_created', v_case.status, v_case.status,
      '创建处置行动', jsonb_build_object('action_id', v_action.id)
    );
    return v_action.id;
  end if;
  select * into v_action from public.hr_employee_relation_action where id = v_id for update;
  if v_action.id is null or v_action.tenant_id <> v_tenant_id
    or v_action.status <> 'planned' then
    raise exception '只有待开始的处置行动可以编辑';
  end if;
  update public.hr_employee_relation_action set
    action_type = p_payload->>'action_type', title = btrim(p_payload->>'title'),
    owner_employee_id = (p_payload->>'owner_employee_id')::uuid,
    due_date = (p_payload->>'due_date')::date,
    remark = nullif(btrim(p_payload->>'remark'), '')
  where id = v_action.id returning * into v_action;
  perform app_private.hr_add_employee_relation_event(
    v_case, 'action_updated', v_case.status, v_case.status,
    '更新处置行动', jsonb_build_object('action_id', v_action.id)
  );
  return v_action.id;
end
$function$;

create or replace function public.hr_transition_employee_relation_case_secure(
  p_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_case public.hr_employee_relation_case;
  v_from text;
  v_comment text := nullif(btrim(p_payload->>'comment'), '');
begin
  select * into v_case from public.hr_employee_relation_case where id = p_id for update;
  if v_case.id is null or not app_private.hr_employee_relation_case_visible(
    v_case.tenant_id, v_case.subject_employee_id, v_case.reporter_employee_id,
    v_case.owner_employee_id
  ) then
    raise exception '员工关系案件不存在或无权处理' using errcode = '42501';
  end if;
  v_from := v_case.status;

  if p_action = 'submit' then
    if not app_private.has_permission('Hr:EmployeeRelations:Edit') or v_case.status <> 'draft' then
      raise exception '当前案件不能提交报告';
    end if;
    update public.hr_employee_relation_case set status = 'reported', reported_at = now()
      where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'reported', v_from, v_case.status, v_comment
    );
  elsif p_action = 'triage' then
    if not app_private.has_permission('Hr:EmployeeRelations:Assign')
      or v_case.status not in ('reported', 'triaged') then
      raise exception '当前案件不能执行分派与分级';
    end if;
    if nullif(p_payload->>'owner_employee_id', '') is null
      or nullif(p_payload->>'target_resolution_date', '') is null then
      raise exception '分级时必须指定案件负责人和目标解决日期';
    end if;
    update public.hr_employee_relation_case set
      status = 'triaged', owner_employee_id = (p_payload->>'owner_employee_id')::uuid,
      severity = coalesce(nullif(p_payload->>'severity', ''), severity),
      confidentiality_level = coalesce(
        nullif(p_payload->>'confidentiality_level', ''), confidentiality_level
      ),
      target_resolution_date = (p_payload->>'target_resolution_date')::date,
      triaged_at = coalesce(triaged_at, now())
    where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, case when v_from = 'reported' then 'triaged' else 'assigned' end,
      v_from, v_case.status, v_comment,
      jsonb_build_object('owner_employee_id', v_case.owner_employee_id)
    );
  elsif p_action = 'start_investigation' then
    if not app_private.has_permission('Hr:EmployeeRelations:Investigate')
      or v_case.status <> 'triaged' then
      raise exception '只有已分级案件可以启动调查';
    end if;
    update public.hr_employee_relation_case set
      status = 'investigating', investigation_started_at = now()
    where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'investigation_started', v_from, v_case.status, v_comment
    );
  elsif p_action = 'require_action' then
    if not app_private.has_permission('Hr:EmployeeRelations:Investigate')
      or v_case.status <> 'investigating' then
      raise exception '只有调查中案件可以进入处置阶段';
    end if;
    if nullif(btrim(p_payload->>'findings_summary'), '') is null then
      raise exception '进入处置阶段前必须填写调查发现';
    end if;
    update public.hr_employee_relation_case set
      status = 'action_required', findings_summary = btrim(p_payload->>'findings_summary')
    where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'action_required', v_from, v_case.status, v_comment
    );
  elsif p_action = 'resolve' then
    if not app_private.has_permission('Hr:EmployeeRelations:Resolve')
      or v_case.status not in ('investigating', 'action_required') then
      raise exception '当前案件不能提交解决结论';
    end if;
    if nullif(p_payload->>'outcome', '') is null
      or nullif(btrim(p_payload->>'resolution_summary'), '') is null then
      raise exception '解决案件必须填写案件结论和解决摘要';
    end if;
    if exists (
      select 1 from public.hr_employee_relation_action action
      where action.case_id = v_case.id and action.tenant_id = v_case.tenant_id
        and action.status in ('planned', 'in_progress')
    ) then
      raise exception '仍有未完成的处置行动，不能解决案件';
    end if;
    update public.hr_employee_relation_case set
      status = 'resolved', outcome = p_payload->>'outcome',
      findings_summary = coalesce(
        nullif(btrim(p_payload->>'findings_summary'), ''), findings_summary
      ),
      resolution_summary = btrim(p_payload->>'resolution_summary'), resolved_at = now(),
      closed_at = null
    where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'resolved', v_from, v_case.status, v_comment
    );
  elsif p_action = 'close' then
    if not app_private.has_permission('Hr:EmployeeRelations:Close')
      or v_case.status <> 'resolved' then
      raise exception '只有已解决案件可以正式结案';
    end if;
    update public.hr_employee_relation_case set status = 'closed', closed_at = now()
      where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'closed', v_from, v_case.status, v_comment
    );
  elsif p_action = 'reopen' then
    if not app_private.has_permission('Hr:EmployeeRelations:Close')
      or v_case.status not in ('resolved', 'closed') or v_comment is null then
      raise exception '重新调查已解决案件时必须填写原因';
    end if;
    update public.hr_employee_relation_case set
      status = 'investigating', resolved_at = null, closed_at = null,
      outcome = null, resolution_summary = null
    where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'reopened', v_from, v_case.status, v_comment
    );
  elsif p_action = 'cancel' then
    if not app_private.has_permission('Hr:EmployeeRelations:Resolve')
      or v_case.status not in ('reported', 'triaged') or v_comment is null then
      raise exception '取消已报告案件时必须填写原因';
    end if;
    update public.hr_employee_relation_case set status = 'cancelled'
      where id = v_case.id returning * into v_case;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'cancelled', v_from, v_case.status, v_comment
    );
  elsif p_action = 'comment' then
    if not app_private.has_permission('Hr:EmployeeRelations:Investigate') or v_comment is null then
      raise exception '补充案件说明需要调查权限并填写内容';
    end if;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'commented', v_from, v_case.status, v_comment
    );
  else
    raise exception '不支持的员工关系案件动作';
  end if;
  return true;
end
$function$;

create or replace function public.hr_transition_employee_relation_action_secure(
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
  v_action public.hr_employee_relation_action;
  v_case public.hr_employee_relation_case;
  v_from text;
  v_comment text := nullif(btrim(p_comment), '');
  v_event_type text;
begin
  if not app_private.has_permission('Hr:EmployeeRelations:Action:Manage') then
    raise exception '当前账号没有管理员工关系处置行动的权限' using errcode = '42501';
  end if;
  select * into v_action from public.hr_employee_relation_action where id = p_id for update;
  if v_action.id is null then raise exception '处置行动不存在'; end if;
  select * into v_case from public.hr_employee_relation_case where id = v_action.case_id;
  if not app_private.hr_employee_relation_case_visible(
    v_case.tenant_id, v_case.subject_employee_id, v_case.reporter_employee_id,
    v_case.owner_employee_id
  ) then
    raise exception '处置行动不存在或无权处理' using errcode = '42501';
  end if;
  v_from := v_action.status;
  if p_action = 'start' and v_action.status = 'planned' then
    update public.hr_employee_relation_action set status = 'in_progress', started_at = now()
      where id = v_action.id returning * into v_action;
    v_event_type := 'action_started';
  elsif p_action = 'complete' and v_action.status in ('planned', 'in_progress') then
    if v_comment is null then raise exception '完成处置行动必须填写完成说明'; end if;
    update public.hr_employee_relation_action set
      status = 'completed', started_at = coalesce(started_at, now()),
      completed_at = now(), completion_note = v_comment
    where id = v_action.id returning * into v_action;
    v_event_type := 'action_completed';
  elsif p_action = 'cancel' and v_action.status in ('planned', 'in_progress') then
    if v_comment is null then raise exception '取消处置行动必须填写原因'; end if;
    update public.hr_employee_relation_action set status = 'cancelled', completion_note = v_comment
      where id = v_action.id returning * into v_action;
    v_event_type := 'action_cancelled';
  else
    raise exception '当前处置行动不能执行该动作';
  end if;
  perform app_private.hr_add_employee_relation_event(
    v_case, v_event_type, v_case.status, v_case.status, v_comment,
    jsonb_build_object('action_id', v_action.id, 'from_action_status', v_from,
      'to_action_status', v_action.status)
  );
  return true;
end
$function$;

create or replace function public.hr_delete_employee_relations_record_secure(
  p_kind text,
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_case public.hr_employee_relation_case;
  v_action public.hr_employee_relation_action;
begin
  if p_kind = 'case' then
    if not app_private.can_execute_business_action(
      'HrEmployeeRelations', 'Hr:EmployeeRelations:Delete', p_id, false
    ) then
      raise exception '当前账号没有删除案件草稿的权限' using errcode = '42501';
    end if;
    select * into v_case from public.hr_employee_relation_case where id = p_id for update;
    if v_case.id is null or v_case.status <> 'draft'
      or not app_private.hr_employee_relation_case_visible(
        v_case.tenant_id, v_case.subject_employee_id, v_case.reporter_employee_id,
        v_case.owner_employee_id
      ) then
      raise exception '只有有权访问的案件草稿可以删除';
    end if;
    delete from public.hr_employee_relation_case where id = v_case.id;
    return true;
  elsif p_kind = 'action' then
    if not app_private.has_permission('Hr:EmployeeRelations:Action:Manage') then
      raise exception '当前账号没有删除处置行动的权限' using errcode = '42501';
    end if;
    select * into v_action from public.hr_employee_relation_action where id = p_id for update;
    if v_action.id is null or v_action.status <> 'planned' then
      raise exception '只有待开始的处置行动可以删除';
    end if;
    select * into v_case from public.hr_employee_relation_case where id = v_action.case_id;
    if not app_private.hr_employee_relation_case_visible(
      v_case.tenant_id, v_case.subject_employee_id, v_case.reporter_employee_id,
      v_case.owner_employee_id
    ) then
      raise exception '处置行动不存在或无权删除' using errcode = '42501';
    end if;
    delete from public.hr_employee_relation_action where id = v_action.id;
    perform app_private.hr_add_employee_relation_event(
      v_case, 'action_cancelled', v_case.status, v_case.status,
      '删除尚未启动的处置行动', jsonb_build_object('action_id', v_action.id)
    );
    return true;
  end if;
  raise exception '不支持的员工关系记录类型';
end
$function$;

revoke all on function public.hr_employee_relations_overview_secure(uuid)
  from public, anon;
revoke all on function public.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) from public, anon;
revoke all on function public.hr_get_employee_relation_case_detail_secure(uuid)
  from public, anon;
revoke all on function public.hr_save_employee_relations_record_secure(text, jsonb)
  from public, anon;
revoke all on function public.hr_transition_employee_relation_case_secure(uuid, text, jsonb)
  from public, anon;
revoke all on function public.hr_transition_employee_relation_action_secure(uuid, text, text)
  from public, anon;
revoke all on function public.hr_delete_employee_relations_record_secure(text, uuid)
  from public, anon;

grant execute on function public.hr_employee_relations_overview_secure(uuid)
  to authenticated, service_role;
grant execute on function public.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) to authenticated, service_role;
grant execute on function public.hr_get_employee_relation_case_detail_secure(uuid)
  to authenticated, service_role;
grant execute on function public.hr_save_employee_relations_record_secure(text, jsonb)
  to authenticated, service_role;
grant execute on function public.hr_transition_employee_relation_case_secure(uuid, text, jsonb)
  to authenticated, service_role;
grant execute on function public.hr_transition_employee_relation_action_secure(uuid, text, text)
  to authenticated, service_role;
grant execute on function public.hr_delete_employee_relations_record_secure(text, uuid)
  to authenticated, service_role;

;
