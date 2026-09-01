
alter function public.trg_set_update_time_and_by() security definer;

revoke all on function public.trg_set_update_time_and_by()
from public, anon, authenticated;

grant execute on function public.trg_set_update_time_and_by()
to service_role;

comment on function public.trg_set_update_time_and_by() is
  'Generic update audit trigger. Runs as its owner so permitted writes can resolve the current user display name without exposing the private resolver to API roles.';
;
