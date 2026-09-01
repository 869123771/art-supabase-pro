do $$
declare
  v_tenant_id uuid;
  v_definition_id uuid;
  v_previous_version_id uuid;
  v_new_version_id uuid := gen_random_uuid();
  v_new_version_no integer;
  v_primary_approver_id uuid;
  v_fallback_approver_id uuid;
  v_previous_config jsonb;
  v_new_config jsonb;
  v_migrated_instance_count integer;
begin
  select tenant.id
  into strict v_tenant_id
  from public.sys_tenant tenant
  where tenant.tenant_code = 'yq_2026_001'
    and tenant.status = '1';

  select app_user.id
  into strict v_primary_approver_id
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = '武安子成'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select app_user.id
  into strict v_fallback_approver_id
  from public.sys_user app_user
  where app_user.tenant_id = v_tenant_id
    and app_user.user_name = '王俊'
    and app_user.status = '1'
    and app_user.deleted_at is null
    and app_user.auth_user_id is not null;

  select definition.id, definition.current_version_id, version.config
  into strict v_definition_id, v_previous_version_id, v_previous_config
  from public.wf_definition definition
  join public.wf_version version on version.id = definition.current_version_id
  where definition.tenant_id = v_tenant_id
    and definition.code = 'smis_tool_return_multi_level'
    and definition.business_type = 'smis_tool_return'
    and definition.status = 'published'
    and version.status = 'published'
  for update of definition, version;

  if not exists (
    select 1
    from jsonb_array_elements(v_previous_config -> 'nodes') node
    where node ->> 'key' = 'warehouse_final_review'
  ) then
    raise exception '工器具归还流程缺少库房终审节点，无法应用备用审批人修复';
  end if;

  select jsonb_set(
    v_previous_config,
    '{nodes}',
    jsonb_agg(
      case
        when node ->> 'key' = 'warehouse_final_review' then
          jsonb_set(
            node,
            '{assignee,userIds}',
            jsonb_build_array(v_primary_approver_id::text, v_fallback_approver_id::text),
            true
          )
        else node
      end
      order by (node ->> 'order')::integer
    ),
    true
  )
  into v_new_config
  from jsonb_array_elements(v_previous_config -> 'nodes') node;

  perform app_private.validate_workflow_config(v_new_config);

  select coalesce(max(version.version_no), 0) + 1
  into v_new_version_no
  from public.wf_version version
  where version.definition_id = v_definition_id;

  update public.wf_version
  set status = 'retired',
      update_by = 'workflow-remediation',
      update_time = now()
  where id = v_previous_version_id
    and status = 'published';

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
    v_new_version_id,
    v_definition_id,
    v_new_version_no,
    'published',
    v_new_config,
    '库房终审增加备用审批人，避免发起人与唯一审批人相同时无法进入下一节点',
    now(),
    'workflow-remediation',
    v_tenant_id,
    'workflow-remediation',
    'workflow-remediation'
  );

  update public.wf_definition
  set current_version_id = v_new_version_id,
      published_at = now(),
      published_by = 'workflow-remediation',
      update_by = 'workflow-remediation',
      update_time = now()
  where id = v_definition_id;

  update public.wf_instance instance
  set version_id = v_new_version_id,
      row_version = instance.row_version + 1,
      update_by = 'workflow-remediation',
      update_time = now()
  where instance.definition_id = v_definition_id
    and instance.version_id = v_previous_version_id
    and instance.business_type = 'smis_tool_return'
    and instance.status = 'running'
    and instance.current_node_key = 'safety_joint_review'
    and instance.business_id = (
      select tool_return.id
      from public.smis_tool_return tool_return
      where tool_return.tenant_id = v_tenant_id
        and tool_return.return_no = 'GH2026080001'
      order by tool_return.create_time desc
      limit 1
    );

  get diagnostics v_migrated_instance_count = row_count;

  if v_migrated_instance_count <> 1 then
    raise exception '当前工器具归还审批实例状态已变化，请重新核对后再应用修复';
  end if;
end;
$$;

;
