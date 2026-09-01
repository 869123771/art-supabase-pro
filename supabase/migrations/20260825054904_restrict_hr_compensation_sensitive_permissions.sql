-- Compensation amounts and mutations are least-privilege by default.
-- Existing business roles keep the page and masked read access. Tenant admins,
-- platform super users, and explicitly assigned HR roles may receive sensitive
-- buttons through role management.

delete from public.sys_role_menu role_menu
using public.sys_role role_row
where role_row.id = role_menu.role_id
  and role_menu.menu_id in (
    'c0de0000-0000-4000-8205-000000000002'::uuid,
    'c0de0000-0000-4000-8205-000000000003'::uuid,
    'c0de0000-0000-4000-8205-000000000004'::uuid,
    'c0de0000-0000-4000-8205-000000000005'::uuid,
    'c0de0000-0000-4000-8205-000000000006'::uuid,
    'c0de0000-0000-4000-8205-000000000007'::uuid,
    'c0de0000-0000-4000-8205-000000000008'::uuid,
    'c0de0000-0000-4000-8205-000000000009'::uuid,
    'c0de0000-0000-4000-8205-000000000010'::uuid
  )
  and coalesce(role_row.builtin_type, '') <> 'platform_super'
  and role_row.role_code not in ('R_SUPER', 'R_ADMIN');
insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  role_row.id, menu_seed.menu_id, role_row.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role role_row
cross join (values
  ('c0de0000-0000-4000-8000-000000000205'::uuid),
  ('c0de0000-0000-4000-8205-000000000001'::uuid),
  ('c0de0000-0000-4000-8205-000000000002'::uuid),
  ('c0de0000-0000-4000-8205-000000000003'::uuid),
  ('c0de0000-0000-4000-8205-000000000004'::uuid),
  ('c0de0000-0000-4000-8205-000000000005'::uuid),
  ('c0de0000-0000-4000-8205-000000000006'::uuid),
  ('c0de0000-0000-4000-8205-000000000007'::uuid),
  ('c0de0000-0000-4000-8205-000000000008'::uuid),
  ('c0de0000-0000-4000-8205-000000000009'::uuid),
  ('c0de0000-0000-4000-8205-000000000010'::uuid)
) as menu_seed(menu_id)
where role_row.enabled
  and (
    role_row.builtin_type = 'platform_super'
    or role_row.role_code in ('R_SUPER', 'R_ADMIN')
  )
on conflict (role_id, menu_id) do nothing;
