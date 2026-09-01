begin;
insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values (
  'a1000000-0000-4000-8000-000000000013'::uuid,
  'a1000000-0000-4000-8000-000000000001'::uuid,
  'FinanceAccountingSubject',
  'accounting-subject',
  '/fms/accounting-subject',
  'menu',
  14,
  jsonb_build_object(
    'icon', 'ri:node-tree',
    'title', '会计科目',
    'is_enable', true,
    'keep_alive', true
  ),
  '624944977@qq.com',
  '624944977@qq.com'
)
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
select rm.role_id,
  'a1000000-0000-4000-8000-000000000013'::uuid,
  rm.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu rm
where rm.menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
on conflict (role_id, menu_id) do nothing;
commit;
