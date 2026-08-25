create or replace function app_private.current_user_email()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select public.get_app_user_display_name()
$function$;

revoke all on function app_private.current_user_email()
from public, anon, authenticated;
