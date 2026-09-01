-- Expand equipment archives with category-driven profile templates and a route-based detail page.

alter table public.smis_equipment_category
  add column if not exists equipment_profile_type text not null default 'general';

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'smis_equipment_category_profile_type_format'
      and conrelid = 'public.smis_equipment_category'::regclass
  ) then
    alter table public.smis_equipment_category
      add constraint smis_equipment_category_profile_type_format
      check (equipment_profile_type ~ '^[a-z][a-z0-9_]{0,59}$');
  end if;
end;
$migration$;

update public.smis_equipment_category
set equipment_profile_type = case
  when category_name like '%压力容器%' then 'pressure_vessel'
  when category_name like '%压力管道%' then 'pressure_pipeline'
  when category_name like '%起重机械%' then 'lifting_machinery'
  when category_name like '%厂内车辆%' then 'industrial_vehicle'
  when category_name like '%安全阀%' then 'safety_valve'
  when category_name like '%压力表%' then 'pressure_gauge'
  when category_name like '%气瓶%' then 'gas_cylinder'
  when category_name like '%锅炉%' then 'boiler'
  when category_name like '%电梯%' then 'elevator'
  else equipment_profile_type
end
where equipment_profile_type = 'general';

alter table public.smis_equipment
  add column if not exists registration_code text,
  add column if not exists internal_no text,
  add column if not exists use_certificate_no text,
  add column if not exists detail_location text,
  add column if not exists maintenance_organization text,
  add column if not exists installation_organization text,
  add column if not exists design_organization text,
  add column if not exists maintenance_qualification_url text,
  add column if not exists use_registration_certificate_url text,
  add column if not exists nameplate_url text,
  add column if not exists photo_url text,
  add column if not exists special_parameters jsonb not null default '{}'::jsonb;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'smis_equipment_special_parameters_object'
      and conrelid = 'public.smis_equipment'::regclass
  ) then
    alter table public.smis_equipment
      add constraint smis_equipment_special_parameters_object
      check (jsonb_typeof(special_parameters) = 'object');
  end if;
end;
$migration$;

update public.smis_equipment equipment
set registration_code = coalesce(equipment.registration_code, boiler.registration_code),
    internal_no = coalesce(equipment.internal_no, boiler.internal_no),
    use_certificate_no = coalesce(equipment.use_certificate_no, boiler.use_certificate_no),
    maintenance_organization = coalesce(
      equipment.maintenance_organization,
      boiler.maintenance_organization
    ),
    installation_organization = coalesce(
      equipment.installation_organization,
      boiler.installation_organization
    ),
    special_parameters = equipment.special_parameters || jsonb_strip_nulls(jsonb_build_object(
      'boilerType', boiler.boiler_type,
      'evaporationCapacity', boiler.rated_evaporation,
      'designPressure', boiler.design_pressure,
      'workingPressure', boiler.working_pressure,
      'workingTemperature', boiler.working_temperature,
      'combustionMethod', boiler.fuel_type,
      'purpose', boiler.purpose
    ))
from public.smis_equipment_boiler boiler
where boiler.equipment_id = equipment.id
  and boiler.tenant_id = equipment.tenant_id;

create or replace function public.smis_list_equipment_category_profiles_secure()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看设备分类档案模板';
  end if;
  if not (
    app_private.has_permission('SmisEquipmentCategory:View')
    or app_private.has_permission('SmisEquipmentLedger:View')
  ) then
    raise exception '当前账号无权查看设备分类档案模板';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', category.id,
      'tenantId', category.tenant_id,
      'profileType', category.equipment_profile_type
    ) order by category.sort, category.category_name, category.category_code)
    from public.smis_equipment_category category
    where app_private.current_read_tenant_id() is null
      or category.tenant_id = app_private.current_read_tenant_id()
  ), '[]'::jsonb);
end;
$function$;

create or replace function public.smis_save_equipment_category_profile_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result_id uuid;
  v_profile_type text := coalesce(nullif(p_payload ->> 'profile_type', ''), 'general');
  v_tenant_id uuid;
