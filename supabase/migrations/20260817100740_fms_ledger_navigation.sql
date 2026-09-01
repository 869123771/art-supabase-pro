begin;

with accounting_menu as (
  select id
  from public.sys_menu
  where name = 'FinanceAccounting'
  limit 1
)
insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
select
  'a1000000-0000-4000-8000-000000000027'::uuid,
  accounting_menu.id,
  'FinanceLedgerCenter',
  'ledger-center',
  '/fms/ledger-center/index',
  'menu',
  9,
  jsonb_build_object(
    'icon', 'ri:book-open-line',
    'title', '账簿查询',
    'is_hide', false,
    'is_enable', true,
    'menu_type', 'menu',
    'keep_alive', true
  ),
  '624944977@qq.com',
  '624944977@qq.com'
from accounting_menu
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  role_menu.role_id,
  'a1000000-0000-4000-8000-000000000027'::uuid,
  role_menu.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu role_menu
join public.sys_menu parent
  on parent.id = role_menu.menu_id
 and parent.name = 'FinanceAccounting'
on conflict (role_id, menu_id) do nothing;

commit;;
