begin;

select pg_advisory_xact_lock(
  hashtextextended('seed_complete_smis_hazard_dictionary_catalog', 0)
);

create temporary table smis_primary_hazard_seed (
  item_key text primary key,
  label text not null,
  sort bigint not null
) on commit drop;

insert into smis_primary_hazard_seed (item_key, label, sort)
values
  ('basic_management', '基础管理', 1),
  ('site_management', '现场管理', 2);

create temporary table smis_secondary_hazard_seed (
  primary_key text not null references smis_primary_hazard_seed (item_key),
  item_key text primary key,
  label text not null,
  sort bigint not null
) on commit drop;

insert into smis_secondary_hazard_seed (primary_key, item_key, label, sort)
values
  ('basic_management', 'personal_protective_equipment', '个体防护装备', 1),
  ('basic_management', 'accident_report_investigation', '事故报告、调查和处理', 2),
  ('basic_management', 'hazard_inspection_governance', '事故隐患排查治理', 3),
  ('basic_management', 'basic_other', '其他', 4),
  ('basic_management', 'safety_training', '安全培训教育', 5),
  ('basic_management', 'safety_investment', '安全投入', 6),
  ('basic_management', 'safety_management_organization', '安全生产管理机构及人员', 7),
  ('basic_management', 'safety_rules', '安全规章制度', 8),
  ('basic_management', 'emergency_management', '应急管理', 9),
  ('basic_management', 'related_party_management', '相关方管理', 10),
  ('basic_management', 'occupational_health', '职业健康', 11),
  ('basic_management', 'qualification_license', '资质证照', 12),
  ('basic_management', 'major_hazard_source', '重大危险源管理', 13),
  ('site_management', 'personal_protection', '个体防护', 1),
  ('site_management', 'workplace', '作业场所', 2),
  ('site_management', 'work_permit', '作业许可', 3),
  ('site_management', 'site_other', '其他', 4),
  ('site_management', 'raw_material_product', '原辅物料、产品', 5),
  ('site_management', 'safety_skill', '安全技能', 6),
  ('site_management', 'related_party_operation', '相关方作业', 7),
  ('site_management', 'occupational_hazard', '职业病危害', 8),
  ('site_management', 'equipment_facility', '设备设施', 9),
  ('site_management', 'protective_equipment', '防护、保险、信号等装置装备', 10);

create temporary table smis_hazard_content_seed (
  secondary_key text not null references smis_secondary_hazard_seed (item_key),
  item_key text primary key,
  label text not null,
  sort bigint not null
) on commit drop;

