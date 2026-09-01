alter table public.smis_equipment_inspection
  add column if not exists inspection_institution_id uuid,
  add column if not exists needs_extension boolean not null default false,
  add column if not exists extension_date date,
  add column if not exists reminder_months integer not null default 1;

alter table public.smis_equipment_inspection
  add constraint smis_equipment_inspection_institution_fkey
    foreign key (inspection_institution_id, tenant_id)
    references public.vehicle_supplier(id, tenant_id) on delete restrict,
  add constraint smis_equipment_inspection_conclusion_check
    check (conclusion is null or conclusion in ('operable', 'inoperable', 'operable_after_rectification')),
  add constraint smis_equipment_inspection_extension_check
    check ((needs_extension and extension_date is not null) or (not needs_extension and extension_date is null)),
  add constraint smis_equipment_inspection_reminder_months_check
    check (reminder_months in (1, 2, 3));

comment on column public.smis_equipment_inspection.inspection_no is '检验报告编号；由租户编号规则 smis.equipment_inspection 自动生成';
comment on column public.smis_equipment_inspection.reminder_months is '提前提醒月数；权威配置值，reminder_days 仅保留用于兼容既有提醒计算';

create unique index if not exists smis_equipment_inspection_no_unique
  on public.smis_equipment_inspection(tenant_id, lower(inspection_no))
  where inspection_no is not null;
create index if not exists smis_equipment_inspection_institution_idx
  on public.smis_equipment_inspection(inspection_institution_id, tenant_id)
  where inspection_institution_id is not null;
create index if not exists smis_equipment_using_org_category_special_idx
  on public.smis_equipment(tenant_id, using_organization_id, category_id)
  where is_special_equipment or is_major_hazard_source or equipment_kind = 'boiler';

create table public.smis_equipment_inspection_image (
  inspection_id uuid not null,
  attachment_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  primary key (inspection_id, attachment_id),
  constraint smis_equipment_inspection_image_inspection_fkey
    foreign key (inspection_id, tenant_id)
    references public.smis_equipment_inspection(id, tenant_id) on delete cascade,
  constraint smis_equipment_inspection_image_attachment_fkey
    foreign key (attachment_id, tenant_id)
    references public.sys_attachment(id, tenant_id) on delete restrict,
  constraint smis_equipment_inspection_image_sort_check check (sort between 0 and 1000)
);

create index smis_equipment_inspection_image_attachment_idx
  on public.smis_equipment_inspection_image(attachment_id, tenant_id);
create trigger smis_equipment_inspection_image_create_audit
before insert on public.smis_equipment_inspection_image
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_inspection_image_update_audit
before update on public.smis_equipment_inspection_image
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_equipment_inspection_image enable row level security;

drop policy if exists smis_equipment_inspection_select on public.smis_equipment_inspection;
drop policy if exists smis_equipment_inspection_insert on public.smis_equipment_inspection;
drop policy if exists smis_equipment_inspection_update on public.smis_equipment_inspection;
drop policy if exists smis_equipment_inspection_delete on public.smis_equipment_inspection;

create policy smis_equipment_inspection_select on public.smis_equipment_inspection
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:View'))
    or (select app_private.has_permission('SmisEquipmentLedger:View'))
  )) or (select app_private.is_platform_super())
);
create policy smis_equipment_inspection_insert on public.smis_equipment_inspection
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Add'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);
create policy smis_equipment_inspection_update on public.smis_equipment_inspection
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
) with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);
create policy smis_equipment_inspection_delete on public.smis_equipment_inspection
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Delete'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);

create policy smis_equipment_inspection_image_select on public.smis_equipment_inspection_image
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:View'))
    or (select app_private.has_permission('SmisEquipmentLedger:View'))
  )) or (select app_private.is_platform_super())
);
create policy smis_equipment_inspection_image_insert on public.smis_equipment_inspection_image
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Add'))
    or (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);
