revoke execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, jsonb, jsonb, text, jsonb, text
) from public, anon;

grant execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, jsonb, jsonb, text, jsonb, text
) to authenticated, service_role;

;
