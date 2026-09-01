-- Cover foreign-key lookups with indexes whose leading columns match each FK definition.
create index smis_risk_point_site_fk_idx
  on public.smis_risk_point(site_id);

create index smis_risk_point_equipment_fk_idx
  on public.smis_risk_point(equipment_id)
  where equipment_id is not null;

create index smis_risk_point_organization_point_fk_idx
  on public.smis_risk_point_organization(tenant_id, risk_point_id);

create index smis_risk_point_organization_organization_fk_idx
  on public.smis_risk_point_organization(organization_id);

create index smis_risk_item_activity_item_fk_idx
  on public.smis_risk_item_activity(tenant_id, risk_item_id);;