create policy smis_equipment_inspection_image_update on public.smis_equipment_inspection_image
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
) with check (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);
create policy smis_equipment_inspection_image_delete on public.smis_equipment_inspection_image
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id()) and (
    (select app_private.has_permission('SmisInspectionDeclaration:Edit'))
    or (select app_private.has_permission('SmisInspectionDeclaration:Delete'))
    or (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
  )
);

grant select, insert, update, delete on table public.smis_equipment_inspection_image to authenticated, service_role;

create or replace function public.smis_list_equipment_inspections_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_equipment_id uuid default null,
  p_organization_id uuid default null,
  p_inspection_category_id uuid default null,
  p_status text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_keyword text := nullif(btrim(p_keyword), '');
  v_total bigint;
  v_records jsonb;
  v_overview jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看检验申报'; end if;
  if not (
    app_private.has_permission('SmisInspectionDeclaration:View')
    or app_private.has_permission('SmisEquipmentLedger:View')
  ) then raise exception '当前账号无权查看检验申报'; end if;
  v_tenant_id := app_private.current_user_tenant_id();

  select count(*) into v_total
  from public.smis_equipment_inspection inspection
  join public.smis_equipment equipment on equipment.id = inspection.equipment_id and equipment.tenant_id = inspection.tenant_id
  where inspection.tenant_id = v_tenant_id
    and (p_equipment_id is null or inspection.equipment_id = p_equipment_id)
    and (p_organization_id is null or equipment.using_organization_id = p_organization_id)
    and (p_inspection_category_id is null or inspection.inspection_category_id = p_inspection_category_id)
    and (p_status is null or inspection.status = p_status)
    and (v_keyword is null or inspection.inspection_no ilike '%' || v_keyword || '%'
      or equipment.equipment_code ilike '%' || v_keyword || '%'
      or equipment.equipment_name ilike '%' || v_keyword || '%');

  select coalesce(jsonb_agg(item.payload order by item.inspection_date desc, item.create_time desc), '[]'::jsonb)
  into v_records from (
    select inspection.inspection_date, inspection.create_time, jsonb_build_object(
      'id', inspection.id,
      'equipmentId', inspection.equipment_id,
      'inspectionCategoryId', inspection.inspection_category_id,
      'inspectionInstitutionId', inspection.inspection_institution_id,
      'inspectionNo', inspection.inspection_no,
      'inspectionDate', inspection.inspection_date,
      'conclusion', inspection.conclusion,
      'nextDueDate', inspection.next_due_date,
      'needsExtension', inspection.needs_extension,
      'extensionDate', inspection.extension_date,
      'reminderMonths', inspection.reminder_months,
      'status', inspection.status,
      'remark', inspection.remark,
      'createBy', inspection.create_by,
      'createTime', inspection.create_time,
      'updateBy', inspection.update_by,
      'updateTime', inspection.update_time,
      'equipment', jsonb_build_object(
        'id', equipment.id, 'equipmentCode', equipment.equipment_code,
        'equipmentName', equipment.equipment_name, 'equipmentKind', equipment.equipment_kind,
        'model', equipment.model,
        'categoryName', category.category_name,
        'organizationId', using_org.id, 'organizationName', using_org.organization_name
      ),
      'inspectionCategory', jsonb_build_object(
        'id', inspection_category.id, 'categoryCode', inspection_category.category_code,
        'categoryName', inspection_category.category_name
      ),
      'inspectionInstitution', case when institution.id is null then null else jsonb_build_object(
        'id', institution.id, 'supplierCode', institution.supplier_code, 'supplierName', institution.supplier_name
      ) end,
      'images', coalesce((
        select jsonb_agg(jsonb_build_object(
          'attachmentId', image.attachment_id,
          'sort', image.sort,
          'originName', attachment.origin_name,
          'url', attachment.url,
          'mimeType', attachment.mime_type,
          'suffix', attachment.suffix,
          'sizeInfo', attachment.size_info
        ) order by image.sort, image.create_time)
        from public.smis_equipment_inspection_image image
        join public.sys_attachment attachment on attachment.id = image.attachment_id and attachment.tenant_id = image.tenant_id
        where image.inspection_id = inspection.id and image.tenant_id = inspection.tenant_id
      ), '[]'::jsonb)
    ) payload
    from public.smis_equipment_inspection inspection
    join public.smis_equipment equipment on equipment.id = inspection.equipment_id and equipment.tenant_id = inspection.tenant_id
    join public.smis_equipment_category category on category.id = equipment.category_id and category.tenant_id = equipment.tenant_id
    join public.sys_organization using_org on using_org.id = equipment.using_organization_id and using_org.tenant_id = equipment.tenant_id
    join public.smis_inspection_category inspection_category on inspection_category.id = inspection.inspection_category_id and inspection_category.tenant_id = inspection.tenant_id
    left join public.vehicle_supplier institution on institution.id = inspection.inspection_institution_id and institution.tenant_id = inspection.tenant_id
    where inspection.tenant_id = v_tenant_id
      and (p_equipment_id is null or inspection.equipment_id = p_equipment_id)
      and (p_organization_id is null or equipment.using_organization_id = p_organization_id)
      and (p_inspection_category_id is null or inspection.inspection_category_id = p_inspection_category_id)
      and (p_status is null or inspection.status = p_status)
      and (v_keyword is null or inspection.inspection_no ilike '%' || v_keyword || '%'
        or equipment.equipment_code ilike '%' || v_keyword || '%'
        or equipment.equipment_name ilike '%' || v_keyword || '%')
    order by inspection.inspection_date desc, inspection.create_time desc
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  ) item;

  select jsonb_build_object(
    'total', count(*),
    'completed', count(*) filter (where status = 'completed'),
    'dueSoon', count(*) filter (where next_due_date between current_date and current_date + 90 and status in ('planned', 'completed')),
    'imageCount', (select count(*) from public.smis_equipment_inspection_image where tenant_id = v_tenant_id)
  ) into v_overview from public.smis_equipment_inspection where tenant_id = v_tenant_id;

  return jsonb_build_object('records', v_records, 'total', v_total, 'overview', v_overview);
