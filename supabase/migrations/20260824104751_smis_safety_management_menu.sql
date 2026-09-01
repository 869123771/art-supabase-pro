begin;

with menu_seed (
  id,
  parent_id,
  name,
  path,
  component,
  title,
  icon,
  sort,
  type
) as (
  values
    ('a1530000-0000-4000-8000-000000000001'::uuid, null::uuid, 'SmisSafetyManagement', '/smis', '/index/index', 'SMIS安全管理', 'ri:shield-check-line', 14, 'folder'),
    ('a1530000-0000-4000-8000-000000000002'::uuid, 'a1530000-0000-4000-8000-000000000001'::uuid, 'SmisBasicData', 'basic-data', '', '基础数据', 'ri:database-2-line', 1, 'folder'),
    ('a1530000-0000-4000-8000-000000000003'::uuid, 'a1530000-0000-4000-8000-000000000001'::uuid, 'SmisEquipmentLedger', 'equipment-ledger', '', '设备台账', 'ri:archive-stack-line', 2, 'folder'),
    ('a1530000-0000-4000-8000-000000000004'::uuid, 'a1530000-0000-4000-8000-000000000001'::uuid, 'SmisSafetyProduction', 'safety-production', '', '安全生产', 'ri:shield-star-line', 3, 'folder'),
    ('a1530000-0000-4000-8000-000000000005'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisPositionSafetyResponsibility', 'position-safety-responsibility', '/smis/basic-data/position-safety-responsibility', '岗位安全责任制', 'ri:user-settings-line', 1, 'menu'),
    ('a1530000-0000-4000-8000-000000000006'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisPositionRiskList', 'position-risk-list', '/smis/basic-data/position-risk-list', '岗位风险清单', 'ri:alert-line', 2, 'menu'),
    ('a1530000-0000-4000-8000-000000000007'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisPositionWorkInstruction', 'position-work-instruction', '/smis/basic-data/position-work-instruction', '岗位作业指导书', 'ri:file-list-3-line', 3, 'menu'),
    ('a1530000-0000-4000-8000-000000000008'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisLeaveInformation', 'leave-information', '/smis/basic-data/leave-information', '请假信息维护', 'ri:calendar-event-line', 4, 'menu'),
    ('a1530000-0000-4000-8000-000000000009'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisStatutoryHoliday', 'statutory-holiday', '/smis/basic-data/statutory-holiday', '法定节假日', 'ri:calendar-check-line', 5, 'menu'),
    ('a1530000-0000-4000-8000-000000000010'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisSite', 'site', '/smis/basic-data/site', '场所维护', 'ri:map-pin-2-line', 6, 'menu'),
    ('a1530000-0000-4000-8000-000000000011'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisInspectionCategory', 'inspection-category', '/smis/basic-data/inspection-category', '检验类别', 'ri:filter-3-line', 7, 'menu'),
    ('a1530000-0000-4000-8000-000000000012'::uuid, 'a1530000-0000-4000-8000-000000000002'::uuid, 'SmisSupplier', 'supplier', '/smis/basic-data/supplier', '供应商', 'ri:store-2-line', 8, 'menu'),
    ('a1530000-0000-4000-8000-000000000013'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisEquipmentCategory', 'equipment-category', '/smis/equipment-ledger/equipment-category', '设备分类', 'ri:node-tree', 1, 'menu'),
    ('a1530000-0000-4000-8000-000000000014'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisStorageLocation', 'storage-location', '/smis/equipment-ledger/storage-location', '存放位置', 'ri:map-pin-line', 2, 'menu'),
    ('a1530000-0000-4000-8000-000000000015'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisEquipmentDepreciation', 'equipment-depreciation', '/smis/equipment-ledger/equipment-depreciation', '设备折旧', 'ri:line-chart-line', 3, 'menu'),
    ('a1530000-0000-4000-8000-000000000016'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisEquipmentLedgerList', 'equipment-ledger', '/smis/equipment-ledger/equipment-ledger', '设备台账', 'ri:book-2-line', 4, 'menu'),
    ('a1530000-0000-4000-8000-000000000017'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisInspectionDeclaration', 'inspection-declaration', '/smis/equipment-ledger/inspection-declaration', '检验申报', 'ri:file-add-line', 5, 'menu'),
    ('a1530000-0000-4000-8000-000000000018'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisSpecialEquipmentAnalysis', 'special-equipment-analysis', '/smis/equipment-ledger/special-equipment-analysis', '特种设备统计分析', 'ri:bar-chart-box-line', 6, 'menu'),
    ('a1530000-0000-4000-8000-000000000019'::uuid, 'a1530000-0000-4000-8000-000000000003'::uuid, 'SmisSpecialEquipmentLedger', 'special-equipment-ledger', '/smis/equipment-ledger/special-equipment-ledger', '特种设备管理台账', 'ri:archive-drawer-line', 7, 'menu'),
    ('a1530000-0000-4000-8000-000000000020'::uuid, 'a1530000-0000-4000-8000-000000000004'::uuid, 'SmisEmergencyRescue', 'emergency-rescue', '', '应急救援', 'ri:first-aid-kit-line', 1, 'folder'),
    ('a1530000-0000-4000-8000-000000000021'::uuid, 'a1530000-0000-4000-8000-000000000020'::uuid, 'SmisHazardSourceLedger', 'hazard-source-ledger', '/smis/safety-production/emergency-rescue/hazard-source-ledger', '危险源台账', 'ri:alarm-warning-line', 1, 'menu'),
    ('a1530000-0000-4000-8000-000000000022'::uuid, 'a1530000-0000-4000-8000-000000000020'::uuid, 'SmisEmergencyRescuePlan', 'emergency-rescue-plan', '/smis/safety-production/emergency-rescue/emergency-rescue-plan', '应急救援预案', 'ri:file-shield-2-line', 2, 'menu'),
    ('a1530000-0000-4000-8000-000000000023'::uuid, 'a1530000-0000-4000-8000-000000000020'::uuid, 'SmisEmergencyDrillPlan', 'emergency-drill-plan', '/smis/safety-production/emergency-rescue/emergency-drill-plan', '应急演练计划', 'ri:calendar-todo-line', 3, 'menu'),
    ('a1530000-0000-4000-8000-000000000024'::uuid, 'a1530000-0000-4000-8000-000000000020'::uuid, 'SmisEmergencyDrillRecord', 'emergency-drill-record', '/smis/safety-production/emergency-rescue/emergency-drill-record', '应急演练记录', 'ri:clipboard-line', 4, 'menu'),
    ('a1530000-0000-4000-8000-000000000025'::uuid, 'a1530000-0000-4000-8000-000000000020'::uuid, 'SmisEmergencyDrillReport', 'emergency-drill-report', '/smis/safety-production/emergency-rescue/emergency-drill-report', '应急演练报表', 'ri:pie-chart-line', 5, 'menu')
)
insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  meta,
  sort,
  type,
  app_code,
  create_by,
  update_by
)
select
  id,
  parent_id,
  name,
  path,
  component,
  jsonb_build_object(
    'title', title,
    'icon', icon,
    'roles', jsonb_build_array(),
    'is_hide', false,
    'fixed_tab', false,
    'is_enable', true,
    'is_iframe', false,
    'keep_alive', true,
    'show_badge', false,
    'active_path', '',
    'is_hide_tab', false,
    'is_full_page', false,
    'show_text_badge', ''
  ),
  sort,
  type,
  'smis',
  '624944977@qq.com',
  '624944977@qq.com'
from menu_seed
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code,
    update_by = excluded.update_by,
    update_time = now();

with target_users as (
  select id, tenant_id, user_roles
  from public.sys_user
  where lower(user_email) = '67611039@qq.com'
    and status = '1'
    and deleted_at is null
),
target_roles as (
  select distinct role_row.id, role_row.tenant_id
  from target_users user_row
  join public.sys_role role_row
    on role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
   and role_row.tenant_id = user_row.tenant_id
   and role_row.enabled
)
insert into public.sys_role_menu (
  id,
  role_id,
  menu_id,
  permission,
  create_by,
  update_by,
  tenant_id
)
select
  gen_random_uuid(),
  target_role.id,
  menu_row.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  target_role.tenant_id
from target_roles target_role
cross join public.sys_menu menu_row
where menu_row.id between
      'a1530000-0000-4000-8000-000000000001'::uuid
      and 'a1530000-0000-4000-8000-000000000025'::uuid
on conflict (role_id, menu_id) do update
set permission = excluded.permission,
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id;

commit;

;
