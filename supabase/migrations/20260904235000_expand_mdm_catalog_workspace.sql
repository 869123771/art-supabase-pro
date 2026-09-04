begin;

create or replace view app_private.mdm_catalog_projection as
select
  tenant_id,
  'organization'::text as domain_key,
  'organization'::text as scope_key,
  'organization'::text as source_type,
  '组织机构'::text as source_label,
  'platform'::text as source_app,
  id,
  organization_code::text as code,
  organization_name::text as name,
  status::text,
  lower(status) not in ('0', 'disabled', 'inactive') as is_active,
  coalesce(organization_type, '组织类型待补充')::text as subtitle,
  jsonb_build_array(
    jsonb_build_object('label', '组织类型', 'value', organization_type),
    jsonb_build_object('label', '系统组织', 'value', case when is_system then '是' else '否' end),
    jsonb_build_object('label', '地址', 'value', address),
    jsonb_build_object('label', '说明', 'value', description)
  ) as attributes,
  100 - case when nullif(btrim(organization_type), '') is null then 15 else 0 end as quality_score,
  array_remove(array[
    case when nullif(btrim(organization_type), '') is null then '组织类型待补充' end
  ], null)::text[] as quality_issues,
  create_time,
  update_time
from public.mdm_organization

union all
select tenant_id, 'organization', 'position', 'job_family', '职族', 'hr', id,
  family_code::text, family_name::text,
  case when enabled then 'enabled' else 'disabled' end,
  enabled,
  coalesce(description, '标准职族')::text,
  jsonb_build_array(jsonb_build_object('label', '说明', 'value', description)),
  100, array[]::text[], create_time, update_time
from public.mdm_job_family

union all
select tenant_id, 'organization', 'position', 'grade', '职级', 'hr', id,
  grade_code::text, grade_name::text,
  case when enabled then 'enabled' else 'disabled' end,
  enabled,
  ('职级层级 ' || grade_level::text)::text,
  jsonb_build_array(
    jsonb_build_object('label', '职级层级', 'value', grade_level),
    jsonb_build_object('label', '说明', 'value', description)
  ),
  100, array[]::text[], create_time, update_time
from public.mdm_grade

union all
select tenant_id, 'organization', 'position', 'job_profile', '标准职务', 'hr', id,
  job_code::text, job_name::text,
  case when enabled then 'enabled' else 'disabled' end,
  enabled,
  coalesce(description, responsibilities, '职责说明待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '主要职责', 'value', responsibilities),
    jsonb_build_object('label', '任职要求', 'value', requirements),
    jsonb_build_object('label', '说明', 'value', description)
  ),
  100 - case when nullif(btrim(responsibilities), '') is null then 10 else 0 end
      - case when nullif(btrim(requirements), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(responsibilities), '') is null then '主要职责待补充' end,
    case when nullif(btrim(requirements), '') is null then '任职要求待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_job_profile

union all
select tenant_id, 'organization', 'position', 'position', '岗位', 'hr', id,
  position_code::text, position_name::text,
  case when enabled then 'enabled' else 'disabled' end,
  enabled,
  coalesce(position_kind, 'standard')::text,
  jsonb_build_array(
    jsonb_build_object('label', '岗位类型', 'value', position_kind),
    jsonb_build_object('label', '编制人数', 'value', headcount_limit),
    jsonb_build_object('label', '允许多人任职', 'value', case when multiple_incumbents_allowed then '是' else '否' end),
    jsonb_build_object('label', '说明', 'value', description)
  ),
  100 - case when organization_id is null then 15 else 0 end
      - case when job_profile_id is null then 15 else 0 end,
  array_remove(array[
    case when organization_id is null then '所属组织待关联' end,
    case when job_profile_id is null then '标准职务待关联' end
  ], null)::text[],
  create_time, update_time
from public.mdm_position

