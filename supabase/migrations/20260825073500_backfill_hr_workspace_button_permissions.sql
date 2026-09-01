-- The three HR workspace pages existed before their button rows were introduced.
-- Keep current page access compatible by granting each new direct child button to
-- roles that already own the corresponding page menu.

with button_seed(menu_name, button_name, title, sort_order) as (
  values
    ('HrPersonnelChange', 'Hr:PersonnelChange:View', '查看异动', 1),
    ('HrPersonnelChange', 'Hr:PersonnelChange:Add', '新增异动', 2),
    ('HrPersonnelChange', 'Hr:PersonnelChange:Edit', '编辑异动', 3),
    ('HrPersonnelChange', 'Hr:PersonnelChange:Delete', '删除异动', 4),
    ('HrPersonnelChange', 'Hr:PersonnelChange:Submit', '提交审批', 5),
    ('HrPersonnelChange', 'Hr:PersonnelChange:Effect', '生效异动', 6),
    ('HrLifecycle', 'Hr:Lifecycle:View', '查看事项', 1),
    ('HrLifecycle', 'Hr:Lifecycle:Add', '新增事项', 2),
    ('HrLifecycle', 'Hr:Lifecycle:Edit', '编辑事项', 3),
    ('HrLifecycle', 'Hr:Lifecycle:Delete', '删除事项', 4),
    ('HrLifecycle', 'Hr:Lifecycle:Submit', '提交审批', 5),
    ('HrLifecycle', 'Hr:Lifecycle:CompleteTask', '完成任务', 6),
    ('HrCompliance', 'Hr:Compliance:View', '查看合同资质', 1),
    ('HrCompliance', 'Hr:Compliance:Add', '新增资质', 2),
    ('HrCompliance', 'Hr:Compliance:Edit', '编辑合同资质', 3),
    ('HrCompliance', 'Hr:Compliance:Delete', '删除资质', 4)
)
insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  meta,
  sort,
  type,
  app_code,
  create_by,
  update_by
)
select
  gen_random_uuid(),
  page_menu.id,
  seed.button_name,
  '',
  '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'roles', jsonb_build_array(),
    'is_hide', true,
    'is_enable', true,
    'is_auth_button', true
  ),
  seed.sort_order,
  'button',
  'hr',
  'codex-hr-workspace-permission-migration',
  'codex-hr-workspace-permission-migration'
from button_seed seed
join public.sys_menu page_menu
  on page_menu.name = seed.menu_name
 and page_menu.type = 'menu'
where not exists (
  select 1
  from public.sys_menu existing_button
  where existing_button.parent_id = page_menu.id
    and existing_button.name = seed.button_name
);

insert into public.sys_role_menu (
  role_id,
  menu_id,
  tenant_id,
  permission,
  create_by,
  update_by
)
select
  page_grant.role_id,
  button_menu.id,
  page_grant.tenant_id,
  '{}'::jsonb,
  'codex-hr-workspace-permission-migration',
  'codex-hr-workspace-permission-migration'
from public.sys_role_menu page_grant
join public.sys_menu page_menu
  on page_menu.id = page_grant.menu_id
 and page_menu.name in ('HrPersonnelChange', 'HrLifecycle', 'HrCompliance')
join public.sys_menu button_menu
  on button_menu.parent_id = page_menu.id
 and button_menu.type = 'button'
 and (
   button_menu.name like 'Hr:PersonnelChange:%'
   or button_menu.name like 'Hr:Lifecycle:%'
   or button_menu.name like 'Hr:Compliance:%'
 )
where not exists (
  select 1
  from public.sys_role_menu existing_grant
  where existing_grant.role_id = page_grant.role_id
    and existing_grant.menu_id = button_menu.id
    and existing_grant.tenant_id is not distinct from page_grant.tenant_id
);

;
