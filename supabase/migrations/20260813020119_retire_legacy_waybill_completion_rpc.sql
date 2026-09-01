
-- Retire the legacy Web signature RPC that combined signature and completion.
revoke execute on function public.tms_complete_order_with_waybill(
  uuid, numeric, jsonb, timestamptz
) from public, anon, authenticated;

;
