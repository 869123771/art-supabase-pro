-- 设备台账使用租户可维护的真实排序值，列表按该值稳定分页。
alter table public.smis_equipment add column sort integer;

with ranked as (
  select id,
    row_number() over (
      partition by tenant_id
      order by create_time, equipment_name, equipment_code, id
    )::integer * 10 as sort
  from public.smis_equipment
)
update public.smis_equipment equipment
set sort = ranked.sort
from ranked
where ranked.id = equipment.id;

alter table public.smis_equipment
  alter column sort set default 10,
  alter column sort set not null,
  add constraint smis_equipment_sort_range_check check (sort between 0 and 999999);

create index idx_smis_equipment_tenant_sort
  on public.smis_equipment (tenant_id, sort, equipment_name, equipment_code, id);

comment on column public.smis_equipment.sort is '设备台账展示顺序，数值越小越靠前';

CREATE OR REPLACE FUNCTION public.smis_list_equipment_ledger_secure(p_from integer DEFAULT 0, p_to integer DEFAULT 19, p_keyword text DEFAULT NULL::text, p_category_id uuid DEFAULT NULL::uuid, p_location_id uuid DEFAULT NULL::uuid, p_equipment_kind text DEFAULT NULL::text, p_model text DEFAULT NULL::text, p_operation_status text DEFAULT NULL::text, p_supplier_id uuid DEFAULT NULL::uuid, p_importance_level text DEFAULT NULL::text, p_enable_date_from date DEFAULT NULL::date, p_enable_date_to date DEFAULT NULL::date, p_asset_status text DEFAULT NULL::text, p_use_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tenant_id uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1);
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_model text := nullif(btrim(coalesce(p_model, '')), '');
  v_records jsonb := '[]'::jsonb;
  v_category_tree jsonb := '[]'::jsonb;
  v_location_tree jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_overview jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看设备台账'; end if;
  if not app_private.has_permission('SmisEquipmentLedger:View') then
    raise exception '当前账号无权查看设备台账';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;

  with recursive category_scope as (
    select id from public.smis_equipment_category
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id()) and id = p_category_id
    union all
    select child.id from public.smis_equipment_category child
    join category_scope parent on parent.id = child.parent_id
    where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())
  ), location_scope as (
    select id from public.smis_storage_location
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id()) and id = p_location_id
    union all
    select child.id from public.smis_storage_location child
    join location_scope parent on parent.id = child.parent_id
    where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())
  )
  select count(*) into v_total
  from public.smis_equipment equipment
  where (app_private.current_read_tenant_id() is null or equipment.tenant_id = app_private.current_read_tenant_id())
    and (p_category_id is null or equipment.category_id in (select id from category_scope))
    and (p_location_id is null or equipment.location_id in (select id from location_scope))
    and (p_equipment_kind is null or equipment.equipment_kind = p_equipment_kind)
    and (v_model is null or coalesce(equipment.model, '') ilike '%' || v_model || '%')
    and (p_operation_status is null or equipment.operation_status = p_operation_status)
    and (p_supplier_id is null or equipment.supplier_id = p_supplier_id)
    and (p_importance_level is null or equipment.importance_level = p_importance_level)
    and (p_enable_date_from is null or equipment.enable_date >= p_enable_date_from)
    and (p_enable_date_to is null or equipment.enable_date <= p_enable_date_to)
    and (p_asset_status is null or equipment.asset_status = p_asset_status)
    and (p_use_status is null or equipment.use_status = p_use_status)
    and (
      v_keyword is null
      or equipment.equipment_code ilike '%' || v_keyword || '%'
      or equipment.equipment_name ilike '%' || v_keyword || '%'
      or coalesce(equipment.equipment_short_name, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.specification, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.model, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.factory_no, '') ilike '%' || v_keyword || '%'
    );

  with recursive category_scope as (
    select id from public.smis_equipment_category
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id()) and id = p_category_id
    union all
    select child.id from public.smis_equipment_category child
    join category_scope parent on parent.id = child.parent_id
    where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())
  ), location_scope as (
    select id from public.smis_storage_location
    where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id()) and id = p_location_id
    union all
    select child.id from public.smis_storage_location child
    join location_scope parent on parent.id = child.parent_id
    where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())
  )
  select coalesce(jsonb_agg(item.payload order by item.sort, item.equipment_name, item.equipment_code), '[]'::jsonb)
  into v_records
  from (
    select equipment.sort, equipment.equipment_name, equipment.equipment_code,
      jsonb_build_object(
        'id', equipment.id,
        'sort', equipment.sort,
        'categoryId', equipment.category_id,
        'locationId', equipment.location_id,
        'usingOrganizationId', equipment.using_organization_id,
        'managingOrganizationId', equipment.managing_organization_id,
        'responsibleEmployeeId', equipment.responsible_employee_id,
        'supplierId', equipment.supplier_id,
        'equipmentCode', equipment.equipment_code,
        'equipmentName', equipment.equipment_name,
        'equipmentShortName', equipment.equipment_short_name,
        'equipmentKind', equipment.equipment_kind,
        'specification', equipment.specification,
        'model', equipment.model,
        'manufacturer', equipment.manufacturer,
        'factoryNo', equipment.factory_no,
        'manufactureDate', equipment.manufacture_date,
        'installationDate', equipment.installation_date,
        'commissioningDate', equipment.commissioning_date,
        'enableDate', equipment.enable_date,
        'useStatus', equipment.use_status,
        'operationStatus', equipment.operation_status,
        'assetStatus', equipment.asset_status,
        'importanceLevel', equipment.importance_level,
        'assetOriginalValue', equipment.asset_original_value,
        'serviceLifeYears', equipment.service_life_years,
        'netValue', equipment.net_value,
        'fixedAssetNo', equipment.fixed_asset_no,
        'erpCode', equipment.erp_code,
        'electronicTagCode', equipment.electronic_tag_code,
        'qrToken', equipment.qr_token,
        'isMajorHazardSource', equipment.is_major_hazard_source,
        'isSpecialEquipment', equipment.is_special_equipment,
        'remark', equipment.remark,
        'status', equipment.status,
        'createBy', equipment.create_by,
        'createTime', equipment.create_time,
        'updateBy', equipment.update_by,
        'updateTime', equipment.update_time,
        'category', jsonb_build_object(
          'id', category.id,
          'categoryCode', category.category_code,
          'categoryName', category.category_name
        ),
        'location', case when location.id is null then null else jsonb_build_object(
          'id', location.id,
          'locationCode', location.location_code,
          'locationName', location.location_name,
          'detailLocation', location.detail_location
        ) end,
        'usingOrganization', jsonb_build_object(
          'id', using_org.id,
          'organizationCode', using_org.organization_code,
          'organizationName', using_org.organization_name
        ),
        'managingOrganization', jsonb_build_object(
          'id', managing_org.id,
          'organizationCode', managing_org.organization_code,
          'organizationName', managing_org.organization_name
        ),
        'responsible', case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'jobTitle', employee.job_title,
          'employmentStatus', employee.employment_status,
          'organizationId', employee.organization_id,
          'organizationCode', employee_org.organization_code,
          'organizationName', employee_org.organization_name
        ) end,
        'supplier', case when supplier.id is null then null else jsonb_build_object(
          'id', supplier.id,
          'supplierCode', supplier.supplier_code,
          'supplierName', supplier.supplier_name
        ) end,
        'boiler', case when boiler.equipment_id is null then null else jsonb_build_object(
          'boilerType', boiler.boiler_type,
          'registrationCode', boiler.registration_code,
          'useCertificateNo', boiler.use_certificate_no,
          'internalNo', boiler.internal_no,
          'ratedEvaporation', boiler.rated_evaporation,
          'designPressure', boiler.design_pressure,
          'workingPressure', boiler.working_pressure,
          'workingTemperature', boiler.working_temperature,
          'fuelType', boiler.fuel_type,
          'purpose', boiler.purpose,
          'maintenanceOrganization', boiler.maintenance_organization,
          'installationOrganization', boiler.installation_organization
        ) end,
        'pressureGaugeIds', coalesce((
          select jsonb_agg(relation.target_equipment_id order by relation.target_equipment_id)
          from public.smis_equipment_relation relation
          where (app_private.current_read_tenant_id() is null or relation.tenant_id = app_private.current_read_tenant_id())
            and relation.source_equipment_id = equipment.id
            and relation.relation_type = 'pressure_gauge'
        ), '[]'::jsonb),
        'safetyValveIds', coalesce((
          select jsonb_agg(relation.target_equipment_id order by relation.target_equipment_id)
          from public.smis_equipment_relation relation
          where (app_private.current_read_tenant_id() is null or relation.tenant_id = app_private.current_read_tenant_id())
            and relation.source_equipment_id = equipment.id
            and relation.relation_type = 'safety_valve'
        ), '[]'::jsonb),
        'attachmentCount', (
          select count(*) from public.smis_equipment_attachment attachment
          where (app_private.current_read_tenant_id() is null or attachment.tenant_id = app_private.current_read_tenant_id()) and attachment.equipment_id = equipment.id
        ),
        'inspectionCount', (
          select count(*) from public.smis_equipment_inspection inspection
          where (app_private.current_read_tenant_id() is null or inspection.tenant_id = app_private.current_read_tenant_id()) and inspection.equipment_id = equipment.id
        ),
        'nextInspectionDueDate', (
          select min(inspection.next_due_date)
          from public.smis_equipment_inspection inspection
          where (app_private.current_read_tenant_id() is null or inspection.tenant_id = app_private.current_read_tenant_id())
            and inspection.equipment_id = equipment.id
            and inspection.next_due_date is not null
            and inspection.status in ('planned', 'completed')
        )
      ) as payload
    from public.smis_equipment equipment
    join public.smis_equipment_category category
      on category.tenant_id = equipment.tenant_id and category.id = equipment.category_id
    left join public.smis_storage_location location
      on location.tenant_id = equipment.tenant_id and location.id = equipment.location_id
    join public.sys_organization using_org
      on using_org.tenant_id = equipment.tenant_id and using_org.id = equipment.using_organization_id
    join public.sys_organization managing_org
      on managing_org.tenant_id = equipment.tenant_id and managing_org.id = equipment.managing_organization_id
    left join public.hr_employee employee
      on employee.tenant_id = equipment.tenant_id and employee.id = equipment.responsible_employee_id
    left join public.sys_organization employee_org
      on employee_org.tenant_id = employee.tenant_id and employee_org.id = employee.organization_id
    left join public.vehicle_supplier supplier
      on supplier.tenant_id = equipment.tenant_id and supplier.id = equipment.supplier_id
    left join public.smis_equipment_boiler boiler
      on boiler.tenant_id = equipment.tenant_id and boiler.equipment_id = equipment.id
    where (app_private.current_read_tenant_id() is null or equipment.tenant_id = app_private.current_read_tenant_id())
      and (p_category_id is null or equipment.category_id in (select id from category_scope))
      and (p_location_id is null or equipment.location_id in (select id from location_scope))
      and (p_equipment_kind is null or equipment.equipment_kind = p_equipment_kind)
      and (v_model is null or coalesce(equipment.model, '') ilike '%' || v_model || '%')
      and (p_operation_status is null or equipment.operation_status = p_operation_status)
      and (p_supplier_id is null or equipment.supplier_id = p_supplier_id)
      and (p_importance_level is null or equipment.importance_level = p_importance_level)
      and (p_enable_date_from is null or equipment.enable_date >= p_enable_date_from)
      and (p_enable_date_to is null or equipment.enable_date <= p_enable_date_to)
      and (p_asset_status is null or equipment.asset_status = p_asset_status)
      and (p_use_status is null or equipment.use_status = p_use_status)
      and (
        v_keyword is null
        or equipment.equipment_code ilike '%' || v_keyword || '%'
        or equipment.equipment_name ilike '%' || v_keyword || '%'
        or coalesce(equipment.equipment_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.specification, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.model, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.factory_no, '') ilike '%' || v_keyword || '%'
      )
    order by equipment.sort, equipment.equipment_name, equipment.equipment_code
    offset v_from limit v_limit
  ) item;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', category.id,
    'parentId', category.parent_id,
    'categoryCode', category.category_code,
    'categoryName', category.category_name,
    'status', category.status,
    'childCount', (
      select count(*) from public.smis_equipment_category child
      where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id()) and child.parent_id = category.id
    )
  ) order by category.category_name), '[]'::jsonb)
  into v_category_tree
  from public.smis_equipment_category category
  where (app_private.current_read_tenant_id() is null or category.tenant_id = app_private.current_read_tenant_id());

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', location.id,
    'parentId', location.parent_id,
    'locationCode', location.location_code,
    'locationName', location.location_name,
    'status', location.status,
    'childCount', (
      select count(*) from public.smis_storage_location child
      where (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id()) and child.parent_id = location.id
    )
  ) order by location.location_name), '[]'::jsonb)
  into v_location_tree
  from public.smis_storage_location location
  where (app_private.current_read_tenant_id() is null or location.tenant_id = app_private.current_read_tenant_id());

  select jsonb_build_object(
    'total', count(*),
    'inUse', count(*) filter (where use_status = 'in_use'),
    'boilerCount', count(*) filter (where equipment_kind = 'boiler'),
    'dueSoon', (
      select count(distinct inspection.equipment_id)
      from public.smis_equipment_inspection inspection
      where (app_private.current_read_tenant_id() is null or inspection.tenant_id = app_private.current_read_tenant_id())
        and inspection.status in ('planned', 'completed')
        and inspection.next_due_date between current_date and current_date + 30
    )
  ) into v_overview
  from public.smis_equipment
  where (app_private.current_read_tenant_id() is null or tenant_id = app_private.current_read_tenant_id());

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'categoryTree', v_category_tree,
    'locationTree', v_location_tree,
    'overview', v_overview
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.smis_save_equipment_ledger_secure(p_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tenant_id uuid;
  v_category_id uuid := nullif(p_payload ->> 'category_id', '')::uuid;
  v_location_id uuid := nullif(p_payload ->> 'location_id', '')::uuid;
  v_using_organization_id uuid := nullif(p_payload ->> 'using_organization_id', '')::uuid;
  v_managing_organization_id uuid := nullif(p_payload ->> 'managing_organization_id', '')::uuid;
  v_responsible_employee_id uuid := nullif(p_payload ->> 'responsible_employee_id', '')::uuid;
  v_supplier_id uuid := nullif(p_payload ->> 'supplier_id', '')::uuid;
  v_sort integer;
  v_equipment_code text := upper(btrim(coalesce(p_payload ->> 'equipment_code', '')));
  v_equipment_name text := btrim(coalesce(p_payload ->> 'equipment_name', ''));
  v_equipment_short_name text := nullif(btrim(coalesce(p_payload ->> 'equipment_short_name', '')), '');
  v_equipment_kind text := coalesce(nullif(p_payload ->> 'equipment_kind', ''), 'general');
  v_use_status text := coalesce(nullif(p_payload ->> 'use_status', ''), 'in_use');
  v_operation_status text := coalesce(nullif(p_payload ->> 'operation_status', ''), 'normal');
  v_asset_status text := coalesce(nullif(p_payload ->> 'asset_status', ''), 'active');
  v_importance_level text := coalesce(nullif(p_payload ->> 'importance_level', ''), 'general');
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'enabled');
  v_result_id uuid;
  v_boiler jsonb := coalesce(p_payload -> 'boiler', '{}'::jsonb);
  v_pressure_gauge_ids uuid[];
  v_safety_valve_ids uuid[];
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护设备台账'; end if;
  if p_id is null and not app_private.has_permission('SmisEquipmentLedger:Add') then
    raise exception '当前账号无权新增设备';
  end if;
  if p_id is not null and not app_private.has_permission('SmisEquipmentLedger:Edit') then
    raise exception '当前账号无权编辑设备';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((select target.tenant_id from public.smis_equipment target where target.id = p_id));
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;
  v_sort := coalesce(
    nullif(p_payload ->> 'sort', '')::integer,
    (select target.sort from public.smis_equipment target where target.id = p_id and target.tenant_id = v_tenant_id),
    10
  );

  if v_equipment_name = '' then raise exception '请输入设备名称'; end if;
  if char_length(v_equipment_name) > 120 then raise exception '设备名称不能超过120个字符'; end if;
  if v_sort < 0 or v_sort > 999999 then raise exception '排序必须在0到999999之间'; end if;
  if v_category_id is null then raise exception '请选择设备分类'; end if;
  if v_using_organization_id is null then raise exception '请选择使用部门'; end if;
  if v_managing_organization_id is null then raise exception '请选择管理部门'; end if;
  if v_equipment_kind not in ('general', 'boiler', 'pressure_gauge', 'safety_valve') then
    raise exception '设备类型不合法';
  end if;
  if v_use_status not in ('in_use', 'stopped', 'scrapped', 'dismantled', 'installing') then
    raise exception '使用状态不合法';
  end if;
  if v_operation_status not in ('normal', 'maintenance', 'fault', 'idle') then
    raise exception '运行状态不合法';
  end if;
  if v_asset_status not in ('active', 'pending_disposal', 'disposed') then
    raise exception '资产状态不合法';
  end if;
  if not app_private.is_enabled_dictionary_value(
    'smisEquipmentImportanceLevel', v_importance_level
  ) and not (
    p_id is not null
    and exists (
      select 1
      from public.smis_equipment existing_equipment
      where existing_equipment.id = p_id
        and existing_equipment.tenant_id = v_tenant_id
        and btrim(existing_equipment.importance_level) = v_importance_level
    )
  ) then
    raise exception '设备重要级别无效或已停用';
  end if;
  if v_status not in ('enabled', 'disabled') then raise exception '启用状态不合法'; end if;

  if not exists (
    select 1 from public.smis_equipment_category
    where id = v_category_id and tenant_id = v_tenant_id
      and (p_id is not null or status = 'enabled')
  ) then raise exception '所选设备分类不存在、已停用或不属于当前租户'; end if;
  if v_location_id is not null and not exists (
    select 1 from public.smis_storage_location
    where id = v_location_id and tenant_id = v_tenant_id
      and (p_id is not null or status = 'enabled')
  ) then raise exception '所选安装位置不存在、已停用或不属于当前租户'; end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_using_organization_id and tenant_id = v_tenant_id
  ) then raise exception '所选使用部门不存在或不属于当前租户'; end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_managing_organization_id and tenant_id = v_tenant_id
  ) then raise exception '所选管理部门不存在或不属于当前租户'; end if;
  if v_responsible_employee_id is not null and not exists (
    select 1 from public.hr_employee
    where id = v_responsible_employee_id and tenant_id = v_tenant_id
  ) then raise exception '所选运行负责人不存在或不属于当前租户'; end if;
  if v_supplier_id is not null and not exists (
    select 1 from public.vehicle_supplier
    where id = v_supplier_id and tenant_id = v_tenant_id
  ) then raise exception '所选供应商不存在或不属于当前租户'; end if;

  if p_id is null then
    if v_equipment_code = '' then
      v_equipment_code := app_private.next_document_number('smis.equipment', v_tenant_id);
    end if;
  else
    select equipment_code into v_equipment_code
    from public.smis_equipment
    where id = p_id and tenant_id = v_tenant_id
    for update;
    if not found then raise exception '待编辑设备不存在或无权访问'; end if;
  end if;
  if char_length(v_equipment_code) > 60 then raise exception '设备编码不能超过60个字符'; end if;
  if exists (
    select 1 from public.smis_equipment
    where tenant_id = v_tenant_id
      and lower(btrim(equipment_code)) = lower(v_equipment_code)
      and (p_id is null or id <> p_id)
  ) then raise exception '设备编码已存在'; end if;

  if p_id is null then
    insert into public.smis_equipment(
      tenant_id, category_id, location_id, using_organization_id, managing_organization_id,
      responsible_employee_id, supplier_id, sort, equipment_code, equipment_name,
      equipment_short_name, equipment_kind, specification, model, manufacturer, factory_no,
      manufacture_date, installation_date, commissioning_date, enable_date,
      use_status, operation_status, asset_status, importance_level,
      asset_original_value, service_life_years, net_value, fixed_asset_no, erp_code,
      electronic_tag_code, is_major_hazard_source, is_special_equipment, remark, status
    ) values (
      v_tenant_id, v_category_id, v_location_id, v_using_organization_id,
      v_managing_organization_id, v_responsible_employee_id, v_supplier_id, v_sort,
      v_equipment_code, v_equipment_name, v_equipment_short_name, v_equipment_kind,
      nullif(btrim(p_payload ->> 'specification'), ''), nullif(btrim(p_payload ->> 'model'), ''),
      nullif(btrim(p_payload ->> 'manufacturer'), ''), nullif(btrim(p_payload ->> 'factory_no'), ''),
      nullif(p_payload ->> 'manufacture_date', '')::date,
      nullif(p_payload ->> 'installation_date', '')::date,
      nullif(p_payload ->> 'commissioning_date', '')::date,
      nullif(p_payload ->> 'enable_date', '')::date,
      v_use_status, v_operation_status, v_asset_status, v_importance_level,
      nullif(p_payload ->> 'asset_original_value', '')::numeric,
      nullif(p_payload ->> 'service_life_years', '')::numeric,
      nullif(p_payload ->> 'net_value', '')::numeric,
      nullif(btrim(p_payload ->> 'fixed_asset_no'), ''),
      nullif(btrim(p_payload ->> 'erp_code'), ''),
      nullif(btrim(p_payload ->> 'electronic_tag_code'), ''),
      coalesce((p_payload ->> 'is_major_hazard_source')::boolean, false),
      coalesce((p_payload ->> 'is_special_equipment')::boolean, false),
      nullif(btrim(p_payload ->> 'remark'), ''), v_status
    ) returning id into v_result_id;
  else
    update public.smis_equipment set
      sort = v_sort,
      category_id = v_category_id,
      location_id = v_location_id,
      using_organization_id = v_using_organization_id,
      managing_organization_id = v_managing_organization_id,
      responsible_employee_id = v_responsible_employee_id,
      supplier_id = v_supplier_id,
      equipment_name = v_equipment_name,
      equipment_short_name = v_equipment_short_name,
      equipment_kind = v_equipment_kind,
      specification = nullif(btrim(p_payload ->> 'specification'), ''),
      model = nullif(btrim(p_payload ->> 'model'), ''),
      manufacturer = nullif(btrim(p_payload ->> 'manufacturer'), ''),
      factory_no = nullif(btrim(p_payload ->> 'factory_no'), ''),
      manufacture_date = nullif(p_payload ->> 'manufacture_date', '')::date,
      installation_date = nullif(p_payload ->> 'installation_date', '')::date,
      commissioning_date = nullif(p_payload ->> 'commissioning_date', '')::date,
      enable_date = nullif(p_payload ->> 'enable_date', '')::date,
      use_status = v_use_status,
      operation_status = v_operation_status,
      asset_status = v_asset_status,
      importance_level = v_importance_level,
      asset_original_value = nullif(p_payload ->> 'asset_original_value', '')::numeric,
      service_life_years = nullif(p_payload ->> 'service_life_years', '')::numeric,
      net_value = nullif(p_payload ->> 'net_value', '')::numeric,
      fixed_asset_no = nullif(btrim(p_payload ->> 'fixed_asset_no'), ''),
      erp_code = nullif(btrim(p_payload ->> 'erp_code'), ''),
      electronic_tag_code = nullif(btrim(p_payload ->> 'electronic_tag_code'), ''),
      is_major_hazard_source = coalesce((p_payload ->> 'is_major_hazard_source')::boolean, false),
      is_special_equipment = coalesce((p_payload ->> 'is_special_equipment')::boolean, false),
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      status = v_status
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result_id;
  end if;

  if v_equipment_kind = 'boiler' then
    if coalesce(v_boiler ->> 'boiler_type', '') not in ('water', 'steam') then
      raise exception '请选择锅炉种类';
    end if;
    insert into public.smis_equipment_boiler(
      equipment_id, tenant_id, boiler_type, registration_code, use_certificate_no,
      internal_no, rated_evaporation, design_pressure, working_pressure,
      working_temperature, fuel_type, purpose, maintenance_organization,
      installation_organization
    ) values (
      v_result_id, v_tenant_id, v_boiler ->> 'boiler_type',
      nullif(btrim(v_boiler ->> 'registration_code'), ''),
      nullif(btrim(v_boiler ->> 'use_certificate_no'), ''),
      nullif(btrim(v_boiler ->> 'internal_no'), ''),
      nullif(v_boiler ->> 'rated_evaporation', '')::numeric,
      nullif(v_boiler ->> 'design_pressure', '')::numeric,
      nullif(v_boiler ->> 'working_pressure', '')::numeric,
      nullif(v_boiler ->> 'working_temperature', '')::numeric,
      nullif(btrim(v_boiler ->> 'fuel_type'), ''),
      nullif(btrim(v_boiler ->> 'purpose'), ''),
      nullif(btrim(v_boiler ->> 'maintenance_organization'), ''),
      nullif(btrim(v_boiler ->> 'installation_organization'), '')
    )
    on conflict (equipment_id) do update set
      boiler_type = excluded.boiler_type,
      registration_code = excluded.registration_code,
      use_certificate_no = excluded.use_certificate_no,
      internal_no = excluded.internal_no,
      rated_evaporation = excluded.rated_evaporation,
      design_pressure = excluded.design_pressure,
      working_pressure = excluded.working_pressure,
      working_temperature = excluded.working_temperature,
      fuel_type = excluded.fuel_type,
      purpose = excluded.purpose,
      maintenance_organization = excluded.maintenance_organization,
      installation_organization = excluded.installation_organization;
  else
    delete from public.smis_equipment_boiler
    where equipment_id = v_result_id and tenant_id = v_tenant_id;
  end if;

  select array_agg(value::uuid) into v_pressure_gauge_ids
  from jsonb_array_elements_text(coalesce(p_payload -> 'pressure_gauge_ids', '[]'::jsonb)) value;
  select array_agg(value::uuid) into v_safety_valve_ids
  from jsonb_array_elements_text(coalesce(p_payload -> 'safety_valve_ids', '[]'::jsonb)) value;

  if exists (
    select 1 from public.smis_equipment
    where id = any(coalesce(v_pressure_gauge_ids, '{}'::uuid[]))
      and (tenant_id <> v_tenant_id or equipment_kind <> 'pressure_gauge')
  ) or (
    select count(*) from public.smis_equipment
    where tenant_id = v_tenant_id and equipment_kind = 'pressure_gauge'
      and id = any(coalesce(v_pressure_gauge_ids, '{}'::uuid[]))
  ) <> cardinality(coalesce(v_pressure_gauge_ids, '{}'::uuid[])) then
    raise exception '所选压力表不存在或类型不正确';
  end if;
  if exists (
    select 1 from public.smis_equipment
    where id = any(coalesce(v_safety_valve_ids, '{}'::uuid[]))
      and (tenant_id <> v_tenant_id or equipment_kind <> 'safety_valve')
  ) or (
    select count(*) from public.smis_equipment
    where tenant_id = v_tenant_id and equipment_kind = 'safety_valve'
      and id = any(coalesce(v_safety_valve_ids, '{}'::uuid[]))
  ) <> cardinality(coalesce(v_safety_valve_ids, '{}'::uuid[])) then
    raise exception '所选安全阀不存在或类型不正确';
  end if;

  delete from public.smis_equipment_relation
  where source_equipment_id = v_result_id and tenant_id = v_tenant_id;
  insert into public.smis_equipment_relation(
    source_equipment_id, target_equipment_id, tenant_id, relation_type
  )
  select v_result_id, id, v_tenant_id, 'pressure_gauge'
  from unnest(coalesce(v_pressure_gauge_ids, '{}'::uuid[])) id;
  insert into public.smis_equipment_relation(
    source_equipment_id, target_equipment_id, tenant_id, relation_type
  )
  select v_result_id, id, v_tenant_id, 'safety_valve'
  from unnest(coalesce(v_safety_valve_ids, '{}'::uuid[])) id;

  return v_result_id;
end;
$function$;


;
