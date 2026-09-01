-- Follow-up contracts for editable issue quantities, personal schedules and status dictionaries.

create policy smis_ppe_requisition_insert on public.smis_ppe_personal_requisition for insert to authenticated
with check (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Generate')));
create policy smis_ppe_requisition_update on public.smis_ppe_personal_requisition for update to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and ((select app_private.has_permission('SmisPpePersonalRequisition:Push')) or (select app_private.has_permission('SmisPpePersonalRequisition:Confirm'))))
with check (tenant_id=(select app_private.auth_user_tenant_id()));
create policy smis_ppe_requisition_delete on public.smis_ppe_personal_requisition for delete to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Generate')));
create policy smis_ppe_requisition_item_insert on public.smis_ppe_personal_requisition_item for insert to authenticated
with check (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Generate')));
create policy smis_ppe_requisition_item_update on public.smis_ppe_personal_requisition_item for update to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and ((select app_private.has_permission('SmisPpePersonalRequisition:Push')) or (select app_private.has_permission('SmisPpePersonalRequisition:Confirm'))))
with check (tenant_id=(select app_private.auth_user_tenant_id()));
create policy smis_ppe_requisition_item_delete on public.smis_ppe_personal_requisition_item for delete to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Generate')));
create policy smis_ppe_issuance_insert on public.smis_ppe_issuance_record for insert to authenticated
with check (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:Add')));
create policy smis_ppe_issuance_update on public.smis_ppe_issuance_record for update to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and ((select app_private.has_permission('SmisPpeIssuanceRecord:Edit')) or (select app_private.has_permission('SmisPpeIssuanceRecord:Issue'))))
with check (tenant_id=(select app_private.auth_user_tenant_id()));
create policy smis_ppe_issuance_delete on public.smis_ppe_issuance_record for delete to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:Delete')));
create policy smis_ppe_issuance_item_insert on public.smis_ppe_issuance_record_item for insert to authenticated
with check (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:Add')));
create policy smis_ppe_issuance_item_update on public.smis_ppe_issuance_record_item for update to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and ((select app_private.has_permission('SmisPpeIssuanceRecord:Edit')) or (select app_private.has_permission('SmisPpeIssuanceRecord:Issue'))))
with check (tenant_id=(select app_private.auth_user_tenant_id()));
create policy smis_ppe_issuance_item_delete on public.smis_ppe_issuance_record_item for delete to authenticated
using (tenant_id=(select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:Delete')));

create or replace function public.smis_list_ppe_personal_standard_items_secure(p_employee_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$ begin
  if (select auth.uid()) is null or not (app_private.is_platform_super() or app_private.has_permission('SmisPpePersonalStandard:View')) then raise exception '当前账号没有查看个人标准明细的权限' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'sourceStandardId',s.id,'sourceStandardNo',s.standard_no,'sourceStandardName',s.standard_name,
    'materialId',m.id,'materialCode',m.material_code,'materialName',m.material_name,'categoryName',c.category_name,
    'specificationModel',m.specification_model,'basicUnit',m.basic_unit,'imageUrls',m.image_urls,
    'quotaQuantity',i.quota_quantity,'issuanceCycle',i.issuance_cycle,'issuanceFrequency',i.issuance_frequency,
    'status',i.status,'initialIssueDate',i.initial_issue_date,'lastIssueDate',i.last_issue_date,'nextIssueDate',i.next_issue_date)
    order by c.category_name,m.material_name)
    from public.smis_ppe_personal_standard ps
    join public.smis_ppe_personal_standard_item i on i.personal_standard_id=ps.id
    join public.smis_ppe_issuance_standard s on s.id=i.source_standard_id
    join public.smis_material m on m.id=i.material_id
    join public.smis_material_category c on c.id=m.category_id
    where ps.employee_id=p_employee_id
      and (app_private.current_read_tenant_id() is null or ps.tenant_id=app_private.current_read_tenant_id())), '[]'::jsonb);
end $$;

drop function if exists public.smis_push_ppe_requisition_items_secure(uuid[],uuid,uuid,date);

