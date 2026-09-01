begin;

-- These three modules are siblings of 资质培训 under SMIS安全管理.
create temp table smis_navigation_seed (
  depth integer not null,
  parent_name text not null,
  name text not null,
  path text not null,
  component text not null,
  type text not null,
  title text not null,
  icon text not null,
  sort integer not null,
  primary key (name)
) on commit drop;

insert into smis_navigation_seed (
  depth,
  parent_name,
  name,
  path,
  component,
  type,
  title,
  icon,
  sort
)
values
  (1, 'SmisSafetyManagement', 'SmisDualControlSystem', 'dual-control-system', '', 'folder', '双控体系', 'ri:git-merge-line', 5),
  (1, 'SmisSafetyManagement', 'SmisSpecialOperationManagement', 'special-operation-management', '', 'folder', '特殊作业管理', 'ri:tools-line', 6),
  (1, 'SmisSafetyManagement', 'SmisHazardousWasteManagement', 'hazardous-waste-management', '', 'folder', '危废管理', 'ri:recycle-line', 7),
  (2, 'SmisDualControlSystem', 'SmisDualControlRiskControl', 'risk-control', '', 'folder', '风险管控', 'ri:shield-check-line', 1),
  (2, 'SmisDualControlSystem', 'SmisDualControlHiddenHazardGovernance', 'hidden-hazard-governance', '', 'folder', '隐患治理', 'ri:error-warning-line', 2),
  (2, 'SmisDualControlSystem', 'SmisDualControlChecklist', 'dual-control-checklist', '', 'folder', '双控清单', 'ri:list-check-3', 3),
  (2, 'SmisDualControlSystem', 'SmisDualControlReport', 'dual-control-report', '', 'folder', '双控报表', 'ri:bar-chart-box-line', 4),
  (2, 'SmisHazardousWasteManagement', 'SmisHazardousWasteWarehouseDefinition', 'warehouse-definition', '/smis/hazardous-waste-management/warehouse-definition', 'menu', '仓库定义', '', 1),
  (2, 'SmisHazardousWasteManagement', 'SmisHazardousWasteCatalog', 'hazardous-waste-catalog', '/smis/hazardous-waste-management/hazardous-waste-catalog', 'menu', '危废名录', '', 2),
  (2, 'SmisHazardousWasteManagement', 'SmisHazardousWasteInbound', 'hazardous-waste-inbound', '/smis/hazardous-waste-management/hazardous-waste-inbound', 'menu', '危废入库', '', 3),
  (2, 'SmisHazardousWasteManagement', 'SmisHazardousWasteOutbound', 'hazardous-waste-outbound', '/smis/hazardous-waste-management/hazardous-waste-outbound', 'menu', '危废出库', '', 4),
  (2, 'SmisSpecialOperationManagement', 'SmisSpecialOperationType', 'operation-type', '/smis/special-operation-management/operation-type', 'menu', '作业类型', '', 1),
  (2, 'SmisSpecialOperationManagement', 'SmisSpecialOperationSafetyChecklist', 'safety-checklist', '/smis/special-operation-management/safety-checklist', 'menu', '安全检查表', '', 2),
  (2, 'SmisSpecialOperationManagement', 'SmisSpecialOperationHazardFactor', 'hazard-factor', '/smis/special-operation-management/hazard-factor', 'menu', '危害因素', '', 3),
  (2, 'SmisSpecialOperationManagement', 'SmisSpecialOperationSiteAnalysisForm', 'site-analysis-form', '/smis/special-operation-management/site-analysis-form', 'menu', '现场分析表', '', 4),
  (2, 'SmisSpecialOperationManagement', 'SmisSpecialOperationWorkbench', 'special-operation-workbench', '/smis/special-operation-management/special-operation-workbench', 'menu', '特殊作业管理', '', 5),
  (2, 'SmisSpecialOperationManagement', 'SmisHotWorkApplication', 'hot-work-application', '/smis/special-operation-management/hot-work-application', 'menu', '动火作业申请', '', 6),
  (2, 'SmisSpecialOperationManagement', 'SmisWorkAtHeightApplication', 'work-at-height-application', '/smis/special-operation-management/work-at-height-application', 'menu', '高处作业申请', '', 7),
  (2, 'SmisSpecialOperationManagement', 'SmisLiftingOperationApplication', 'lifting-operation-application', '/smis/special-operation-management/lifting-operation-application', 'menu', '吊装作业申请', '', 8),
  (2, 'SmisSpecialOperationManagement', 'SmisConfinedSpaceOperationApplication', 'confined-space-operation-application', '/smis/special-operation-management/confined-space-operation-application', 'menu', '受限空间作业申请', '', 9),
  (2, 'SmisSpecialOperationManagement', 'SmisTemporaryElectricityApplication', 'temporary-electricity-application', '/smis/special-operation-management/temporary-electricity-application', 'menu', '临时用电作业申请', '', 10),
  (2, 'SmisSpecialOperationManagement', 'SmisRoadBreakingOperationApplication', 'road-breaking-operation-application', '/smis/special-operation-management/road-breaking-operation-application', 'menu', '断路作业申请', '', 11),
  (2, 'SmisSpecialOperationManagement', 'SmisBlindPlateOperationApplication', 'blind-plate-operation-application', '/smis/special-operation-management/blind-plate-operation-application', 'menu', '盲板抽堵申请', '', 12),
  (3, 'SmisDualControlChecklist', 'SmisDualControlPersonnelChecklist', 'personnel-dual-control-checklist', '/smis/dual-control-system/dual-control-checklist/personnel-dual-control-checklist', 'menu', '人员双控清单', '', 1),
  (3, 'SmisDualControlChecklist', 'SmisDualControlPositionRiskChecklist', 'position-risk-checklist', '/smis/dual-control-system/dual-control-checklist/position-risk-checklist', 'menu', '岗位风险清单', '', 2),
  (3, 'SmisDualControlChecklist', 'SmisDualControlAccidentHiddenHazardInspectionChecklist', 'accident-hidden-hazard-inspection-checklist', '/smis/dual-control-system/dual-control-checklist/accident-hidden-hazard-inspection-checklist', 'menu', '事故隐患排查清单', '', 3),
  (3, 'SmisDualControlChecklist', 'SmisDualControlPositionSafetyResponsibilityChecklist', 'position-safety-responsibility-checklist', '/smis/dual-control-system/dual-control-checklist/position-safety-responsibility-checklist', 'menu', '岗位安全责任制清单', '', 4),
  (3, 'SmisDualControlChecklist', 'SmisDualControlRiskControlInformationChecklist', 'risk-control-information-checklist', '/smis/dual-control-system/dual-control-checklist/risk-control-information-checklist', 'menu', '风险管控信息清单', '', 5),
  (3, 'SmisDualControlChecklist', 'SmisDualControlHiddenHazardGovernanceLedger', 'hidden-hazard-governance-ledger', '/smis/dual-control-system/dual-control-checklist/hidden-hazard-governance-ledger', 'menu', '隐患治理信息台账', '', 6),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlHiddenHazardInspectionPlan', 'hidden-hazard-inspection-plan', '/smis/dual-control-system/hidden-hazard-governance/hidden-hazard-inspection-plan', 'menu', '隐患排查计划', '', 1),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlHiddenHazardInspectionTask', 'hidden-hazard-inspection-task', '/smis/dual-control-system/hidden-hazard-governance/hidden-hazard-inspection-task', 'menu', '隐患排查任务', '', 2),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlHiddenHazardGovernanceTracking', 'hidden-hazard-governance-tracking', '/smis/dual-control-system/hidden-hazard-governance/hidden-hazard-governance-tracking', 'menu', '隐患治理跟踪', '', 3),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlQuickReport', 'quick-report', '/smis/dual-control-system/hidden-hazard-governance/quick-report', 'menu', '随手拍', '', 4),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlPublicHiddenHazardReport', 'public-hidden-hazard-report', '/smis/dual-control-system/hidden-hazard-governance/public-hidden-hazard-report', 'menu', '公众举报隐患', '', 5),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlHiddenHazardRectificationNotice', 'hidden-hazard-rectification-notice', '/smis/dual-control-system/hidden-hazard-governance/hidden-hazard-rectification-notice', 'menu', '隐患整改通知书', '', 6),
  (3, 'SmisDualControlHiddenHazardGovernance', 'SmisDualControlHiddenHazardInspectionRectification', 'hidden-hazard-inspection-rectification', '/smis/dual-control-system/hidden-hazard-governance/hidden-hazard-inspection-rectification', 'menu', '隐患检查落实整改', '', 7),
  (3, 'SmisDualControlReport', 'SmisDualControlManagementReport', 'dual-control-management-report', '/smis/dual-control-system/dual-control-report/dual-control-management-report', 'menu', '双控管控报表', '', 1),
  (3, 'SmisDualControlReport', 'SmisDualControlHiddenHazardInspectionReport', 'hidden-hazard-inspection-report', '/smis/dual-control-system/dual-control-report/hidden-hazard-inspection-report', 'menu', '隐患排查报表', '', 2),
  (3, 'SmisDualControlReport', 'SmisDualControlHiddenHazardGovernanceReport', 'hidden-hazard-governance-report', '/smis/dual-control-system/dual-control-report/hidden-hazard-governance-report', 'menu', '隐患治理报表', '', 3),
  (3, 'SmisDualControlReport', 'SmisDualControlInspectionRateStatistics', 'inspection-rate-statistics', '/smis/dual-control-system/dual-control-report/inspection-rate-statistics', 'menu', '排查率统计', '', 4),
  (3, 'SmisDualControlReport', 'SmisDualControlMissedInspectionRateStatistics', 'missed-inspection-rate-statistics', '/smis/dual-control-system/dual-control-report/missed-inspection-rate-statistics', 'menu', '漏查率统计', '', 5),
  (3, 'SmisDualControlReport', 'SmisDualControlHiddenHazardInspectionRecord', 'hidden-hazard-inspection-record', '/smis/dual-control-system/dual-control-report/hidden-hazard-inspection-record', 'menu', '隐患排查记录', '', 6),
  (3, 'SmisDualControlReport', 'SmisDualControlNoHiddenHazardPersonnelStatistics', 'no-hidden-hazard-personnel-statistics', '/smis/dual-control-system/dual-control-report/no-hidden-hazard-personnel-statistics', 'menu', '未提隐患人员统计', '', 7),
  (3, 'SmisDualControlReport', 'SmisDualControlTeamSelfInspectionCoverage', 'team-self-inspection-coverage', '/smis/dual-control-system/dual-control-report/team-self-inspection-coverage', 'menu', '班组自查涵盖率', '', 8),
  (3, 'SmisDualControlReport', 'SmisDualControlSpecialEquipmentRiskControlStatistics', 'special-equipment-risk-control-statistics', '/smis/dual-control-system/dual-control-report/special-equipment-risk-control-statistics', 'menu', '特种设备风控统计', '', 9),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlHazardFactorCategory', 'hazard-factor-category', '/smis/dual-control-system/risk-control/hazard-factor-category', 'menu', '危害因素类别', '', 1),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlInspectionStandard', 'inspection-standard', '/smis/dual-control-system/risk-control/inspection-standard', 'menu', '排查标准', '', 2),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlInspectionType', 'inspection-type', '/smis/dual-control-system/risk-control/inspection-type', 'menu', '排查类型', '', 3),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlDuplicateConfiguration', 'duplicate-configuration', '/smis/dual-control-system/risk-control/duplicate-configuration', 'menu', '重复配置', '', 4),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskAssessmentStandardModel', 'risk-assessment-standard-model', '/smis/dual-control-system/risk-control/risk-assessment-standard-model', 'menu', '风险评估标准模型', '', 5),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskIdentification', 'risk-identification', '/smis/dual-control-system/risk-control/risk-identification', 'menu', '风险辨识', '', 6),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlSafetyRiskList', 'safety-risk-list', '/smis/dual-control-system/risk-control/safety-risk-list', 'menu', '安全风险清单', '', 7),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskClassificationControl', 'risk-classification-control', '/smis/dual-control-system/risk-control/risk-classification-control', 'menu', '风险分级管控', '', 8),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskListSummary', 'risk-list-summary', '/smis/dual-control-system/risk-control/risk-list-summary', 'menu', '风险清单汇总', '', 9),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskEvaluationControl', 'risk-evaluation-control', '/smis/dual-control-system/risk-control/risk-evaluation-control', 'menu', '风险评价及管控', '', 10),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskInspectionTask', 'risk-inspection-task', '/smis/dual-control-system/risk-control/risk-inspection-task', 'menu', '风险巡查任务', '', 11),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlSafetyInspection', 'safety-inspection', '/smis/dual-control-system/risk-control/safety-inspection', 'menu', '安全检查', '', 12),
  (3, 'SmisDualControlRiskControl', 'SmisDualControlRiskFourColorMap', 'risk-four-color-map', '/smis/dual-control-system/risk-control/risk-four-color-map', 'menu', '风险四色图', '', 13);

