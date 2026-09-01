-- The carrier tenant currently has one enabled administrator and no users in
-- the finance-owner role. Keep the approval lifecycle intact, but allow that
-- single administrator to submit and then approve the waybill-cost task.
do $migration$
declare
  v_tenant_id uuid;
  v_definition public.wf_definition;
  v_current_version public.wf_version;
  v_new_version public.wf_version;
  v_new_config jsonb;
  v_actor constant text := 'system:workflow-repair';
begin
  select t.id
  into v_tenant_id
  from public.sys_tenant t
  where t.tenant_code = 'yq_2026_001'
    and t.status = '1';

  if not found then
    raise exception '未找到启用的目标租户 yq_2026_001';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_tenant_id::text || ':tms_waybill_cost',
      81173
    )
  );

  select d.*
  into v_definition
  from public.wf_definition d
  where d.tenant_id = v_tenant_id
    and d.code = 'tms_003'
    and d.business_type = 'tms_waybill_cost'
    and d.status = 'published'
  for update;

  if not found then
    raise exception '未找到目标租户已发布的运单费用审批流程';
  end if;

  select v.*
  into v_current_version
  from public.wf_version v
  where v.id = v_definition.current_version_id
    and v.definition_id = v_definition.id
    and v.status = 'published'
  for update;

  if not found then
    raise exception '运单费用审批流程未指向有效的已发布版本';
  end if;

  if coalesce(
    (v_current_version.config #>> '{nodes,0,allowSelfApproval}')::boolean,
    false
  ) then
    return;
  end if;

  if jsonb_array_length(coalesce(v_current_version.config -> 'nodes', '[]'::jsonb)) <> 1
     or v_current_version.config #>> '{nodes,0,name}' <> '财务负责人'
     or not (
       v_current_version.config #> '{nodes,0,assignee,roleCodes}'
       @> '["yq_2026_001"]'::jsonb
     ) then
    raise exception '运单费用审批流程配置已变化，请重新评估自审修复';
  end if;

  v_new_config := jsonb_set(
    v_current_version.config,
    '{nodes,0,allowSelfApproval}',
    'true'::jsonb,
    false
  );
  perform app_private.validate_workflow_config(v_new_config);

  insert into public.wf_version (
    definition_id,
    version_no,
    status,
    config,
    change_note,
    tenant_id,
    create_by,
    update_by
  )
  select
    v_definition.id,
    coalesce(max(v.version_no), 0) + 1,
    'draft',
    v_new_config,
    '修复单用户租户提交时无可用审批人：允许本节点发起人自审',
    v_definition.tenant_id,
    v_actor,
    v_actor
  from public.wf_version v
  where v.definition_id = v_definition.id
  returning * into v_new_version;

  update public.wf_version
  set status = 'retired', update_by = v_actor
  where id = v_current_version.id;

  update public.wf_version
  set status = 'published',
      published_at = now(),
      published_by = v_actor,
      update_by = v_actor
  where id = v_new_version.id
  returning * into v_new_version;

  update public.wf_definition
  set current_version_id = v_new_version.id,
      published_at = now(),
      published_by = v_actor,
      update_by = v_actor
  where id = v_definition.id;
end
$migration$;

;
