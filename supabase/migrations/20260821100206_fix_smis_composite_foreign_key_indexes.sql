-- 覆盖 SMIS 复合租户外键，保证关联查询与父记录删除检查使用索引。
create index smis_site_tenant_organization_fk_idx
  on public.smis_site (tenant_id, organization_id);

create index smis_area_tenant_parent_fk_idx
  on public.smis_area (tenant_id, parent_id);
create index smis_area_manager_tenant_fk_idx
  on public.smis_area (manager_user_id, tenant_id);

create index smis_risk_point_tenant_site_fk_idx
  on public.smis_risk_point (tenant_id, site_id);
create index smis_risk_point_tenant_area_fk_idx
  on public.smis_risk_point (tenant_id, area_id);
create index smis_risk_point_tenant_organization_fk_idx
  on public.smis_risk_point (tenant_id, organization_id);
create index smis_risk_point_responsible_tenant_fk_idx
  on public.smis_risk_point (responsible_user_id, tenant_id);

create index smis_risk_assessment_assessor_tenant_fk_idx
  on public.smis_risk_assessment (assessor_user_id, tenant_id);
create index smis_risk_assessment_reviewer_tenant_fk_idx
  on public.smis_risk_assessment (reviewer_user_id, tenant_id);

create index smis_risk_assessment_item_tenant_source_fk_idx
  on public.smis_risk_assessment_item (tenant_id, hazard_source_id);

create index smis_control_measure_tenant_item_fk_idx
  on public.smis_control_measure (tenant_id, assessment_item_id);
create index smis_control_measure_responsible_tenant_fk_idx
  on public.smis_control_measure (responsible_user_id, tenant_id);

create index smis_risk_assessment_event_tenant_assessment_fk_idx
  on public.smis_risk_assessment_event (tenant_id, assessment_id);
create index smis_risk_assessment_event_actor_tenant_fk_idx
  on public.smis_risk_assessment_event (actor_user_id, tenant_id);

;
