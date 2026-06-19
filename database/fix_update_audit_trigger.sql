create or replace function public.trg_set_update_time_and_by()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  begin
    new.update_time := now();
  exception when undefined_column then
    null;
  end;

  begin
    new.update_by := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      nullif(old.update_by, ''),
      'unknown'
    );
  exception when undefined_column then
    null;
  end;

  return new;
end
$function$;
