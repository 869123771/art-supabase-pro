create index if not exists hr_service_request_event_request_fk_idx
  on public.hr_service_request_event(request_id, tenant_id);
