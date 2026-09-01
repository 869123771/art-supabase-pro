create index if not exists idx_document_number_counter_tenant
  on public.sys_document_number_counter (tenant_id);;
