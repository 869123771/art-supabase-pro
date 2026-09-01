-- Keep score aggregation independent from the one-to-many action-plan table.
-- Multiple actions for one survey dimension must not multiply anonymous answer rows.
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
        (select count(*)::integer
          from public.hr_experience_action action
          where action.survey_id = survey.id
            and action.tenant_id = survey.tenant_id
            and action.dimension = question.dimension
            and action.status <> 'cancelled') action_count
      from public.hr_experience_survey survey
      join public.hr_experience_response response on response.survey_id = survey.id
        and response.tenant_id = survey.tenant_id
      join public.hr_experience_answer answer on answer.response_id = response.id
        and answer.tenant_id = response.tenant_id and answer.numeric_score is not null
      join public.hr_experience_question question on question.id = answer.question_id
        and question.tenant_id = answer.tenant_id
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

;
