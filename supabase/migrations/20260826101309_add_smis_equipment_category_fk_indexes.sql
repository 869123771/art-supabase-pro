create index if not exists smis_equipment_category_parent_fk_idx
  on public.smis_equipment_category(parent_id, tenant_id)
  where parent_id is not null;

create index if not exists smis_equipment_category_inspection_equipment_fk_idx
  on public.smis_equipment_category_inspection(equipment_category_id, tenant_id);

create index if not exists smis_equipment_category_inspection_inspection_fk_idx
  on public.smis_equipment_category_inspection(inspection_category_id, tenant_id);;
