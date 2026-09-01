-- The project serves a China-based HR workspace. PostgreSQL runs in UTC, so
-- current_date can lag the browser by one day after local midnight. Keep the
-- existing aggregate implementation as a private callable core and expose a
-- wrapper whose date default and future-date clamp run in the HR business zone.

alter function public.hr_people_analytics_overview_secure(date, integer, uuid)
  rename to hr_people_analytics_overview_business_date_core;

revoke all on function public.hr_people_analytics_overview_business_date_core(date, integer, uuid)
  from public, anon, authenticated;

alter function public.hr_people_analytics_overview_business_date_core(date, integer, uuid)
  set timezone = 'Asia/Shanghai';

create or replace function public.hr_people_analytics_overview_secure(
  p_as_of_date date default null,
  p_period_months integer default 12,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
begin
  return public.hr_people_analytics_overview_business_date_core(
    coalesce(p_as_of_date, current_date),
    p_period_months,
    p_tenant_id
  );
end
$function$;

revoke all on function public.hr_people_analytics_overview_secure(date, integer, uuid)
  from public, anon;
grant execute on function public.hr_people_analytics_overview_secure(date, integer, uuid)
  to authenticated;

;
