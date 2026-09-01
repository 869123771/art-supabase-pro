create index if not exists idx_smis_safety_inspection_type_fk
  on public.smis_safety_inspection(inspection_type_id);

create index if not exists idx_smis_safety_inspection_inspection_org
  on public.smis_safety_inspection(tenant_id, inspection_organization_id);

;