end;
$$;

create or replace function public.smis_save_equipment_inspection_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_equipment_id uuid := nullif(p_payload ->> 'equipment_id', '')::uuid;
  v_category_id uuid := nullif(p_payload ->> 'inspection_category_id', '')::uuid;
  v_institution_id uuid := nullif(p_payload ->> 'inspection_institution_id', '')::uuid;
  v_inspection_no text := upper(btrim(coalesce(p_payload ->> 'inspection_no', '')));
  v_inspection_date date := nullif(p_payload ->> 'inspection_date', '')::date;
  v_conclusion text := nullif(p_payload ->> 'conclusion', '');
  v_next_due_date date := nullif(p_payload ->> 'next_due_date', '')::date;
  v_needs_extension boolean := coalesce((p_payload ->> 'needs_extension')::boolean, false);
  v_extension_date date := nullif(p_payload ->> 'extension_date', '')::date;
  v_reminder_months integer := coalesce(nullif(p_payload ->> 'reminder_months', '')::integer, 1);
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'completed');
  v_image_ids uuid[];
  v_result uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护检验申报'; end if;
  if p_id is null and not app_private.has_permission('SmisInspectionDeclaration:Add') then raise exception '当前账号无权新增检验申报'; end if;
  if p_id is not null and not app_private.has_permission('SmisInspectionDeclaration:Edit') then raise exception '当前账号无权编辑检验申报'; end if;
  v_tenant_id := app_private.current_user_tenant_id();

  if v_equipment_id is null or not exists (select 1 from public.smis_equipment where id = v_equipment_id and tenant_id = v_tenant_id) then raise exception '请选择当前租户的有效设备'; end if;
  if v_category_id is null or not exists (select 1 from public.smis_inspection_category where id = v_category_id and tenant_id = v_tenant_id and status = 'enabled') then raise exception '请选择当前租户已启用的检验类别'; end if;
  if v_institution_id is null or not exists (select 1 from public.vehicle_supplier where id = v_institution_id and tenant_id = v_tenant_id and supplier_category = 'inspection_agency') then raise exception '请选择当前租户有效的检验机构'; end if;
  if v_inspection_date is null then raise exception '请选择检验日期'; end if;
  if v_conclusion not in ('operable', 'inoperable', 'operable_after_rectification') then raise exception '请选择有效检验结论'; end if;
  if v_status not in ('planned', 'completed', 'overdue', 'cancelled') then raise exception '请选择有效检验状态'; end if;
  if v_reminder_months not in (1, 2, 3) then raise exception '提前提醒时间仅支持 1、2、3 个月'; end if;
  if v_next_due_date is not null and v_next_due_date < v_inspection_date then raise exception '下次检验日期不能早于检验日期'; end if;
  if v_needs_extension and v_extension_date is null then raise exception '需要延期时请选择延期日期'; end if;
  if not v_needs_extension then v_extension_date := null; end if;
  if v_extension_date is not null and v_next_due_date is not null and v_extension_date < v_next_due_date then raise exception '延期日期不能早于原下次检验日期'; end if;

  select coalesce(array_agg(value::uuid order by ordinal), '{}'::uuid[])
  into v_image_ids
  from jsonb_array_elements_text(coalesce(p_payload -> 'image_attachment_ids', '[]'::jsonb)) with ordinality as image(value, ordinal);
  if cardinality(v_image_ids) > 9 then raise exception '检验图片最多上传 9 张'; end if;
  if exists (
    select 1 from unnest(v_image_ids) image_id
    where not exists (select 1 from public.sys_attachment where id = image_id and tenant_id = v_tenant_id)
  ) then raise exception '检验图片不存在或不属于当前租户'; end if;

  if p_id is null then
    if v_inspection_no = '' then v_inspection_no := app_private.next_document_number('smis.equipment_inspection', v_tenant_id); end if;
    insert into public.smis_equipment_inspection(
      tenant_id, equipment_id, inspection_category_id, inspection_institution_id,
      inspection_no, inspection_date, conclusion, next_due_date,
      needs_extension, extension_date, reminder_months, reminder_days, status, remark
    ) values (
      v_tenant_id, v_equipment_id, v_category_id, v_institution_id,
      v_inspection_no, v_inspection_date, v_conclusion, v_next_due_date,
      v_needs_extension, v_extension_date, v_reminder_months, v_reminder_months * 30,
      v_status, nullif(btrim(p_payload ->> 'remark'), '')
    ) returning id into v_result;
  else
    select inspection_no into v_inspection_no from public.smis_equipment_inspection
    where id = p_id and tenant_id = v_tenant_id for update;
    if not found then raise exception '待编辑检验申报不存在或无权访问'; end if;
    update public.smis_equipment_inspection set
      equipment_id = v_equipment_id,
      inspection_category_id = v_category_id,
      inspection_institution_id = v_institution_id,
      inspection_date = v_inspection_date,
      conclusion = v_conclusion,
      next_due_date = v_next_due_date,
      needs_extension = v_needs_extension,
      extension_date = v_extension_date,
      reminder_months = v_reminder_months,
      reminder_days = v_reminder_months * 30,
      status = v_status,
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = p_id and tenant_id = v_tenant_id returning id into v_result;
  end if;

  delete from public.smis_equipment_inspection_image where inspection_id = v_result and tenant_id = v_tenant_id;
  insert into public.smis_equipment_inspection_image(inspection_id, attachment_id, tenant_id, sort)
  select v_result, image_id, v_tenant_id, ordinal::integer
  from unnest(v_image_ids) with ordinality as image(image_id, ordinal);
  return v_result;