create or replace function public.smis_push_ppe_requisition_items_secure(p_items jsonb,p_warehouse_id uuid,p_issuer_employee_id uuid,p_issue_date date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_employee uuid; v_record_id uuid; v_no text; v_employee_row record; v_warehouse record; v_issuer record; v_item_ids uuid[];
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpePersonalRequisition:Push') then raise exception '当前账号没有下推发放的权限' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception '请选择待发放的领用明细' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'id','') is null or coalesce((x->>'issue_quantity')::numeric,0)<=0) then raise exception '领用明细或发放数量无效' using errcode='22023'; end if;
  select array_agg((x->>'id')::uuid) into v_item_ids from jsonb_array_elements(p_items) x;
  if cardinality(v_item_ids)<>jsonb_array_length(p_items) or cardinality(v_item_ids)<>(select count(distinct id) from unnest(v_item_ids) id) then raise exception '领用明细不能重复' using errcode='22023'; end if;
  select min(r.tenant_id),min(r.employee_id) into v_tenant,v_employee from public.smis_ppe_personal_requisition_item i join public.smis_ppe_personal_requisition r on r.id=i.requisition_id where i.id=any(v_item_ids) and i.status='pending_issue';
  if v_tenant is null or (select count(*) from public.smis_ppe_personal_requisition_item where id=any(v_item_ids))<>cardinality(v_item_ids)
    or exists(select 1 from public.smis_ppe_personal_requisition_item i join public.smis_ppe_personal_requisition r on r.id=i.requisition_id where i.id=any(v_item_ids) and (r.tenant_id<>v_tenant or r.employee_id<>v_employee or i.status<>'pending_issue')) then raise exception '只能选择同一领用人的待发放明细' using errcode='22023'; end if;
  if not app_private.is_platform_super() and v_tenant<>app_private.auth_user_tenant_id() then raise exception '所选数据不属于当前租户' using errcode='42501'; end if;
  select e.*,o.organization_name,p.position_name into v_employee_row from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=v_employee and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=p_warehouse_id and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=p_issuer_employee_id and tenant_id=v_tenant;
  if v_employee_row.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  insert into public.smis_ppe_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status)
  values(v_tenant,app_private.next_document_number('smis.ppe_issuance_record',v_tenant),v_employee_row.id,v_employee_row.employee_no,v_employee_row.employee_name,v_employee_row.position_name,v_employee_row.organization_id,v_employee_row.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce(p_issue_date,current_date),'draft') returning id into v_record_id;
  insert into public.smis_ppe_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity)
  select v_tenant,v_record_id,i.id,i.material_id,i.material_category_snapshot,i.material_name_snapshot,i.specification_model_snapshot,i.unit_snapshot,(x->>'issue_quantity')::numeric
  from jsonb_array_elements(p_items) x join public.smis_ppe_personal_requisition_item i on i.id=(x->>'id')::uuid;
  v_no:=app_private.post_ppe_issuance_record(v_record_id);
  return jsonb_build_object('id',v_record_id,'issuanceNo',v_no);
end $$;

revoke all on function public.smis_push_ppe_requisition_items_secure(jsonb,uuid,uuid,date) from public,anon;
grant execute on function public.smis_push_ppe_requisition_items_secure(jsonb,uuid,uuid,date) to authenticated;

do $$
declare v_platform uuid; v_parent uuid; v_type uuid; v_row record;
begin
  select id into v_platform from public.sys_tenant where tenant_code='platform' limit 1;
  select id into v_parent from public.sys_dict_type where tenant_id=v_platform and code='smisProtectiveEquipmentManagement' limit 1;
  for v_row in select * from (values
    ('防护用品领用状态','smisPpeRequisitionStatus',40),
    ('防护用品发放状态','smisPpeIssuanceStatus',41)
  ) t(name,code,sort) loop
    insert into public.sys_dict_type(name,code,status,create_by,update_by,remark,tenant_id,parent_id,node_type,sort)
    select v_row.name,v_row.code,'1','624944977@qq.com','624944977@qq.com','防护用品领用与发放状态',v_platform,v_parent,'dictionary',v_row.sort
    where not exists(select 1 from public.sys_dict_type where tenant_id=v_platform and code=v_row.code);
  end loop;
  select id into v_type from public.sys_dict_type where tenant_id=v_platform and code='smisPpeRequisitionStatus' limit 1;
  insert into public.sys_dictionary(type_id,code,status,create_by,update_by,remark,value,label,i18n_scope,sort,tenant_id,tag_type)
  select v_type,'smisPpeRequisitionStatus_'||x.value,'1','624944977@qq.com','624944977@qq.com','',x.value,x.label,'1',x.sort,v_platform,x.tag_type
  from (values('pending_issue','待发放',1::bigint,'warning'),('issued_pending_confirmation','待本人确认',2::bigint,'primary'),('confirmed','已确认',3::bigint,'success'),('denied','已否认',4::bigint,'danger'),('cancelled','已取消',5::bigint,'info')) x(value,label,sort,tag_type)
  where not exists(select 1 from public.sys_dictionary d where d.type_id=v_type and d.value=x.value);
  select id into v_type from public.sys_dict_type where tenant_id=v_platform and code='smisPpeIssuanceStatus' limit 1;
  insert into public.sys_dictionary(type_id,code,status,create_by,update_by,remark,value,label,i18n_scope,sort,tenant_id,tag_type)
  select v_type,'smisPpeIssuanceStatus_'||x.value,'1','624944977@qq.com','624944977@qq.com','',x.value,x.label,'1',x.sort,v_platform,x.tag_type
  from (values('draft','草稿',1::bigint,'warning'),('posted','已过账',2::bigint,'success'),('voided','已作废',3::bigint,'info')) x(value,label,sort,tag_type)
  where not exists(select 1 from public.sys_dictionary d where d.type_id=v_type and d.value=x.value);
end $$;

;
