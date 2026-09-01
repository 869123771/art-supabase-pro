
revoke all on function public.tms_complete_order_with_waybill(
  uuid,
  numeric,
  jsonb,
  timestamptz
) from public, anon;

grant execute on function public.tms_complete_order_with_waybill(
  uuid,
  numeric,
  jsonb,
  timestamptz
) to authenticated, service_role;
;
