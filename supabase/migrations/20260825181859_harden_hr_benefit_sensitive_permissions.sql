-- Separate benefit amount editing and life-event evidence access from broad
-- plan/enrollment maintenance. These permissions are intentionally not
-- inherited by existing page holders.
insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000208'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8208-000000000008'::uuid, 'Hr:Benefits:Amount:Edit', '维护福利缴费金额', 8),
  ('c0de0000-0000-4000-8208-000000000009'::uuid, 'Hr:Benefits:Evidence:View', '查看福利人生事件附件', 9)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

;
