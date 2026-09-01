-- Close the permission gap for create-like workflows and add covering indexes for
-- every PPE foreign key surfaced by the Supabase performance advisor.

create or replace function public.smis_save_ppe_issuance_record_secure(p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_id uuid; v_employee record; v_warehouse record; v_issuer record; v_item jsonb; v_material record;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_id is null and not (
    app_private.has_permission('SmisPpeIssuanceRecord:Add')
    or app_private.has_permission('SmisPpeIssuanceRecord:Copy')
    or app_private.has_permission('SmisPpeIssuanceRecord:Import')
  ) then raise exception '当前账号没有新增、复制或导入发放记录的权限' using errcode='42501'; end if;
  if p_id is not null and not app_private.has_permission('SmisPpeIssuanceRecord:Edit') then raise exception '当前账号没有编辑发放记录的权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_ppe_issuance_record where id=p_id));
  select e.*,o.organization_name,p.position_name into v_employee from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=(p_payload->>'employee_id')::uuid and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=(p_payload->>'warehouse_id')::uuid and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=(p_payload->>'issuer_employee_id')::uuid and tenant_id=v_tenant;
  if v_employee.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  if jsonb_array_length(coalesce(p_payload->'items','[]'::jsonb))=0 then raise exception '请至少添加一条发放明细' using errcode='22023'; end if;
  if p_id is null then
    insert into public.smis_ppe_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status,remark)
    values(v_tenant,app_private.next_document_number('smis.ppe_issuance_record',v_tenant),v_employee.id,v_employee.employee_no,v_employee.employee_name,v_employee.position_name,v_employee.organization_id,v_employee.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce((p_payload->>'issue_date')::date,current_date),'draft',nullif(btrim(coalesce(p_payload->>'remark','')),'')) returning id into v_id;
  else
    if not exists(select 1 from public.smis_ppe_issuance_record where id=p_id and tenant_id=v_tenant and status='draft') then raise exception '仅草稿状态允许编辑' using errcode='P0001'; end if;
    update public.smis_ppe_issuance_record set employee_id=v_employee.id,employee_no_snapshot=v_employee.employee_no,employee_name_snapshot=v_employee.employee_name,position_name_snapshot=v_employee.position_name,organization_id=v_employee.organization_id,organization_name_snapshot=v_employee.organization_name,warehouse_id=v_warehouse.id,warehouse_name_snapshot=v_warehouse.location_name,issuer_employee_id=v_issuer.id,issuer_name_snapshot=v_issuer.employee_name,issue_date=coalesce((p_payload->>'issue_date')::date,current_date),remark=nullif(btrim(coalesce(p_payload->>'remark','')),'') where id=p_id returning id into v_id;
    delete from public.smis_ppe_issuance_record_item where issuance_record_id=v_id;
  end if;
  for v_item in select value from jsonb_array_elements(p_payload->'items') loop
    select m.*,c.category_name into v_material from public.smis_material m join public.smis_material_category c on c.id=m.category_id where m.id=(v_item->>'material_id')::uuid and m.tenant_id=v_tenant and m.material_type='protective_equipment';
    if v_material.id is null then raise exception '发放明细中的防护用品无效' using errcode='P0002'; end if;
    insert into public.smis_ppe_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity,remark)
    values(v_tenant,v_id,nullif(v_item->>'requisition_item_id','')::uuid,v_material.id,v_material.category_name,v_material.material_name,v_material.specification_model,v_material.basic_unit,(v_item->>'issue_quantity')::numeric,nullif(btrim(coalesce(v_item->>'remark','')),''));
  end loop;
  return v_id;
end $$;

create index if not exists smis_ppe_issuance_record_employee_fk_idx on public.smis_ppe_issuance_record(employee_id);
create index if not exists smis_ppe_issuance_record_issuer_fk_idx on public.smis_ppe_issuance_record(issuer_employee_id);
create index if not exists smis_ppe_issuance_record_org_fk_idx on public.smis_ppe_issuance_record(organization_id);
create index if not exists smis_ppe_issuance_record_warehouse_fk_idx on public.smis_ppe_issuance_record(warehouse_id);
create index if not exists smis_ppe_issuance_item_record_fk_idx on public.smis_ppe_issuance_record_item(issuance_record_id);
create index if not exists smis_ppe_issuance_item_material_fk_idx on public.smis_ppe_issuance_record_item(material_id);
create index if not exists smis_ppe_requisition_employee_fk_idx on public.smis_ppe_personal_requisition(employee_id);
create index if not exists smis_ppe_requisition_org_fk_idx on public.smis_ppe_personal_requisition(organization_id);
create index if not exists smis_ppe_requisition_position_fk_idx on public.smis_ppe_personal_requisition(position_id);
create index if not exists smis_ppe_requisition_item_parent_fk_idx on public.smis_ppe_personal_requisition_item(requisition_id);
create index if not exists smis_ppe_requisition_item_material_fk_idx on public.smis_ppe_personal_requisition_item(material_id);
create index if not exists smis_ppe_requisition_item_plan_fk_idx on public.smis_ppe_personal_requisition_item(personal_standard_item_id);
create index if not exists smis_ppe_standard_position_position_fk_idx on public.smis_ppe_issuance_standard_position(position_id);
create index if not exists smis_ppe_standard_position_standard_fk_idx on public.smis_ppe_issuance_standard_position(standard_id);
create index if not exists smis_ppe_standard_org_org_fk_idx on public.smis_ppe_issuance_standard_organization(organization_id);
create index if not exists smis_ppe_standard_org_standard_fk_idx on public.smis_ppe_issuance_standard_organization(standard_id);
create index if not exists smis_ppe_standard_detail_standard_fk_idx on public.smis_ppe_issuance_standard_detail(standard_id);
create index if not exists smis_ppe_standard_detail_material_fk_idx on public.smis_ppe_issuance_standard_detail(material_id);
create index if not exists smis_ppe_personal_employee_fk_idx on public.smis_ppe_personal_standard(employee_id);
create index if not exists smis_ppe_personal_org_fk_idx on public.smis_ppe_personal_standard(organization_id);
create index if not exists smis_ppe_personal_position_fk_idx on public.smis_ppe_personal_standard(position_id);
create index if not exists smis_ppe_personal_item_detail_fk_idx on public.smis_ppe_personal_standard_item(source_detail_id);
create index if not exists smis_ppe_personal_item_material_fk_idx on public.smis_ppe_personal_standard_item(material_id);
create index if not exists smis_ppe_personal_item_personal_fk_idx on public.smis_ppe_personal_standard_item(personal_standard_id);
create index if not exists smis_ppe_personal_item_standard_fk_idx on public.smis_ppe_personal_standard_item(source_standard_id);

;
