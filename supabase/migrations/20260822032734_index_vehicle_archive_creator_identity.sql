create index if not exists vehicle_archive_created_by_user_tenant_idx
  on public.vehicle_archive(created_by_user_id, tenant_id);;