insert into smis_hazard_content_seed (secondary_key, item_key, label, sort)
values
  ('personal_protective_equipment', 'personal_protective_equipment_management', '个体防护装备管理缺陷', 1),
  ('personal_protective_equipment', 'personal_protective_equipment_shortage', '个体防护装备配备不足', 2),
  ('personal_protective_equipment', 'personal_protective_equipment_other', '其他', 3),
  ('accident_report_investigation', 'accident_report_defect', '事故报告缺陷', 1),
  ('accident_report_investigation', 'accident_investigation_defect', '事故调查和处理缺陷', 2),
  ('accident_report_investigation', 'accident_report_investigation_other', '其他', 3),
  ('hazard_inspection_governance', 'hazard_reporting_insufficient', '事故隐患上报不足', 1),
  ('hazard_inspection_governance', 'hazard_inspection_insufficient', '事故隐患排查不足', 2),
  ('hazard_inspection_governance', 'hazard_governance_insufficient', '事故隐患治理不足', 3),
  ('hazard_inspection_governance', 'hazard_inspection_governance_other', '其他', 4),
  ('basic_other', 'basic_other_defect', '其他缺陷', 1),
  ('safety_training', 'general_employee_training_insufficient', '一般从业人员培训教育不足', 1),
  ('safety_training', 'responsible_manager_training_insufficient', '主要负责人、安全管理人员培训教育不足', 2),
  ('safety_training', 'special_operation_training_insufficient', '特种作业人员、特种设备作业人员培训教育不足', 3),
  ('safety_investment', 'safety_investment_other', '其他', 1),
  ('safety_investment', 'safety_investment_insufficient', '安全投入不足', 2),
  ('safety_investment', 'safety_investment_use_defect', '安全投入使用缺陷', 3),
  ('safety_management_organization', 'safety_management_organization_other', '其他', 1),
  ('safety_management_organization', 'safety_management_organization_setup', '安全生产管理机构（含职业健康管理机构）设置缺陷', 2),
  ('safety_management_organization', 'safety_management_staffing', '安全管理人员（含职业健康管理人员）配备缺陷', 3),
  ('safety_rules', 'safety_rules_other', '其他', 1),
  ('safety_rules', 'document_management_defect', '制度（文件）管理缺陷', 2),
  ('safety_rules', 'safety_operation_procedure_defect', '安全操作规程缺陷', 3),
  ('safety_rules', 'safety_responsibility_system_defect', '安全生产责任制缺陷', 4),
  ('safety_rules', 'safety_management_system_defect', '安全管理制度缺陷', 5),
  ('emergency_management', 'emergency_management_other', '其他', 1),
  ('emergency_management', 'emergency_drill_assessment_defect', '应急演练实施及评估总结缺陷', 2),
  ('emergency_management', 'emergency_organization_defect', '应急组织机构和队伍缺陷', 3),
  ('emergency_management', 'emergency_resources_management_defect', '应急设施、装备、物资设置配备、维修保养和管理缺陷', 4),
  ('emergency_management', 'emergency_plan_management_defect', '应急预案制定及管理缺陷', 5),
  ('related_party_management', 'related_party_management_other', '其他', 1),
  ('related_party_management', 'related_party_supervision_defect', '安全教育、监督管理缺陷', 2),
  ('related_party_management', 'related_party_responsibility_defect', '安全职责约定缺陷', 3),
  ('related_party_management', 'related_party_qualification_defect', '相关方资质缺陷', 4),
  ('occupational_health', 'occupational_health_other', '其他', 1),
  ('occupational_health', 'occupational_health_examination_defect', '职业健康检查缺陷', 2),
  ('occupational_health', 'occupational_hazard_notification_defect', '职业病危害因素告知缺陷', 3),
  ('occupational_health', 'occupational_hazard_evaluation_defect', '职业病危害因素检测评价缺陷', 4),
  ('occupational_health', 'occupational_hazard_declaration_defect', '职业病危害项目申报缺陷', 5),
  ('qualification_license', 'qualification_license_other', '其他', 1),
  ('qualification_license', 'qualification_license_missing', '缺少资质证照', 2),
  ('qualification_license', 'qualification_license_invalid', '资质证照未合法有效', 3),
  ('major_hazard_source', 'major_hazard_source_other', '其他', 1),
  ('major_hazard_source', 'major_hazard_source_filing_defect', '登记建档备案缺陷', 2),
  ('major_hazard_source', 'major_hazard_source_monitoring_defect', '重大危险源监控预警缺陷', 3),
  ('major_hazard_source', 'major_hazard_source_assessment_defect', '重大危险源辨识与评估缺陷', 4),
  ('personal_protection', 'unsafe_dress', '不安全装束', 1),
  ('personal_protection', 'personal_protective_equipment_use_defect', '个体防护装备使用缺陷', 2),
  ('personal_protection', 'personal_protection_other', '其他', 3),
  ('workplace', 'traffic_route_configuration_defect', '交通线路的配置缺陷', 1),
  ('workplace', 'workplace_other', '其他', 2),
  ('workplace', 'temporary_opening_defect', '临时开口缺陷', 3),
  ('workplace', 'workplace_narrow_cluttered', '场地狭窄杂乱', 4),
  ('workplace', 'safety_sign_defect', '安全标志缺陷', 5),
  ('workplace', 'safety_escape_defect', '安全逃生缺陷', 6),
  ('workplace', 'layout_defect', '平面布局缺陷', 7),
  ('workplace', 'design_construction_defect', '设计、施工缺陷', 8),
  ('workplace', 'site_selection_defect', '选址缺陷', 9),
  ('work_permit', 'work_permit_not_obtained', '作业前未办理许可手续', 1),
  ('work_permit', 'work_permit_other', '其他', 2),
  ('work_permit', 'safety_measures_implementation_defect', '安全措施落实缺陷', 3),
  ('site_other', 'site_other_defect', '其他缺陷', 1),
  ('raw_material_product', 'general_goods_disposal_improper', '一般物品处置不当', 1),
  ('raw_material_product', 'raw_material_product_other', '其他', 2),
  ('raw_material_product', 'hazardous_chemical_disposal_improper', '危险化学品处置不当', 3),
  ('safety_skill', 'unsafe_equipment_tool_use', '使用不安全设备、工具', 1),
  ('safety_skill', 'safety_skill_other', '其他', 2),
  ('safety_skill', 'risky_operation', '冒险作业', 3),
  ('safety_skill', 'tool_use_error', '工具使用错误', 4),
  ('safety_skill', 'operation_error', '操作错误', 5),
  ('safety_skill', 'illegal_command', '违章指挥', 6),
  ('related_party_operation', 'related_party_operation_defect', '相关方作业缺陷', 1),
  ('occupational_hazard', 'occupational_hazard_other', '其他', 1),
  ('occupational_hazard', 'occupational_hazard_identification_unclear', '职业病危害因素标识不清', 2),
  ('occupational_hazard', 'occupational_hazard_exceeded', '职业病危害超标', 3),
  ('equipment_facility', 'dedicated_equipment_facility_defect', '专用设备设施缺陷', 1),
  ('equipment_facility', 'equipment_facility_other', '其他', 2),
  ('equipment_facility', 'safety_monitoring_equipment_defect', '安全监控设备缺陷', 3),
  ('equipment_facility', 'process_flow_defect', '工艺流程缺陷', 4),
  ('equipment_facility', 'high_risk_equipment_facility_defect', '有较大危险因素设备设施缺陷', 5),
  ('equipment_facility', 'firefighting_equipment_facility_defect', '消防设备设施缺陷', 6),
  ('equipment_facility', 'special_equipment_defect', '特种设备缺陷', 7),
  ('equipment_facility', 'electrical_equipment_defect', '电气设备缺陷', 8),
  ('equipment_facility', 'general_equipment_facility_defect', '通用设备设施缺陷', 9),
  ('protective_equipment', 'protective_equipment_other', '其他', 1),
  ('protective_equipment', 'no_protection', '无防护', 2),
  ('protective_equipment', 'improper_protection', '防护不当', 3),
  ('protective_equipment', 'protective_device_facility_defect', '防护装置、设施缺陷', 4);

