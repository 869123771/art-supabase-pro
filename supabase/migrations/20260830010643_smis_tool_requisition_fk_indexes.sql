
create index if not exists smis_tool_issuance_record_item_parent_idx
  on public.smis_tool_issuance_record_item (issuance_record_id, tenant_id);
create index if not exists smis_tool_issuance_standard_detail_parent_idx
  on public.smis_tool_issuance_standard_detail (standard_id, tenant_id);
create index if not exists smis_tool_issuance_standard_organization_parent_idx
  on public.smis_tool_issuance_standard_organization (standard_id, tenant_id);
create index if not exists smis_tool_issuance_standard_position_parent_idx
  on public.smis_tool_issuance_standard_position (standard_id, tenant_id);
create index if not exists smis_tool_personal_requisition_item_parent_idx
  on public.smis_tool_personal_requisition_item (requisition_id, tenant_id);
create index if not exists smis_tool_personal_standard_item_parent_idx
  on public.smis_tool_personal_standard_item (personal_standard_id, tenant_id);
create index if not exists smis_tool_personal_standard_item_source_idx
  on public.smis_tool_personal_standard_item (source_standard_id, tenant_id);
;
