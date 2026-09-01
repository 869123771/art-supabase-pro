do $$
declare
  v_tenant_id uuid;
  v_definition_id uuid;
  v_version_id uuid := gen_random_uuid();
  v_version_no integer;
  v_department_approver_1 uuid;
  v_department_approver_2 uuid;
  v_safety_approver_1 uuid;
  v_safety_approver_2 uuid;
  v_warehouse_approver uuid;
  v_config jsonb;
begin
  select tenant.id
  into strict v_tenant_id
  from public.sys_tenant tenant
  where tenant.tenant_code = 'yq_2026_001'
    and tenant.status = '1';

  select app_user.id
  into strict v_department_approver_1
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = '王俊'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select app_user.id
  into strict v_department_approver_2
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = '刘学乐'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select app_user.id
  into strict v_safety_approver_1
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = 'EMP202608006'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select app_user.id
  into strict v_safety_approver_2
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = 'EMP202608007'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select app_user.id
  into strict v_warehouse_approver
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = '武安子成'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  v_config := jsonb_build_object(
    'allowAutoApprove', false,
    'nodes', jsonb_build_array(
      jsonb_build_object(
        'key', 'department_joint_review',
        'name', '部门负责人会签',
        'order', 1,
        'approvalMode', 'all',
        'rejectVetoEnabled', true,
        'allowSelfApproval', false,
        'dueHours', 24,
        'reminderBeforeMinutes', 120,
        'escalationEnabled', true,
        'escalateAfterHours', 4,
        'assignee', jsonb_build_object(
          'type', 'users',
          'userIds', jsonb_build_array(
            v_department_approver_1::text,
            v_department_approver_2::text
          )
        ),
        'condition', jsonb_build_object('operator', 'always')
      ),
      jsonb_build_object(
        'key', 'safety_joint_review',
        'name', '安全管理会签',
        'order', 2,
        'approvalMode', 'all',
        'rejectVetoEnabled', true,
        'allowSelfApproval', false,
        'dueHours', 24,
        'reminderBeforeMinutes', 120,
        'escalationEnabled', true,
        'escalateAfterHours', 4,
        'assignee', jsonb_build_object(
          'type', 'users',
          'userIds', jsonb_build_array(
            v_safety_approver_1::text,
            v_safety_approver_2::text
          )
        ),
        'condition', jsonb_build_object('operator', 'always')
      ),
      jsonb_build_object(
        'key', 'warehouse_final_review',
        'name', '库房终审',
        'order', 3,
        'approvalMode', 'any',
        'rejectVetoEnabled', true,
        'allowSelfApproval', false,
        'dueHours', 12,
        'reminderBeforeMinutes', 60,
        'escalationEnabled', true,
        'escalateAfterHours', 4,
        'assignee', jsonb_build_object(
          'type', 'users',
          'userIds', jsonb_build_array(v_warehouse_approver::text)
        ),
        'condition', jsonb_build_object('operator', 'always')
      )
    )
  );

  perform app_private.validate_workflow_config(v_config);

  select definition.id
  into v_definition_id
  from public.wf_definition definition
  where definition.tenant_id = v_tenant_id
    and definition.code = 'smis_tool_return_multi_level';

  if v_definition_id is null then
    v_definition_id := gen_random_uuid();

    insert into public.wf_definition(
      id,
      code,
      name,
      business_type,
      description,
      status,
      tenant_id,
      create_by,
      update_by
    ) values (
      v_definition_id,
      'smis_tool_return_multi_level',
      '工器具领用归还多级审批',
      'smis_tool_return',
      '部门负责人双人会签、安全管理双人会签、库房终审。用于验证多人多环节审批、提醒与归还过账效果。',
      'draft',
      v_tenant_id,
      'workflow-setup',
      'workflow-setup'
    );
  end if;

  if exists (
    select 1
    from public.wf_definition definition
    where definition.tenant_id = v_tenant_id
      and definition.business_type = 'smis_tool_return'
      and definition.status = 'published'
      and definition.id <> v_definition_id
  ) then
    raise exception '工器具领用归还已存在其他启用流程，请先停用后再应用本配置';
  end if;

  update public.wf_version
  set status = 'retired',
      update_by = 'workflow-setup',
      update_time = now()
  where definition_id = v_definition_id
    and status in ('draft', 'published');

  select coalesce(max(version.version_no), 0) + 1
  into v_version_no
  from public.wf_version version
  where version.definition_id = v_definition_id;

  insert into public.wf_version(
    id,
    definition_id,
    version_no,
    status,
    config,
    change_note,
    published_at,
    published_by,
    tenant_id,
    create_by,
    update_by
  ) values (
    v_version_id,
    v_definition_id,
    v_version_no,
    'published',
    v_config,
    '配置三阶段、五人参与的工器具领用归还审批演示流程',
    now(),
    'workflow-setup',
    v_tenant_id,
    'workflow-setup',
    'workflow-setup'
  );

  update public.wf_definition
  set name = '工器具领用归还多级审批',
      business_type = 'smis_tool_return',
      description = '部门负责人双人会签、安全管理双人会签、库房终审。用于验证多人多环节审批、提醒与归还过账效果。',
      status = 'published',
      current_version_id = v_version_id,
      published_at = now(),
      published_by = 'workflow-setup',
      update_by = 'workflow-setup',
      update_time = now()
  where id = v_definition_id;
end;
$$;

;
