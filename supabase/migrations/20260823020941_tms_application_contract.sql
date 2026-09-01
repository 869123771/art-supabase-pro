begin;

insert into public.sys_application (
  app_code,
  app_name,
  description,
  base_url,
  menu_root_path,
  enabled,
  sort,
  created_at,
  updated_at
)
values (
  'tms',
  'Art Supabase TMS',
  '智慧运输管理系统',
  '/tms/',
  '/tms',
  true,
  45,
  now(),
  now()
)
on conflict (app_code) do update
set app_name = excluded.app_name,
    description = excluded.description,
    base_url = excluded.base_url,
    menu_root_path = excluded.menu_root_path,
    enabled = excluded.enabled,
    sort = excluded.sort,
    updated_at = now();

with recursive tms_menu_tree as (
  select menu_row.id
  from public.sys_menu menu_row
  where menu_row.path = '/tms'
    and menu_row.parent_id is null

  union all

  select child.id
  from public.sys_menu child
  join tms_menu_tree parent on parent.id = child.parent_id
)
update public.sys_menu menu_row
set app_code = 'tms'
where menu_row.id in (select id from tms_menu_tree);

commit;

;
