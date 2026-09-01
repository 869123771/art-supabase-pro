do $$
declare
  v_parent_id uuid;
  v_tenant_id uuid;
  v_type_id uuid;
begin
  select id, tenant_id
  into v_parent_id, v_tenant_id
  from public.sys_dict_type
  where code = 'smisEmergencyRescue'
  limit 1;

  if v_parent_id is null then
    raise exception '未找到应急救援字典目录';
  end if;

  select id
  into v_type_id
  from public.sys_dict_type
  where code = 'smisEmergencyDrillRecordStatus'
  limit 1;

  if v_type_id is null then
    insert into public.sys_dict_type (
      name, code, status, create_by, update_by, tenant_id, parent_id, node_type, sort
    ) values (
      '应急演练记录状态', 'smisEmergencyDrillRecordStatus', '1',
      'migration', 'migration', v_tenant_id, v_parent_id, 'dictionary', 8
    )
    returning id into v_type_id;
  end if;

  if not exists (
    select 1 from public.sys_dictionary
    where type_id = v_type_id and value = 'draft'
  ) then
    insert into public.sys_dictionary (
      type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
    ) values (
      v_type_id, 'smisEmergencyDrillRecordStatus_draft', '1',
      'migration', 'migration', 'draft', '草稿', 1, v_tenant_id, 'info'
    );
  end if;

  if not exists (
    select 1 from public.sys_dictionary
    where type_id = v_type_id and value = 'submitted'
  ) then
    insert into public.sys_dictionary (
      type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
    ) values (
      v_type_id, 'smisEmergencyDrillRecordStatus_submitted', '1',
      'migration', 'migration', 'submitted', '已提交', 2, v_tenant_id, 'success'
    );
  end if;
end
$$;;
