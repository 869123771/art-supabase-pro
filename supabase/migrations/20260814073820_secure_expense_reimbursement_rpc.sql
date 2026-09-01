-- Keep the privileged transaction engine outside the exposed Data API schema.
alter function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) set schema app_private;

revoke all on function app_private.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) from public, anon;
grant execute on function app_private.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) to authenticated;

-- PostgREST exposes only this invoker wrapper. The authenticated caller must pass
-- every tenant, lifecycle and driver-account check in the private engine.
create function public.create_tms_expense_reimbursement(
  p_cost_ids uuid[],
  p_payee_name text,
  p_payee_bank text,
  p_payee_account text,
  p_planned_payment_date date,
  p_payment_method text,
  p_basis_urls jsonb default '[]'::jsonb,
  p_remark text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select app_private.create_tms_expense_reimbursement(
    p_cost_ids,
    p_payee_name,
    p_payee_bank,
    p_payee_account,
    p_planned_payment_date,
    p_payment_method,
    p_basis_urls,
    p_remark
  );
$$;

revoke all on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) from public, anon;
grant execute on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) to authenticated;

;
