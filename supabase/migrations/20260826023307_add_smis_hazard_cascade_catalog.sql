alter table public.sys_dictionary
add column if not exists cascade_parent_id uuid;

comment on column public.sys_dictionary.cascade_parent_id is
'跨字典类型级联的上级字典项；同类型树仍使用 parent_id';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sys_dictionary_cascade_parent_id_fkey'
      and conrelid = 'public.sys_dictionary'::regclass
  ) then
    alter table public.sys_dictionary
    add constraint sys_dictionary_cascade_parent_id_fkey
    foreign key (cascade_parent_id)
    references public.sys_dictionary(id)
    on delete restrict;
  end if;
end
$$;

create index if not exists idx_sys_dictionary_cascade_parent_id
on public.sys_dictionary(cascade_parent_id);

do $$
declare
  v_actor constant text := '624944977@qq.com';
  v_platform_tenant_id uuid;
  v_basic_data_directory_id uuid;
  v_hazard_content_type_id uuid;
  v_canonical_safety_rules_id uuid;
  v_legacy_safety_rules_id uuid;
begin
  select tenant.id
  into v_platform_tenant_id
  from public.sys_tenant tenant
  where tenant.tenant_code = 'platform'
  limit 1;

  select dictionary_type.id
  into v_basic_data_directory_id
  from public.sys_dict_type dictionary_type
  where dictionary_type.tenant_id = v_platform_tenant_id
    and dictionary_type.code = 'smisBasicData'
    and dictionary_type.node_type = 'directory'
  limit 1;

  if v_platform_tenant_id is null or v_basic_data_directory_id is null then
    raise exception 'SMIS 基础数据字典目录不存在，无法建立隐患级联字典';
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
  values (
    gen_random_uuid(),
    '隐患内容',
    'smisHazardContent',
    '1',
    v_actor,
    v_actor,
    '按二级隐患类别级联的隐患内容',
    v_platform_tenant_id,
    v_basic_data_directory_id,
    'dictionary',
    12
  )
  on conflict (code) do update
  set
    name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now(),
    remark = excluded.remark,
    tenant_id = excluded.tenant_id,
    parent_id = excluded.parent_id,
    node_type = excluded.node_type,
    sort = excluded.sort;

  update public.sys_dict_type dictionary_type
  set
    parent_id = v_basic_data_directory_id,
    sort = placement.sort,
    update_by = v_actor,
    update_time = now()
  from (
    values
      ('smisHolidayType', 10),
      ('smisSiteCategory', 11),
      ('smisHazardContent', 12)
  ) as placement(code, sort)
  where dictionary_type.tenant_id = v_platform_tenant_id
    and dictionary_type.code = placement.code;

  select id
  into v_hazard_content_type_id
  from public.sys_dict_type
  where tenant_id = v_platform_tenant_id
    and code = 'smisHazardContent'
  limit 1;

  select dictionary_item.id
  into v_canonical_safety_rules_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisSecondaryHazardCategory'
    and dictionary_item.value = 'safety_rules'
  limit 1;

  select dictionary_item.id
  into v_legacy_safety_rules_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisSecondaryHazardCategory'
    and dictionary_item.value = '03'
  limit 1;

  if v_canonical_safety_rules_id is not null and v_legacy_safety_rules_id is not null then
    update public.sys_dictionary
    set cascade_parent_id = v_canonical_safety_rules_id
    where cascade_parent_id = v_legacy_safety_rules_id;

    update public.smis_position_safety_responsibility
    set secondary_hazard_category = 'safety_rules'
    where secondary_hazard_category = '03';

    update public.smis_position_risk_control
    set secondary_hazard_category = 'safety_rules'
    where secondary_hazard_category = '03';

    delete from public.sys_dictionary
    where id = v_legacy_safety_rules_id;
  end if;

  update public.sys_dictionary child
  set
    cascade_parent_id = parent.id,
    update_by = v_actor,
    update_time = now()
  from public.sys_dict_type child_type,
       public.sys_dictionary parent,
       public.sys_dict_type parent_type
  where child.type_id = child_type.id
    and child_type.code = 'smisSecondaryHazardCategory'
    and parent.type_id = parent_type.id
    and parent_type.code = 'smisPrimaryHazardCategory'
    and child.tenant_id = v_platform_tenant_id
    and parent.tenant_id = v_platform_tenant_id
    and child.remark in (parent.value, parent.label);

  if exists (
    select 1
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisSecondaryHazardCategory'
      and dictionary_item.status = '1'
      and dictionary_item.cascade_parent_id is null
  ) then
    raise exception '存在未关联一级类别的二级隐患类别，无法启用三级级联';
  end if;

  insert into public.sys_dictionary (
    id,
    type_id,
    code,
    status,
    create_by,
    update_by,
    remark,
    value,
    label,
    tenant_id,
    tag_type,
    sort,
    cascade_parent_id
  )
  select
    gen_random_uuid(),
    v_hazard_content_type_id,
    'smisHazardContent_' || seed.item_code,
    '1',
    v_actor,
    v_actor,
    '来源于隐患排查标准级联目录',
    seed.content,
    seed.content,
    v_platform_tenant_id,
    '',
    seed.sort,
    secondary.id
  from (
    values
      ('safety_rules', 'safety_rules_management', '安全管理制度缺陷', 1),
      ('safety_rules', 'safety_rules_fire', '火灾', 2),
      ('01', 'emergency_plan', '应急预案制定及管理缺陷', 1),
      ('01', 'emergency_organization', '应急组织机构和队伍缺陷', 2),
      ('01', 'emergency_drill', '应急演练实施及评估总结缺陷', 3),
      ('01', 'emergency_equipment', '应急设施、装备、物资设置配备、维修保养和管理缺陷', 4),
      ('02', 'qualification_invalid', '资质证照未合法有效', 1),
      ('02', 'qualification_missing', '缺少资质证照', 2),
      ('occupational_hazard', 'occupational_identification', '职业病危害因素标识不清', 1),
      ('occupational_hazard', 'occupational_exceeded', '职业病危害超标', 2),
      ('equipment_facility', 'dedicated_equipment', '专用设备设施缺陷', 1),
      ('equipment_facility', 'special_equipment', '特种设备缺陷', 2),
      ('equipment_facility', 'general_equipment', '通用设备设施缺陷', 3),
      ('equipment_facility', 'high_risk_equipment', '有较大危险因素设备设施缺陷', 4),
      ('equipment_facility', 'process_flow', '工艺流程缺陷', 5),
      ('equipment_facility', 'fire_equipment', '消防设备设施缺陷', 6),
      ('equipment_facility', 'safety_monitoring', '安全监控设备缺陷', 7),
      ('equipment_facility', 'electrical_equipment', '电气设备缺陷', 8)
  ) as seed(secondary_value, item_code, content, sort)
  join public.sys_dictionary secondary on secondary.value = seed.secondary_value
  join public.sys_dict_type secondary_type on secondary_type.id = secondary.type_id
    and secondary_type.code = 'smisSecondaryHazardCategory'
  where not exists (
    select 1
    from public.sys_dictionary existing
    where existing.type_id = v_hazard_content_type_id
      and existing.cascade_parent_id = secondary.id
      and existing.value = seed.content
  );

  insert into public.sys_dictionary (
    id,
    type_id,
    code,
    status,
    create_by,
    update_by,
    remark,
    value,
    label,
    tenant_id,
    tag_type,
    sort,
    cascade_parent_id
  )
  select
    gen_random_uuid(),
    v_hazard_content_type_id,
    'smisHazardContent_legacy_' || substr(md5(source.secondary_value || ':' || source.content), 1, 16),
    '1',
    v_actor,
    v_actor,
    '由现有隐患排查标准补录',
    source.content,
    source.content,
    v_platform_tenant_id,
    '',
    900,
    secondary.id
  from (
    select distinct
      responsibility.secondary_hazard_category as secondary_value,
      btrim(responsibility.hazard_content) as content
    from public.smis_position_safety_responsibility responsibility
    where btrim(responsibility.hazard_content) <> ''
  ) source
  join public.sys_dictionary secondary on secondary.value = source.secondary_value
  join public.sys_dict_type secondary_type on secondary_type.id = secondary.type_id
    and secondary_type.code = 'smisSecondaryHazardCategory'
  where not exists (
    select 1
    from public.sys_dictionary existing
    where existing.type_id = v_hazard_content_type_id
      and existing.cascade_parent_id = secondary.id
      and existing.value = source.content
  );

  insert into public.sys_dictionary (
    id,
    type_id,
    code,
    status,
    create_by,
    update_by,
    remark,
    value,
    label,
    tenant_id,
    tag_type,
    sort,
    cascade_parent_id
  )
  select
    gen_random_uuid(),
    v_hazard_content_type_id,
    'smisHazardContent_' || secondary.value || '_other',
    '1',
    v_actor,
    v_actor,
    '兜底隐患内容',
    '其他',
    '其他',
    v_platform_tenant_id,
    '',
    999,
    secondary.id
  from public.sys_dictionary secondary
  join public.sys_dict_type secondary_type on secondary_type.id = secondary.type_id
    and secondary_type.code = 'smisSecondaryHazardCategory'
  where secondary.status = '1'
    and not exists (
      select 1
      from public.sys_dictionary existing
      where existing.type_id = v_hazard_content_type_id
        and existing.cascade_parent_id = secondary.id
        and existing.value = '其他'
    );
