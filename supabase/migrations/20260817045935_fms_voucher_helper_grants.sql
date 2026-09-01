begin;

grant execute on function app_private.next_fms_voucher_no(uuid, uuid, smallint, smallint, text)
  to authenticated, service_role;
grant execute on function app_private.refresh_fms_voucher_totals(uuid)
  to authenticated, service_role;
grant execute on function app_private.assert_fms_voucher_ready(uuid)
  to authenticated, service_role;

commit;

;
