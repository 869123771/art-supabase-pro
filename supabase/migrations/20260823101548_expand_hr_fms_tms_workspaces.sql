-- Productize existing tenant-scoped data as read-only cross-module workspaces.
-- New menu/view permissions are copied from adjacent read-only modules so enabled
-- ordinary roles retain access without receiving mutation privileges.

insert into public.sys_menu (
  id, parent_id, name, path, component, type, app_code, sort, meta,
  create_by, create_time, update_by, update_time
)
values
  (
    'c0de0000-0000-4000-8000-000000000204'::uuid,
    'c0de0000-0000-4000-8000-000000000200'::uuid,
    'HrWorkforceRisk', 'workforce-risk', '/hr/operations/workforce-risk', 'menu', 'hr', 4,
    '{"icon":"ri:shield-user-line","title":"人力风险中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'a1000000-0000-4000-8000-000000000035'::uuid,
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'FinanceCashForecast', 'cash-forecast', '/fms/cash-forecast/index', 'menu', 'fms', 5,
    '{"icon":"ri:funds-line","title":"资金预测","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'b2000000-0000-4000-8000-000000000001'::uuid,
    '5cb6af14-977a-4a51-8e4d-107db0f1af2e'::uuid,
    'TmsTransportEvent', 'transport-event', '/tms/transport-event', 'menu', 'tms', 9,
    '{"icon":"ri:route-line","title":"运输事件中心","is_hide":false,"is_enable":true,"keep_alive":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'c0de0000-0000-4000-8204-000000000001'::uuid,
    'c0de0000-0000-4000-8000-000000000204'::uuid,
    'Hr:WorkforceRisk:View', '', '', 'button', 'hr', 1,
    '{"icon":"","title":"查看人力风险","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'a1000000-0000-4000-8035-000000000001'::uuid,
    'a1000000-0000-4000-8000-000000000035'::uuid,
    'FinanceCashForecast:View', '', '', 'button', 'fms', 1,
    '{"icon":"","title":"查看资金预测","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  ),
  (
    'b2000000-0000-4000-8100-000000000001'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'TmsTransportEvent:View', '', '', 'button', 'tms', 1,
    '{"icon":"","title":"查看运输事件","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
    'migration', now(), 'migration', now()
  )
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  app_code = excluded.app_code,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();

with grants(source_menu_id, target_menu_id) as (
  values
    ('c0de0000-0000-4000-8000-000000000201'::uuid, 'c0de0000-0000-4000-8000-000000000204'::uuid),
    ('c0de0000-0000-4000-8000-000000000201'::uuid, 'c0de0000-0000-4000-8204-000000000001'::uuid),
    ('a1000000-0000-4000-8000-000000000026'::uuid, 'a1000000-0000-4000-8000-000000000035'::uuid),
    ('a1000000-0000-4000-8000-000000000026'::uuid, 'a1000000-0000-4000-8035-000000000001'::uuid),
    ('062a648a-494e-47ef-b2db-94620a565ca0'::uuid, 'b2000000-0000-4000-8000-000000000001'::uuid),
    ('062a648a-494e-47ef-b2db-94620a565ca0'::uuid, 'b2000000-0000-4000-8100-000000000001'::uuid)
)
insert into public.sys_role_menu (
  permission, create_by, create_time, role_id, menu_id, update_by, update_time, tenant_id
)
select
  source.permission,
  'migration',
  now(),
  source.role_id,
  grants.target_menu_id,
  'migration',
  now(),
  source.tenant_id
from grants
join public.sys_role_menu source on source.menu_id = grants.source_menu_id
on conflict (role_id, menu_id) do update set
  permission = excluded.permission,
  update_by = excluded.update_by,
  update_time = now(),
  tenant_id = excluded.tenant_id;

;