create temporary table smis_hazard_level_seed (
  item_key text primary key,
  label text not null,
  sort bigint not null
) on commit drop;

insert into smis_hazard_level_seed (item_key, label, sort)
values
  ('major', '重大隐患', 1),
  ('general_a', '一般隐患A', 2),
  ('general_b', '一般隐患B', 3),
  ('general_c', '一般隐患C', 4),
  ('general_d', '一般隐患D', 5);

create temporary table smis_risk_level_seed (
  item_key text primary key,
  label text not null,
  sort bigint not null
) on commit drop;

insert into smis_risk_level_seed (item_key, label, sort)
values
  ('major_a', '重大风险(A级)', 1),
  ('higher_b', '较大风险(B级)', 2),
  ('general_c', '一般风险(C级)', 3),
  ('low_d', '低风险(D级)', 4);

do $$
declare
  v_type_count integer;
begin
  select count(*)
  into v_type_count
  from public.sys_dict_type
  where code in (
    'smisPrimaryHazardCategory',
    'smisSecondaryHazardCategory',
    'smisHazardContent',
    'smisHazardLevel',
    'smisRiskLevel'
  );

  if v_type_count <> 5 then
    raise exception 'SMIS 隐患字典类型不完整，期望 5 个，实际 % 个', v_type_count;
  end if;

  if exists (
    select 1
    from public.sys_dict_type
    where code in (
      'smisPrimaryHazardCategory',
      'smisSecondaryHazardCategory',
      'smisHazardContent',
      'smisHazardLevel',
      'smisRiskLevel'
    )
    group by code
    having count(*) <> 1
  ) then
    raise exception 'SMIS 隐患字典类型编码存在重复';
  end if;