begin
  if v_profile_type !~ '^[a-z][a-z0-9_]{0,59}$' then
    raise exception '设备档案模板编码不合法';
  end if;

  v_result_id := public.smis_save_equipment_category_secure(p_id, p_payload);
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select category.tenant_id
    from public.smis_equipment_category category
    where category.id = v_result_id
  ));

  update public.smis_equipment_category
  set equipment_profile_type = v_profile_type
  where id = v_result_id
    and tenant_id = v_tenant_id;

  return v_result_id;
end;
$function$;

create or replace function public.smis_save_equipment_archive_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result_id uuid;
  v_tenant_id uuid;
  v_category_id uuid := nullif(p_payload ->> 'category_id', '')::uuid;
  v_profile_type text;
  v_legacy_kind text;
  v_base_payload jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护设备档案';
  end if;

  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select equipment.tenant_id
    from public.smis_equipment equipment
    where equipment.id = p_id
  ));
  if v_tenant_id is null then
    raise exception '当前账号未绑定有效租户';
  end if;

  select category.equipment_profile_type
  into v_profile_type
  from public.smis_equipment_category category
  where category.id = v_category_id
    and category.tenant_id = v_tenant_id;

  if v_profile_type is null then
    raise exception '所选设备分类不存在或不属于当前租户';
  end if;

  v_legacy_kind := case v_profile_type
    when 'boiler' then 'boiler'
    when 'pressure_gauge' then 'pressure_gauge'
    when 'safety_valve' then 'safety_valve'
    else 'general'
  end;
  v_base_payload := p_payload || jsonb_build_object('equipment_kind', v_legacy_kind);
  v_result_id := public.smis_save_equipment_ledger_secure(p_id, v_base_payload);

  update public.smis_equipment
  set registration_code = nullif(btrim(p_payload ->> 'registration_code'), ''),
      internal_no = nullif(btrim(p_payload ->> 'internal_no'), ''),
      use_certificate_no = nullif(btrim(p_payload ->> 'use_certificate_no'), ''),
      detail_location = nullif(btrim(p_payload ->> 'detail_location'), ''),
      maintenance_organization = nullif(btrim(p_payload ->> 'maintenance_organization'), ''),
      installation_organization = nullif(btrim(p_payload ->> 'installation_organization'), ''),
      design_organization = nullif(btrim(p_payload ->> 'design_organization'), ''),
      maintenance_qualification_url = nullif(btrim(p_payload ->> 'maintenance_qualification_url'), ''),
      use_registration_certificate_url = nullif(
        btrim(p_payload ->> 'use_registration_certificate_url'),
        ''
      ),
      nameplate_url = nullif(btrim(p_payload ->> 'nameplate_url'), ''),
      photo_url = nullif(btrim(p_payload ->> 'photo_url'), ''),
      special_parameters = coalesce(p_payload -> 'special_parameters', '{}'::jsonb)
  where id = v_result_id
    and tenant_id = v_tenant_id;

  return v_result_id;
end;
$function$;

