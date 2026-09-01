-- Allow existing RPC-based creation flows to pass a manual number without duplicating business logic.

create or replace function app_private.trg_assign_configurable_number()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rule public.sys_document_number_rule;
  v_tenant_id uuid;
  v_current text;
  v_override text;
  v_value text;
begin
  v_tenant_id := coalesce(new.tenant_id, app_private.current_user_tenant_id());
  select * into v_rule
  from public.sys_document_number_rule
  where tenant_id = v_tenant_id and rule_key = tg_argv[0] and enabled;
  if not found then
    raise exception '未找到已启用的编号规则：%', tg_argv[0];
  end if;

  v_current := nullif(btrim(coalesce(to_jsonb(new) ->> tg_argv[1], '')), '');
  v_override := nullif(btrim(current_setting(
    'app.document_number.' || replace(tg_argv[0], '.', '_'), true
  )), '');
  if v_rule.auto_enabled then
    v_value := app_private.next_document_number(tg_argv[0], v_tenant_id);
  else
    v_value := coalesce(v_current, v_override);
    if v_rule.manual_required and v_value is null then
      raise exception '%未启用自动编码，请手工填写', v_rule.rule_name;
    end if;
  end if;
  new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], v_value));
  return new;
end;
$function$;

create or replace function public.create_tms_customer_statement(
  p_customer_id uuid, p_period_start date, p_period_end date,
  p_waybill_ids uuid[], p_remark text, p_statement_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_customer_statement', coalesce(p_statement_no, ''), true);
  return public.create_tms_customer_statement(
    p_customer_id, p_period_start, p_period_end, p_waybill_ids, p_remark
  );
end;
$function$;

create or replace function public.create_tms_carrier_statement(
  p_carrier_id uuid, p_period_start date, p_period_end date,
  p_cost_ids uuid[], p_remark text, p_statement_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_carrier_statement', coalesce(p_statement_no, ''), true);
  return public.create_tms_carrier_statement(
    p_carrier_id, p_period_start, p_period_end, p_cost_ids, p_remark
  );
end;
$function$;

create or replace function public.save_tms_carrier_payment_application(
  p_application_id uuid, p_carrier_id uuid, p_planned_payment_date date,
  p_amount numeric, p_payment_method text, p_basis_urls jsonb,
  p_remark text, p_allocations jsonb, p_application_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_carrier_payment_application', coalesce(p_application_no, ''), true);
  return public.save_tms_carrier_payment_application(
    p_application_id, p_carrier_id, p_planned_payment_date, p_amount,
    p_payment_method, p_basis_urls, p_remark, p_allocations
  );
end;
$function$;

create or replace function public.create_tms_carrier_payment(
  p_carrier_id uuid, p_transaction_date date, p_amount numeric,
  p_payment_method text, p_bank_reference text, p_voucher_urls jsonb,
  p_remark text, p_allocations jsonb, p_transaction_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_cash_transaction', coalesce(p_transaction_no, ''), true);
  return public.create_tms_carrier_payment(
    p_carrier_id, p_transaction_date, p_amount, p_payment_method,
    p_bank_reference, p_voucher_urls, p_remark, p_allocations
  );
end;
$function$;

create or replace function public.create_tms_customer_receipt(
  p_customer_id uuid, p_transaction_date date, p_amount numeric,
  p_payment_method text, p_bank_reference text, p_voucher_urls jsonb,
  p_remark text, p_allocations jsonb, p_transaction_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_cash_transaction', coalesce(p_transaction_no, ''), true);
  return public.create_tms_customer_receipt(
    p_customer_id, p_transaction_date, p_amount, p_payment_method,
    p_bank_reference, p_voucher_urls, p_remark, p_allocations
  );
end;
$function$;

create or replace function public.save_tms_invoice(
  p_invoice_id uuid, p_direction text, p_invoice_type text,
  p_customer_id uuid, p_carrier_id uuid, p_invoice_title text,
  p_tax_number text, p_invoice_code text, p_invoice_no text,
  p_issue_date date, p_tax_rate numeric, p_amount_excluding_tax numeric,
  p_tax_amount numeric, p_total_amount numeric, p_attachments jsonb,
  p_remark text, p_statement_links jsonb, p_invoice_record_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_invoice_record', coalesce(p_invoice_record_no, ''), true);
  return public.save_tms_invoice(
    p_invoice_id, p_direction, p_invoice_type, p_customer_id, p_carrier_id,
    p_invoice_title, p_tax_number, p_invoice_code, p_invoice_no, p_issue_date,
    p_tax_rate, p_amount_excluding_tax, p_tax_amount, p_total_amount,
    p_attachments, p_remark, p_statement_links
  );
end;
$function$;

create or replace function public.create_tms_expense_reimbursement(
  p_expense_ids uuid[], p_payee_name text, p_payee_bank text,
  p_payee_account text, p_planned_payment_date date, p_payment_method text,
  p_basis_urls jsonb, p_remark text, p_reimbursement_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_expense_reimbursement', coalesce(p_reimbursement_no, ''), true);
  return public.create_tms_expense_reimbursement(
    p_expense_ids, p_payee_name, p_payee_bank, p_payee_account,
    p_planned_payment_date, p_payment_method, p_basis_urls, p_remark
  );
end;
$function$;

create or replace function public.execute_tms_expense_reimbursement(
  p_reimbursement_id uuid, p_payment_date date, p_bank_reference text,
  p_voucher_urls jsonb, p_remark text, p_payment_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_expense_payment', coalesce(p_payment_no, ''), true);
  return public.execute_tms_expense_reimbursement(
    p_reimbursement_id, p_payment_date, p_bank_reference, p_voucher_urls, p_remark
  );
end;
$function$;

create or replace function public.create_ai_receipt_exception_work_order(
  p_artifact_id uuid, p_order_id uuid, p_evidence_urls jsonb, p_work_order_no text
)
returns public.tms_receipt_exception_work_order
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_receipt_exception', coalesce(p_work_order_no, ''), true);
  return public.create_ai_receipt_exception_work_order(p_artifact_id, p_order_id, p_evidence_urls);
end;
$function$;

revoke all on function public.create_tms_customer_statement(uuid,date,date,uuid[],text,text) from public, anon;
revoke all on function public.create_tms_carrier_statement(uuid,date,date,uuid[],text,text) from public, anon;
revoke all on function public.save_tms_carrier_payment_application(uuid,uuid,date,numeric,text,jsonb,text,jsonb,text) from public, anon;
revoke all on function public.create_tms_carrier_payment(uuid,date,numeric,text,text,jsonb,text,jsonb,text) from public, anon;
revoke all on function public.create_tms_customer_receipt(uuid,date,numeric,text,text,jsonb,text,jsonb,text) from public, anon;
revoke all on function public.save_tms_invoice(uuid,text,text,uuid,uuid,text,text,text,text,date,numeric,numeric,numeric,numeric,jsonb,text,jsonb,text) from public, anon;
revoke all on function public.create_tms_expense_reimbursement(uuid[],text,text,text,date,text,jsonb,text,text) from public, anon;
revoke all on function public.execute_tms_expense_reimbursement(uuid,date,text,jsonb,text,text) from public, anon;
revoke all on function public.create_ai_receipt_exception_work_order(uuid,uuid,jsonb,text) from public, anon;

grant execute on function public.create_tms_customer_statement(uuid,date,date,uuid[],text,text) to authenticated;
grant execute on function public.create_tms_carrier_statement(uuid,date,date,uuid[],text,text) to authenticated;
grant execute on function public.save_tms_carrier_payment_application(uuid,uuid,date,numeric,text,jsonb,text,jsonb,text) to authenticated;
grant execute on function public.create_tms_carrier_payment(uuid,date,numeric,text,text,jsonb,text,jsonb,text) to authenticated;
grant execute on function public.create_tms_customer_receipt(uuid,date,numeric,text,text,jsonb,text,jsonb,text) to authenticated;
grant execute on function public.save_tms_invoice(uuid,text,text,uuid,uuid,text,text,text,text,date,numeric,numeric,numeric,numeric,jsonb,text,jsonb,text) to authenticated;
grant execute on function public.create_tms_expense_reimbursement(uuid[],text,text,text,date,text,jsonb,text,text) to authenticated;
grant execute on function public.execute_tms_expense_reimbursement(uuid,date,text,jsonb,text,text) to authenticated;
grant execute on function public.create_ai_receipt_exception_work_order(uuid,uuid,jsonb,text) to authenticated;


;
