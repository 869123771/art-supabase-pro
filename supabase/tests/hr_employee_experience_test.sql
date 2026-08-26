begin;

create temporary table hr_employee_experience_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  organization_id uuid not null,
  position_id uuid not null,
  employee_status text not null,
  ordinary_auth_user_id uuid not null,
  ordinary_sys_user_id uuid not null,
  ordinary_role_id uuid not null,
  ordinary_role_code text not null,
  survey_id uuid,
  rating_question_id uuid,
  text_question_id uuid,
  participant_id uuid,
  action_id uuid
) on commit drop;

create temporary table hr_employee_experience_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_employee_experience_test_context(
  tenant_id, employee_id, organization_id, position_id, employee_status,
  ordinary_auth_user_id, ordinary_sys_user_id, ordinary_role_id, ordinary_role_code
)
select employee.tenant_id, employee.id, employee.organization_id, employee.position_id,
  employee.employment_status, app_user.auth_user_id, app_user.id, gen_random_uuid(),
  'TEST_EXP_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9))
from public.sys_user app_user
join public.hr_employee employee
  on employee.id = app_user.hr_employee_id and employee.tenant_id = app_user.tenant_id
where app_user.auth_user_id is not null
  and app_user.deleted_at is null
  and coalesce(app_user.user_type, '') <> '0'
  and not ('R_SUPER' = any(coalesce(app_user.user_roles, '{}'::text[])))
  and employee.organization_id is not null
  and employee.employment_status not in ('left', 'terminated')
order by employee.employee_no
limit 1;

do $test$
begin
  if not exists(select 1 from hr_employee_experience_test_context) then
    raise exception 'No ordinary linked active HR employee fixture for experience test';
  end if;
end
$test$;

insert into public.sys_role(
  id, tenant_id, role_name, role_code, description, enabled, create_by, update_by
)
select ordinary_role_id, tenant_id, '员工体验答卷测试角色', ordinary_role_code,
  '事务回滚内的员工匿名答卷与聚合阈值验证角色', true,
  'automated-test', 'automated-test'
from hr_employee_experience_test_context;

update public.sys_user app_user
set user_roles = array[context.ordinary_role_code], update_by = 'automated-test'
from hr_employee_experience_test_context context
where app_user.id = context.ordinary_sys_user_id;

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select context.ordinary_role_id, target.menu_id, context.tenant_id,
  '{}'::jsonb, 'automated-test', 'automated-test'
from hr_employee_experience_test_context context
cross join (values
  ('c0de0000-0000-4000-8000-000000000209'::uuid),
  ('c0de0000-0000-4000-8209-000000000001'::uuid),
  ('c0de0000-0000-4000-8209-000000000005'::uuid)
) target(menu_id);

grant select, update on hr_employee_experience_test_context to authenticated;
grant select, insert on hr_employee_experience_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_small_survey_id uuid;
  v_small_question_id uuid;
  v_survey_id uuid;
  v_rating_question_id uuid;
  v_text_question_id uuid;
  v_threshold_blocked boolean := false;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;

  v_small_survey_id := public.hr_save_employee_experience_record_secure(
    'survey', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_code', 'TEST-EXP-SMALL-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
      'survey_name', '匿名阈值阻断调查',
      'survey_type', 'pulse',
      'cadence', 'one_time',
      'audience_type', 'all_active',
      'minimum_group_size', 50,
      'start_date', current_date,
      'end_date', current_date + 14
    )
  );
  v_small_question_id := public.hr_save_employee_experience_record_secure(
    'question', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_id', v_small_survey_id,
      'dimension', 'engagement',
      'question_text', '我愿意推荐这里作为工作场所。',
      'answer_type', 'rating_5',
      'required', true,
      'enabled', true,
      'sort', 10
    )
  );
  begin
    perform public.hr_transition_employee_experience_record_secure(
      'survey', v_small_survey_id, 'launch', null
    );
  exception when others then
    v_threshold_blocked := position('少于匿名汇报阈值 50 人' in sqlerrm) > 0;
  end;
  insert into hr_employee_experience_test_result values(
    'minimum_anonymity_threshold_blocks_launch',
    v_threshold_blocked,
    '符合条件员工不足最小匿名汇报人数时调查不能发布'
  );

  v_survey_id := public.hr_save_employee_experience_record_secure(
    'survey', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_code', 'TEST-EXP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      'survey_name', '自动化员工敬业度脉搏调查',
      'survey_type', 'engagement',
      'cadence', 'quarterly',
      'audience_type', 'all_active',
      'minimum_group_size', 5,
      'start_date', current_date,
      'end_date', current_date + 14,
      'description', '验证匿名参与、阈值聚合与行动闭环'
    )
  );
  v_rating_question_id := public.hr_save_employee_experience_record_secure(
    'question', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_id', v_survey_id,
      'dimension', 'engagement',
      'question_text', '我愿意持续为团队目标投入精力。',
      'answer_type', 'rating_5',
      'required', true,
      'enabled', true,
      'sort', 10
    )
  );
  v_text_question_id := public.hr_save_employee_experience_record_secure(
    'question', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_id', v_survey_id,
      'dimension', 'engagement',
      'question_text', '哪一项改变最能改善你的工作体验？',
      'answer_type', 'open_text',
      'required', false,
      'enabled', true,
      'sort', 20
    )
  );
  update hr_employee_experience_test_context set
    survey_id = v_survey_id,
    rating_question_id = v_rating_question_id,
    text_question_id = v_text_question_id;
