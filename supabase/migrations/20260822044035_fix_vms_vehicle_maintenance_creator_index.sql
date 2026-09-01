drop index if exists public.vehicle_maintenance_record_creator_tenant_idx;

create index vehicle_maintenance_record_creator_tenant_idx
  on public.vehicle_maintenance_record(created_by_user_id, tenant_id);

;
