create index if not exists tms_customer_creator_tenant_fk_idx
  on public.tms_customer (created_by_user_id, tenant_id);

create index if not exists tms_customer_address_creator_tenant_fk_idx
  on public.tms_customer_address (created_by_user_id, tenant_id);

;
