begin;

revoke all on function public.fms_subject_balance_report(uuid, integer, integer, integer, uuid, boolean)
  from public, anon;
revoke all on function public.fms_general_ledger_report(uuid, integer, uuid, integer, integer)
  from public, anon;
revoke all on function public.fms_subsidiary_ledger_report(uuid, integer, uuid, integer, integer, uuid, uuid)
  from public, anon;

grant execute on function public.fms_subject_balance_report(uuid, integer, integer, integer, uuid, boolean)
  to authenticated, service_role;
grant execute on function public.fms_general_ledger_report(uuid, integer, uuid, integer, integer)
  to authenticated, service_role;
grant execute on function public.fms_subsidiary_ledger_report(uuid, integer, uuid, integer, integer, uuid, uuid)
  to authenticated, service_role;

commit;

;