end;
$$;

update public.sys_dictionary dictionary_item
set status = '1',
    sort = seed.sort,
    update_by = 'system:migration',
    update_time = now()
from public.sys_dict_type dictionary_type,
     smis_primary_hazard_seed seed
where dictionary_type.code = 'smisPrimaryHazardCategory'
  and dictionary_item.type_id = dictionary_type.id
  and btrim(dictionary_item.label) = seed.label;

insert into public.sys_dictionary (
  type_id,
  code,
  status,
  create_by,
  remark,
  value,
  label,
  sort,
  tenant_id
)
select
  dictionary_type.id,
  seed.item_key,
  '1',
  'system:migration',
  '依据隐患分类目录补齐',
  seed.item_key,
  seed.label,
  seed.sort,
  app_private.platform_tenant_id()
from public.sys_dict_type dictionary_type
cross join smis_primary_hazard_seed seed
where dictionary_type.code = 'smisPrimaryHazardCategory'
  and not exists (
    select 1
    from public.sys_dictionary dictionary_item
    where dictionary_item.type_id = dictionary_type.id
      and btrim(dictionary_item.label) = seed.label
  );

do $$
begin
  if exists (
    select 1
    from smis_primary_hazard_seed seed
    join public.sys_dict_type dictionary_type
      on dictionary_type.code = 'smisPrimaryHazardCategory'
    left join public.sys_dictionary dictionary_item
      on dictionary_item.type_id = dictionary_type.id
     and btrim(dictionary_item.label) = seed.label
    group by seed.item_key
    having count(dictionary_item.id) <> 1
  ) then
    raise exception '一级隐患类别存在缺失或同名重复项';
  end if;
end;
$$;

update public.sys_dictionary secondary_item
set status = '1',
    sort = secondary_seed.sort,
    update_by = 'system:migration',
    update_time = now()
from smis_secondary_hazard_seed secondary_seed
join smis_primary_hazard_seed primary_seed
  on primary_seed.item_key = secondary_seed.primary_key
join public.sys_dict_type primary_type
  on primary_type.code = 'smisPrimaryHazardCategory'
join public.sys_dictionary primary_item
  on primary_item.type_id = primary_type.id
 and btrim(primary_item.label) = primary_seed.label
join public.sys_dict_type secondary_type
  on secondary_type.code = 'smisSecondaryHazardCategory'
where secondary_item.type_id = secondary_type.id
  and secondary_item.cascade_parent_id = primary_item.id
  and btrim(secondary_item.label) = secondary_seed.label;

insert into public.sys_dictionary (
  type_id,
  code,
  status,
  create_by,
  remark,
  value,
  label,
  sort,
  tenant_id,
  cascade_parent_id
)
select
  secondary_type.id,
  secondary_seed.item_key,
  '1',
  'system:migration',
  '依据隐患分类目录补齐',
  secondary_seed.item_key,
  secondary_seed.label,
  secondary_seed.sort,
  app_private.platform_tenant_id(),
  primary_item.id
from smis_secondary_hazard_seed secondary_seed
join smis_primary_hazard_seed primary_seed
  on primary_seed.item_key = secondary_seed.primary_key
join public.sys_dict_type primary_type
  on primary_type.code = 'smisPrimaryHazardCategory'
join public.sys_dictionary primary_item
  on primary_item.type_id = primary_type.id
 and btrim(primary_item.label) = primary_seed.label
join public.sys_dict_type secondary_type
  on secondary_type.code = 'smisSecondaryHazardCategory'
where not exists (
  select 1
  from public.sys_dictionary secondary_item
  where secondary_item.type_id = secondary_type.id
    and secondary_item.cascade_parent_id = primary_item.id
    and btrim(secondary_item.label) = secondary_seed.label
);

