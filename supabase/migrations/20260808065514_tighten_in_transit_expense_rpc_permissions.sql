revoke all on function public.create_tms_expense_reimbursement(uuid[], text, text, text, date, text, jsonb, text) from public, anon;
grant execute on function public.create_tms_expense_reimbursement(uuid[], text, text, text, date, text, jsonb, text) to authenticated;
revoke all on function public.delete_tms_expense_reimbursement(uuid) from public, anon;
grant execute on function public.delete_tms_expense_reimbursement(uuid) to authenticated;
revoke all on function public.execute_tms_expense_reimbursement(uuid, date, text, jsonb, text) from public, anon;
grant execute on function public.execute_tms_expense_reimbursement(uuid, date, text, jsonb, text) to authenticated;;
