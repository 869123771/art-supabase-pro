
create index if not exists tms_invoice_customer_id_idx
  on public.tms_invoice (customer_id)
  where customer_id is not null;
create index if not exists tms_invoice_carrier_id_idx
  on public.tms_invoice (carrier_id)
  where carrier_id is not null;
create index if not exists tms_invoice_statement_link_invoice_id_idx
  on public.tms_invoice_statement_link (invoice_id);
;