do $$
begin
  if exists (
    select 1
    from smis_secondary_hazard_seed secondary_seed
    join smis_primary_hazard_seed primary_seed
      on primary_seed.item_key = secondary_seed.primary_key
    join public.sys_dict_type primary_type
      on primary_type.code = 'smisPrimaryHazardCategory'
    join public.sys_dictionary primary_item
      on primary_item.type_id = primary_type.id
     and btrim(primary_item.label) = primary_seed.label
    join public.sys_dict_type secondary_type
      on secondary_type.code = 'smisSecondaryHazardCategory'
    left join public.sys_dictionary secondary_item
      on secondary_item.type_id = secondary_type.id
     and secondary_item.cascade_parent_id = primary_item.id
     and btrim(secondary_item.label) = secondary_seed.label
    group by secondary_seed.item_key
    having count(secondary_item.id) <> 1
  ) then
    raise exception '二级隐患类别存在缺失、同名重复或级联错误';
  end if;
end;
$$;

update public.sys_dictionary content_item
set status = '1',
    sort = content_seed.sort,
    update_by = 'system:migration',
    update_time = now()
from smis_hazard_content_seed content_seed
join smis_secondary_hazard_seed secondary_seed
  on secondary_seed.item_key = content_seed.secondary_key
join smis_primary_hazard_seed primary_seed
  on primary_seed.item_key = secondary_seed.primary_key
join public.sys_dict_type primary_type
  on primary_type.code = 'smisPrimaryHazardCategory'
join public.sys_dictionary primary_item
  on primary_item.type_id = primary_type.id
 and btrim(primary_item.label) = primary_seed.label
join public.sys_dict_type secondary_type
  on secondary_type.code = 'smisSecondaryHazardCategory'
join public.sys_dictionary secondary_item
  on secondary_item.type_id = secondary_type.id
 and secondary_item.cascade_parent_id = primary_item.id
 and btrim(secondary_item.label) = secondary_seed.label
join public.sys_dict_type content_type
  on content_type.code = 'smisHazardContent'
where content_item.type_id = content_type.id
  and content_item.cascade_parent_id = secondary_item.id
  and btrim(content_item.label) = content_seed.label;

insert into public.sys_dictionary (
  type_id,
  code,
  status,
  create_by,
  remark,
  value,
  label,
  sort,
  tenant_id,
  cascade_parent_id
)
select
  content_type.id,
  'smisHazardContent_' || content_seed.item_key,
  '1',
  'system:migration',
  '依据隐患分类目录补齐',
  content_seed.label,
  content_seed.label,
  content_seed.sort,
  app_private.platform_tenant_id(),
  secondary_item.id
from smis_hazard_content_seed content_seed
join smis_secondary_hazard_seed secondary_seed
  on secondary_seed.item_key = content_seed.secondary_key
join smis_primary_hazard_seed primary_seed
  on primary_seed.item_key = secondary_seed.primary_key
join public.sys_dict_type primary_type
  on primary_type.code = 'smisPrimaryHazardCategory'
join public.sys_dictionary primary_item
  on primary_item.type_id = primary_type.id
 and btrim(primary_item.label) = primary_seed.label
join public.sys_dict_type secondary_type
  on secondary_type.code = 'smisSecondaryHazardCategory'
join public.sys_dictionary secondary_item
  on secondary_item.type_id = secondary_type.id
 and secondary_item.cascade_parent_id = primary_item.id
 and btrim(secondary_item.label) = secondary_seed.label
join public.sys_dict_type content_type
  on content_type.code = 'smisHazardContent'
where not exists (
  select 1
  from public.sys_dictionary content_item
  where content_item.type_id = content_type.id
    and content_item.cascade_parent_id = secondary_item.id
    and btrim(content_item.label) = content_seed.label
);

