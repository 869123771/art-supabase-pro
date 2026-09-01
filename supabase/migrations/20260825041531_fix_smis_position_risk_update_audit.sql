create or replace function app_private.smis_trg_set_position_risk_update_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.update_time := now();
  new.update_by := coalesce(
    nullif(auth.jwt() ->> 'email', ''),
    nullif(old.update_by, ''),
    'unknown'
  );
  return new;
end;
$function$;

revoke all on function app_private.smis_trg_set_position_risk_update_audit()
  from public, anon, authenticated;

drop trigger if exists smis_position_risk_control_update_audit
  on public.smis_position_risk_control;
create trigger smis_position_risk_control_update_audit
before update on public.smis_position_risk_control
for each row
execute function app_private.smis_trg_set_position_risk_update_audit();

;
