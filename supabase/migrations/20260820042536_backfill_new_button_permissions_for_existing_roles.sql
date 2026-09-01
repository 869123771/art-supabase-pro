-- Preserve the effective access of roles that already owned a page menu before
-- the managed business/system button permissions were introduced. Only buttons
-- created by the two permission catalog migrations are inherited; pre-existing
-- buttons that an administrator intentionally left unselected remain unchanged.
insert into public.sys_role_menu (
  role_id,
  menu_id,
  tenant_id,
  permission,
  create_by,
  update_by
)
select distinct
  parent_grant.role_id,
  button.id,
  coalesce(parent_grant.tenant_id, role.tenant_id),
  '{}'::jsonb,
  'codex-permission-compatibility',
  'codex-permission-compatibility'
from public.sys_role_menu as parent_grant
join public.sys_role as role
  on role.id = parent_grant.role_id
join public.sys_menu as button
  on button.parent_id = parent_grant.menu_id
 and button.type = 'button'
where button.create_by in (
  'codex-business-permission-migration',
  'codex-system-permission-migration'
)
on conflict (role_id, menu_id) do nothing;

;