do $$
begin
  if exists (
    select 1
    from smis_hazard_content_seed content_seed
    join smis_secondary_hazard_seed secondary_seed
      on secondary_seed.item_key = content_seed.secondary_key
    join smis_primary_hazard_seed primary_seed
      on primary_seed.item_key = secondary_seed.primary_key
    join public.sys_dict_type primary_type
      on primary_type.code = 'smisPrimaryHazardCategory'
    join public.sys_dictionary primary_item
      on primary_item.type_id = primary_type.id
     and btrim(primary_item.label) = primary_seed.label
    join public.sys_dict_type secondary_type
      on secondary_type.code = 'smisSecondaryHazardCategory'
    join public.sys_dictionary secondary_item
      on secondary_item.type_id = secondary_type.id
     and secondary_item.cascade_parent_id = primary_item.id
     and btrim(secondary_item.label) = secondary_seed.label
    join public.sys_dict_type content_type
      on content_type.code = 'smisHazardContent'
    left join public.sys_dictionary content_item
      on content_item.type_id = content_type.id
     and content_item.cascade_parent_id = secondary_item.id
     and btrim(content_item.label) = content_seed.label
    group by content_seed.item_key
    having count(content_item.id) <> 1
  ) then
    raise exception '隐患内容存在缺失、同名重复或级联错误';
  end if;
end;
$$;

update public.sys_dictionary dictionary_item
set status = '1',
    sort = seed.sort,
    update_by = 'system:migration',
    update_time = now()
from public.sys_dict_type dictionary_type,
     smis_hazard_level_seed seed
where dictionary_type.code = 'smisHazardLevel'
  and dictionary_item.type_id = dictionary_type.id
  and btrim(dictionary_item.label) = seed.label;

insert into public.sys_dictionary (
  type_id, code, status, create_by, remark, value, label, sort, tenant_id
)
select
  dictionary_type.id,
  seed.item_key,
  '1',
  'system:migration',
  '依据隐患级别目录补齐',
  seed.item_key,
  seed.label,
  seed.sort,
  app_private.platform_tenant_id()
from public.sys_dict_type dictionary_type
cross join smis_hazard_level_seed seed
where dictionary_type.code = 'smisHazardLevel'
  and not exists (
    select 1
    from public.sys_dictionary dictionary_item
    where dictionary_item.type_id = dictionary_type.id
      and btrim(dictionary_item.label) = seed.label
  );

update public.sys_dictionary dictionary_item
set status = '1',
    sort = seed.sort,
    update_by = 'system:migration',
    update_time = now()
from public.sys_dict_type dictionary_type,
     smis_risk_level_seed seed
where dictionary_type.code = 'smisRiskLevel'
  and dictionary_item.type_id = dictionary_type.id
  and btrim(dictionary_item.label) = seed.label;

insert into public.sys_dictionary (
  type_id, code, status, create_by, remark, value, label, sort, tenant_id
)
select
  dictionary_type.id,
  seed.item_key,
  '1',
  'system:migration',
  '依据风险等级目录补齐',
  seed.item_key,
  seed.label,
  seed.sort,
  app_private.platform_tenant_id()
from public.sys_dict_type dictionary_type
cross join smis_risk_level_seed seed
where dictionary_type.code = 'smisRiskLevel'
  and not exists (
    select 1
    from public.sys_dictionary dictionary_item
    where dictionary_item.type_id = dictionary_type.id
      and btrim(dictionary_item.label) = seed.label
  );

do $$
begin
  if exists (
    select 1
    from smis_hazard_level_seed seed
    join public.sys_dict_type dictionary_type
      on dictionary_type.code = 'smisHazardLevel'
    left join public.sys_dictionary dictionary_item
      on dictionary_item.type_id = dictionary_type.id
     and btrim(dictionary_item.label) = seed.label
     and dictionary_item.status = '1'
    group by seed.item_key
    having count(dictionary_item.id) <> 1
  ) then
    raise exception '隐患级别存在缺失或同名重复项';
  end if;

  if exists (
    select 1
    from smis_risk_level_seed seed
    join public.sys_dict_type dictionary_type
      on dictionary_type.code = 'smisRiskLevel'
    left join public.sys_dictionary dictionary_item
      on dictionary_item.type_id = dictionary_type.id
     and btrim(dictionary_item.label) = seed.label
     and dictionary_item.status = '1'
    group by seed.item_key
    having count(dictionary_item.id) <> 1
  ) then
    raise exception '隐患风险等级存在缺失或同名重复项';
  end if;
end;
$$;

commit;

;
