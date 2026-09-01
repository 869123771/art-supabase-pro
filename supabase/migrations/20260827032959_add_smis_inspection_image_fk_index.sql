create index if not exists smis_equipment_inspection_image_inspection_tenant_idx
  on public.smis_equipment_inspection_image(inspection_id, tenant_id);;
