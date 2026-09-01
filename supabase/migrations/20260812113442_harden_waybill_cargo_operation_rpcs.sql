-- SECURITY DEFINER RPCs are authenticated API boundaries, never anonymous endpoints.

revoke execute on function public.tms_get_waybill_cargo_operation_context(uuid, text)
  from public, anon;
revoke execute on function public.tms_check_in_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, text, text, boolean
) from public, anon;
revoke execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, jsonb, jsonb, text
) from public, anon;
revoke execute on function public.tms_save_geofence_config(jsonb)
  from public, anon;

grant execute on function public.tms_get_waybill_cargo_operation_context(uuid, text)
  to authenticated;
grant execute on function public.tms_check_in_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, text, text, boolean
) to authenticated;
grant execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, jsonb, jsonb, text
) to authenticated;
grant execute on function public.tms_save_geofence_config(jsonb)
  to authenticated;

;
