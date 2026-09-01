-- Compensation review exposes a tenant-scoped read-only workspace to ordinary
-- enabled users. Sensitive amounts and every controlled write are opt-in and
-- default only to the platform-super role.

delete from public.sys_role_menu role_menu
using public.sys_role role_row, public.sys_menu menu_row
where role_menu.role_id = role_row.id
  and role_menu.menu_id = menu_row.id
  and menu_row.name in (
    'Hr:CompensationReview:Cycle:Manage',
    'Hr:CompensationReview:Budget:Manage',
    'Hr:CompensationReview:Recommend',
    'Hr:CompensationReview:Calibrate',
    'Hr:CompensationReview:Approve',
    'Hr:CompensationReview:Effect',
    'Hr:CompensationReview:Amount:View',
    'Hr:CompensationReview:Amount:Edit'
  )
  and role_row.role_code <> 'R_SUPER';

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  role_row.id,
  menu_row.id,
  role_row.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role role_row
cross join public.sys_menu menu_row
where role_row.role_code = 'R_SUPER'
  and menu_row.name in (
    'HrCompensationReview',
    'Hr:CompensationReview:View',
    'Hr:CompensationReview:Cycle:Manage',
    'Hr:CompensationReview:Budget:Manage',
    'Hr:CompensationReview:Recommend',
    'Hr:CompensationReview:Calibrate',
    'Hr:CompensationReview:Approve',
    'Hr:CompensationReview:Effect',
    'Hr:CompensationReview:Amount:View',
    'Hr:CompensationReview:Amount:Edit'
  )
on conflict (role_id, menu_id) do nothing;


;
