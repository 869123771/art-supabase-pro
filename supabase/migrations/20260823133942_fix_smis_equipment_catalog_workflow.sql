-- Complete the SMIS equipment catalog reference and numbering contracts.

create or replace function public.smis_list_employee_reference_options(
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns table (
  id uuid,
  employee_no text,
  employee_name text,
  organization_name text,
  job_title text,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 9), greatest(coalesce(p_from, 0), 0));
begin
  if app_private.smis_current_user_id() is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:View') then
    raise exception 'Missing permission: SmisCatalog:View';
  end if;

  return query
  with filtered as (
    select
      employee_row.id,
      employee_row.employee_no,
      employee_row.employee_name,
      organization_row.organization_name,
      employee_row.job_title
    from public.hr_employee employee_row
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
     and organization_row.tenant_id = employee_row.tenant_id
    where employee_row.tenant_id = v_tenant_id
      and employee_row.employment_status = any(array['probation', 'active']::text[])
      and (
        v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or coalesce(employee_row.job_title, '') ilike '%' || v_keyword || '%'
        or coalesce(organization_row.organization_name, '') ilike '%' || v_keyword || '%'
      )
  ), counted as (
    select filtered.*, count(*) over() as total_count
    from filtered
  )
  select counted.id, counted.employee_no, counted.employee_name,
         counted.organization_name, counted.job_title, counted.total_count
  from counted
  order by counted.employee_no, counted.employee_name
  offset v_from
  limit greatest(v_to - v_from + 1, 1);
end;
$$;

revoke all on function public.smis_list_employee_reference_options(text, integer, integer)
  from public, anon;
grant execute on function public.smis_list_employee_reference_options(text, integer, integer)
  to authenticated, service_role;

create or replace function public.smis_list_supplier_reference_options(
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns table (
  id uuid,
  supplier_code text,
  supplier_name text,
  contact_name text,
  contact_phone text,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_keyword text := nullif(btrim(p_keyword), '');
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 9), greatest(coalesce(p_from, 0), 0));
begin
  if app_private.smis_current_user_id() is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:View') then
    raise exception 'Missing permission: SmisCatalog:View';
  end if;

  return query
  with filtered as (
    select
      supplier_row.id,
      'SUP-' || upper(left(replace(supplier_row.id::text, '-', ''), 8)) as supplier_code,
      supplier_row.supplier_name::text,
      supplier_row.contact_person::text as contact_name,
      supplier_row.contact_phone::text
    from public.vehicle_supplier supplier_row
    where supplier_row.tenant_id = v_tenant_id
      and (
        v_keyword is null
        or supplier_row.supplier_name ilike '%' || v_keyword || '%'
        or coalesce(supplier_row.contact_person, '') ilike '%' || v_keyword || '%'
        or coalesce(supplier_row.contact_phone, '') ilike '%' || v_keyword || '%'
      )
  ), counted as (
    select filtered.*, count(*) over() as total_count
    from filtered
  )
  select counted.id, counted.supplier_code, counted.supplier_name,
         counted.contact_name, counted.contact_phone, counted.total_count
  from counted
  order by counted.supplier_name
  offset v_from
  limit greatest(v_to - v_from + 1, 1);
end;
$$;

revoke all on function public.smis_list_supplier_reference_options(text, integer, integer)
  from public, anon;
grant execute on function public.smis_list_supplier_reference_options(text, integer, integer)
  to authenticated, service_role;

do $$
declare
  v_platform_tenant_id uuid;
  v_type_id uuid;
begin
  select tenant_row.id into v_platform_tenant_id
  from public.sys_tenant tenant_row
  where tenant_row.tenant_code = 'platform'
  limit 1;

  insert into public.sys_dict_type (
    name, code, status, create_by, update_by, remark,
    tenant_id, parent_id, node_type, sort
  ) values (
    'SMIS检验记录类型', 'smisInspectionRecordType', '1', 'migration', 'migration',
    '设备外部、内部、年度和定期检验记录分类', v_platform_tenant_id, null, 'dictionary', 635
  )
  on conflict (code) do update set
    name = excluded.name,
    status = '1',
    remark = excluded.remark,
    update_by = 'migration',
    update_time = now();

  select type_row.id into v_type_id
  from public.sys_dict_type type_row
  where type_row.code = 'smisInspectionRecordType';

  insert into public.sys_dictionary (
    type_id, code, status, create_by, update_by, value, label,
    sort, tenant_id, tag_type
  )
  select v_type_id, item.value, '1', 'migration', 'migration', item.value, item.label,
         item.sort, v_platform_tenant_id, item.tag_type
  from (values
    ('external', '外部检验', 1, 'primary'),
    ('internal', '内部检验', 2, 'success'),
    ('annual', '年度检验', 3, 'warning'),
    ('periodic', '定期检验', 4, 'info')
  ) as item(value, label, sort, tag_type)
  where not exists (
    select 1 from public.sys_dictionary dictionary_row
    where dictionary_row.type_id = v_type_id and dictionary_row.value = item.value
  );
