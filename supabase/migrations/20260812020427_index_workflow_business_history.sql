
create index if not exists wf_instance_tenant_business_history_idx
  on public.wf_instance (tenant_id, business_type, business_id, started_at desc);
;
