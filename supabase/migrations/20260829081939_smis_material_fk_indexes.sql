create index smis_material_category_parent_fk_idx
  on public.smis_material_category (parent_id, tenant_id);

create index smis_material_category_fk_idx
  on public.smis_material (category_id, tenant_id);

;