end;
$$;

with scene_definition (
  rule_key, rule_name, field_label, menu_name, default_template, remark
) as (
  values
    ('smis.equipment_depreciation', '设备折旧单号', '折旧单号', 'SmisDocEquipmentDepreciation', 'SMIS-ZJ{YYYYMM}{SEQ:4}', 'SMIS设备折旧业务编号'),
    ('smis.external_inspection', '外部检验编号', '外部检验编号', 'SmisDocExternalInspection', 'SMIS-WJ{YYYYMM}{SEQ:4}', 'SMIS设备外部检验编号'),
    ('smis.internal_inspection', '内部检验编号', '内部检验编号', 'SmisDocInternalInspection', 'SMIS-NJ{YYYYMM}{SEQ:4}', 'SMIS设备内部检验编号'),
    ('smis.annual_inspection', '年度检验编号', '年度检验编号', 'SmisDocAnnualInspection', 'SMIS-ND{YYYYMM}{SEQ:4}', 'SMIS设备年度检验编号'),
    ('smis.periodic_inspection', '定期检验编号', '定期检验编号', 'SmisDocPeriodicInspection', 'SMIS-DQ{YYYYMM}{SEQ:4}', 'SMIS设备定期检验编号')
)
insert into public.sys_document_number_scene (
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  tenant_id, create_by, update_by
)
select definition.rule_key, definition.rule_name, definition.field_label,
       'business_document', menu_row.id, 'smis_business_record', 'record_no',
       definition.default_template, 'month', true, true, definition.remark,
       platform_tenant.id, 'migration', 'migration'
from scene_definition definition
join public.sys_menu menu_row on menu_row.name = definition.menu_name
join public.sys_tenant platform_tenant on platform_tenant.tenant_code = 'platform'
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  menu_id = excluded.menu_id,
  default_template = excluded.default_template,
  enabled = true,
  remark = excluded.remark,
  update_by = 'migration',
  update_time = now();

insert into public.sys_document_number_rule (
  id, tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select gen_random_uuid(), tenant_row.id, scene.rule_key, scene.rule_name, scene.category,
       scene.target_table, scene.target_column, true, scene.default_template,
       scene.default_reset_cycle, 1, 'Asia/Shanghai', 1, scene.manual_required,
       true, true, scene.remark, 'migration', 'migration'
from public.sys_document_number_scene scene
cross join public.sys_tenant tenant_row
where scene.rule_key = any(array[
  'smis.equipment_depreciation', 'smis.external_inspection',
  'smis.internal_inspection', 'smis.annual_inspection', 'smis.periodic_inspection'
]::text[])
  and tenant_row.status = '1'
on conflict (tenant_id, rule_key) do nothing;

create or replace function app_private.trg_assign_smis_business_record_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule_key text;
begin
  if nullif(btrim(new.record_no), '') is not null then
    return new;
  end if;

  v_rule_key := case new.module_code
    when 'equipment-depreciation' then 'smis.equipment_depreciation'
    when 'external-inspection' then 'smis.external_inspection'
    when 'internal-inspection' then 'smis.internal_inspection'
    when 'annual-inspection' then 'smis.annual_inspection'
    when 'periodic-inspection' then 'smis.periodic_inspection'
    else null
  end;

  if v_rule_key is null then
    return new;
  end if;

  new.record_no := app_private.next_document_number(v_rule_key, new.tenant_id);
  new.payload := jsonb_set(coalesce(new.payload, '{}'::jsonb), '{record_no}', to_jsonb(new.record_no), true);
  return new;
end;
$$;

drop trigger if exists document_number_smis_business_record on public.smis_business_record;
create trigger document_number_smis_business_record
before insert on public.smis_business_record
for each row execute function app_private.trg_assign_smis_business_record_number();

create index if not exists idx_smis_business_record_equipment_category
  on public.smis_business_record (tenant_id, (payload->>'category'))
  where module_code = 'equipment-ledger';

create index if not exists idx_smis_business_record_equipment_storage_location
  on public.smis_business_record (tenant_id, (payload->>'storage_location'))
  where module_code = 'equipment-ledger';

;
