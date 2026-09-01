-- The source PPE schema and its follow-up FK migration contain equivalent indexes
-- under different names. Keep one covering index per access path.
drop index if exists public.smis_tool_issuance_record_employee_id_idx;
drop index if exists public.smis_tool_issuance_record_issuer_fk_idx;
drop index if exists public.smis_tool_issuance_record_item_issuance_record_id_idx;
drop index if exists public.smis_tool_issuance_record_item_material_id_idx;
drop index if exists public.smis_tool_issuance_record_item_tenant_id_material_id_idx;
drop index if exists public.smis_tool_issuance_record_organization_id_idx;
drop index if exists public.smis_tool_issuance_record_warehouse_id_idx;
drop index if exists public.smis_tool_issuance_scope_idx;
drop index if exists public.smis_tool_issuance_standard_tenant_id_lower_idx;
drop index if exists public.smis_tool_issuance_standard_tenant_id_status_standard_name_idx;
drop index if exists public.smis_tool_personal_standard_employee_id_idx;
drop index if exists public.smis_tool_personal_standard_i_tenant_id_personal_standard_i_idx;
drop index if exists public.smis_tool_personal_standard_i_tenant_id_status_next_issue_d_idx;
drop index if exists public.smis_tool_personal_standard_item_material_id_idx;
drop index if exists public.smis_tool_personal_standard_item_personal_standard_id_idx;
drop index if exists public.smis_tool_personal_standard_item_source_detail_id_idx;
drop index if exists public.smis_tool_personal_standard_item_source_standard_id_idx;
drop index if exists public.smis_tool_personal_standard_organization_id_idx;
drop index if exists public.smis_tool_personal_standard_position_id_idx;
drop index if exists public.smis_tool_personal_standard_tenant_id_organization_id_posit_idx;
drop index if exists public.smis_tool_requisition_employee_fk_idx;
drop index if exists public.smis_tool_requisition_item_material_fk_idx;
drop index if exists public.smis_tool_requisition_item_parent_fk_idx;
drop index if exists public.smis_tool_requisition_item_plan_fk_idx;
drop index if exists public.smis_tool_requisition_org_fk_idx;
drop index if exists public.smis_tool_requisition_position_fk_idx;
drop index if exists public.smis_tool_requisition_scope_idx;
drop index if exists public.smis_tool_requisition_status_idx;
drop index if exists public.smis_tool_standard_detail_material_fk_idx;
drop index if exists public.smis_tool_standard_detail_material_idx;
drop index if exists public.smis_tool_standard_detail_standard_fk_idx;
drop index if exists public.smis_tool_standard_detail_standard_idx;
drop index if exists public.smis_tool_standard_org_org_fk_idx;
drop index if exists public.smis_tool_standard_org_standard_fk_idx;
drop index if exists public.smis_tool_standard_org_tenant_idx;
drop index if exists public.smis_tool_standard_position_position_fk_idx;
drop index if exists public.smis_tool_standard_position_standard_fk_idx;
drop index if exists public.smis_tool_standard_position_tenant_idx;

-- Cover every return-item foreign key in its declared column order.
create index if not exists smis_tool_return_item_parent_tenant_idx
  on public.smis_tool_return_item(return_id, tenant_id);
create index if not exists smis_tool_return_item_source_record_idx
  on public.smis_tool_return_item(source_issuance_record_id);
create index if not exists smis_tool_return_item_tenant_idx
  on public.smis_tool_return_item(tenant_id);

;
