-- The built-in R_REGISTER account is also the default Web business operator in
-- this project and may legitimately be linked to a driver archive. Do not infer
-- a driver-only session from the phone binding alone. R_DASHBOARD remains read-only.
create or replace function app_private.can_manage_tms()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sys_user u
    where u.auth_user_id = (select auth.uid())
      and u.status = '1'
      and coalesce(u.user_roles, '{}'::text[])
        && array['R_SUPER', 'R_ADMIN', 'YQ_ADMIN', 'R_REGISTER']::text[]
  );
$$;
revoke execute on function app_private.can_manage_tms() from public, anon;
grant execute on function app_private.can_manage_tms() to authenticated, service_role;
