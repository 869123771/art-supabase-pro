with source_menu as (
  select *
  from public.sys_menu
  where name = 'HrEmployeeProfile'
  limit 1
),
inserted_menu as (
  insert into public.sys_menu (
    id,
    name,
    path,
    component,
    meta,
    sort,
    create_by,
    create_time,
    update_by,
    update_time,
    parent_id,
    type
  )
  select
    gen_random_uuid(),
    'HrEmployeeDetail',
    'employee-detail/:id',
    '/hr/personnel/employee-profile',
    jsonb_set(
      jsonb_set(meta, '{title}', '"员工档案详情"'::jsonb),
      '{icon}',
      '"ri:profile-line"'::jsonb
    ),
    3,
    'migration',
    now(),
    'migration',
    now(),
    parent_id,
    type
  from source_menu
  where not exists (
    select 1 from public.sys_menu where name = 'HrEmployeeDetail'
  )
  returning id
),
target_menu as (
  select id from inserted_menu
  union all
  select id from public.sys_menu where name = 'HrEmployeeDetail'
  limit 1
)
insert into public.sys_role_menu (
  id,
  permission,
  create_by,
  create_time,
  role_id,
  menu_id,
  update_by,
  update_time,
  tenant_id
)
select
  gen_random_uuid(),
  role_menu.permission,
  'migration',
  now(),
  role_menu.role_id,
  target_menu.id,
  'migration',
  now(),
  role_menu.tenant_id
from public.sys_role_menu role_menu
join source_menu on source_menu.id = role_menu.menu_id
cross join target_menu
where not exists (
  select 1
  from public.sys_role_menu existing
  where existing.role_id = role_menu.role_id
    and existing.menu_id = target_menu.id
    and existing.tenant_id is not distinct from role_menu.tenant_id
);;
