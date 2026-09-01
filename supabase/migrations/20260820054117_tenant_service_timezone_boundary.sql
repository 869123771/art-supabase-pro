-- Tenant service dates are business dates in China Standard Time. Keep the RLS
-- boundary aligned with the pre-login status check and reminder scheduler.

create or replace function app_private.current_user_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select user_row.tenant_id
  from public.sys_user user_row
  join public.sys_tenant tenant_row on tenant_row.id = user_row.tenant_id
  where user_row.auth_user_id = (select auth.uid())
    and user_row.status = '1'
    and user_row.deleted_at is null
    and tenant_row.status = '1'
    and (
      tenant_row.service_start_date is null
      or tenant_row.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
    )
    and (
      tenant_row.service_end_date is null
      or tenant_row.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
    )
  limit 1;
$$;

;
