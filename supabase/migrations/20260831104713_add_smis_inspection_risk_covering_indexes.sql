-- Cover tenant-scoped foreign keys used by risk evaluation and control queries.
create index if not exists smis_risk_assessment_dimension_tenant_model_idx
  on public.smis_risk_assessment_dimension(tenant_id, model_id);

create index if not exists smis_risk_assessment_criterion_tenant_dimension_idx
  on public.smis_risk_assessment_criterion(tenant_id, dimension_id);

create index if not exists smis_risk_item_tenant_factor_category_idx
  on public.smis_risk_item(tenant_id, factor_category_id);

create index if not exists smis_risk_item_organization_idx
  on public.smis_risk_item(organization_id)
  where organization_id is not null;

create index if not exists smis_risk_evaluation_tenant_item_idx
  on public.smis_risk_evaluation(tenant_id, risk_item_id);

create index if not exists smis_risk_evaluation_tenant_model_idx
  on public.smis_risk_evaluation(tenant_id, model_id);

create index if not exists smis_risk_evaluation_tenant_model_level_idx
  on public.smis_risk_evaluation(tenant_id, model_id, risk_level_id);

create index if not exists smis_risk_control_measure_position_tenant_measure_idx
  on public.smis_risk_control_measure_position(tenant_id, measure_id);

create index if not exists smis_risk_control_measure_position_organization_idx
  on public.smis_risk_control_measure_position(organization_id)
  where organization_id is not null;

create index if not exists smis_risk_control_measure_position_position_fk_idx
  on public.smis_risk_control_measure_position(position_id);

;
