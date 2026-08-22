begin;

do $$
declare
  v_tenant_id uuid;
  v_definition_id uuid;
  v_version_id uuid;
  v_user_id uuid;
  v_auth_user_id uuid;
  v_user_email text;
  v_site_id uuid := gen_random_uuid();
  v_area_id uuid := gen_random_uuid();
  v_risk_point_id uuid := gen_random_uuid();
  v_danger_id uuid := gen_random_uuid();
  v_instance_id uuid := gen_random_uuid();
  v_snapshot jsonb;
begin
  select definition_row.tenant_id, definition_row.id, version_row.id
  into v_tenant_id, v_definition_id, v_version_id
  from public.wf_definition definition_row
  join public.wf_version version_row
    on version_row.definition_id = definition_row.id
   and version_row.status = 'published'
  order by definition_row.create_time
  limit 1;

  if v_tenant_id is null then
    raise exception '测试环境缺少已发布工作流版本';
  end if;

  select user_row.id, user_row.auth_user_id, user_row.user_email
  into v_user_id, v_auth_user_id, v_user_email
  from public.sys_user user_row
  where user_row.tenant_id = v_tenant_id
    and user_row.deleted_at is null
    and user_row.status = '1'
    and user_row.auth_user_id is not null
  order by user_row.create_time
  limit 1;

  if v_user_id is null then
    raise exception '测试租户缺少可用用户';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_auth_user_id,
      'role', 'authenticated',
      'email', v_user_email,
      'tenant_id', v_tenant_id
    )::text,
    true
  );

  insert into public.smis_site (
    id, tenant_id, site_code, site_name, create_by, update_by
  ) values (
    v_site_id, v_tenant_id, 'QA-WF-SITE', 'QA工作流测试场所', 'qa', 'qa'
  );

  insert into public.smis_area (
    id, tenant_id, site_id, area_code, area_name, create_by, update_by
  ) values (
    v_area_id, v_tenant_id, v_site_id, 'QA-WF-AREA', 'QA工作流测试区域', 'qa', 'qa'
  );

  insert into public.smis_risk_point (
    id, tenant_id, site_id, area_id, responsible_user_id, risk_point_no,
    risk_point_name, current_risk_level, create_by, update_by
  ) values (
    v_risk_point_id, v_tenant_id, v_site_id, v_area_id, v_user_id,
    'QA-WF-RISK', 'QA工作流测试风险点', 'major', 'qa', 'qa'
  );

  insert into public.smis_hidden_danger (
    id, tenant_id, risk_point_id, responsible_user_id, danger_no,
    danger_title, danger_description, danger_level, rectification_requirement,
    rectification_deadline, attachment_refs, create_by, update_by
  ) values (
    v_danger_id, v_tenant_id, v_risk_point_id, v_user_id, 'QA-WF-DANGER',
    'QA隐患流程回调', '验证审批通过自动销号及回调幂等', 'major',
    '完成验证后自动回滚', now() + interval '1 day',
    jsonb_build_array(jsonb_build_object('id', 'qa-file', 'url', 'https://example.invalid/qa')),
    'qa', 'qa'
  );

  update public.smis_hidden_danger
  set status = 'pending_review', rectification_submitted_at = now()
  where id = v_danger_id;

  insert into public.wf_instance (
    id, tenant_id, definition_id, version_id, business_type, business_id,
    business_title, initiator_user_id, initiator_name_snapshot, status,
    context_snapshot, create_by, update_by
  ) values (
    v_instance_id, v_tenant_id, v_definition_id, v_version_id,
    'smis_hidden_danger', v_danger_id, 'QA隐患复查', v_user_id,
    v_user_email, 'running', '{}'::jsonb, 'qa', 'qa'
  );

  perform app_private.execute_workflow_business_callback(
    'smis_hidden_danger', v_danger_id, 'running', v_user_email, '发起审批'
  );

  update public.wf_instance
  set status = 'approved', finished_at = now(), finish_comment = '同意销号'
  where id = v_instance_id;

  perform app_private.execute_workflow_business_callback(
    'smis_hidden_danger', v_danger_id, 'approved', v_user_email, '同意销号'
  );
  perform app_private.execute_workflow_business_callback(
    'smis_hidden_danger', v_danger_id, 'approved', v_user_email, '重复回调'
  );

  if (select status from public.smis_hidden_danger where id = v_danger_id) <> 'closed' then
    raise exception '审批通过后隐患未自动销号';
  end if;
  if (
    select count(*)
    from public.smis_hidden_danger_event event_row
    where event_row.hidden_danger_id = v_danger_id
      and event_row.workflow_instance_id = v_instance_id
  ) <> 2 then
    raise exception '工作流事件幂等校验失败';
  end if;

  v_snapshot := public.get_workflow_business_snapshot(v_instance_id);
  if v_snapshot ->> 'businessNo' <> 'QA-WF-DANGER'
    or jsonb_array_length(v_snapshot -> 'attachments') <> 1 then
    raise exception '隐患审批快照校验失败';
  end if;
end;
$$;

rollback;
