create index if not exists tms_customer_statement_creator_tenant_idx
  on public.tms_customer_statement (created_by_user_id, tenant_id);

create index if not exists tms_carrier_statement_creator_tenant_idx
  on public.tms_carrier_statement (created_by_user_id, tenant_id);

;