union all
select tenant_id, 'organization', 'employee', 'employee', '员工', 'hr', id,
  employee_no::text, employee_name::text, employment_status::text,
  lower(employment_status) in ('active', 'probation', 'on_duty', '在职', '试用'),
  coalesce(job_title, employment_type, '任职信息待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '职务', 'value', job_title),
    jsonb_build_object('label', '用工类型', 'value', employment_type),
    jsonb_build_object('label', '入职日期', 'value', hire_date),
    jsonb_build_object('label', '合同到期', 'value', contract_end_date)
  ),
  100 - case when organization_id is null then 15 else 0 end
      - case when position_id is null then 15 else 0 end
      - case when hire_date is null then 10 else 0 end,
  array_remove(array[
    case when organization_id is null then '所属组织待关联' end,
    case when position_id is null then '岗位待关联' end,
    case when hire_date is null then '入职日期待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_employee

union all
select tenant_id, 'partner', 'partner', 'business_partner', '统一往来主体', 'mdm', id,
  coalesce(source_code, partner_code)::text, partner_name::text, status::text, enabled,
  coalesce(legal_name, region, '主体资料待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '法定名称', 'value', legal_name),
    jsonb_build_object('label', '登记号码', 'value', registration_no),
    jsonb_build_object('label', '税号', 'value', tax_no),
    jsonb_build_object('label', '所在地区', 'value', region),
    jsonb_build_object('label', '详细地址', 'value', address_detail)
  ),
  100 - case when nullif(btrim(registration_no), '') is null and nullif(btrim(tax_no), '') is null then 20 else 0 end
      - case when nullif(btrim(region), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(registration_no), '') is null and nullif(btrim(tax_no), '') is null then '登记号码或税号待补充' end,
    case when nullif(btrim(region), '') is null then '所在地区待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_business_partner

union all
select tenant_id, 'partner', 'partner', 'customer', '客户', 'tms', id,
  customer_code::text, customer_name::text,
  case when enabled then 'enabled' else 'disabled' end, enabled,
  coalesce(customer_level, industry, '客户分类待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '客户等级', 'value', customer_level),
    jsonb_build_object('label', '所属行业', 'value', industry),
    jsonb_build_object('label', '所在地区', 'value', region),
    jsonb_build_object('label', '税号', 'value', tax_no)
  ),
  100 - case when nullif(btrim(customer_level), '') is null then 10 else 0 end
      - case when nullif(btrim(region), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(customer_level), '') is null then '客户等级待补充' end,
    case when nullif(btrim(region), '') is null then '所在地区待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_customer

union all
select tenant_id, 'partner', 'partner', 'carrier', '承运商', 'tms', id,
  carrier_code::text, company_name::text,
  case when enabled then 'enabled' else 'disabled' end, enabled,
  coalesce(carrier_type, region, '承运商分类待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '承运商类型', 'value', carrier_type),
    jsonb_build_object('label', '所在地区', 'value', region),
    jsonb_build_object('label', '已签合同', 'value', case when signed_contract then '是' else '否' end),
    jsonb_build_object('label', '司机数量', 'value', driver_count),
    jsonb_build_object('label', '车辆数量', 'value', vehicle_count)
  ),
  100 - case when nullif(btrim(business_license_no), '') is null then 15 else 0 end
      - case when nullif(btrim(region), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(business_license_no), '') is null then '营业执照号待补充' end,
    case when nullif(btrim(region), '') is null then '所在地区待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_carrier

union all
select tenant_id, 'partner', 'partner', 'supplier', '供应商', 'vms', id,
  supplier_code::text, supplier_name::text, 'enabled', true,
  coalesce(supplier_category, supplier_type, '供应商分类待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '供应商分类', 'value', supplier_category),
    jsonb_build_object('label', '供应商类型', 'value', supplier_type),
    jsonb_build_object('label', '企业性质', 'value', enterprise_nature),
    jsonb_build_object('label', '所属行业', 'value', industry),
    jsonb_build_object('label', '所在地区', 'value', region)
  ),
  100 - case when nullif(btrim(supplier_category), '') is null then 10 else 0 end
      - case when nullif(btrim(region), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(supplier_category), '') is null then '供应商分类待补充' end,
    case when nullif(btrim(region), '') is null then '所在地区待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_supplier

union all
select tenant_id, 'partner', 'partner', 'insurance_company', '保险公司', 'vms', id,
  ('INS-' || left(id::text, 8))::text, company_name::text, 'enabled', true,
  coalesce(region, '所在地区待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '所在地区', 'value', region),
    jsonb_build_object('label', '详细地址', 'value', address_detail)
  ),
  80 - case when nullif(btrim(region), '') is null then 10 else 0 end,
  array_remove(array[
    '尚未建立保险公司业务编码',
    case when nullif(btrim(region), '') is null then '所在地区待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_insurance_company

union all
select tenant_id, 'partner', 'partner', 'external_vendor', '外部服务商', 'hr', id,
  vendor_code::text, vendor_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(service_scope, compliance_status, '服务范围待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '服务范围', 'value', service_scope),
    jsonb_build_object('label', '合规状态', 'value', compliance_status),
    jsonb_build_object('label', '风险等级', 'value', risk_level),
    jsonb_build_object('label', '合同开始', 'value', contract_start_date),
    jsonb_build_object('label', '合同结束', 'value', contract_end_date)
  ),
  100 - case when nullif(btrim(registration_no), '') is null then 15 else 0 end
      - case when nullif(btrim(service_scope), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(registration_no), '') is null then '登记号码待补充' end,
    case when nullif(btrim(service_scope), '') is null then '服务范围待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_external_vendor

union all
select tenant_id, 'logistics', 'logistics', 'station', '站点', 'tms', id,
  station_code::text, station_name::text,
  case when enabled then 'enabled' else 'disabled' end, enabled,
  coalesce(station_type, region_code, '站点类型待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '站点类型', 'value', station_type),
    jsonb_build_object('label', '行政区划', 'value', region_code),
    jsonb_build_object('label', '负责人', 'value', manager_name)
  ),
  100 - case when nullif(btrim(station_type), '') is null then 15 else 0 end
      - case when nullif(btrim(region_code), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(station_type), '') is null then '站点类型待补充' end,
    case when nullif(btrim(region_code), '') is null then '行政区划待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_station

union all
select tenant_id, 'logistics', 'logistics', 'cargo', '货物', 'tms', id,
  cargo_code::text, cargo_name::text,
  case when enabled then 'enabled' else 'disabled' end, enabled,
  ('基本单位：' || unit)::text,
  jsonb_build_array(
    jsonb_build_object('label', '基本单位', 'value', unit),
    jsonb_build_object('label', '体积（m³）', 'value', volume_m3),
    jsonb_build_object('label', '重量（kg）', 'value', weight_kg)
  ),
  100 - case when nullif(btrim(unit), '') is null then 20 else 0 end,
  array_remove(array[
    case when nullif(btrim(unit), '') is null then '基本单位待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_cargo

union all
select tenant_id, 'logistics', 'logistics', 'driver', '司机', 'tms', id,
  ('DRV-' || left(id::text, 8))::text, driver_name::text,
  case when enabled then 'enabled' else 'disabled' end, enabled,
  coalesce(license_type, driver_type, '驾驶资质待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '司机类型', 'value', driver_type),
    jsonb_build_object('label', '准驾车型', 'value', license_type),
    jsonb_build_object('label', '驾照到期', 'value', license_expire_date)
  ),
  80 - case when license_expire_date is null then 10 else 0 end,
  array_remove(array[
    '尚未建立司机业务编码',
    case when license_expire_date is null then '驾照到期日待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_driver

union all
select tenant_id, 'asset', 'vehicle', 'vehicle', '车辆', 'vms', id,
  plate_no::text, plate_no::text, operation_status::text,
  lower(operation_status) not in ('0', 'disabled', 'inactive', 'retired', 'scrapped'),
  coalesce(company_name, brand_model, vehicle_type, '车辆分类待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '所属单位', 'value', company_name),
    jsonb_build_object('label', '车辆类型', 'value', vehicle_type),
    jsonb_build_object('label', '品牌型号', 'value', brand_model),
    jsonb_build_object('label', '生产厂商', 'value', manufacturer),
    jsonb_build_object('label', '新能源', 'value', case when is_new_energy then '是' else '否' end),
    jsonb_build_object('label', '审核状态', 'value', audit_status)
  ),
  100 - case when nullif(btrim(vin), '') is null then 20 else 0 end
      - case when nullif(btrim(company_name), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(vin), '') is null then 'VIN 待补充' end,
    case when nullif(btrim(company_name), '') is null then '所属单位待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_vehicle

union all
select tenant_id, 'asset', 'equipment', 'equipment_category', '设备分类', 'smis', id,
  category_code::text, category_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(category_short_name, equipment_profile_type, '分类说明待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '分类简称', 'value', category_short_name),
    jsonb_build_object('label', '设备档案类型', 'value', equipment_profile_type),
    jsonb_build_object('label', '说明', 'value', remark)
  ),
  100, array[]::text[], create_time, update_time
from public.mdm_equipment_category

union all
select tenant_id, 'asset', 'equipment', 'equipment', '设备', 'smis', id,
  equipment_code::text, equipment_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive', 'scrapped'),
  coalesce(specification, model, equipment_kind, '设备规格待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '设备类型', 'value', equipment_kind),
    jsonb_build_object('label', '规格', 'value', specification),
    jsonb_build_object('label', '型号', 'value', model),
    jsonb_build_object('label', '制造商', 'value', manufacturer),
    jsonb_build_object('label', '使用状态', 'value', use_status),
    jsonb_build_object('label', '资产状态', 'value', asset_status),
    jsonb_build_object('label', '重要等级', 'value', importance_level)
  ),
  100 - case when category_id is null then 15 else 0 end
      - case when location_id is null then 10 else 0 end
      - case when nullif(btrim(specification), '') is null and nullif(btrim(model), '') is null then 10 else 0 end,
  array_remove(array[
    case when category_id is null then '设备分类待关联' end,
    case when location_id is null then '所在位置待关联' end,
    case when nullif(btrim(specification), '') is null and nullif(btrim(model), '') is null then '规格型号待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_equipment

union all
select tenant_id, 'asset', 'equipment', 'part_category', '备件分类', 'vms', id,
  category_code::text, category_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  ('分类层级 ' || category_level::text)::text,
  jsonb_build_array(
    jsonb_build_object('label', '分类层级', 'value', category_level),
    jsonb_build_object('label', '说明', 'value', remark)
  ),
  100, array[]::text[], create_time, update_time
from public.mdm_part_category

union all
select tenant_id, 'asset', 'equipment', 'part', '备件', 'vms', id,
  part_code::text, part_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(model, brand, unit, '备件规格待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '品牌', 'value', brand),
    jsonb_build_object('label', '型号', 'value', model),
    jsonb_build_object('label', '单位', 'value', unit),
    jsonb_build_object('label', '制造商', 'value', manufacturer),
    jsonb_build_object('label', '耗材', 'value', case when is_consumable then '是' else '否' end)
  ),
  100 - case when category_id is null then 15 else 0 end
      - case when nullif(btrim(unit), '') is null then 10 else 0 end,
  array_remove(array[
    case when category_id is null then '备件分类待关联' end,
    case when nullif(btrim(unit), '') is null then '计量单位待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_part

union all
select tenant_id, 'material', 'material', 'material_category', '物料分类', 'smis', id,
  category_code::text, category_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(description, '标准物料分类')::text,
  jsonb_build_array(jsonb_build_object('label', '说明', 'value', description)),
  100, array[]::text[], create_time, update_time
from public.mdm_material_category

union all
select tenant_id, 'material', 'material', 'material', '物料', 'smis', id,
  material_code::text, material_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(specification_model, brand, basic_unit, '物料规格待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '规格型号', 'value', specification_model),
    jsonb_build_object('label', '基本单位', 'value', basic_unit),
    jsonb_build_object('label', '物料类型', 'value', material_type),
    jsonb_build_object('label', '物料来源', 'value', material_source),
    jsonb_build_object('label', '品牌', 'value', brand),
    jsonb_build_object('label', '产地', 'value', place_of_origin)
  ),
  100 - case when category_id is null then 15 else 0 end
      - case when nullif(btrim(basic_unit), '') is null then 15 else 0 end
      - case when nullif(btrim(specification_model), '') is null then 10 else 0 end,
  array_remove(array[
    case when category_id is null then '物料分类待关联' end,
    case when nullif(btrim(basic_unit), '') is null then '基本单位待补充' end,
    case when nullif(btrim(specification_model), '') is null then '规格型号待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_material

union all
select tenant_id, 'material', 'material', 'site', '场所', 'smis', id,
  ('SITE-' || left(id::text, 8))::text, site_name::text, 'enabled', true,
  coalesce(category_code, address_detail, '场所分类待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '场所分类', 'value', category_code),
    jsonb_build_object('label', '详细地址', 'value', address_detail),
    jsonb_build_object('label', '坐标系', 'value', coordinate_system),
    jsonb_build_object('label', '说明', 'value', remark)
  ),
  80 - case when nullif(btrim(address_detail), '') is null then 10 else 0 end,
  array_remove(array[
    '尚未建立场所业务编码',
    case when nullif(btrim(address_detail), '') is null then '详细地址待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_site

union all
select tenant_id, 'material', 'material', 'storage_location', '存放位置', 'smis', id,
  location_code::text, location_name::text, status::text,
  lower(status) not in ('0', 'disabled', 'inactive'),
  coalesce(location_short_name, detail_location, '位置说明待补充')::text,
  jsonb_build_array(
    jsonb_build_object('label', '位置简称', 'value', location_short_name),
    jsonb_build_object('label', '详细位置', 'value', detail_location),
    jsonb_build_object('label', '说明', 'value', remark)
  ),
  100 - case when nullif(btrim(detail_location), '') is null then 10 else 0 end,
  array_remove(array[
    case when nullif(btrim(detail_location), '') is null then '详细位置待补充' end
  ], null)::text[],
  create_time, update_time
from public.mdm_storage_location;

revoke all on app_private.mdm_catalog_projection from public, anon, authenticated;

create or replace function public.mdm_list_catalog_secure(
  p_scope text,
  p_keyword text default null,
  p_source_type text default null,
  p_state text default null,
  p_quality text default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  tenant_value uuid;
  is_super boolean;
  normalized_scope text := lower(nullif(btrim(p_scope), ''));
  normalized_keyword text := nullif(btrim(p_keyword), '');
  normalized_source text := lower(nullif(btrim(p_source_type), ''));
  normalized_state text := lower(nullif(btrim(p_state), ''));
  normalized_quality text := lower(nullif(btrim(p_quality), ''));
  safe_from integer := greatest(coalesce(p_from, 0), 0);
  safe_to integer;
  result_value jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_scope not in (
    'organization', 'position', 'employee', 'partner',
    'logistics', 'vehicle', 'equipment', 'material'
  ) then
    raise exception 'Invalid MDM catalog scope' using errcode = '22023';
  end if;

  if normalized_state is not null and normalized_state not in ('active', 'inactive') then
    raise exception 'Invalid MDM record state' using errcode = '22023';
  end if;

  if normalized_quality is not null and normalized_quality not in ('complete', 'attention') then
    raise exception 'Invalid MDM quality state' using errcode = '22023';
  end if;

  safe_to := least(greatest(coalesce(p_to, safe_from + 19), safe_from), safe_from + 99);
  tenant_value := app_private.current_user_tenant_id();
  is_super := app_private.is_platform_super();

  with visible as materialized (
    select *
    from app_private.mdm_catalog_projection
    where scope_key = normalized_scope
      and (is_super or tenant_id = tenant_value)
  ),
  filtered as materialized (
    select *
    from visible
    where (normalized_source is null or source_type = normalized_source)
      and (
        normalized_state is null
        or (normalized_state = 'active' and is_active)
        or (normalized_state = 'inactive' and not is_active)
      )
      and (
        normalized_quality is null
        or (normalized_quality = 'complete' and quality_score >= 90)
        or (normalized_quality = 'attention' and quality_score < 90)
      )
      and (
        normalized_keyword is null
        or code ilike '%' || normalized_keyword || '%'
        or name ilike '%' || normalized_keyword || '%'
        or source_label ilike '%' || normalized_keyword || '%'
        or subtitle ilike '%' || normalized_keyword || '%'
      )
  ),
  paged as (
    select *
    from filtered
    order by update_time desc nulls last, source_label, name, id
    offset safe_from
    limit safe_to - safe_from + 1
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'code', coalesce(nullif(code, ''), '—'),
        'name', coalesce(nullif(name, ''), '未命名记录'),
        'status', coalesce(nullif(status, ''), '未标记'),
        'isActive', is_active,
        'subtitle', coalesce(nullif(subtitle, ''), '暂无摘要'),
        'sourceType', source_type,
        'sourceLabel', source_label,
        'sourceApp', source_app,
        'qualityScore', quality_score,
        'qualityIssues', to_jsonb(quality_issues),
        'attributes', attributes,
        'createTime', create_time,
        'updateTime', update_time
      ) order by update_time desc nulls last, source_label, name, id)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', source_type,
        'label', source_label,
        'app', source_app,
        'count', record_count,
        'attentionCount', attention_count
      ) order by source_label)
      from (
        select source_type, source_label, source_app,
          count(*)::integer as record_count,
          count(*) filter (where quality_score < 90)::integer as attention_count
        from visible
        group by source_type, source_label, source_app
      ) source_counts
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', (select count(*) from visible),
      'active', (select count(*) from visible where is_active),
      'inactive', (select count(*) from visible where not is_active),
      'complete', (select count(*) from visible where quality_score >= 90),
      'attention', (select count(*) from visible where quality_score < 90),
      'averageScore', coalesce((select round(avg(quality_score))::integer from visible), 0)
    )
  ) into result_value;

  return result_value;
end;
$$;

comment on view app_private.mdm_catalog_projection is
  'Internal tenant-aware projection of non-sensitive master-data fields for the MDM application.';

comment on function public.mdm_list_catalog_secure(text, text, text, text, text, integer, integer) is
  'Lists tenant-safe MDM catalog records with source, lifecycle and completeness filters.';

revoke all on function public.mdm_list_catalog_secure(text, text, text, text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.mdm_list_catalog_secure(text, text, text, text, text, integer, integer)
  to authenticated, service_role;

commit;