end
$$;

create or replace function app_private.validate_smis_hazard_cascade()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_primary_item_id uuid;
  v_secondary_item_id uuid;
begin
  select dictionary_item.id
  into v_primary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisPrimaryHazardCategory'
    and dictionary_item.status = '1'
    and dictionary_item.value = new.primary_hazard_category
  limit 1;

  if v_primary_item_id is null then
    raise exception '一级隐患类别无效，请重新选择' using errcode = '23514';
  end if;

  select dictionary_item.id
  into v_secondary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisSecondaryHazardCategory'
    and dictionary_item.status = '1'
    and dictionary_item.cascade_parent_id = v_primary_item_id
    and dictionary_item.value = new.secondary_hazard_category
  limit 1;

  if v_secondary_item_id is null then
    raise exception '二级隐患类别不属于所选一级类别，请重新选择' using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisHazardContent'
      and dictionary_item.status = '1'
      and dictionary_item.cascade_parent_id = v_secondary_item_id
      and dictionary_item.value = btrim(new.hazard_content)
  ) then
    raise exception '隐患内容不属于所选二级类别，请重新选择' using errcode = '23514';
  end if;

  new.hazard_content := btrim(new.hazard_content);
  return new;
end;
$$;

drop trigger if exists smis_position_safety_responsibility_validate_hazard_cascade
on public.smis_position_safety_responsibility;

create trigger smis_position_safety_responsibility_validate_hazard_cascade
before insert or update of primary_hazard_category, secondary_hazard_category, hazard_content
on public.smis_position_safety_responsibility
for each row
execute function app_private.validate_smis_hazard_cascade();

revoke all on function app_private.validate_smis_hazard_cascade() from public, anon, authenticated;

;
