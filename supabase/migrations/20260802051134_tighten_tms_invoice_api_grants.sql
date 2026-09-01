
revoke all on table public.tms_invoice, public.tms_invoice_statement_link from anon;
revoke all on table public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench from anon;

revoke all on table public.tms_invoice, public.tms_invoice_statement_link from authenticated;
grant select, insert, update, delete on table public.tms_invoice, public.tms_invoice_statement_link to authenticated;

revoke all on table public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench from authenticated;
grant select on table public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench to authenticated;

revoke all on table public.tms_invoice, public.tms_invoice_statement_link from service_role;
grant select, insert, update, delete on table public.tms_invoice, public.tms_invoice_statement_link to service_role;

revoke all on table public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench from service_role;
grant select on table public.tms_invoice_summary, public.tms_invoice_detail_link,
  public.tms_invoiceable_statement, public.tms_finance_workbench to service_role;

revoke all on sequence public.tms_invoice_record_no_seq from anon;
revoke all on sequence public.tms_invoice_record_no_seq from authenticated, service_role;
grant usage, select on sequence public.tms_invoice_record_no_seq to authenticated, service_role;
;
