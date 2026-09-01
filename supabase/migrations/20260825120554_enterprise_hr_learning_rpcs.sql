create or replace function public.hr_learning_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrTalentDevelopment', 'Hr:Talent:View', null, false) then
    raise exception '当前账号没有查看学习发展工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  update public.hr_learning_certificate
  set status = 'expired'
  where status = 'valid' and expires_on is not null and expires_on < current_date
    and (p_tenant_id is null or tenant_id = p_tenant_id);

  return jsonb_build_object(
    'published_course_count', (
      select count(*) from public.hr_learning_course c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status = 'published'
    ),
    'open_session_count', (
      select count(*) from public.hr_learning_session s
      where (p_tenant_id is null or s.tenant_id = p_tenant_id)
        and s.status in ('open', 'in_progress')
    ),
    'active_learner_count', (
      select count(distinct e.employee_id) from public.hr_training_enrollment e
      where (p_tenant_id is null or e.tenant_id = p_tenant_id)
        and e.status in ('enrolled', 'attending') and e.session_id is not null
    ),
    'completion_rate', (
      select coalesce(round(
        100 * count(*) filter (where e.status = 'passed')::numeric
        / nullif(count(*) filter (where e.status in ('passed', 'failed', 'no_show')), 0), 1
      ), 0)
      from public.hr_training_enrollment e
      where (p_tenant_id is null or e.tenant_id = p_tenant_id) and e.session_id is not null
    ),
    'expiring_certificate_count', (
      select count(*) from public.hr_learning_certificate c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and c.status = 'valid' and c.expires_on between current_date and current_date + 60
    ),
    'budget_execution_rate', (
      select coalesce(round(100 * sum(coalesce(p.actual_cost, 0)) / nullif(sum(coalesce(p.budget, 0)), 0), 1), 0)
      from public.hr_training_plan p
      where (p_tenant_id is null or p.tenant_id = p_tenant_id)
        and p.status in ('published', 'in_progress', 'completed')
    )
  );
end
$function$;

