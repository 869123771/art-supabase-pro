create index if not exists tms_customer_statement_customer_id_idx
  on public.tms_customer_statement (customer_id);

create index if not exists tms_customer_statement_item_customer_id_idx
  on public.tms_customer_statement_item (customer_id);

create index if not exists tms_customer_statement_item_waybill_id_idx
  on public.tms_customer_statement_item (waybill_id);

;
