-- Keep newly created public-schema functions private from anonymous callers
-- unless a migration grants access explicitly.
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

-- Trigger functions are invoked by PostgreSQL triggers, never as client-facing RPCs.
revoke execute on function public.clean_role_menus_on_role_delete()
  from public, anon, authenticated;

revoke execute on function public.trg_set_create_time_and_by()
  from public, anon, authenticated;;
