-- Hidden detail routes must inherit the same role reachability as the equipment ledger list.
insert into public.sys_role_menu(
  id,
  role_id,
  menu_id,
  permission,
  tenant_id,
  create_by,
  create_time,
  update_by,
  update_time
)
select
  gen_random_uuid(),
  source.role_id,
  detail.id,
  source.permission,
  source.tenant_id,
  'migration',
  now(),
  'migration',
  now()
from public.sys_role_menu source
join public.sys_menu list_menu
  on list_menu.id = source.menu_id
  and list_menu.app_code = 'smis'
  and list_menu.name = 'SmisEquipmentLedgerList'
join public.sys_menu detail
  on detail.app_code = 'smis'
  and detail.name = 'SmisEquipmentLedgerDetail'
on conflict (role_id, menu_id) do nothing;

;
