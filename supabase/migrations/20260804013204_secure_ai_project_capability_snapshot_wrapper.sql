
alter function public.get_ai_project_capability_snapshot() set schema app_private;

revoke all on function app_private.get_ai_project_capability_snapshot() from public, anon, authenticated;
grant execute on function app_private.get_ai_project_capability_snapshot() to service_role;

create function public.get_ai_project_capability_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null or not public.current_is_super() then
    raise exception 'Platform super administrator permission is required'
      using errcode = '42501';
  end if;

  return app_private.get_ai_project_capability_snapshot();
end;
$function$;

comment on function public.get_ai_project_capability_snapshot() is
  'Platform-super-only wrapper for the aggregate AI project capability snapshot.';

revoke all on function public.get_ai_project_capability_snapshot() from public, anon;
grant execute on function public.get_ai_project_capability_snapshot() to authenticated, service_role;
;
