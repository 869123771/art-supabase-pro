-- Remove PostgreSQL's default PUBLIC execute grant from voucher security RPCs.

revoke execute on function public.fms_list_vouchers_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid[], text
) from public, anon;
revoke execute on function public.fms_get_voucher_secure(uuid) from public, anon;
revoke execute on function public.fms_voucher_summary_secure(uuid) from public, anon;
revoke execute on function public.fms_list_cash_flow_allocations_secure(uuid) from public, anon;
revoke execute on function public.save_fms_voucher_secure(jsonb) from public, anon;
revoke execute on function public.transition_fms_voucher_secure(uuid, text, text, date)
  from public, anon;
revoke execute on function public.save_fms_cash_flow_allocations_secure(uuid, jsonb)
  from public, anon;

grant execute on function public.fms_list_vouchers_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid[], text
) to authenticated;
grant execute on function public.fms_get_voucher_secure(uuid) to authenticated;
grant execute on function public.fms_voucher_summary_secure(uuid) to authenticated;
grant execute on function public.fms_list_cash_flow_allocations_secure(uuid) to authenticated;
grant execute on function public.save_fms_voucher_secure(jsonb) to authenticated;
grant execute on function public.transition_fms_voucher_secure(uuid, text, text, date)
  to authenticated;
grant execute on function public.save_fms_cash_flow_allocations_secure(uuid, jsonb)
  to authenticated;

;