create or replace function public.hr_list_learning_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
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
  if p_kind not in ('plan', 'course', 'session', 'enrollment', 'certificate', 'course_competency') then
    raise exception '不支持的学习发展记录类型';
  end if;
  if not app_private.can_execute_business_action('HrTalentDevelopment', 'Hr:Talent:View', null, false) then
    raise exception '当前账号没有查看学习发展工作台的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'plan' then
    with filtered as materialized (
      select p.*, owner.employee_no owner_no, owner.employee_name owner_name,
        (select count(*) from public.hr_learning_session s where s.plan_id = p.id) session_count,
        (select count(*) from public.hr_training_enrollment e where e.plan_id = p.id and e.session_id is not null) learner_count
      from public.hr_training_plan p
      left join public.hr_employee owner on owner.id = p.owner_employee_id and owner.tenant_id = p.tenant_id
      where (p_tenant_id is null or p.tenant_id = p_tenant_id)
        and (p_status is null or p.status = p_status)
        and (v_keyword is null or p.plan_code ilike '%' || v_keyword || '%'
          or p.plan_name ilike '%' || v_keyword || '%' or owner.employee_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by start_date desc, plan_code offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'owner_no' - 'owner_name') || jsonb_build_object(
          'owner', case when owner_employee_id is null then null else jsonb_build_object(
            'id', owner_employee_id, 'code', owner_no, 'name', owner_name
          ) end
        ) order by start_date desc, plan_code
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'course' then
    with filtered as materialized (
      select c.*,
        (select count(*) from public.hr_learning_session s where s.course_id = c.id) session_count,
        (select count(*) from public.hr_learning_course_competency cc where cc.course_id = c.id) competency_count
      from public.hr_learning_course c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id)
        and (p_status is null or c.status = p_status)
        and (v_keyword is null or c.course_code ilike '%' || v_keyword || '%'
          or c.course_name ilike '%' || v_keyword || '%' or c.provider_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by course_code offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(paged) order by course_code), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'session' then
    with filtered as materialized (
      select s.*, p.plan_code, p.plan_name, c.course_code, c.course_name,
        (select count(*) from public.hr_training_enrollment e where e.session_id = s.id) enrollment_count,
        (select count(*) from public.hr_training_enrollment e where e.session_id = s.id and e.status = 'passed') passed_count
      from public.hr_learning_session s
      join public.hr_training_plan p on p.id = s.plan_id and p.tenant_id = s.tenant_id
      join public.hr_learning_course c on c.id = s.course_id and c.tenant_id = s.tenant_id
      where (p_tenant_id is null or s.tenant_id = p_tenant_id)
        and (p_status is null or s.status = p_status)
        and (v_keyword is null or s.session_code ilike '%' || v_keyword || '%'
          or p.plan_name ilike '%' || v_keyword || '%' or c.course_name ilike '%' || v_keyword || '%'
          or s.instructor_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by start_at desc, session_code offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'plan_code' - 'plan_name' - 'course_code' - 'course_name')
        || jsonb_build_object(
          'plan', jsonb_build_object('id', plan_id, 'code', plan_code, 'name', plan_name),
          'course', jsonb_build_object('id', course_id, 'code', course_code, 'name', course_name)
        ) order by start_at desc, session_code
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'enrollment' then
    with filtered as materialized (
      select e.*, employee.employee_no, employee.employee_name,
        s.session_code, s.start_at, s.end_at,
        p.plan_code, p.plan_name, c.id course_id, c.course_code, c.course_name,
        nominator.employee_no nominator_no, nominator.employee_name nominator_name
      from public.hr_training_enrollment e
      join public.hr_employee employee on employee.id = e.employee_id and employee.tenant_id = e.tenant_id
      left join public.hr_learning_session s on s.id = e.session_id and s.tenant_id = e.tenant_id
      join public.hr_training_plan p on p.id = e.plan_id and p.tenant_id = e.tenant_id
      left join public.hr_learning_course c on c.id = s.course_id and c.tenant_id = e.tenant_id
      left join public.hr_employee nominator on nominator.id = e.nominated_by_employee_id and nominator.tenant_id = e.tenant_id
      where e.session_id is not null and (p_tenant_id is null or e.tenant_id = p_tenant_id)
        and (p_status is null or e.status = p_status)
        and (v_keyword is null or employee.employee_no ilike '%' || v_keyword || '%'
          or employee.employee_name ilike '%' || v_keyword || '%' or s.session_code ilike '%' || v_keyword || '%'
          or c.course_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by start_at desc, employee_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'employee_no' - 'employee_name' - 'session_code' - 'start_at' - 'end_at'
          - 'plan_code' - 'plan_name' - 'course_code' - 'course_name' - 'nominator_no' - 'nominator_name')
        || jsonb_build_object(
          'employee', jsonb_build_object('id', employee_id, 'code', employee_no, 'name', employee_name),
          'session', jsonb_build_object('id', session_id, 'code', session_code, 'start_at', start_at, 'end_at', end_at),
          'plan', jsonb_build_object('id', plan_id, 'code', plan_code, 'name', plan_name),
          'course', jsonb_build_object('id', course_id, 'code', course_code, 'name', course_name),
          'nominator', case when nominated_by_employee_id is null then null else jsonb_build_object(
            'id', nominated_by_employee_id, 'code', nominator_no, 'name', nominator_name
          ) end
        ) order by start_at desc, employee_no
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'certificate' then
    with filtered as materialized (
      select cert.*, employee.employee_no, employee.employee_name, c.course_code, c.course_name
      from public.hr_learning_certificate cert
      join public.hr_employee employee on employee.id = cert.employee_id and employee.tenant_id = cert.tenant_id
      join public.hr_learning_course c on c.id = cert.course_id and c.tenant_id = cert.tenant_id
      where (p_tenant_id is null or cert.tenant_id = p_tenant_id)
        and (p_status is null or cert.status = p_status)
        and (v_keyword is null or cert.certificate_no ilike '%' || v_keyword || '%'
          or employee.employee_no ilike '%' || v_keyword || '%' or employee.employee_name ilike '%' || v_keyword || '%'
          or c.course_name ilike '%' || v_keyword || '%')
    ), paged as (
      select * from filtered order by issued_on desc, certificate_no offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'employee_no' - 'employee_name' - 'course_code' - 'course_name')
        || jsonb_build_object(
          'employee', jsonb_build_object('id', employee_id, 'code', employee_no, 'name', employee_name),
          'course', jsonb_build_object('id', course_id, 'code', course_code, 'name', course_name)
        ) order by issued_on desc, certificate_no
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  with filtered as materialized (
    select cc.*, c.course_code, c.course_name, competency.competency_code, competency.competency_name
    from public.hr_learning_course_competency cc
    join public.hr_learning_course c on c.id = cc.course_id and c.tenant_id = cc.tenant_id
    join public.hr_competency competency on competency.id = cc.competency_id and competency.tenant_id = cc.tenant_id
    where (p_tenant_id is null or cc.tenant_id = p_tenant_id)
      and (v_keyword is null or c.course_code ilike '%' || v_keyword || '%'
        or c.course_name ilike '%' || v_keyword || '%' or competency.competency_code ilike '%' || v_keyword || '%'
        or competency.competency_name ilike '%' || v_keyword || '%')
  ), paged as (
    select * from filtered order by course_code, competency_code offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(
      (to_jsonb(paged) - 'course_code' - 'course_name' - 'competency_code' - 'competency_name')
      || jsonb_build_object(
        'course', jsonb_build_object('id', course_id, 'code', course_code, 'name', course_name),
        'competency', jsonb_build_object('id', competency_id, 'code', competency_code, 'name', competency_name)
      ) order by course_code, competency_code
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_list_learning_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrTalentDevelopment', 'Hr:Talent:View', null, false) then
    raise exception '当前账号没有查看学习发展选项的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'plan' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'tenant_id', p.tenant_id, 'code', p.plan_code, 'name', p.plan_name, 'status', p.status
    ) order by p.plan_code), '[]'::jsonb) into v_result
    from public.hr_training_plan p
    where (p_tenant_id is null or p.tenant_id = p_tenant_id) and p.status in ('published', 'in_progress');
  elsif p_kind = 'course' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'code', c.course_code, 'name', c.course_name,
      'status', c.status, 'duration_hours', c.duration_hours
    ) order by c.course_code), '[]'::jsonb) into v_result
    from public.hr_learning_course c
    where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status = 'published';
  elsif p_kind = 'session' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'tenant_id', s.tenant_id, 'code', s.session_code, 'name', c.course_name,
      'plan_id', s.plan_id, 'course_id', s.course_id, 'start_at', s.start_at, 'status', s.status
    ) order by s.start_at), '[]'::jsonb) into v_result
    from public.hr_learning_session s
    join public.hr_learning_course c on c.id = s.course_id and c.tenant_id = s.tenant_id
    where (p_tenant_id is null or s.tenant_id = p_tenant_id) and s.status = 'open';
  elsif p_kind = 'competency' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'code', c.competency_code, 'name', c.competency_name
    ) order by c.competency_code), '[]'::jsonb) into v_result
    from public.hr_competency c
    where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.enabled;
  else
    raise exception '不支持的学习发展选项类型';
  end if;
  return v_result;
