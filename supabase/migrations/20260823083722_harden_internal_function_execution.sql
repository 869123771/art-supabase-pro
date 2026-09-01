-- Restrict legacy internal and trigger functions that inherited PostgreSQL's default PUBLIC
-- EXECUTE grant. Authenticated access remains only where normal application writes or reads rely
-- on the function, while anonymous callers no longer receive a privileged RPC surface.

alter function public.clean_role_menus_on_role_delete()
  set search_path = pg_catalog, public;
revoke execute on function public.clean_role_menus_on_role_delete() from public, anon;
grant execute on function public.clean_role_menus_on_role_delete() to authenticated, service_role;

alter function public.get_app_user_display_name()
  set search_path = pg_catalog, public;
revoke execute on function public.get_app_user_display_name() from public, anon;
grant execute on function public.get_app_user_display_name() to authenticated, service_role;

revoke execute on function public.get_menus_for_current_user() from public, anon;
grant execute on function public.get_menus_for_current_user() to authenticated, service_role;

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
grant execute on function public.rls_auto_enable() to service_role;

alter function public.set_vehicle_parts_category_level()
  set search_path = pg_catalog, public;

alter function public.trg_set_create_time_and_by()
  set search_path = pg_catalog, public;
revoke execute on function public.trg_set_create_time_and_by() from public, anon;
grant execute on function public.trg_set_create_time_and_by() to authenticated, service_role;

;
