-- 新按钮继承其所属菜单的既有角色范围，不扩大原菜单可见性。
insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select parent_grant.role_id,button.id,parent_grant.tenant_id,'{}'::jsonb,'system','system'
from public.sys_menu button
join public.sys_menu parent on parent.id=button.parent_id
join public.sys_role_menu parent_grant on parent_grant.menu_id=parent.id
where button.name like 'SmisEmergencyDrillPlan:%'
   or button.name like 'SmisEmergencyDrillRecord:%'
   or button.name like 'SmisEmergencyDrillReport:%'
on conflict(role_id,menu_id) do nothing;

;