-- Insert one level at a time so every child can resolve its newly-created parent.
insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  type,
  meta,
  sort,
  create_by,
  update_by,
  app_code
)
select
  gen_random_uuid(),
  parent.id,
  seed.name,
  seed.path,
  seed.component,
  seed.type,
  jsonb_build_object(
    'icon', seed.icon,
    'roles', '[]'::jsonb,
    'title', seed.title,
    'is_hide', false,
    'is_enable', true
  ),
  seed.sort,
  '624944977@qq.com',
  '624944977@qq.com',
  'smis'
from smis_navigation_seed seed
join public.sys_menu parent on parent.name = seed.parent_name
where seed.depth = 1
  and not exists (
    select 1
    from public.sys_menu existing
    where existing.name = seed.name
  );

insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  type,
  meta,
  sort,
  create_by,
  update_by,
  app_code
)
select
  gen_random_uuid(),
  parent.id,
  seed.name,
  seed.path,
  seed.component,
  seed.type,
  jsonb_build_object(
    'icon', seed.icon,
    'roles', '[]'::jsonb,
    'title', seed.title,
    'is_hide', false,
    'is_enable', true
  ),
  seed.sort,
  '624944977@qq.com',
  '624944977@qq.com',
  'smis'
from smis_navigation_seed seed
join public.sys_menu parent on parent.name = seed.parent_name
where seed.depth = 2
  and not exists (
    select 1
    from public.sys_menu existing
    where existing.name = seed.name
  );

insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  type,
  meta,
  sort,
  create_by,
  update_by,
  app_code
)
select
  gen_random_uuid(),
  parent.id,
  seed.name,
  seed.path,
  seed.component,
  seed.type,
  jsonb_build_object(
    'icon', seed.icon,
    'roles', '[]'::jsonb,
    'title', seed.title,
    'is_hide', false,
    'is_enable', true
  ),
  seed.sort,
  '624944977@qq.com',
  '624944977@qq.com',
  'smis'
from smis_navigation_seed seed
join public.sys_menu parent on parent.name = seed.parent_name
where seed.depth = 3
  and not exists (
    select 1
    from public.sys_menu existing
    where existing.name = seed.name
  );

-- Keep reruns idempotent and repair an existing partial menu definition.
update public.sys_menu menu
set
  parent_id = parent.id,
  path = seed.path,
  component = seed.component,
  type = seed.type,
  meta = coalesce(menu.meta, '{}'::jsonb) || jsonb_build_object(
    'icon', seed.icon,
    'roles', '[]'::jsonb,
    'title', seed.title,
    'is_hide', false,
    'is_enable', true
  ),
  sort = seed.sort,
  update_by = '624944977@qq.com',
  update_time = now(),
  app_code = 'smis'
from smis_navigation_seed seed
join public.sys_menu parent on parent.name = seed.parent_name
where menu.name = seed.name;

do $$
begin
  if (
    select count(*)
    from public.sys_menu menu
    join smis_navigation_seed seed on seed.name = menu.name
  ) <> 58 then
    raise exception 'SMIS navigation seed is incomplete';
  end if;
end
$$;

-- Preserve rollout access for every role that already owns the neighboring 资质培训 menu.
insert into public.sys_role_menu (
  role_id,
  menu_id,
  tenant_id,
  create_by,
  update_by
)
select distinct
  source_grant.role_id,
  menu.id,
  source_grant.tenant_id,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu source_grant
join public.sys_menu source_menu
  on source_menu.id = source_grant.menu_id
 and source_menu.name = 'SmisQualificationTraining'
cross join smis_navigation_seed seed
join public.sys_menu menu on menu.name = seed.name
on conflict (role_id, menu_id) do nothing;

commit;

;
