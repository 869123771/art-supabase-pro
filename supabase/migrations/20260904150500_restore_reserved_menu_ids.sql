begin;

-- The first registration reused two historical menu IDs. Restore their original
-- VMS/workflow records before assigning fresh IDs to the new application roots.
update public.sys_menu
set parent_id = '200d5e4c-b49d-49b5-962f-cd1c6744b637',
    name = 'VehicleFleetHealth',
    path = 'fleet-health',
    component = '/vms/fleet-health',
    type = 'menu',
    app_code = 'vms',
    sort = 3,
    meta = '{"icon":"ri:heart-pulse-line","title":"车队健康中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    update_by = 'migration',
    update_time = now()
where id = 'd1000000-0000-4000-8000-000000000001';

update public.sys_menu
set parent_id = 'adcddc55-d5a2-4e11-872e-86156d2b7d36',
    name = 'WorkflowAnalytics',
    path = 'analytics',
    component = '/workflow/analytics',
    type = 'menu',
    app_code = 'platform',
    sort = 4,
    meta = '{"icon":"ri:bar-chart-grouped-line","title":"审批效能","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    update_by = 'migration',
    update_time = now()
where id = 'd2000000-0000-4000-8000-000000000001';

delete from public.sys_role_menu role_menu
using public.sys_role role_record
where role_menu.role_id = role_record.id
  and role_menu.menu_id = 'd1000000-0000-4000-8000-000000000001'
  and role_record.role_code = 'R_ADMIN'
  and role_menu.create_time >= '2026-09-04 14:19:00+00';

delete from public.sys_role_menu role_menu
using public.sys_role role_record
where role_menu.role_id = role_record.id
  and role_menu.menu_id = 'd2000000-0000-4000-8000-000000000001'
  and role_record.role_code in ('R_SUPER', 'R_ADMIN')
  and role_menu.create_time >= '2026-09-04 14:19:00+00';

insert into public.sys_menu (
  id, name, path, component, parent_id, type, app_code, sort, meta, create_by
) values
  (
    'a08a35e5-cd58-450a-858c-cbb8d9415ce2', 'WmsWarehouseManagement', '/wms', '/index/index', null,
    'folder', 'wms', 14,
    '{"icon":"ri:warehouse-line","roles":["R_SUPER","R_ADMIN"],"title":"WMS仓储管理","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  ),
  (
    '452c7953-4f35-4973-8f47-5a31adb91264', 'MesManufacturingExecution', '/mes', '/index/index', null,
    'folder', 'mes', 15,
    '{"icon":"ri:factory-line","roles":["R_SUPER","R_ADMIN"],"title":"MES制造执行","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
    'migration'
  );

update public.sys_menu
set parent_id = 'a08a35e5-cd58-450a-858c-cbb8d9415ce2',
    update_by = 'migration',
    update_time = now()
where id = 'd1000000-0000-4000-8000-000000000002';

update public.sys_menu
set parent_id = '452c7953-4f35-4973-8f47-5a31adb91264',
    update_by = 'migration',
    update_time = now()
where id = 'd2000000-0000-4000-8000-000000000002';

insert into public.sys_role_menu (id, role_id, menu_id, permission, create_by, tenant_id)
select gen_random_uuid(), role_record.id, menu_record.id, '{}'::jsonb, 'migration', role_record.tenant_id
from public.sys_role role_record
cross join public.sys_menu menu_record
where role_record.enabled
  and role_record.role_code in ('R_SUPER', 'R_ADMIN')
  and menu_record.id in (
    'a08a35e5-cd58-450a-858c-cbb8d9415ce2',
    '452c7953-4f35-4973-8f47-5a31adb91264'
  )
  and not exists (
    select 1
    from public.sys_role_menu existing
    where existing.role_id = role_record.id
      and existing.menu_id = menu_record.id
  );

commit;
