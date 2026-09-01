create or replace function public.execute_tms_carrier_payment_application(
  p_application_id uuid, p_transaction_date date, p_bank_reference text,
  p_voucher_urls jsonb, p_transaction_no text
)
returns uuid
language plpgsql
set search_path to ''
as $function$
begin
  perform set_config('app.document_number.tms_cash_transaction', coalesce(p_transaction_no, ''), true);
  return public.execute_tms_carrier_payment_application(
    p_application_id, p_transaction_date, p_bank_reference, p_voucher_urls
  );
end;
$function$;

revoke all on function public.execute_tms_carrier_payment_application(uuid,date,text,jsonb,text)
  from public, anon;
grant execute on function public.execute_tms_carrier_payment_application(uuid,date,text,jsonb,text)
  to authenticated;


;