exception when unique_violation then
  raise exception '检验报告编号已存在，请检查租户编号规则';
end;
$$;

create or replace function public.smis_delete_equipment_inspections_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if not app_private.has_permission('SmisInspectionDeclaration:Delete') then raise exception '当前账号无权删除检验申报'; end if;
  delete from public.smis_equipment_inspection
  where tenant_id = app_private.current_user_tenant_id() and id = any(coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.smis_get_special_equipment_analysis_secure(p_organization_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_rows jsonb;
  v_categories jsonb;
  v_organizations jsonb;
  v_overview jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看特种设备统计'; end if;
  if not (
    app_private.has_permission('SmisSpecialEquipmentAnalysis:View')
    or app_private.has_permission('SmisSpecialEquipmentLedger:View')
  ) then raise exception '当前账号无权查看特种设备统计'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if p_organization_id is not null and not exists (
    select 1 from public.sys_organization where id = p_organization_id and tenant_id = v_tenant_id
  ) then raise exception '所选部门不存在或不属于当前租户'; end if;

  with recursive organization_scope as (
    select id from public.sys_organization where tenant_id = v_tenant_id and (p_organization_id is null or id = p_organization_id)
    union all
    select child.id from public.sys_organization child join organization_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_tenant_id and p_organization_id is not null
  ), special_equipment as (
    select equipment.id, equipment.using_organization_id, equipment.category_id,
      equipment.equipment_kind, equipment.is_major_hazard_source
    from public.smis_equipment equipment
    where equipment.tenant_id = v_tenant_id
      and (equipment.is_special_equipment or equipment.is_major_hazard_source or equipment.equipment_kind = 'boiler')
      and (p_organization_id is null or equipment.using_organization_id in (select id from organization_scope))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId', grouped.using_organization_id,
    'organizationName', organization.organization_name,
    'categoryId', grouped.category_id,
    'categoryName', category.category_name,
    'count', grouped.count
  ) order by organization.organization_name, category.category_name), '[]'::jsonb)
  into v_rows
  from (select using_organization_id, category_id, count(*) count from special_equipment group by using_organization_id, category_id) grouped
  join public.sys_organization organization on organization.id = grouped.using_organization_id and organization.tenant_id = v_tenant_id
  join public.smis_equipment_category category on category.id = grouped.category_id and category.tenant_id = v_tenant_id;

  with special_equipment as (
    select equipment.category_id from public.smis_equipment equipment
    where equipment.tenant_id = v_tenant_id
      and (equipment.is_special_equipment or equipment.is_major_hazard_source or equipment.equipment_kind = 'boiler')
      and (p_organization_id is null or equipment.using_organization_id in (
        with recursive scope as (
          select id from public.sys_organization where id = p_organization_id and tenant_id = v_tenant_id
          union all select child.id from public.sys_organization child join scope parent on child.parent_id = parent.id where child.tenant_id = v_tenant_id
        ) select id from scope
      ))
  )
  select coalesce(jsonb_agg(jsonb_build_object('categoryId', category.id, 'categoryName', category.category_name, 'count', grouped.count)
    order by grouped.count desc, category.category_name), '[]'::jsonb)
  into v_categories
  from (select category_id, count(*) count from special_equipment group by category_id) grouped
  join public.smis_equipment_category category on category.id = grouped.category_id and category.tenant_id = v_tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', organization.id, 'parentId', organization.parent_id,
    'organizationCode', organization.organization_code, 'organizationName', organization.organization_name,
    'organizationType', organization.organization_type, 'sort', organization.sort
  ) order by organization.sort, organization.organization_name), '[]'::jsonb)
  into v_organizations from public.sys_organization organization where organization.tenant_id = v_tenant_id;

  with recursive organization_scope as (
    select id from public.sys_organization where tenant_id = v_tenant_id and (p_organization_id is null or id = p_organization_id)
    union all select child.id from public.sys_organization child join organization_scope parent on child.parent_id = parent.id
      where child.tenant_id = v_tenant_id and p_organization_id is not null
  ), special_equipment as (
    select equipment.* from public.smis_equipment equipment
    where equipment.tenant_id = v_tenant_id
      and (equipment.is_special_equipment or equipment.is_major_hazard_source or equipment.equipment_kind = 'boiler')
      and (p_organization_id is null or equipment.using_organization_id in (select id from organization_scope))
  )
  select jsonb_build_object(
    'total', count(*),
    'organizationCount', count(distinct using_organization_id),
    'categoryCount', count(distinct category_id),
    'boilerCount', count(*) filter (where equipment_kind = 'boiler'),
    'majorHazardCount', count(*) filter (where is_major_hazard_source)
  ) into v_overview from special_equipment;

  return jsonb_build_object('rows', v_rows, 'categories', v_categories, 'organizations', v_organizations, 'overview', v_overview);