end
$test$;

reset role;

-- Add rollback-only active employees so the main survey can satisfy the five-person threshold.
with source_position as (
  select position.*
  from public.hr_position position
  join hr_employee_experience_test_context context
    on context.position_id = position.id and context.tenant_id = position.tenant_id
), inserted_position as (
  insert into public.hr_position(
    id, tenant_id, organization_id, job_profile_id, grade_id,
    position_code, position_name, position_kind, system_code, enabled, sort,
    description, headcount_limit, multiple_incumbents_allowed, create_by, update_by
  )
  select gen_random_uuid(), tenant_id, organization_id, job_profile_id, grade_id,
    'TEST-EXP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    '员工体验回归测试岗位', position_kind, system_code, true, sort,
    '事务回滚内的匿名调查参与人测试岗位', 10, true,
    'automated-test', 'automated-test'
  from source_position
  returning id
)
update hr_employee_experience_test_context context
set position_id = inserted_position.id
from inserted_position;

insert into public.hr_employee(
  id, tenant_id, organization_id, position_id, employee_no, employee_name,
  job_title, employment_status, employment_type, phone, email, id_card_no,
  create_by, update_by
)
select gen_random_uuid(), context.tenant_id, context.organization_id, context.position_id,
  'TESTEXP' || series.value || substr(replace(gen_random_uuid()::text, '-', ''), 1, 5),
  '体验测试员工' || series.value,
  '匿名调查测试岗位', 'active', 'full_time',
  '19900000' || lpad(series.value::text, 3, '0'),
  'experience-test-' || series.value || '-' || substr(gen_random_uuid()::text, 1, 6) || '@example.invalid',
  '9900000000000000' || lpad(series.value::text, 2, '0'),
  'automated-test', 'automated-test'
from hr_employee_experience_test_context context
cross join generate_series(1, 4) series(value);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_survey_detail jsonb;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;
  perform public.hr_transition_employee_experience_record_secure(
    'survey', v_context.survey_id, 'launch', null
  );
  v_survey_detail := public.hr_get_employee_experience_detail_secure(
    'survey', v_context.survey_id, null
  );

  insert into hr_employee_experience_test_result values(
    'survey_launch_snapshots_eligible_employees',
    v_survey_detail ->> 'status' = 'open'
      and (v_survey_detail ->> 'participant_count')::integer >= 5,
    '发布调查时固化符合范围的员工参与记录并进入开放状态'
  );
end
$test$;

