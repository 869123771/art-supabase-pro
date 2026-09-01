drop policy if exists sys_menu_update_authorized on public.sys_menu;

create policy sys_menu_update_authorized
on public.sys_menu
for update
to authenticated
using (app_private.has_permission('System:Menu:Edit'))
with check (app_private.has_permission('System:Menu:Edit'));

comment on policy sys_menu_update_authorized on public.sys_menu is
  'Allows menu updates, including tree ordering, only through System:Menu:Edit permission.';;
