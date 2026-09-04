begin;

insert into public.sys_application (
  app_code, app_name, description, base_url, menu_root_path, enabled, sort
) values
  ('mdm', 'Art Supabase MDM', '跨业务域主数据治理与统一目录', '/mdm/', '/mdm', true, 15),
  ('wms', 'Art Supabase WMS', '仓库、库存与仓内作业管理', '/wms/', '/wms', true, 55),
  ('mes', 'Art Supabase MES', '生产执行、工艺与制造协同', '/mes/', '/mes', true, 60)
on conflict (app_code) do update
set app_name = excluded.app_name,
    description = excluded.description,
    base_url = excluded.base_url,
    menu_root_path = excluded.menu_root_path,
    enabled = excluded.enabled,
    sort = excluded.sort,
    updated_at = now();

insert into public.sys_menu (
  id, name, path, component, parent_id, type, app_code, sort, meta, create_by
) values
  (
    'd0000000-0000-4000-8000-000000000001', 'MdmMasterData', '/mdm', '/index/index', null,
    'folder', 'mdm', 13,
    '{"icon":"ri:database-2-line","roles":["R_SUPER","R_ADMIN"],"title":"MDM主数据","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000002', 'MdmWorkbench', 'workbench', '/mdm/workbench',
    'd0000000-0000-4000-8000-000000000001', 'menu', 'mdm', 0,
    '{"icon":"ri:dashboard-3-line","roles":["R_SUPER","R_ADMIN"],"title":"治理总览","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000010', 'MdmOrganization', 'organization', '',
    'd0000000-0000-4000-8000-000000000001', 'folder', 'mdm', 1,
    '{"icon":"ri:organization-chart","roles":["R_SUPER","R_ADMIN"],"title":"组织与人员","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000011', 'MdmPartner', 'partner', '',
    'd0000000-0000-4000-8000-000000000001', 'folder', 'mdm', 2,
    '{"icon":"ri:building-4-line","roles":["R_SUPER","R_ADMIN"],"title":"往来主体","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000012', 'MdmLogistics', 'logistics', '',
    'd0000000-0000-4000-8000-000000000001', 'folder', 'mdm', 3,
    '{"icon":"ri:route-line","roles":["R_SUPER","R_ADMIN"],"title":"物流基础","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000013', 'MdmAsset', 'asset', '',
    'd0000000-0000-4000-8000-000000000001', 'folder', 'mdm', 4,
    '{"icon":"ri:tools-line","roles":["R_SUPER","R_ADMIN"],"title":"资产与设备","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000014', 'MdmMaterial', 'material', '',
    'd0000000-0000-4000-8000-000000000001', 'folder', 'mdm', 5,
    '{"icon":"ri:archive-stack-line","roles":["R_SUPER","R_ADMIN"],"title":"物料与场所","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000020', 'MdmOrganizationDirectory', 'organization-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000010', 'menu', 'mdm', 1,
    '{"icon":"ri:node-tree","roles":["R_SUPER","R_ADMIN"],"title":"组织机构","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000021', 'MdmPositionDirectory', 'position-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000010', 'menu', 'mdm', 2,
    '{"icon":"ri:briefcase-4-line","roles":["R_SUPER","R_ADMIN"],"title":"岗位与职务","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000022', 'MdmEmployeeDirectory', 'employee-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000010', 'menu', 'mdm', 3,
    '{"icon":"ri:contacts-book-3-line","roles":["R_SUPER","R_ADMIN"],"title":"员工身份","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000023', 'MdmBusinessPartnerDirectory', 'business-partner-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000011', 'menu', 'mdm', 1,
    '{"icon":"ri:community-line","roles":["R_SUPER","R_ADMIN"],"title":"统一往来主体","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000024', 'MdmLogisticsDirectory', 'logistics-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000012', 'menu', 'mdm', 1,
    '{"icon":"ri:map-pin-range-line","roles":["R_SUPER","R_ADMIN"],"title":"站点货物与司机","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000025', 'MdmVehicleDirectory', 'vehicle-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000013', 'menu', 'mdm', 1,
    '{"icon":"ri:truck-line","roles":["R_SUPER","R_ADMIN"],"title":"车辆主数据","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000026', 'MdmEquipmentDirectory', 'equipment-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000013', 'menu', 'mdm', 2,
    '{"icon":"ri:settings-5-line","roles":["R_SUPER","R_ADMIN"],"title":"设备与备件","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd0000000-0000-4000-8000-000000000027', 'MdmMaterialDirectory', 'material-directory', '/mdm/catalog',
    'd0000000-0000-4000-8000-000000000014', 'menu', 'mdm', 1,
    '{"icon":"ri:box-3-line","roles":["R_SUPER","R_ADMIN"],"title":"物料与场所","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd1000000-0000-4000-8000-000000000001', 'WmsWarehouseManagement', '/wms', '/index/index', null,
    'folder', 'wms', 14,
    '{"icon":"ri:warehouse-line","roles":["R_SUPER","R_ADMIN"],"title":"WMS仓储管理","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  ),
  (
    'd1000000-0000-4000-8000-000000000002', 'WmsWorkbench', 'workbench', '/wms/workbench',
    'd1000000-0000-4000-8000-000000000001', 'menu', 'wms', 1,
    '{"icon":"ri:dashboard-3-line","roles":["R_SUPER","R_ADMIN"],"title":"仓储工作台","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  ),
  (
    'd2000000-0000-4000-8000-000000000001', 'MesManufacturingExecution', '/mes', '/index/index', null,
    'folder', 'mes', 15,
    '{"icon":"ri:factory-line","roles":["R_SUPER","R_ADMIN"],"title":"MES制造执行","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  ),
  (
    'd2000000-0000-4000-8000-000000000002', 'MesWorkbench', 'workbench', '/mes/workbench',
    'd2000000-0000-4000-8000-000000000001', 'menu', 'mes', 1,
    '{"icon":"ri:dashboard-3-line","roles":["R_SUPER","R_ADMIN"],"title":"制造工作台","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
    'migration'
  )
on conflict (id) do update
set name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    parent_id = excluded.parent_id,
    type = excluded.type,
    app_code = excluded.app_code,
    sort = excluded.sort,
    meta = excluded.meta,
    update_by = 'migration',
    update_time = now();

insert into public.sys_role_menu (
  id, role_id, menu_id, permission, create_by, tenant_id
)
select
  gen_random_uuid(), role_record.id, menu_record.id, '{}'::jsonb, 'migration', role_record.tenant_id
from public.sys_role role_record
cross join public.sys_menu menu_record
where role_record.enabled
  and role_record.role_code in ('R_SUPER', 'R_ADMIN')
  and menu_record.app_code in ('mdm', 'wms', 'mes')
  and not exists (
    select 1
    from public.sys_role_menu existing
    where existing.role_id = role_record.id
      and existing.menu_id = menu_record.id
  );

commit;
