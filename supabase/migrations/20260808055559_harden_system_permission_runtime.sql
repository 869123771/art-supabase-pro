
alter function public.current_has_permission(text) security invoker;

drop policy if exists tenant_update on public.sys_user;
create policy tenant_update
on public.sys_user
for update
to authenticated
using (
  auth_user_id = (select auth.uid())
  or (
    (
      app_private.has_permission('System:User:Edit')
      or app_private.has_permission('System:User:AssignRole')
    )
    and (
      app_private.is_platform_super()
      or tenant_id = app_private.current_user_tenant_id()
    )
  )
)
with check (
  app_private.is_platform_super()
  or tenant_id = app_private.current_user_tenant_id()
);

create index if not exists idx_sys_role_menu_menu_id
  on public.sys_role_menu (menu_id);
;
