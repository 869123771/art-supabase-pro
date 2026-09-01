-- 避免单个 jsonb_build_object 超过 PostgreSQL 100 参数上限。
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
      jsonb_build_object('sort', equipment.sort) || jsonb_build_object(
        'id', equipment.id,
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


;