reset role;
update hr_employee_experience_test_context context
set participant_id = participant.id
from public.hr_experience_participant participant
where participant.survey_id = context.survey_id
  and participant.employee_id = context.employee_id;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_employee_experience_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_response_id uuid;
  v_duplicate_blocked boolean := false;
  v_my_detail jsonb;
  v_my_record jsonb;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;
  v_my_detail := public.hr_get_employee_experience_detail_secure(
    'my', v_context.participant_id, null
  );
  v_response_id := public.hr_submit_employee_experience_response_secure(
    v_context.participant_id,
    jsonb_build_array(
      jsonb_build_object('question_id', v_context.rating_question_id, 'numeric_score', 4),
      jsonb_build_object('question_id', v_context.text_question_id,
        'text_answer', '减少重复审批并增加主管及时反馈。')
    )
  );
  begin
    perform public.hr_submit_employee_experience_response_secure(
      v_context.participant_id,
      jsonb_build_array(jsonb_build_object(
        'question_id', v_context.rating_question_id, 'numeric_score', 5
      ))
    );
  exception when others then
    v_duplicate_blocked := position('已完成或不再允许填写' in sqlerrm) > 0;
  end;
  select record into v_my_record
  from jsonb_array_elements(public.hr_list_employee_experience_records_secure(
    'my', 0, 19, null, null, null, v_context.tenant_id
  ) -> 'records') record
  where (record ->> 'id')::uuid = v_context.participant_id;

  insert into hr_employee_experience_test_result values(
    'employee_can_submit_once_without_identity_link',
    v_response_id is not null
      and v_my_detail ->> 'privacy_note' is not null
      and v_duplicate_blocked
      and v_my_record ->> 'status' = 'completed',
    '员工只能提交本人开放调查一次，参与记录仅保存完成状态'
  );
end
$test$;

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER' = any(user_roles) or user_type = '0')
    order by case when 'R_SUPER' = any(user_roles) then 0 else 1 end limit 1),
  'role', 'authenticated'
)::text, true);

insert into hr_employee_experience_test_result values(
  'insight_is_hidden_below_threshold',
  jsonb_array_length(public.hr_list_employee_experience_records_secure(
    'insight', 0, 19, null, null, null,
    (select tenant_id from hr_employee_experience_test_context limit 1)
  ) -> 'records') = 0,
  '未达到五人匿名阈值时不返回任何主题洞察'
);

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_participant record;
  v_response_id uuid;
  v_seeded integer := 0;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;
  for v_participant in
    select participant.id, participant.organization_snapshot_id
    from public.hr_experience_participant participant
    where participant.survey_id = v_context.survey_id
      and participant.status = 'invited'
    order by participant.id
    limit 4
  loop
    insert into public.hr_experience_response(
      tenant_id, survey_id, cohort_organization_id
    ) values (
      v_context.tenant_id, v_context.survey_id,
      v_participant.organization_snapshot_id
    ) returning id into v_response_id;
    insert into public.hr_experience_answer(
      tenant_id, response_id, question_id, numeric_score, text_answer
    ) values
      (v_context.tenant_id, v_response_id, v_context.rating_question_id, 5, null),
      (v_context.tenant_id, v_response_id, v_context.text_question_id, null,
        '测试匿名反馈，不包含员工身份。');
    update public.hr_experience_participant
    set status = 'completed', completed_on = current_date
    where id = v_participant.id;
    v_seeded := v_seeded + 1;
  end loop;
  if v_seeded <> 4 then raise exception 'Failed to seed four anonymous responses'; end if;
end
$test$;

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_insight jsonb;
  v_action_id uuid;
  v_action_detail jsonb;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;
  select record into v_insight
  from jsonb_array_elements(public.hr_list_employee_experience_records_secure(
    'insight', 0, 19, null, null, null, v_context.tenant_id
  ) -> 'records') record
  where record ->> 'dimension' = 'engagement';

  insert into hr_employee_experience_test_result values(
    'threshold_safe_insight_is_generated',
    (v_insight ->> 'respondent_count')::integer = 5
      and (v_insight ->> 'question_count')::integer = 1
      and (v_insight ->> 'score_percent')::numeric = 95.0,
    '达到匿名阈值后按量表统一到百分制并生成主题风险洞察'
  );

  v_action_id := public.hr_save_employee_experience_record_secure(
    'action', jsonb_build_object(
      'tenant_id', v_context.tenant_id,
      'survey_id', v_context.survey_id,
      'organization_id', v_context.organization_id,
      'dimension', 'engagement',
      'title', '减少重复审批并强化主管反馈',
      'owner_employee_id', v_context.employee_id,
      'due_date', current_date + 30,
      'success_measure', '下次脉搏调查敬业度主题提升不少于 5 分',
      'progress_note', '先梳理高频重复审批节点'
    )
  );
  perform public.hr_transition_employee_experience_record_secure(
    'action', v_action_id, 'start', '已完成行动责任人与工作范围确认'
  );
  perform public.hr_transition_employee_experience_record_secure(
    'action', v_action_id, 'complete', '已减少两项重复审批并建立每周反馈机制'
  );
  update hr_employee_experience_test_context set action_id = v_action_id;
  v_action_detail := public.hr_get_employee_experience_detail_secure(
    'action', v_action_id, null
  );

  insert into hr_employee_experience_test_result values(
    'experience_action_lifecycle_is_audited',
    v_action_detail ->> 'status' = 'completed'
      and nullif(v_action_detail ->> 'result_summary', '') is not null
      and jsonb_array_length(v_action_detail -> 'events') >= 3,
    '匿名洞察可以转化为有负责人、期限、衡量标准和验收结果的行动闭环'
  );
