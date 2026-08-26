begin;

create temporary table hr_employee_relations_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  employee_status text not null,
  ordinary_auth_user_id uuid not null,
  ordinary_sys_user_id uuid not null,
  ordinary_role_id uuid not null,
  ordinary_role_code text not null,
  case_id uuid,
  action_id uuid
) on commit drop;

create temporary table hr_employee_relations_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_employee_relations_test_context(
  tenant_id, employee_id, employee_status, ordinary_auth_user_id,
  ordinary_sys_user_id, ordinary_role_id, ordinary_role_code
)
select employee.tenant_id, employee.id, employee.employment_status,
  app_user.auth_user_id, app_user.id, gen_random_uuid(),
  'TEST_ER_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
from public.sys_user app_user
join public.hr_employee employee
  on employee.id = app_user.hr_employee_id and employee.tenant_id = app_user.tenant_id
where app_user.auth_user_id is not null
  and app_user.deleted_at is null
  and coalesce(app_user.user_type, '') <> '0'
  and not ('R_SUPER' = any(coalesce(app_user.user_roles, '{}'::text[])))
  and employee.employment_status not in ('left', 'terminated')
order by employee.employee_no
limit 1;

do $test$
begin
  if not exists(select 1 from hr_employee_relations_test_context) then
    raise exception 'No ordinary linked HR employee fixture for employee relations test';
  end if;
end
$test$;

insert into public.sys_role(
  id, tenant_id, role_name, role_code, description, enabled, create_by, update_by
)
select ordinary_role_id, tenant_id, '员工关系脱敏测试角色', ordinary_role_code,
  '事务回滚内的员工关系脱敏验证角色', true, 'automated-test', 'automated-test'
from hr_employee_relations_test_context;

update public.sys_user app_user
set user_roles = array[context.ordinary_role_code], update_by = 'automated-test'
from hr_employee_relations_test_context context
where app_user.id = context.ordinary_sys_user_id;

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select context.ordinary_role_id, target.menu_id, context.tenant_id,
  '{}'::jsonb, 'automated-test', 'automated-test'
from hr_employee_relations_test_context context
cross join (values
  ('c0de0000-0000-4000-8000-000000000207'::uuid),
  ('c0de0000-0000-4000-8207-000000000001'::uuid)
) target(menu_id);

grant select, update on hr_employee_relations_test_context to authenticated;
grant select, insert on hr_employee_relations_test_result to authenticated;
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
  v_context hr_employee_relations_test_context%rowtype;
  v_case_id uuid;
  v_action_id uuid;
  v_detail jsonb;
  v_resolve_blocked boolean := false;
  v_case_direct_blocked boolean := false;
  v_action_direct_blocked boolean := false;
  v_event_direct_blocked boolean := false;