end;
$$;

revoke all on function public.smis_list_equipment_inspections_secure(integer, integer, text, uuid, uuid, uuid, text) from public, anon;
revoke all on function public.smis_save_equipment_inspection_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_equipment_inspections_secure(uuid[]) from public, anon;
revoke all on function public.smis_get_special_equipment_analysis_secure(uuid) from public, anon;
grant execute on function public.smis_list_equipment_inspections_secure(integer, integer, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function public.smis_save_equipment_inspection_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_equipment_inspections_secure(uuid[]) to authenticated, service_role;
grant execute on function public.smis_get_special_equipment_analysis_secure(uuid) to authenticated, service_role;

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark, create_by, update_by, tenant_id
)
select 'smis.equipment_inspection', '检验报告编号', '检验报告编号', 'business_document',
  'a1530000-0000-4000-8000-000000000017'::uuid,
  'smis_equipment_inspection', 'inspection_no', 'JY{YYYY}-{SEQ:5}', 'year', false, true,
  '设备检验报告年度五位流水号，可在编号规则中心按租户配置', 'number-engine', 'number-engine', platform_tenant.id
from platform_tenant on conflict (rule_key) do update set
  rule_name = excluded.rule_name, field_label = excluded.field_label, category = excluded.category,
  menu_id = excluded.menu_id, target_table = excluded.target_table, target_column = excluded.target_column,
  default_template = excluded.default_template, default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required, enabled = excluded.enabled, remark = excluded.remark,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_document_number_rule(
  tenant_id, rule_key, rule_name, category, target_table, target_column, auto_enabled,
  template, reset_cycle, sequence_start, timezone, manual_required, builtin, enabled, remark, create_by, update_by
)
select id, 'smis.equipment_inspection', '检验报告编号', 'business_document',
  'smis_equipment_inspection', 'inspection_no', true, 'JY{YYYY}-{SEQ:5}', 'year', 1,
  'Asia/Shanghai', false, true, true, '设备检验报告年度五位流水规则', 'number-engine', 'number-engine'
