create index if not exists smis_position_safety_responsibility_position_idx
  on public.smis_position_safety_responsibility
  (position_id, tenant_id, organization_id);

;
