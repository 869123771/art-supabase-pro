create or replace function app_private.hr_experience_insights_visible()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or app_private.has_permission('Hr:Experience:Insights:View')
$function$;

revoke all on function app_private.hr_experience_insights_visible()
  from public, anon, authenticated;

create or replace function app_private.hr_experience_comments_visible()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or app_private.has_permission('Hr:Experience:Comments:View')
$function$;

revoke all on function app_private.hr_experience_comments_visible()
  from public, anon, authenticated;

create or replace function app_private.hr_add_experience_event(
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
  insert into public.hr_experience_event(
    tenant_id, entity_type, entity_id, event_type, from_status, to_status,
    summary, payload, actor_user_id, actor_name
  ) values (
    p_tenant_id, p_entity_type, p_entity_id, p_event_type,
    p_from_status, p_to_status, p_summary, coalesce(p_payload, '{}'::jsonb),
    app_private.current_app_user_id(), public.get_app_user_display_name()
  );
end
$function$;

revoke all on function app_private.hr_add_experience_event(
  uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;

create or replace function public.hr_employee_experience_overview_secure(
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
  v_insights boolean := app_private.hr_experience_insights_visible();
  v_comments boolean := app_private.hr_experience_comments_visible();
  v_respond boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:Experience:Respond');
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrEmployeeExperience', 'Hr:Experience:View', null, false
  ) then raise exception '当前账号没有查看员工体验工作台的权限' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'open_survey_count', case when v_insights then (
      select count(*) from public.hr_experience_survey survey
      where (p_tenant_id is null or survey.tenant_id = p_tenant_id)
        and survey.status = 'open'
    ) when v_respond and v_employee_id is not null then (
      select count(*) from public.hr_experience_participant participant
      join public.hr_experience_survey survey on survey.id = participant.survey_id
        and survey.tenant_id = participant.tenant_id
      where participant.tenant_id = v_tenant_id
        and participant.employee_id = v_employee_id
        and participant.status = 'invited' and survey.status = 'open'
        and current_date between survey.start_date and survey.end_date
    ) else 0 end,
    'my_pending_count', case when v_respond and v_employee_id is not null then (
      select count(*) from public.hr_experience_participant participant
      join public.hr_experience_survey survey on survey.id = participant.survey_id
        and survey.tenant_id = participant.tenant_id
      where participant.tenant_id = v_tenant_id
        and participant.employee_id = v_employee_id
        and participant.status = 'invited' and survey.status = 'open'
        and current_date between survey.start_date and survey.end_date
    ) else 0 end,
    'participant_count', case when v_insights then (
      select count(*) from public.hr_experience_participant participant
      where p_tenant_id is null or participant.tenant_id = p_tenant_id
    ) else 0 end,
    'completed_count', case when v_insights then (
      select count(*) from public.hr_experience_participant participant
      where (p_tenant_id is null or participant.tenant_id = p_tenant_id)
        and participant.status = 'completed'
    ) else 0 end,
    'response_rate', case when v_insights then (
      select case when count(*) = 0 then 0
        else round(100.0 * count(*) filter (where participant.status = 'completed') / count(*), 1)
      end
      from public.hr_experience_participant participant
      where p_tenant_id is null or participant.tenant_id = p_tenant_id
    ) else null end,
    'low_dimension_count', case when v_insights then (
      with dimension_scores as (
        select response.survey_id, question.dimension,
          count(distinct response.id) respondent_count,
          avg(case when question.answer_type = 'rating_5'
            then (answer.numeric_score - 1) * 25
            else answer.numeric_score * 10 end) score_percent,
          max(survey.minimum_group_size) minimum_group_size
        from public.hr_experience_answer answer
        join public.hr_experience_response response on response.id = answer.response_id
          and response.tenant_id = answer.tenant_id
        join public.hr_experience_question question on question.id = answer.question_id
          and question.tenant_id = answer.tenant_id
        join public.hr_experience_survey survey on survey.id = response.survey_id
          and survey.tenant_id = response.tenant_id
        where (p_tenant_id is null or response.tenant_id = p_tenant_id)
          and answer.numeric_score is not null
        group by response.survey_id, question.dimension
      )
      select count(*) from dimension_scores
      where respondent_count >= minimum_group_size and score_percent < 60
    ) else 0 end,
    'open_action_count', case when v_insights then (
      select count(*) from public.hr_experience_action action
      where (p_tenant_id is null or action.tenant_id = p_tenant_id)
        and action.status in ('planned', 'in_progress')
    ) else 0 end,
    'overdue_action_count', case when v_insights then (
      select count(*) from public.hr_experience_action action
      where (p_tenant_id is null or action.tenant_id = p_tenant_id)
        and action.status in ('planned', 'in_progress') and action.due_date < current_date
    ) else 0 end,
    'insights_visible', v_insights,
    'comments_visible', v_comments,
    'respond_visible', v_respond
  );
end
$function$;

create or replace function public.hr_list_employee_experience_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_survey_type text default null,
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
  v_limit integer := greatest(least(p_to - p_from + 1, 200), 1);
  v_offset integer := greatest(p_from, 0);
  v_insights boolean := app_private.hr_experience_insights_visible();
  v_result jsonb;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrEmployeeExperience', 'Hr:Experience:View', null, false
  ) then raise exception '当前账号没有查看员工体验工作台的权限' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'my' then
    if v_employee_id is null or not (
      app_private.is_platform_super() or app_private.has_permission('Hr:Experience:Respond')
    ) then raise exception '当前账号没有填写员工体验调查的权限' using errcode = '42501'; end if;
    with base as (
      select participant.id, participant.tenant_id, participant.survey_id,
        participant.status, participant.assigned_on, participant.completed_on,
        survey.survey_code, survey.survey_name, survey.survey_type,
        survey.cadence, survey.start_date, survey.end_date, survey.description,
        survey.minimum_group_size,
        (select count(*) from public.hr_experience_question question
          where question.survey_id = survey.id and question.tenant_id = survey.tenant_id
            and question.enabled) question_count,
        case when participant.status = 'invited' and survey.status = 'open'
          and current_date between survey.start_date and survey.end_date then 'available'
          when participant.status = 'completed' then 'completed'
          when survey.end_date < current_date then 'expired'
          else 'unavailable' end availability
      from public.hr_experience_participant participant
      join public.hr_experience_survey survey on survey.id = participant.survey_id
        and survey.tenant_id = participant.tenant_id
      where participant.tenant_id = v_tenant_id
        and participant.employee_id = v_employee_id
        and (p_status is null or participant.status = p_status)
        and (p_survey_type is null or survey.survey_type = p_survey_type)
        and (p_keyword is null or survey.survey_name ilike '%' || btrim(p_keyword) || '%'
          or survey.survey_code ilike '%' || btrim(p_keyword) || '%')
    ), page as (
      select * from base order by
        case availability when 'available' then 0 when 'unavailable' then 1
          when 'completed' then 2 else 3 end,
        end_date, survey_name limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(page)), '[]'::jsonb),
      'total', (select count(*) from base)
    ) into v_result from page;
  elsif p_kind = 'survey' then
    if not v_insights then raise exception '当前账号没有查看调查管理数据的权限' using errcode = '42501'; end if;
    with base as (
      select survey.*,
        organization.organization_name audience_organization_name,
        (select count(*) from public.hr_experience_question question
          where question.survey_id = survey.id and question.tenant_id = survey.tenant_id
            and question.enabled) question_count,
        (select count(*) from public.hr_experience_participant participant
          where participant.survey_id = survey.id and participant.tenant_id = survey.tenant_id)
          participant_count,
        (select count(*) from public.hr_experience_participant participant
          where participant.survey_id = survey.id and participant.tenant_id = survey.tenant_id
            and participant.status = 'completed') completed_count
      from public.hr_experience_survey survey
      left join public.sys_organization organization
        on organization.id = survey.audience_organization_id
        and organization.tenant_id = survey.tenant_id
      where (p_tenant_id is null or survey.tenant_id = p_tenant_id)
        and (p_status is null or survey.status = p_status)
        and (p_survey_type is null or survey.survey_type = p_survey_type)
        and (p_keyword is null or survey.survey_name ilike '%' || btrim(p_keyword) || '%'
          or survey.survey_code ilike '%' || btrim(p_keyword) || '%')
    ), page as (
      select * from base order by start_date desc, create_time desc
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(page) || jsonb_build_object(
        'response_rate', case when page.participant_count = 0 then 0
          else round(100.0 * page.completed_count / page.participant_count, 1) end
      )), '[]'::jsonb),
      'total', (select count(*) from base)
    ) into v_result from page;
  elsif p_kind = 'insight' then
    if not v_insights then raise exception '当前账号没有查看匿名聚合洞察的权限' using errcode = '42501'; end if;
    with scores as (
      select survey.id survey_id, survey.tenant_id, survey.survey_code,
        survey.survey_name, survey.survey_type, survey.status survey_status,
        survey.minimum_group_size, question.dimension,
        count(distinct response.id)::integer respondent_count,
        count(distinct question.id)::integer question_count,
        round(avg(case when question.answer_type = 'rating_5'
          then (answer.numeric_score - 1) * 25
          else answer.numeric_score * 10 end), 1) score_percent,
        count(distinct action.id)::integer action_count
      from public.hr_experience_survey survey
      join public.hr_experience_response response on response.survey_id = survey.id
        and response.tenant_id = survey.tenant_id
      join public.hr_experience_answer answer on answer.response_id = response.id
        and answer.tenant_id = response.tenant_id and answer.numeric_score is not null
      join public.hr_experience_question question on question.id = answer.question_id
        and question.tenant_id = answer.tenant_id
      left join public.hr_experience_action action on action.survey_id = survey.id
        and action.tenant_id = survey.tenant_id and action.dimension = question.dimension
        and action.status <> 'cancelled'
      where (p_tenant_id is null or survey.tenant_id = p_tenant_id)
        and (p_status is null or survey.status = p_status)
        and (p_survey_type is null or survey.survey_type = p_survey_type)
        and (p_keyword is null or survey.survey_name ilike '%' || btrim(p_keyword) || '%'
          or survey.survey_code ilike '%' || btrim(p_keyword) || '%')
      group by survey.id, survey.tenant_id, survey.survey_code, survey.survey_name,
        survey.survey_type, survey.status, survey.minimum_group_size, question.dimension
    ), eligible as (
      select *, case when score_percent < 60 then 'high'
        when score_percent < 75 then 'medium' else 'healthy' end risk_level
      from scores where respondent_count >= minimum_group_size
    ), page as (
      select * from eligible order by
        case risk_level when 'high' then 0 when 'medium' then 1 else 2 end,
        score_percent, survey_name, dimension limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(page)), '[]'::jsonb),
      'total', (select count(*) from eligible),
      'privacy_note', '仅展示达到最小汇报人数的匿名聚合结果'
    ) into v_result from page;
  elsif p_kind = 'action' then
    if not v_insights then raise exception '当前账号没有查看员工体验行动的权限' using errcode = '42501'; end if;
    with base as (
      select action.*, survey.survey_code, survey.survey_name,
        organization.organization_name,
        employee.employee_no owner_employee_no,
        employee.employee_name owner_employee_name,
        employee.job_title owner_job_title,
        case when action.status in ('planned', 'in_progress')
          and action.due_date < current_date then 'overdue'
          when action.status in ('planned', 'in_progress')
          and action.due_date <= current_date + 7 then 'due_soon'
          else 'clear' end due_status
      from public.hr_experience_action action
      join public.hr_experience_survey survey on survey.id = action.survey_id
        and survey.tenant_id = action.tenant_id
      left join public.sys_organization organization on organization.id = action.organization_id
        and organization.tenant_id = action.tenant_id
      join public.hr_employee employee on employee.id = action.owner_employee_id
        and employee.tenant_id = action.tenant_id
      where (p_tenant_id is null or action.tenant_id = p_tenant_id)
        and (p_status is null or action.status = p_status)
        and (p_survey_type is null or survey.survey_type = p_survey_type)
        and (p_keyword is null or action.title ilike '%' || btrim(p_keyword) || '%'
          or survey.survey_name ilike '%' || btrim(p_keyword) || '%'
          or employee.employee_name ilike '%' || btrim(p_keyword) || '%')
    ), page as (
      select * from base order by
        case due_status when 'overdue' then 0 when 'due_soon' then 1 else 2 end,
        due_date, create_time desc limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(to_jsonb(page)), '[]'::jsonb),
      'total', (select count(*) from base)
    ) into v_result from page;
  else
    raise exception '不支持的员工体验记录类型';
  end if;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_get_employee_experience_detail_secure(
  p_kind text,
  p_id uuid,
  p_dimension text default null
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
  v_insights boolean := app_private.hr_experience_insights_visible();
  v_comments boolean := app_private.hr_experience_comments_visible();
  v_result jsonb;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrEmployeeExperience', 'Hr:Experience:View', p_id, false
  ) then raise exception '当前账号没有查看员工体验详情的权限' using errcode = '42501'; end if;

  if p_kind = 'my' then
    if v_employee_id is null or not (
      app_private.is_platform_super() or app_private.has_permission('Hr:Experience:Respond')
    ) then raise exception '当前账号没有填写员工体验调查的权限' using errcode = '42501'; end if;
    select to_jsonb(participant) || jsonb_build_object(
      'survey', to_jsonb(survey),
      'questions', coalesce((select jsonb_agg(to_jsonb(question) order by question.sort, question.id)
        from public.hr_experience_question question
        where question.survey_id = survey.id and question.tenant_id = survey.tenant_id
          and question.enabled), '[]'::jsonb),
      'privacy_note', '系统仅记录您是否完成，答案不保存员工或参与记录标识。'
    ) into v_result
    from public.hr_experience_participant participant
    join public.hr_experience_survey survey on survey.id = participant.survey_id
      and survey.tenant_id = participant.tenant_id
    where participant.id = p_id and participant.tenant_id = v_tenant_id
      and participant.employee_id = v_employee_id;
  elsif p_kind = 'survey' then
    if not v_insights then raise exception '当前账号没有查看调查详情的权限' using errcode = '42501'; end if;
    select to_jsonb(survey) || jsonb_build_object(
      'audience_organization', case when organization.id is null then null else
        jsonb_build_object('id', organization.id, 'organization_name', organization.organization_name) end,
      'questions', coalesce((select jsonb_agg(to_jsonb(question) order by question.sort, question.id)
        from public.hr_experience_question question
        where question.survey_id = survey.id and question.tenant_id = survey.tenant_id), '[]'::jsonb),
      'participant_count', (select count(*) from public.hr_experience_participant participant
        where participant.survey_id = survey.id and participant.tenant_id = survey.tenant_id),
      'completed_count', (select count(*) from public.hr_experience_participant participant
        where participant.survey_id = survey.id and participant.tenant_id = survey.tenant_id
          and participant.status = 'completed'),
      'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.create_time desc)
        from public.hr_experience_event event where event.entity_type = 'survey'
          and event.entity_id = survey.id and event.tenant_id = survey.tenant_id), '[]'::jsonb)
    ) into v_result
    from public.hr_experience_survey survey
    left join public.sys_organization organization on organization.id = survey.audience_organization_id
      and organization.tenant_id = survey.tenant_id
    where survey.id = p_id and (app_private.is_platform_super() or survey.tenant_id = v_tenant_id);
  elsif p_kind = 'insight' then
    if not v_insights or nullif(p_dimension, '') is null then
      raise exception '当前账号没有查看匿名聚合洞察的权限' using errcode = '42501';
    end if;
    with survey_context as (
      select * from public.hr_experience_survey survey
      where survey.id = p_id and (app_private.is_platform_super() or survey.tenant_id = v_tenant_id)
    ), response_count as (
      select count(distinct response.id)::integer value
      from public.hr_experience_response response
      join survey_context survey on survey.id = response.survey_id
        and survey.tenant_id = response.tenant_id
      join public.hr_experience_answer answer on answer.response_id = response.id
        and answer.tenant_id = response.tenant_id
      join public.hr_experience_question question on question.id = answer.question_id
        and question.tenant_id = answer.tenant_id
      where question.dimension = p_dimension
    )
    select to_jsonb(survey) || jsonb_build_object(
      'dimension', p_dimension,
      'respondent_count', response_count.value,
      'privacy_threshold_met', response_count.value >= survey.minimum_group_size,
      'question_scores', case when response_count.value >= survey.minimum_group_size then
        coalesce((select jsonb_agg(jsonb_build_object(
          'question_id', question.id, 'question_text', question.question_text,
          'answer_type', question.answer_type,
          'respondent_count', aggregate.respondent_count,
          'score_percent', aggregate.score_percent
        ) order by question.sort, question.id)
        from public.hr_experience_question question
        join lateral (
          select count(distinct response.id)::integer respondent_count,
            round(avg(case when question.answer_type = 'rating_5'
              then (answer.numeric_score - 1) * 25 else answer.numeric_score * 10 end), 1)
              score_percent
          from public.hr_experience_answer answer
          join public.hr_experience_response response on response.id = answer.response_id
            and response.tenant_id = answer.tenant_id
          where answer.question_id = question.id and answer.tenant_id = survey.tenant_id
            and answer.numeric_score is not null
        ) aggregate on true
        where question.survey_id = survey.id and question.tenant_id = survey.tenant_id
          and question.dimension = p_dimension and question.answer_type <> 'open_text'), '[]'::jsonb)
        else '[]'::jsonb end,
      'organization_scores', case when response_count.value >= survey.minimum_group_size then
        coalesce((select jsonb_agg(to_jsonb(cohort) order by cohort.score_percent, cohort.organization_name)
        from (
          select organization.id organization_id, organization.organization_name,
            count(distinct response.id)::integer respondent_count,
            round(avg(case when question.answer_type = 'rating_5'
              then (answer.numeric_score - 1) * 25 else answer.numeric_score * 10 end), 1)
              score_percent
          from public.hr_experience_response response
          join public.hr_experience_answer answer on answer.response_id = response.id
            and answer.tenant_id = response.tenant_id and answer.numeric_score is not null
          join public.hr_experience_question question on question.id = answer.question_id
            and question.tenant_id = answer.tenant_id and question.dimension = p_dimension
          join public.sys_organization organization on organization.id = response.cohort_organization_id
            and organization.tenant_id = response.tenant_id
          where response.survey_id = survey.id and response.tenant_id = survey.tenant_id
          group by organization.id, organization.organization_name
          having count(distinct response.id) >= survey.minimum_group_size
        ) cohort), '[]'::jsonb) else '[]'::jsonb end,
      'comments_restricted', not v_comments,
      'comments', case when response_count.value >= survey.minimum_group_size and v_comments then
        coalesce((select jsonb_agg(jsonb_build_object(
          'question_text', question.question_text,
          'text', answer.text_answer,
          'submitted_at', response.submitted_at
        ) order by response.submitted_at desc)
        from public.hr_experience_answer answer
        join public.hr_experience_response response on response.id = answer.response_id
          and response.tenant_id = answer.tenant_id
        join public.hr_experience_question question on question.id = answer.question_id
          and question.tenant_id = answer.tenant_id
        where response.survey_id = survey.id and response.tenant_id = survey.tenant_id
          and question.dimension = p_dimension and answer.text_answer is not null), '[]'::jsonb)
        else '[]'::jsonb end,
      'actions', coalesce((select jsonb_agg(to_jsonb(action) order by action.due_date)
        from public.hr_experience_action action where action.survey_id = survey.id
          and action.tenant_id = survey.tenant_id and action.dimension = p_dimension
          and action.status <> 'cancelled'), '[]'::jsonb)
    ) into v_result
    from survey_context survey cross join response_count;
  elsif p_kind = 'action' then
    if not v_insights then raise exception '当前账号没有查看员工体验行动的权限' using errcode = '42501'; end if;
    select to_jsonb(action) || jsonb_build_object(
      'survey', jsonb_build_object('id', survey.id, 'survey_code', survey.survey_code,
        'survey_name', survey.survey_name, 'survey_type', survey.survey_type),
      'organization', case when organization.id is null then null else
        jsonb_build_object('id', organization.id, 'organization_name', organization.organization_name) end,
      'owner_employee', jsonb_build_object('id', employee.id, 'employee_no', employee.employee_no,
        'employee_name', employee.employee_name, 'job_title', employee.job_title),
      'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.create_time desc)
        from public.hr_experience_event event where event.entity_type = 'action'
          and event.entity_id = action.id and event.tenant_id = action.tenant_id), '[]'::jsonb)
    ) into v_result
    from public.hr_experience_action action
    join public.hr_experience_survey survey on survey.id = action.survey_id
      and survey.tenant_id = action.tenant_id
    left join public.sys_organization organization on organization.id = action.organization_id
      and organization.tenant_id = action.tenant_id
    join public.hr_employee employee on employee.id = action.owner_employee_id
      and employee.tenant_id = action.tenant_id
    where action.id = p_id and (app_private.is_platform_super() or action.tenant_id = v_tenant_id);
  else
    raise exception '不支持的员工体验详情类型';
  end if;

  if v_result is null then raise exception '员工体验记录不存在或无权查看' using errcode = '42501'; end if;
  return v_result;