begin
  select * into v_context from hr_employee_relations_test_context limit 1;

  v_case_id := public.hr_save_employee_relations_record_secure('case', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'case_no', 'TEST-ER-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    'case_type', 'workplace_conflict',
    'title', '自动化员工关系案件',
    'subject_employee_id', v_context.employee_id,
    'reporter_employee_id', v_context.employee_id,
    'anonymous_report', false,
    'source', 'hr',
    'severity', 'medium',
    'confidentiality_level', 'restricted',
    'allegation_summary', '用于验证员工关系受控生命周期与审计链路。',
    'external_reference', 'TEST-PRIVATE-REFERENCE',
    'remark', '仅敏感权限可查看的测试备注'
  ));
  update hr_employee_relations_test_context set case_id = v_case_id;

  perform public.hr_transition_employee_relation_case_secure(
    v_case_id, 'submit', jsonb_build_object('comment', '提交案件报告')
  );
  perform public.hr_transition_employee_relation_case_secure(
    v_case_id, 'triage', jsonb_build_object(
      'owner_employee_id', v_context.employee_id,
      'target_resolution_date', current_date + 14,
      'severity', 'high',
      'confidentiality_level', 'restricted',
      'comment', '完成案件分级'
    )
  );
  perform public.hr_transition_employee_relation_case_secure(
    v_case_id, 'start_investigation', jsonb_build_object('comment', '启动事实调查')
  );

  v_action_id := public.hr_save_employee_relations_record_secure('action', jsonb_build_object(
    'tenant_id', v_context.tenant_id,
    'case_id', v_case_id,
    'action_type', 'mediation',
    'title', '组织调解会议',
    'owner_employee_id', v_context.employee_id,
    'due_date', current_date + 7,
    'remark', '自动化验证处置行动'
  ));
  update hr_employee_relations_test_context set action_id = v_action_id;

  begin
    perform public.hr_transition_employee_relation_case_secure(
      v_case_id, 'resolve', jsonb_build_object(
        'outcome', 'resolved_informally',
        'resolution_summary', '未完成行动前不应允许解决案件。'
      )
    );
  exception when others then
    v_resolve_blocked := position('未完成的处置行动' in sqlerrm) > 0;
  end;
  insert into hr_employee_relations_test_result values(
    'open_action_blocks_case_resolution',
    v_resolve_blocked
      and public.hr_get_employee_relation_case_detail_secure(v_case_id) ->> 'status'
        = 'investigating',
    '存在待开始或进行中的处置行动时，案件不能提前解决'
  );

  perform public.hr_transition_employee_relation_action_secure(
    v_action_id, 'start', '开始处置行动'
  );
  perform public.hr_transition_employee_relation_action_secure(
    v_action_id, 'complete', '处置行动已完成'
  );
  perform public.hr_transition_employee_relation_case_secure(
    v_case_id, 'resolve', jsonb_build_object(
      'outcome', 'resolved_informally',
      'findings_summary', '已核验相关事实并完成沟通。',
      'resolution_summary', '双方完成调解并确认后续安排。',
      'comment', '提交案件解决结论'
    )
  );
  perform public.hr_transition_employee_relation_case_secure(
    v_case_id, 'close', jsonb_build_object('comment', '正式结案')
  );

  v_detail := public.hr_get_employee_relation_case_detail_secure(v_case_id);
  insert into hr_employee_relations_test_result values(
    'case_lifecycle_is_closed_and_audited',
    v_detail ->> 'status' = 'closed'
      and jsonb_array_length(v_detail -> 'events') >= 8,
    '案件创建、提交、分级、调查、处置、解决与结案完整留痕'
  );
  insert into hr_employee_relations_test_result values(
    'action_lifecycle_is_completed',
    exists(
      select 1 from jsonb_array_elements(v_detail -> 'actions') action
      where (action ->> 'id')::uuid = v_action_id
        and action ->> 'status' = 'completed'
        and nullif(action ->> 'completion_note', '') is not null
    ),
    '处置行动启动与完成状态可从案件详情核验'
  );
  insert into hr_employee_relations_test_result values(
    'overview_and_list_include_case',
    (public.hr_employee_relations_overview_secure(v_context.tenant_id)
      ->> 'resolved_month_count')::integer >= 1
      and exists(
        select 1 from jsonb_array_elements(public.hr_list_employee_relations_records_secure(
          'case', 0, 99, null, 'closed', null, null, v_context.tenant_id
        ) -> 'records') record
        where (record ->> 'id')::uuid = v_case_id
      ),
    '员工关系总览与案件列表返回已结案件'
  );
  begin
    perform 1 from public.hr_employee_relation_case limit 1;
  exception when insufficient_privilege then
    v_case_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_employee_relation_action limit 1;
  exception when insufficient_privilege then
    v_action_direct_blocked := true;
  end;
  begin
    perform 1 from public.hr_employee_relation_event limit 1;
  exception when insufficient_privilege then
    v_event_direct_blocked := true;
  end;
  insert into hr_employee_relations_test_result values(
    'relation_tables_deny_direct_access',
    v_case_direct_blocked and v_action_direct_blocked and v_event_direct_blocked,
    '已登录用户不能绕过受控 RPC 直接读取案件、行动或审计事件'
  );
end
$test$;

reset role;
insert into hr_employee_relations_test_result
select 'corrective_action_does_not_change_employment_status',
  exists(
    select 1
    from public.hr_employee employee
    join hr_employee_relations_test_context context
      on context.employee_id = employee.id and context.tenant_id = employee.tenant_id
    where employee.employment_status = context.employee_status
  ),
  '员工关系处置只记录建议与行动，不直接变更员工任职状态';

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select ordinary_auth_user_id from hr_employee_relations_test_context limit 1),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $test$
declare
  v_context hr_employee_relations_test_context%rowtype;
  v_detail jsonb;
  v_list_record jsonb;
begin
  select * into v_context from hr_employee_relations_test_context limit 1;
  v_detail := public.hr_get_employee_relation_case_detail_secure(v_context.case_id);
  select record into v_list_record
  from jsonb_array_elements(public.hr_list_employee_relations_records_secure(
    'case', 0, 19, null, 'closed', null, null, v_context.tenant_id
  ) -> 'records') record
  where (record ->> 'id')::uuid = v_context.case_id;

  insert into hr_employee_relations_test_result values(
    'sensitive_content_is_redacted_server_side',
    coalesce((v_detail ->> 'sensitive_restricted')::boolean, false)
      and v_detail ->> 'title' = '受限员工关系案件'
      and not (v_detail ? 'allegation_summary')
      and not (v_detail ? 'findings_summary')
      and not (v_detail ? 'resolution_summary')
      and not (v_detail ? 'attachment_urls')
      and not (v_detail ? 'external_reference')
      and not (v_detail ? 'remark')
      and not (v_detail ? 'reporter_employee')
      and v_list_record ->> 'title' = '受限员工关系案件'
      and not (v_list_record ? 'external_reference')
      and not (v_list_record ? 'remark')
      and not (v_list_record ? 'reporter_employee'),
    '无敏感查看权限时，服务端同时脱敏详情与列表字段'
  );
end
$test$;

reset role;
insert into hr_employee_relations_test_result values(
  'anonymous_rpc_execution_denied',
  not has_function_privilege(
    'anon', 'public.hr_employee_relations_overview_secure(uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.hr_save_employee_relations_record_secure(text,jsonb)', 'execute'
  ),
  '匿名角色不能调用员工关系受控 RPC'
);

select check_name, passed, detail
from hr_employee_relations_test_result
order by check_name;

do $test$
begin
  if exists(select 1 from hr_employee_relations_test_result where not passed) then
    raise exception 'HR employee relations verification failed';
  end if;
end
$test$;

rollback;
