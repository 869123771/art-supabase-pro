do $$
declare
  v_actor constant text := '624944977@qq.com';
  v_platform_tenant_id uuid;
  v_smis_root_id uuid;
  v_basic_data_id uuid;
  v_equipment_ledger_id uuid;
  v_safety_production_id uuid;
begin
  select tenant.id
  into v_platform_tenant_id
  from public.sys_tenant tenant
  where tenant.tenant_code = 'platform'
  limit 1;

  if v_platform_tenant_id is null then
    raise exception 'Platform tenant is required before organizing SMIS dictionaries';
  end if;

  select dictionary_type.id
  into v_smis_root_id
  from public.sys_dict_type dictionary_type
  where dictionary_type.tenant_id = v_platform_tenant_id
    and dictionary_type.code = 'smis'
    and dictionary_type.node_type = 'directory'
  limit 1;

  if v_smis_root_id is null then
    raise exception 'SMIS dictionary root is required before organizing module directories';
  end if;

  insert into public.sys_dict_type (
    id,
    name,
    code,
    status,
    create_by,
    update_by,
    remark,
    tenant_id,
    parent_id,
    node_type,
    sort
  )
  select
    gen_random_uuid(),
    module.name,
    module.code,
    '1',
    v_actor,
    v_actor,
    '按 SMIS 菜单模块组织的数据字典目录',
    v_platform_tenant_id,
    v_smis_root_id,
    'directory',
    module.sort
  from (
    values
      ('基础数据', 'smisBasicData', 1),
      ('设备台账', 'smisEquipmentLedger', 2),
      ('安全生产', 'smisSafetyProduction', 3)
  ) as module(name, code, sort)
  where not exists (
    select 1
    from public.sys_dict_type existing
    where existing.tenant_id = v_platform_tenant_id
      and existing.code = module.code
  );

  update public.sys_dict_type dictionary_type
  set
    name = module.name,
    parent_id = v_smis_root_id,
    node_type = 'directory',
    status = '1',
    sort = module.sort,
    remark = '按 SMIS 菜单模块组织的数据字典目录',
    update_by = v_actor,
    update_time = now()
  from (
    values
      ('基础数据', 'smisBasicData', 1),
      ('设备台账', 'smisEquipmentLedger', 2),
      ('安全生产', 'smisSafetyProduction', 3)
  ) as module(name, code, sort)
  where dictionary_type.tenant_id = v_platform_tenant_id
    and dictionary_type.code = module.code;

  select id into v_basic_data_id
  from public.sys_dict_type
  where tenant_id = v_platform_tenant_id and code = 'smisBasicData'
  limit 1;

  select id into v_equipment_ledger_id
  from public.sys_dict_type
  where tenant_id = v_platform_tenant_id and code = 'smisEquipmentLedger'
  limit 1;

  select id into v_safety_production_id
  from public.sys_dict_type
  where tenant_id = v_platform_tenant_id and code = 'smisSafetyProduction'
  limit 1;

  if v_basic_data_id is null
    or v_equipment_ledger_id is null
    or v_safety_production_id is null then
    raise exception 'SMIS module dictionary directories could not be created';
  end if;

  update public.sys_dict_type dictionary_type
  set
    parent_id = v_basic_data_id,
    sort = mapping.sort,
    update_by = v_actor,
    update_time = now()
  from (
    values
      ('smisPrimaryHazardCategory', 1),
      ('smisSecondaryHazardCategory', 2),
      ('smisHazardLevel', 3),
      ('smisFrequencyUnit', 4),
      ('smisInspectionFrequency', 5),
      ('smisRiskLevel', 6),
      ('smisControlLevel', 7),
      ('smisControlMeasureCategory', 8),
      ('smisLeaveType', 9)
  ) as mapping(code, sort)
  where dictionary_type.tenant_id = v_platform_tenant_id
    and dictionary_type.code = mapping.code
    and dictionary_type.node_type = 'dictionary';

  update public.sys_dict_type
  set
    parent_id = v_safety_production_id,
    sort = 1,
    update_by = v_actor,
    update_time = now()
  where tenant_id = v_platform_tenant_id
    and code = 'vmsFleetHealthRisk'
    and node_type = 'dictionary';
end
$$;

;
