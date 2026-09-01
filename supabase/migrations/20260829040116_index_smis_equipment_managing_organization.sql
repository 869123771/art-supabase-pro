create index if not exists smis_equipment_managing_organization_fk_idx
  on public.smis_equipment (tenant_id, managing_organization_id);;
