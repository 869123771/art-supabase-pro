-- Carrier-side financial mutations must never be callable from an anonymous session.
-- RLS remains the tenant boundary for authenticated users, matching the customer-side RPCs.
revoke execute on function public.create_tms_carrier_statement(
  uuid,
  date,
  date,
  uuid[],
  text
) from anon;

revoke execute on function public.create_tms_carrier_payment(
  uuid,
  date,
  numeric,
  text,
  text,
  jsonb,
  text,
  jsonb
) from anon;

revoke execute on function public.allocate_tms_carrier_payment(uuid, jsonb) from anon;

revoke execute on function public.reverse_tms_carrier_cash_allocation(uuid, text) from anon;;