end
$test$;

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select ordinary_role_id, 'c0de0000-0000-4000-8209-000000000006'::uuid,
  tenant_id, '{}'::jsonb, 'automated-test', 'automated-test'
from hr_employee_experience_test_context;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_employee_experience_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_employee_experience_test_context%rowtype;
  v_detail jsonb;
  v_survey_direct_blocked boolean := false;
  v_participant_direct_blocked boolean := false;
  v_response_direct_blocked boolean := false;
  v_answer_direct_blocked boolean := false;
begin
  select * into v_context from hr_employee_experience_test_context limit 1;
  v_detail := public.hr_get_employee_experience_detail_secure(
    'insight', v_context.survey_id, 'engagement'
  );
  insert into hr_employee_experience_test_result values(
    'ordinary_insight_role_cannot_read_comments',
    coalesce((v_detail ->> 'privacy_threshold_met')::boolean, false)
      and coalesce((v_detail ->> 'comments_restricted')::boolean, false)
      and v_detail -> 'comments' = '[]'::jsonb
      and jsonb_array_length(v_detail -> 'question_scores') = 1,
    '普通洞察权限可查看达到阈值的分数，但服务端不返回开放反馈原文'
  );

  begin perform 1 from public.hr_experience_survey limit 1;
  exception when insufficient_privilege then v_survey_direct_blocked := true; end;
  begin perform 1 from public.hr_experience_participant limit 1;
  exception when insufficient_privilege then v_participant_direct_blocked := true; end;
  begin perform 1 from public.hr_experience_response limit 1;
  exception when insufficient_privilege then v_response_direct_blocked := true; end;
  begin perform 1 from public.hr_experience_answer limit 1;
  exception when insufficient_privilege then v_answer_direct_blocked := true; end;
  insert into hr_employee_experience_test_result values(
    'experience_tables_deny_direct_access',
    v_survey_direct_blocked and v_participant_direct_blocked
      and v_response_direct_blocked and v_answer_direct_blocked,
    '已登录用户不能绕过受控 RPC 直接读取调查、参与或匿名答卷表'
  );
end
$test$;

reset role;

insert into hr_employee_experience_test_result values(
  'anonymous_answer_tables_have_no_actor_columns',
  not exists(
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('hr_experience_response', 'hr_experience_answer')
      and column_name in ('employee_id', 'participant_id', 'create_by', 'update_by')
  ),
  '匿名答卷与答案表物理上不保存员工、参与记录或操作人字段'
);

insert into hr_employee_experience_test_result
select 'experience_actions_do_not_change_employment_status',
  exists(
    select 1 from public.hr_employee employee
    join hr_employee_experience_test_context context
      on context.employee_id = employee.id and context.tenant_id = employee.tenant_id
    where employee.employment_status = context.employee_status
  ),
  '调查、答卷、洞察和行动验收不会直接改变员工任职状态';

insert into hr_employee_experience_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege(
    'anon', 'public.hr_employee_experience_overview_secure(uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_submit_employee_experience_response_secure(uuid,jsonb)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_save_employee_experience_record_secure(text,jsonb)', 'execute'
  ),
  '匿名角色不能调用员工体验受控 RPC'
);

select check_name, passed, detail
from hr_employee_experience_test_result
order by check_name;

do $test$
begin
  if exists(select 1 from hr_employee_experience_test_result where not passed) then
    raise exception 'HR employee experience verification failed';
  end if;
end
$test$;

rollback;