end
$function$;

create or replace function public.hr_save_employee_experience_record_secure(
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
  v_status text;
  v_survey public.hr_experience_survey;
  v_question public.hr_experience_question;
  v_action public.hr_experience_action;
begin
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;
  if app_private.is_platform_super() and nullif(p_payload ->> 'tenant_id', '') is not null then
    v_tenant_id := (p_payload ->> 'tenant_id')::uuid;
  end if;

  if p_kind = 'survey' then
    if not app_private.can_execute_business_action(
      'HrEmployeeExperience', 'Hr:Experience:Survey:Manage', v_id, false
    ) then raise exception '当前账号没有管理员工体验调查的权限' using errcode = '42501'; end if;
    if v_id is null then
      insert into public.hr_experience_survey(
        tenant_id, survey_code, survey_name, survey_type, cadence,
        audience_type, audience_organization_id, minimum_group_size,
        start_date, end_date, status, description
      ) values (
        v_tenant_id, btrim(p_payload ->> 'survey_code'), btrim(p_payload ->> 'survey_name'),
        p_payload ->> 'survey_type', coalesce(nullif(p_payload ->> 'cadence', ''), 'one_time'),
        coalesce(nullif(p_payload ->> 'audience_type', ''), 'all_active'),
        nullif(p_payload ->> 'audience_organization_id', '')::uuid,
        coalesce((p_payload ->> 'minimum_group_size')::integer, 5),
        (p_payload ->> 'start_date')::date, (p_payload ->> 'end_date')::date,
        'draft', nullif(btrim(p_payload ->> 'description'), '')
      ) returning * into v_survey;
      v_id := v_survey.id;
      perform app_private.hr_add_experience_event(v_tenant_id, 'survey', v_id,
        'created', null, 'draft', '创建员工体验调查');
    else
      select status into v_status from public.hr_experience_survey
        where id = v_id and tenant_id = v_tenant_id for update;
      if v_status is null then raise exception '调查不存在或无权编辑'; end if;
      if v_status <> 'draft' then raise exception '只有草稿调查可以编辑'; end if;
      update public.hr_experience_survey set
        survey_code = btrim(p_payload ->> 'survey_code'),
        survey_name = btrim(p_payload ->> 'survey_name'),
        survey_type = p_payload ->> 'survey_type',
        cadence = p_payload ->> 'cadence',
        audience_type = p_payload ->> 'audience_type',
        audience_organization_id = nullif(p_payload ->> 'audience_organization_id', '')::uuid,
        minimum_group_size = (p_payload ->> 'minimum_group_size')::integer,
        start_date = (p_payload ->> 'start_date')::date,
        end_date = (p_payload ->> 'end_date')::date,
        description = nullif(btrim(p_payload ->> 'description'), '')
      where id = v_id and tenant_id = v_tenant_id returning * into v_survey;
      perform app_private.hr_add_experience_event(v_tenant_id, 'survey', v_id,
        'updated', 'draft', 'draft', '更新调查设置');
    end if;
  elsif p_kind = 'question' then
    if not app_private.can_execute_business_action(
      'HrEmployeeExperience', 'Hr:Experience:Question:Manage', v_id, false
    ) then raise exception '当前账号没有管理调查题目的权限' using errcode = '42501'; end if;
    if not exists (
      select 1 from public.hr_experience_survey survey
      where survey.id = (p_payload ->> 'survey_id')::uuid
        and survey.tenant_id = v_tenant_id and survey.status = 'draft'
    ) then raise exception '只有草稿调查可以维护题目'; end if;
    if v_id is null then
      insert into public.hr_experience_question(
        tenant_id, survey_id, dimension, question_text, answer_type,
        required, enabled, sort
      ) values (
        v_tenant_id, (p_payload ->> 'survey_id')::uuid,
        p_payload ->> 'dimension', btrim(p_payload ->> 'question_text'),
        p_payload ->> 'answer_type', coalesce((p_payload ->> 'required')::boolean, true),
        coalesce((p_payload ->> 'enabled')::boolean, true),
        coalesce((p_payload ->> 'sort')::integer, 0)
      ) returning * into v_question;
      v_id := v_question.id;
      perform app_private.hr_add_experience_event(v_tenant_id, 'survey', v_question.survey_id,
        'question_created', null, 'draft', '新增调查题目',
        jsonb_build_object('question_id', v_id));
    else
      update public.hr_experience_question set
        dimension = p_payload ->> 'dimension',
        question_text = btrim(p_payload ->> 'question_text'),
        answer_type = p_payload ->> 'answer_type',
        required = coalesce((p_payload ->> 'required')::boolean, true),
        enabled = coalesce((p_payload ->> 'enabled')::boolean, true),
        sort = coalesce((p_payload ->> 'sort')::integer, 0)
      where id = v_id and tenant_id = v_tenant_id
        and survey_id = (p_payload ->> 'survey_id')::uuid
      returning * into v_question;
      if v_question.id is null then raise exception '题目不存在或无权编辑'; end if;
      perform app_private.hr_add_experience_event(v_tenant_id, 'survey', v_question.survey_id,
        'question_updated', null, 'draft', '更新调查题目',
        jsonb_build_object('question_id', v_id));
    end if;
  elsif p_kind = 'action' then
    if not app_private.can_execute_business_action(
      'HrEmployeeExperience', 'Hr:Experience:Action:Manage', v_id, false
    ) then raise exception '当前账号没有管理员工体验行动的权限' using errcode = '42501'; end if;
    if not exists (select 1 from public.hr_experience_survey survey
      where survey.id = (p_payload ->> 'survey_id')::uuid and survey.tenant_id = v_tenant_id
        and survey.status in ('open', 'closed')) then
      raise exception '行动计划只能关联收集中或已关闭的调查';
    end if;
    if not exists (select 1 from public.hr_employee employee
      where employee.id = (p_payload ->> 'owner_employee_id')::uuid
        and employee.tenant_id = v_tenant_id
        and employee.employment_status not in ('left', 'terminated')) then
      raise exception '行动负责人不存在、已离职或不属于当前租户';
    end if;
    if nullif(p_payload ->> 'organization_id', '') is not null and not exists (
      select 1 from public.sys_organization organization
      where organization.id = (p_payload ->> 'organization_id')::uuid
        and organization.tenant_id = v_tenant_id
    ) then raise exception '行动组织不存在或不属于当前租户'; end if;
    if v_id is null then
      insert into public.hr_experience_action(
        tenant_id, survey_id, organization_id, dimension, title,
        owner_employee_id, due_date, status, success_measure, progress_note
      ) values (
        v_tenant_id, (p_payload ->> 'survey_id')::uuid,
        nullif(p_payload ->> 'organization_id', '')::uuid,
        p_payload ->> 'dimension', btrim(p_payload ->> 'title'),
        (p_payload ->> 'owner_employee_id')::uuid, (p_payload ->> 'due_date')::date,
        'planned', btrim(p_payload ->> 'success_measure'),
        nullif(btrim(p_payload ->> 'progress_note'), '')
      ) returning * into v_action;
      v_id := v_action.id;
      perform app_private.hr_add_experience_event(v_tenant_id, 'action', v_id,
        'created', null, 'planned', '创建员工体验改进行动');
    else
      select status into v_status from public.hr_experience_action
        where id = v_id and tenant_id = v_tenant_id for update;
      if v_status not in ('planned', 'in_progress') then
        raise exception '只有待开始或进行中的行动可以编辑';
      end if;
      update public.hr_experience_action set
        organization_id = nullif(p_payload ->> 'organization_id', '')::uuid,
        dimension = p_payload ->> 'dimension', title = btrim(p_payload ->> 'title'),
        owner_employee_id = (p_payload ->> 'owner_employee_id')::uuid,
        due_date = (p_payload ->> 'due_date')::date,
        success_measure = btrim(p_payload ->> 'success_measure'),
        progress_note = nullif(btrim(p_payload ->> 'progress_note'), '')
      where id = v_id and tenant_id = v_tenant_id returning * into v_action;
      perform app_private.hr_add_experience_event(v_tenant_id, 'action', v_id,
        'updated', v_status, v_status, '更新员工体验改进行动');
    end if;
  else
    raise exception '不支持的员工体验记录类型';
  end if;
  return v_id;
end
$function$;

create or replace function public.hr_transition_employee_experience_record_secure(
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
  v_survey public.hr_experience_survey;
  v_action public.hr_experience_action;
  v_target_status text;
  v_participant_count integer;
begin
  if auth.uid() is null then raise exception '请先登录' using errcode = '42501'; end if;
  if p_kind = 'survey' then
    if not app_private.can_execute_business_action(
      'HrEmployeeExperience', 'Hr:Experience:Launch', p_id, false
    ) then raise exception '当前账号没有发布或关闭调查的权限' using errcode = '42501'; end if;
    select * into v_survey from public.hr_experience_survey survey
      where survey.id = p_id and (app_private.is_platform_super() or survey.tenant_id = v_tenant_id)
      for update;
    if v_survey.id is null then raise exception '调查不存在或无权处理'; end if;
    if p_action = 'launch' and v_survey.status = 'draft' then
      if v_survey.end_date < current_date then raise exception '调查结束日期已过，不能发布'; end if;
      if not exists (select 1 from public.hr_experience_question question
        where question.survey_id = p_id and question.tenant_id = v_survey.tenant_id
          and question.enabled and question.answer_type in ('rating_5', 'enps_11')) then
        raise exception '至少维护一道启用的量表题后才能发布调查';
      end if;
      with recursive organization_scope(id) as (
        select v_survey.audience_organization_id
        where v_survey.audience_type = 'organization'
        union all
        select child.id from public.sys_organization child
        join organization_scope parent on child.parent_id = parent.id
        where child.tenant_id = v_survey.tenant_id and child.status = '1'
      )
      insert into public.hr_experience_participant(
        tenant_id, survey_id, employee_id, organization_snapshot_id, status, assigned_on
      )
      select employee.tenant_id, v_survey.id, employee.id, employee.organization_id,
        'invited', current_date
      from public.hr_employee employee
      where employee.tenant_id = v_survey.tenant_id
        and employee.organization_id is not null
        and employee.employment_status not in ('left', 'terminated')
        and (v_survey.audience_type = 'all_active'
          or employee.organization_id in (select id from organization_scope))
      on conflict (survey_id, employee_id) do nothing;
      select count(*) into v_participant_count from public.hr_experience_participant participant
        where participant.survey_id = p_id and participant.tenant_id = v_survey.tenant_id;
      if v_participant_count < v_survey.minimum_group_size then
        raise exception '符合条件的员工少于匿名汇报阈值 % 人，不能发布调查',
          v_survey.minimum_group_size;
      end if;
      v_target_status := case when v_survey.start_date > current_date then 'scheduled' else 'open' end;
      update public.hr_experience_survey set status = v_target_status, launched_at = now()
        where id = p_id;
      perform app_private.hr_add_experience_event(v_survey.tenant_id, 'survey', p_id,
        'launched', 'draft', v_target_status, '发布员工体验调查',
        jsonb_build_object('participant_count', v_participant_count,
          'minimum_group_size', v_survey.minimum_group_size));
    elsif p_action = 'open' and v_survey.status = 'scheduled' then
      if current_date < v_survey.start_date or current_date > v_survey.end_date then
        raise exception '当前日期不在调查开放周期内';
      end if;
      update public.hr_experience_survey set status = 'open' where id = p_id;
      perform app_private.hr_add_experience_event(v_survey.tenant_id, 'survey', p_id,
        'opened', 'scheduled', 'open', '开放员工体验调查');
    elsif p_action = 'close' and v_survey.status in ('scheduled', 'open') then
      update public.hr_experience_survey set status = 'closed', closed_at = now() where id = p_id;
      perform app_private.hr_add_experience_event(v_survey.tenant_id, 'survey', p_id,
        'closed', v_survey.status, 'closed', '关闭员工体验调查');
    elsif p_action = 'cancel' and v_survey.status in ('draft', 'scheduled', 'open') then
      update public.hr_experience_survey set status = 'cancelled', closed_at = now() where id = p_id;
      perform app_private.hr_add_experience_event(v_survey.tenant_id, 'survey', p_id,
        'cancelled', v_survey.status, 'cancelled', '取消员工体验调查',
        jsonb_build_object('comment', nullif(btrim(p_comment), '')));
    else
      raise exception '当前状态不允许执行该调查动作';
    end if;
  elsif p_kind = 'action' then
    select * into v_action from public.hr_experience_action action
      where action.id = p_id and (app_private.is_platform_super() or action.tenant_id = v_tenant_id)
      for update;
    if v_action.id is null then raise exception '改进行动不存在或无权处理'; end if;
    if p_action = 'start' then
      if not app_private.can_execute_business_action(
        'HrEmployeeExperience', 'Hr:Experience:Action:Manage', p_id, false
      ) or v_action.status <> 'planned' then raise exception '当前改进行动不能启动'; end if;
      update public.hr_experience_action set status = 'in_progress', started_at = now(),
        progress_note = coalesce(nullif(btrim(p_comment), ''), progress_note) where id = p_id;
      perform app_private.hr_add_experience_event(v_action.tenant_id, 'action', p_id,
        'started', 'planned', 'in_progress', '启动员工体验改进行动');
    elsif p_action = 'complete' then
      if not app_private.can_execute_business_action(
        'HrEmployeeExperience', 'Hr:Experience:Action:Close', p_id, false
      ) or v_action.status <> 'in_progress' or nullif(btrim(p_comment), '') is null then
        raise exception '验收进行中的行动时必须填写结果总结';
      end if;
      update public.hr_experience_action set status = 'completed', completed_at = now(),
        result_summary = btrim(p_comment) where id = p_id;
      perform app_private.hr_add_experience_event(v_action.tenant_id, 'action', p_id,
        'completed', 'in_progress', 'completed', '验收员工体验改进行动');
    elsif p_action = 'cancel' then
      if not app_private.can_execute_business_action(
        'HrEmployeeExperience', 'Hr:Experience:Action:Manage', p_id, false
      ) or v_action.status not in ('planned', 'in_progress') or nullif(btrim(p_comment), '') is null then
        raise exception '取消未完成行动时必须填写原因';
      end if;
      update public.hr_experience_action set status = 'cancelled',
        progress_note = btrim(p_comment) where id = p_id;
      perform app_private.hr_add_experience_event(v_action.tenant_id, 'action', p_id,
        'cancelled', v_action.status, 'cancelled', '取消员工体验改进行动',
        jsonb_build_object('comment', btrim(p_comment)));
    else
      raise exception '当前状态不允许执行该行动动作';
    end if;
  else
    raise exception '不支持的员工体验记录类型';
  end if;
  return true;
end
$function$;

create or replace function public.hr_submit_employee_experience_response_secure(
  p_participant_id uuid,
  p_answers jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_employee_id uuid := app_private.hr_current_employee_id();
  v_participant public.hr_experience_participant;
  v_survey public.hr_experience_survey;
  v_response_id uuid;
  v_question public.hr_experience_question;
  v_answer jsonb;
  v_numeric numeric;
  v_text text;
begin
  if auth.uid() is null or v_employee_id is null or not app_private.can_execute_business_action(
    'HrEmployeeExperience', 'Hr:Experience:Respond', p_participant_id, false
  ) then raise exception '当前账号没有填写员工体验调查的权限' using errcode = '42501'; end if;
  if jsonb_typeof(p_answers) <> 'array' then raise exception '调查答案格式不正确'; end if;

  select * into v_participant from public.hr_experience_participant participant
    where participant.id = p_participant_id and participant.tenant_id = v_tenant_id
      and participant.employee_id = v_employee_id for update;
  if v_participant.id is null then raise exception '待填写调查不存在或不属于当前员工'; end if;
  if v_participant.status <> 'invited' then raise exception '该调查已完成或不再允许填写'; end if;
  select * into v_survey from public.hr_experience_survey survey
    where survey.id = v_participant.survey_id and survey.tenant_id = v_participant.tenant_id;
  if v_survey.status <> 'open' or current_date not between v_survey.start_date and v_survey.end_date then
    raise exception '调查当前未开放或已超过填写周期';
  end if;
  if exists (
    select 1 from (
      select value ->> 'question_id' question_id, count(*) count_value
      from jsonb_array_elements(p_answers) value
      group by value ->> 'question_id' having count(*) > 1
    ) duplicate
  ) then raise exception '同一道题不能重复提交答案'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_answers) value
    where not exists (select 1 from public.hr_experience_question question
      where question.id = nullif(value ->> 'question_id', '')::uuid
        and question.survey_id = v_survey.id and question.tenant_id = v_tenant_id
        and question.enabled)
  ) then raise exception '答案包含不属于当前调查的题目'; end if;
  if exists (
    select 1 from public.hr_experience_question question
    where question.survey_id = v_survey.id and question.tenant_id = v_tenant_id
      and question.enabled and question.required
      and not exists (select 1 from jsonb_array_elements(p_answers) value
        where nullif(value ->> 'question_id', '')::uuid = question.id)
  ) then raise exception '请完成全部必答题后再提交'; end if;

  insert into public.hr_experience_response(
    tenant_id, survey_id, cohort_organization_id
  ) values (
    v_tenant_id, v_survey.id, v_participant.organization_snapshot_id
  ) returning id into v_response_id;

  for v_answer in select value from jsonb_array_elements(p_answers)
  loop
    select * into v_question from public.hr_experience_question question
      where question.id = (v_answer ->> 'question_id')::uuid
        and question.survey_id = v_survey.id and question.tenant_id = v_tenant_id;
    v_numeric := nullif(v_answer ->> 'numeric_score', '')::numeric;
    v_text := nullif(btrim(v_answer ->> 'text_answer'), '');
    if v_question.answer_type = 'rating_5' then
      if v_numeric is null or v_numeric < 1 or v_numeric > 5 then
        raise exception '五分量表答案必须在 1 到 5 之间';
      end if;
      v_text := null;
    elsif v_question.answer_type = 'enps_11' then
      if v_numeric is null or v_numeric < 0 or v_numeric > 10 then
        raise exception 'eNPS 答案必须在 0 到 10 之间';
      end if;
      v_text := null;
    else
      v_numeric := null;
      if v_question.required and v_text is null then raise exception '开放题不能为空'; end if;
      if v_text is null then continue; end if;
    end if;
    insert into public.hr_experience_answer(
      tenant_id, response_id, question_id, numeric_score, text_answer
    ) values (v_tenant_id, v_response_id, v_question.id, v_numeric, v_text);
  end loop;

  update public.hr_experience_participant set status = 'completed', completed_on = current_date
    where id = v_participant.id;
  return v_response_id;
end
$function$;

revoke all on function public.hr_employee_experience_overview_secure(uuid)
  from public, anon;
revoke all on function public.hr_list_employee_experience_records_secure(
  text, integer, integer, text, text, text, uuid
) from public, anon;
revoke all on function public.hr_get_employee_experience_detail_secure(text, uuid, text)
  from public, anon;
revoke all on function public.hr_save_employee_experience_record_secure(text, jsonb)
  from public, anon;
revoke all on function public.hr_transition_employee_experience_record_secure(
  text, uuid, text, text
) from public, anon;
revoke all on function public.hr_submit_employee_experience_response_secure(uuid, jsonb)
  from public, anon;

grant execute on function public.hr_employee_experience_overview_secure(uuid)
  to authenticated, service_role;
grant execute on function public.hr_list_employee_experience_records_secure(
  text, integer, integer, text, text, text, uuid
) to authenticated, service_role;
grant execute on function public.hr_get_employee_experience_detail_secure(text, uuid, text)
  to authenticated, service_role;
grant execute on function public.hr_save_employee_experience_record_secure(text, jsonb)
  to authenticated, service_role;
grant execute on function public.hr_transition_employee_experience_record_secure(
  text, uuid, text, text
) to authenticated, service_role;
grant execute on function public.hr_submit_employee_experience_response_secure(uuid, jsonb)
  to authenticated, service_role;

;