create or replace function public.smis_get_equipment_archive_secure(p_equipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看设备档案';
  end if;
  if not app_private.has_permission('SmisEquipmentLedger:View') then
    raise exception '当前账号无权查看设备档案';
  end if;

  select jsonb_build_object(
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
    'profileType', category.equipment_profile_type,
    'specification', equipment.specification,
    'model', equipment.model,
    'manufacturer', equipment.manufacturer,
    'factoryNo', equipment.factory_no,
    'manufactureDate', equipment.manufacture_date,
    'installationDate', equipment.installation_date,
    'commissioningDate', equipment.commissioning_date,
    'enableDate', equipment.enable_date,
    'registrationCode', equipment.registration_code,
    'internalNo', equipment.internal_no,
    'useCertificateNo', equipment.use_certificate_no,
    'detailLocation', equipment.detail_location,
    'maintenanceOrganization', equipment.maintenance_organization,
    'installationOrganization', equipment.installation_organization,
    'designOrganization', equipment.design_organization,
    'maintenanceQualificationUrl', equipment.maintenance_qualification_url,
    'useRegistrationCertificateUrl', equipment.use_registration_certificate_url,
    'nameplateUrl', equipment.nameplate_url,
    'photoUrl', equipment.photo_url,
    'specialParameters', equipment.special_parameters,
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
    'category', jsonb_build_object(
      'id', category.id,
      'categoryCode', category.category_code,
      'categoryName', category.category_name,
      'profileType', category.equipment_profile_type
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
      'organizationId', employee.organization_id
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
      where relation.tenant_id = equipment.tenant_id
        and relation.source_equipment_id = equipment.id
        and relation.relation_type = 'pressure_gauge'
    ), '[]'::jsonb),
    'safetyValveIds', coalesce((
      select jsonb_agg(relation.target_equipment_id order by relation.target_equipment_id)
      from public.smis_equipment_relation relation
      where relation.tenant_id = equipment.tenant_id
        and relation.source_equipment_id = equipment.id
        and relation.relation_type = 'safety_valve'
    ), '[]'::jsonb),
    'attachmentCount', (
      select count(*)
      from public.smis_equipment_attachment attachment
      where attachment.tenant_id = equipment.tenant_id
        and attachment.equipment_id = equipment.id
    ),
    'inspectionCount', (
      select count(*)
      from public.smis_equipment_inspection inspection
      where inspection.tenant_id = equipment.tenant_id
        and inspection.equipment_id = equipment.id
    ),
    'nextInspectionDueDate', (
      select min(inspection.next_due_date)
      from public.smis_equipment_inspection inspection
      where inspection.tenant_id = equipment.tenant_id
        and inspection.equipment_id = equipment.id
        and inspection.next_due_date is not null
        and inspection.status in ('planned', 'completed')
    ),
    'createBy', equipment.create_by,
    'createTime', equipment.create_time,
    'updateBy', equipment.update_by,
    'updateTime', equipment.update_time
  )
  into v_result
  from public.smis_equipment equipment
  join public.smis_equipment_category category
    on category.id = equipment.category_id
    and category.tenant_id = equipment.tenant_id
  left join public.smis_storage_location location
    on location.id = equipment.location_id
    and location.tenant_id = equipment.tenant_id
  join public.sys_organization using_org
    on using_org.id = equipment.using_organization_id
    and using_org.tenant_id = equipment.tenant_id
  join public.sys_organization managing_org
    on managing_org.id = equipment.managing_organization_id
    and managing_org.tenant_id = equipment.tenant_id
  left join public.hr_employee employee
    on employee.id = equipment.responsible_employee_id
    and employee.tenant_id = equipment.tenant_id
  left join public.vehicle_supplier supplier
    on supplier.id = equipment.supplier_id
    and supplier.tenant_id = equipment.tenant_id
  left join public.smis_equipment_boiler boiler
    on boiler.equipment_id = equipment.id
    and boiler.tenant_id = equipment.tenant_id
  where equipment.id = p_equipment_id
    and (
      app_private.current_read_tenant_id() is null
      or equipment.tenant_id = app_private.current_read_tenant_id()
    );

  return v_result;
end;
$function$;

revoke all on function public.smis_list_equipment_category_profiles_secure() from public, anon;
revoke all on function public.smis_save_equipment_category_profile_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_save_equipment_archive_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_get_equipment_archive_secure(uuid) from public, anon;
grant execute on function public.smis_list_equipment_category_profiles_secure() to authenticated;
grant execute on function public.smis_save_equipment_category_profile_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_save_equipment_archive_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_get_equipment_archive_secure(uuid) to authenticated;

do $migration$
declare
  v_parent_id uuid;
begin
  select id into v_parent_id
  from public.sys_menu
  where app_code = 'smis'
    and name = 'SmisEquipmentLedger'
  order by create_time
  limit 1;

  if v_parent_id is not null and not exists (
    select 1
    from public.sys_menu
    where app_code = 'smis'
      and name = 'SmisEquipmentLedgerDetail'
  ) then
    insert into public.sys_menu(id, parent_id, name, path, component, type, app_code, sort, meta)
    values (
      gen_random_uuid(),
      v_parent_id,
      'SmisEquipmentLedgerDetail',
      'equipment-ledger-detail/:id',
      '/smis/equipment-ledger/equipment-ledger-detail',
      'menu',
      'smis',
      8,
      jsonb_build_object(
        'icon', 'ri:archive-drawer-line',
        'title', '设备档案详情',
        'is_hide', true,
        'is_enable', true,
        'keep_alive', false,
        'active_path', '/smis/equipment-ledger/equipment-ledger'
      )
    );
  end if;
end;
$migration$;

;
