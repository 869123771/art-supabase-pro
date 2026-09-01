drop policy if exists document_number_scene_select on public.sys_document_number_scene;
create policy document_number_scene_select on public.sys_document_number_scene
for select to authenticated
using (enabled);

with source_roles as (
  select role_menu.role_id
  from public.sys_role_menu role_menu
  join public.sys_menu source_menu on source_menu.id = role_menu.menu_id
  where source_menu.name = 'SystemParam'
), target_menu as (
  select id
  from public.sys_menu
  where name = 'DocumentNumberRule'
  limit 1
)
insert into public.sys_role_menu (
  role_id, menu_id, permission, create_by, update_by, tenant_id
)
select source_roles.role_id,
       target_menu.id,
       '{}'::jsonb,
       'number-engine',
       'number-engine',
       role.tenant_id
from source_roles
join public.sys_role role on role.id = source_roles.role_id
cross join target_menu
where not exists (
  select 1
  from public.sys_role_menu existing
  where existing.role_id = source_roles.role_id
    and existing.menu_id = target_menu.id
);

comment on policy document_number_scene_select on public.sys_document_number_scene is
  'Authenticated users may read enabled static scene metadata for tenant-safe menu navigation.';;