from public.sys_tenant on conflict (tenant_id, rule_key) do nothing;

create or replace function app_private.trg_seed_smis_equipment_inspection_number_rule()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.sys_document_number_rule(
    tenant_id, rule_key, rule_name, category, target_table, target_column, auto_enabled,
    template, reset_cycle, sequence_start, timezone, manual_required, builtin, enabled, remark, create_by, update_by
  ) values (
    new.id, 'smis.equipment_inspection', '检验报告编号', 'business_document',
    'smis_equipment_inspection', 'inspection_no', true, 'JY{YYYY}-{SEQ:5}', 'year', 1,
    'Asia/Shanghai', false, true, true, '设备检验报告年度五位流水规则', 'number-engine', 'number-engine'
  ) on conflict (tenant_id, rule_key) do nothing;
  return new;
end;
$$;
create trigger trg_seed_smis_equipment_inspection_number_rule
after insert on public.sys_tenant for each row
execute function app_private.trg_seed_smis_equipment_inspection_number_rule();

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
types(name, code, remark, sort) as (values
  ('设备检验结论', 'smisEquipmentInspectionConclusion', '设备检验结果', 21),
  ('设备检验提前提醒', 'smisEquipmentInspectionReminderMonths', '检验到期前提醒月数', 22)
)
insert into public.sys_dict_type(id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com', types.remark,
  platform_tenant.id, (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1), 'dictionary', types.sort
from types cross join platform_tenant on conflict (code) do update set
  name = excluded.name, status = excluded.status, remark = excluded.remark,
  parent_id = excluded.parent_id, sort = excluded.sort, update_time = now();

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
items(type_code, value, label, sort, tag_type, remark) as (values
  ('smisEquipmentInspectionConclusion', 'operable', '可运行', 1, 'success', null),
  ('smisEquipmentInspectionConclusion', 'operable_after_rectification', '整改后运行', 2, 'warning', null),
  ('smisEquipmentInspectionConclusion', 'inoperable', '不可运行', 3, 'danger', null),
  ('smisEquipmentInspectionReminderMonths', '1', '提前 1 个月', 1, 'primary', null),
  ('smisEquipmentInspectionReminderMonths', '2', '提前 2 个月', 2, 'primary', null),
  ('smisEquipmentInspectionReminderMonths', '3', '提前 3 个月', 3, 'primary', null)
)
insert into public.sys_dictionary(id, type_id, code, status, create_by, update_by, remark, value, label, tenant_id, tag_type, sort)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value, '1',
  '624944977@qq.com', '624944977@qq.com', items.remark, items.value, items.label,
  platform_tenant.id, items.tag_type, items.sort
from items join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant where not exists (
  select 1 from public.sys_dictionary existing where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by)
select seed.id, seed.parent_id, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8170-000000000001'::uuid, 'a1530000-0000-4000-8000-000000000017'::uuid, 'SmisInspectionDeclaration:View', '查看检验申报', 1),
  ('a1530000-0000-4000-8170-000000000002'::uuid, 'a1530000-0000-4000-8000-000000000017'::uuid, 'SmisInspectionDeclaration:Add', '新增检验申报', 2),
  ('a1530000-0000-4000-8170-000000000003'::uuid, 'a1530000-0000-4000-8000-000000000017'::uuid, 'SmisInspectionDeclaration:Edit', '编辑检验申报', 3),
  ('a1530000-0000-4000-8170-000000000004'::uuid, 'a1530000-0000-4000-8000-000000000017'::uuid, 'SmisInspectionDeclaration:Delete', '删除检验申报', 4),
  ('a1530000-0000-4000-8180-000000000001'::uuid, 'a1530000-0000-4000-8000-000000000018'::uuid, 'SmisSpecialEquipmentAnalysis:View', '查看特种设备统计', 1),
  ('a1530000-0000-4000-8190-000000000001'::uuid, 'a1530000-0000-4000-8000-000000000019'::uuid, 'SmisSpecialEquipmentLedger:View', '查看特种设备台账', 1)
) seed(id, parent_id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type, app_code = excluded.app_code, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant join public.sys_role role on role.id = page_grant.role_id
join (values
  ('a1530000-0000-4000-8000-000000000017'::uuid, 'a1530000-0000-4000-8170-000000000001'::uuid),
  ('a1530000-0000-4000-8000-000000000017'::uuid, 'a1530000-0000-4000-8170-000000000002'::uuid),
  ('a1530000-0000-4000-8000-000000000017'::uuid, 'a1530000-0000-4000-8170-000000000003'::uuid),
  ('a1530000-0000-4000-8000-000000000017'::uuid, 'a1530000-0000-4000-8170-000000000004'::uuid),
  ('a1530000-0000-4000-8000-000000000018'::uuid, 'a1530000-0000-4000-8180-000000000001'::uuid),
  ('a1530000-0000-4000-8000-000000000019'::uuid, 'a1530000-0000-4000-8190-000000000001'::uuid)
) button(page_id, id) on button.page_id = page_grant.menu_id
on conflict (role_id, menu_id) do nothing;

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, 'a1530000-0000-4000-8160-000000000001'::uuid, role.tenant_id,
  '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant join public.sys_role role on role.id = page_grant.role_id
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000019'::uuid
on conflict (role_id, menu_id) do nothing;

;