end
$function$;

create or replace function public.hr_save_learning_record_secure(
  p_kind text,
  p_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_tenant_id uuid;
  v_permission text;
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_session public.hr_learning_session%rowtype;
begin
  v_tenant_id := case when app_private.is_platform_super()
    then coalesce((p_payload ->> 'tenant_id')::uuid, v_current_tenant)
    else v_current_tenant end;
  if v_tenant_id is null then raise exception '必须指定所属租户'; end if;

  v_permission := case p_kind
    when 'plan' then case when p_id is null then 'Hr:Talent:Add' else 'Hr:Talent:Edit' end
    when 'course' then case when p_id is null then 'Hr:Talent:Course:Add' else 'Hr:Talent:Course:Edit' end
    when 'session' then case when p_id is null then 'Hr:Talent:Session:Add' else 'Hr:Talent:Session:Edit' end
    when 'enrollment' then case when p_id is null then 'Hr:Talent:Enrollment:Add' else 'Hr:Talent:Enrollment:Manage' end
    when 'course_competency' then 'Hr:Talent:Course:Competency'
    when 'certificate' then 'Hr:Talent:Certificate:Manage'
    else null end;
  if v_permission is null then raise exception '不支持的学习发展记录类型'; end if;
  if not app_private.can_execute_business_action('HrTalentDevelopment', v_permission, null, false) then
    raise exception '当前账号没有维护该学习发展记录的权限' using errcode = '42501';
  end if;

  if p_kind = 'plan' then
    if p_id is not null and not exists (
      select 1 from public.hr_training_plan where id = p_id and tenant_id = v_tenant_id and status = 'draft'
    ) then raise exception '仅草稿培训计划允许编辑'; end if;
    insert into public.hr_training_plan(
      id, tenant_id, plan_code, plan_name, training_type, start_date, end_date,
      provider_name, budget, status, objective, remark, owner_employee_id, target_audience, mandatory
    ) values (
      v_id, v_tenant_id, btrim(p_payload ->> 'plan_code'), btrim(p_payload ->> 'plan_name'),
      p_payload ->> 'training_type', (p_payload ->> 'start_date')::date,
      nullif(p_payload ->> 'end_date', '')::date, nullif(btrim(p_payload ->> 'provider_name'), ''),
      nullif(p_payload ->> 'budget', '')::numeric, 'draft', nullif(btrim(p_payload ->> 'objective'), ''),
      nullif(btrim(p_payload ->> 'remark'), ''), nullif(p_payload ->> 'owner_employee_id', '')::uuid,
      nullif(btrim(p_payload ->> 'target_audience'), ''), coalesce((p_payload ->> 'mandatory')::boolean, false)
    ) on conflict (id) do update set
      plan_code = excluded.plan_code, plan_name = excluded.plan_name, training_type = excluded.training_type,
      start_date = excluded.start_date, end_date = excluded.end_date, provider_name = excluded.provider_name,
      budget = excluded.budget, objective = excluded.objective, remark = excluded.remark,
      owner_employee_id = excluded.owner_employee_id, target_audience = excluded.target_audience,
      mandatory = excluded.mandatory;
    return v_id;
  end if;

  if p_kind = 'course' then
    if p_id is not null and not exists (
      select 1 from public.hr_learning_course where id = p_id and tenant_id = v_tenant_id and status = 'draft'
    ) then raise exception '仅草稿课程允许编辑'; end if;
    insert into public.hr_learning_course(
      id, tenant_id, course_code, course_name, category, delivery_mode, duration_hours, credit_hours,
      provider_name, passing_score, minimum_attendance_percent, certificate_enabled,
      certificate_valid_months, status, description, learning_objectives, target_audience
    ) values (
      v_id, v_tenant_id, btrim(p_payload ->> 'course_code'), btrim(p_payload ->> 'course_name'),
      p_payload ->> 'category', p_payload ->> 'delivery_mode', (p_payload ->> 'duration_hours')::numeric,
      coalesce(nullif(p_payload ->> 'credit_hours', '')::numeric, 0), nullif(btrim(p_payload ->> 'provider_name'), ''),
      nullif(p_payload ->> 'passing_score', '')::numeric,
      coalesce(nullif(p_payload ->> 'minimum_attendance_percent', '')::numeric, 80),
      coalesce((p_payload ->> 'certificate_enabled')::boolean, false),
      nullif(p_payload ->> 'certificate_valid_months', '')::integer, 'draft',
      nullif(btrim(p_payload ->> 'description'), ''), nullif(btrim(p_payload ->> 'learning_objectives'), ''),
      nullif(btrim(p_payload ->> 'target_audience'), '')
    ) on conflict (id) do update set
      course_code = excluded.course_code, course_name = excluded.course_name, category = excluded.category,
      delivery_mode = excluded.delivery_mode, duration_hours = excluded.duration_hours,
      credit_hours = excluded.credit_hours, provider_name = excluded.provider_name,
      passing_score = excluded.passing_score, minimum_attendance_percent = excluded.minimum_attendance_percent,
      certificate_enabled = excluded.certificate_enabled, certificate_valid_months = excluded.certificate_valid_months,
      description = excluded.description, learning_objectives = excluded.learning_objectives,
      target_audience = excluded.target_audience;
    return v_id;
  end if;

  if p_kind = 'session' then
    if p_id is not null and not exists (
      select 1 from public.hr_learning_session where id = p_id and tenant_id = v_tenant_id and status = 'planned'
    ) then raise exception '仅待开放班次允许编辑'; end if;
    if not exists (
      select 1 from public.hr_training_plan where id = (p_payload ->> 'plan_id')::uuid
        and tenant_id = v_tenant_id and status in ('published', 'in_progress')
    ) then raise exception '培训计划尚未发布'; end if;
    if not exists (
      select 1 from public.hr_learning_course where id = (p_payload ->> 'course_id')::uuid
        and tenant_id = v_tenant_id and status = 'published'
    ) then raise exception '课程尚未发布'; end if;
    insert into public.hr_learning_session(
      id, tenant_id, session_code, plan_id, course_id, start_at, end_at, enrollment_deadline,
      capacity, instructor_name, location, meeting_url, estimated_cost, status
    ) values (
      v_id, v_tenant_id, btrim(p_payload ->> 'session_code'), (p_payload ->> 'plan_id')::uuid,
      (p_payload ->> 'course_id')::uuid, (p_payload ->> 'start_at')::timestamptz,
      (p_payload ->> 'end_at')::timestamptz, nullif(p_payload ->> 'enrollment_deadline', '')::timestamptz,
      coalesce((p_payload ->> 'capacity')::integer, 30), nullif(btrim(p_payload ->> 'instructor_name'), ''),
      nullif(btrim(p_payload ->> 'location'), ''), nullif(btrim(p_payload ->> 'meeting_url'), ''),
      nullif(p_payload ->> 'estimated_cost', '')::numeric, 'planned'
    ) on conflict (id) do update set
      session_code = excluded.session_code, plan_id = excluded.plan_id, course_id = excluded.course_id,
      start_at = excluded.start_at, end_at = excluded.end_at, enrollment_deadline = excluded.enrollment_deadline,
      capacity = excluded.capacity, instructor_name = excluded.instructor_name, location = excluded.location,
      meeting_url = excluded.meeting_url, estimated_cost = excluded.estimated_cost;
    return v_id;
  end if;

  if p_kind = 'enrollment' then
    if p_id is not null and not exists (
      select 1 from public.hr_training_enrollment where id = p_id and tenant_id = v_tenant_id and status = 'enrolled'
    ) then raise exception '仅已报名记录允许编辑'; end if;
    select * into v_session from public.hr_learning_session
    where id = (p_payload ->> 'session_id')::uuid and tenant_id = v_tenant_id and status = 'open';
    if not found then raise exception '班次当前不可报名'; end if;
    if not exists (
      select 1 from public.hr_employee where id = (p_payload ->> 'employee_id')::uuid and tenant_id = v_tenant_id
    ) then raise exception '员工不属于当前租户'; end if;
    if p_id is null and (
      select count(*) from public.hr_training_enrollment where session_id = v_session.id and status <> 'withdrawn'
    ) >= v_session.capacity then raise exception '班次名额已满'; end if;
    insert into public.hr_training_enrollment(
      id, tenant_id, plan_id, session_id, employee_id, status, nominated_by_employee_id, remark
    ) values (
      v_id, v_tenant_id, v_session.plan_id, v_session.id, (p_payload ->> 'employee_id')::uuid,
      'enrolled', nullif(p_payload ->> 'nominated_by_employee_id', '')::uuid,
      nullif(btrim(p_payload ->> 'remark'), '')
    ) on conflict (id) do update set
      employee_id = excluded.employee_id, nominated_by_employee_id = excluded.nominated_by_employee_id,
      remark = excluded.remark;
    return v_id;
  end if;

  if p_kind = 'course_competency' then
    if not exists (
      select 1 from public.hr_learning_course where id = (p_payload ->> 'course_id')::uuid
        and tenant_id = v_tenant_id and status = 'draft'
    ) then raise exception '仅草稿课程允许维护能力映射'; end if;
    insert into public.hr_learning_course_competency(
      id, tenant_id, course_id, competency_id, target_level
    ) values (
      v_id, v_tenant_id, (p_payload ->> 'course_id')::uuid,
      (p_payload ->> 'competency_id')::uuid, p_payload ->> 'target_level'
    ) on conflict (id) do update set
      course_id = excluded.course_id, competency_id = excluded.competency_id, target_level = excluded.target_level;
    return v_id;
  end if;

  if p_id is null then raise exception '证书只能由学习完成结果自动生成'; end if;
  update public.hr_learning_certificate
  set credential_url = nullif(btrim(p_payload ->> 'credential_url'), '')
  where id = p_id and tenant_id = v_tenant_id and status = 'valid';
  if not found then raise exception '仅有效证书允许维护凭证地址'; end if;
  return p_id;
end
$function$;

create or replace function public.hr_transition_learning_record_secure(
  p_kind text,
  p_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_permission text;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_course public.hr_learning_course%rowtype;
  v_session public.hr_learning_session%rowtype;
  v_enrollment public.hr_training_enrollment%rowtype;
  v_status text;
  v_certificate_no text;
begin
  v_permission := case p_kind
    when 'plan' then 'Hr:Talent:Plan:Transition'
    when 'course' then 'Hr:Talent:Course:Publish'
    when 'session' then 'Hr:Talent:Session:Transition'
    when 'enrollment' then 'Hr:Talent:Enrollment:Manage'
    when 'certificate' then 'Hr:Talent:Certificate:Manage'
    else null end;
  if v_permission is null then raise exception '不支持的学习发展状态类型'; end if;
  if not app_private.can_execute_business_action('HrTalentDevelopment', v_permission, null, false) then
    raise exception '当前账号没有推进该学习发展状态的权限' using errcode = '42501';
  end if;

  if p_kind = 'plan' then
    select status into v_status from public.hr_training_plan
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '培训计划不存在'; end if;
    if not ((v_status = 'draft' and p_action = 'publish')
      or (v_status = 'published' and p_action in ('start', 'cancel'))
      or (v_status = 'in_progress' and p_action in ('complete', 'cancel'))) then
      raise exception '培训计划状态不允许执行该操作';
    end if;
    update public.hr_training_plan set
      status = case p_action when 'publish' then 'published' when 'start' then 'in_progress'
        when 'complete' then 'completed' else 'cancelled' end,
      approved_by = case when p_action = 'publish' then public.get_app_user_display_name() else approved_by end,
      approved_at = case when p_action = 'publish' then now() else approved_at end,
      actual_cost = case when p_action = 'complete' then coalesce(
        (select sum(coalesce(actual_cost, estimated_cost, 0)) from public.hr_learning_session where plan_id = p_id), 0
      ) else actual_cost end
    where id = p_id;
    return true;
  end if;

  if p_kind = 'course' then
    select * into v_course from public.hr_learning_course
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '课程不存在'; end if;
    if not ((v_course.status = 'draft' and p_action = 'publish')
      or (v_course.status = 'published' and p_action = 'retire')) then
      raise exception '课程状态不允许执行该操作';
    end if;
    if p_action = 'publish' and nullif(btrim(v_course.learning_objectives), '') is null then
      raise exception '发布课程前必须维护学习目标';
    end if;
    update public.hr_learning_course set status = case when p_action = 'publish' then 'published' else 'retired' end
    where id = p_id;
    return true;
  end if;

  if p_kind = 'session' then
    select * into v_session from public.hr_learning_session
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '培训班次不存在'; end if;
    if not ((v_session.status = 'planned' and p_action in ('open', 'cancel'))
      or (v_session.status = 'open' and p_action in ('start', 'cancel'))
      or (v_session.status = 'in_progress' and p_action in ('complete', 'cancel'))) then
      raise exception '培训班次状态不允许执行该操作';
    end if;
    if p_action = 'complete' and exists (
      select 1 from public.hr_training_enrollment
      where session_id = p_id and status in ('enrolled', 'attending')
    ) then raise exception '仍有学员未登记最终学习结果'; end if;
    update public.hr_learning_session set
      status = case p_action when 'open' then 'open' when 'start' then 'in_progress'
        when 'complete' then 'completed' else 'cancelled' end,
      actual_cost = case when p_action = 'complete' then coalesce(
        nullif(p_payload ->> 'actual_cost', '')::numeric, estimated_cost, 0
      ) else actual_cost end,
      completion_note = case when p_action in ('complete', 'cancel')
        then nullif(btrim(p_payload ->> 'comment'), '') else completion_note end
    where id = p_id;
    return true;
  end if;

  if p_kind = 'enrollment' then
    select * into v_enrollment from public.hr_training_enrollment
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found or v_enrollment.session_id is null then raise exception '学习报名记录不存在'; end if;
    select * into v_session from public.hr_learning_session where id = v_enrollment.session_id;
    select * into v_course from public.hr_learning_course where id = v_session.course_id;
    if not ((v_enrollment.status = 'enrolled' and p_action in ('attend', 'pass', 'fail', 'withdraw', 'no_show'))
      or (v_enrollment.status = 'attending' and p_action in ('pass', 'fail', 'withdraw', 'no_show'))) then
      raise exception '学习参与状态不允许执行该操作';
    end if;
    if p_action in ('pass', 'fail') and nullif(p_payload ->> 'attendance_percent', '') is null then
      raise exception '登记学习结果时必须填写出勤率';
    end if;
    if p_action = 'pass' and (p_payload ->> 'attendance_percent')::numeric < v_course.minimum_attendance_percent then
      raise exception '出勤率未达到课程通过标准';
    end if;
    if p_action = 'pass' and v_course.passing_score is not null
      and coalesce(nullif(p_payload ->> 'score', '')::numeric, -1) < v_course.passing_score then
      raise exception '成绩未达到课程通过标准';
    end if;

    update public.hr_training_enrollment set
      status = case p_action when 'attend' then 'attending' when 'pass' then 'passed'
        when 'fail' then 'failed' when 'withdraw' then 'withdrawn' else 'no_show' end,
      attendance_percent = case when p_action in ('pass', 'fail', 'no_show')
        then coalesce(nullif(p_payload ->> 'attendance_percent', '')::numeric, 0) else attendance_percent end,
      score = case when p_action in ('pass', 'fail') then nullif(p_payload ->> 'score', '')::numeric else score end,
      result = case when p_action = 'pass' then 'passed' when p_action = 'fail' then 'failed' else result end,
      completion_comment = nullif(btrim(p_payload ->> 'comment'), ''),
      completed_at = case when p_action = 'attend' then null else now() end
    where id = p_id;

    if p_action = 'pass' then
      if v_course.certificate_enabled then
        v_certificate_no := 'CERT-' || to_char(current_date, 'YYYY') || '-'
          || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
        insert into public.hr_learning_certificate(
          tenant_id, enrollment_id, employee_id, course_id, certificate_no, certificate_name,
          issued_on, expires_on, status
        ) values (
          v_enrollment.tenant_id, v_enrollment.id, v_enrollment.employee_id, v_course.id,
          v_certificate_no, v_course.course_name || ' 完成证书', current_date,
          case when v_course.certificate_valid_months is null then null
            else (current_date + make_interval(months => v_course.certificate_valid_months))::date end,
          'valid'
        ) on conflict (tenant_id, enrollment_id) do nothing;
        update public.hr_training_enrollment set certificate_no = coalesce(certificate_no, v_certificate_no) where id = p_id;
      end if;

      insert into public.hr_employee_training(
        tenant_id, employee_id, training_name, training_type, provider_name,
        start_date, end_date, training_result, certificate_name, certificate_no, cost, remark
      ) values (
        v_enrollment.tenant_id, v_enrollment.employee_id, v_course.course_name, v_course.category,
        v_course.provider_name, v_session.start_at::date, v_session.end_at::date, 'passed',
        case when v_course.certificate_enabled then v_course.course_name || ' 完成证书' else null end,
        case when v_course.certificate_enabled then v_certificate_no else null end,
        null, '由学习发展闭环自动回写，班次：' || v_session.session_code
      );

      insert into public.hr_employee_competency(
        tenant_id, employee_id, competency_id, current_level, assessed_date, assessor_user_id, evidence
      )
      select mapping.tenant_id, v_enrollment.employee_id, mapping.competency_id,
        mapping.target_level, current_date, null,
        '完成课程 ' || v_course.course_code || ' / 班次 ' || v_session.session_code
      from public.hr_learning_course_competency mapping
      where mapping.course_id = v_course.id
      on conflict (tenant_id, employee_id, competency_id) do update set
        current_level = excluded.current_level, assessed_date = excluded.assessed_date,
        assessor_user_id = null, evidence = excluded.evidence;
    end if;
    return true;
  end if;

  if p_action <> 'revoke' or nullif(btrim(p_payload ->> 'comment'), '') is null then
    raise exception '撤销证书必须填写原因';
  end if;
  update public.hr_learning_certificate set
    status = 'revoked', revoked_reason = btrim(p_payload ->> 'comment'), revoked_at = now()
  where id = p_id and status = 'valid'
    and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  if not found then raise exception '仅有效证书允许撤销'; end if;
  return true;
end
$function$;

create or replace function public.hr_delete_learning_record_secure(p_kind text, p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text;
begin
  v_permission := case p_kind
    when 'plan' then 'Hr:Talent:Delete'
    when 'course' then 'Hr:Talent:Course:Edit'
    when 'session' then 'Hr:Talent:Session:Edit'
    when 'enrollment' then 'Hr:Talent:Enrollment:Manage'
    when 'course_competency' then 'Hr:Talent:Course:Competency'
    else null end;
  if v_permission is null then raise exception '不支持删除该记录'; end if;
  if not app_private.can_execute_business_action('HrTalentDevelopment', v_permission, null, false) then
    raise exception '当前账号没有删除该记录的权限' using errcode = '42501';
  end if;
  if p_kind = 'plan' then
    delete from public.hr_training_plan where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'course' then
    delete from public.hr_learning_course where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'session' then
    delete from public.hr_learning_session where id = p_id and status = 'planned'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'enrollment' then
    delete from public.hr_training_enrollment where id = p_id and status = 'enrolled'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  else
    delete from public.hr_learning_course_competency where id = p_id
      and (app_private.is_platform_super() or tenant_id = v_tenant_id)
      and exists (
        select 1 from public.hr_learning_course c
        where c.id = hr_learning_course_competency.course_id and c.status = 'draft'
      );
  end if;
  if not found then raise exception '记录不存在或当前状态不允许删除'; end if;
  return true;
end
$function$;

revoke all on function public.hr_learning_overview_secure(uuid) from public, anon;
revoke all on function public.hr_list_learning_records_secure(text, integer, integer, text, text, uuid) from public, anon;
revoke all on function public.hr_list_learning_options_secure(text, uuid) from public, anon;
revoke all on function public.hr_save_learning_record_secure(text, uuid, jsonb) from public, anon;
revoke all on function public.hr_transition_learning_record_secure(text, uuid, text, jsonb) from public, anon;
revoke all on function public.hr_delete_learning_record_secure(text, uuid) from public, anon;
grant execute on function public.hr_learning_overview_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_learning_records_secure(text, integer, integer, text, text, uuid) to authenticated, service_role;
grant execute on function public.hr_list_learning_options_secure(text, uuid) to authenticated, service_role;
grant execute on function public.hr_save_learning_record_secure(text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.hr_transition_learning_record_secure(text, uuid, text, jsonb) to authenticated, service_role;
grant execute on function public.hr_delete_learning_record_secure(text, uuid) to authenticated, service_role;

;
