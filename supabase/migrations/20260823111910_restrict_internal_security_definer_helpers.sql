-- These helpers are invoked only by owner-executed database functions.
-- They are not client-facing PostgREST RPC endpoints.
revoke execute on function public.get_app_user_display_name()
  from public, anon, authenticated;

revoke execute on function public.validate_tms_expense_reimbursement_submission_secure(uuid)
  from public, anon, authenticated;

revoke execute on function public.validate_tms_waybill_cost_submission_secure(uuid)
  from public, anon, authenticated;;
