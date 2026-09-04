begin;

create or replace function public.mdm_get_governance_workspace_secure(
  p_scope text default null,
  p_keyword text default null
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
  result_value jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  tenant_value := app_private.current_user_tenant_id();
  is_super := app_private.is_platform_super();

  with catalog as materialized (
    select 'organization'::text as domain_key, 'organization'::text as scope_key,
           'organization'::text as source_type, '组织机构'::text as source_label,
           id, organization_code::text as code, organization_name::text as name,
           status::text as status, update_time
    from public.mdm_organization
    where is_super or tenant_id = tenant_value
    union all
    select 'organization', 'position', 'position', '岗位', id,
           position_code::text, position_name::text,
           case when enabled then '启用' else '停用' end, update_time
    from public.mdm_position
    where is_super or tenant_id = tenant_value
    union all
    select 'organization', 'position', 'job_profile', '标准职务', id,
           job_code::text, job_name::text,
           case when enabled then '启用' else '停用' end, update_time
    from public.mdm_job_profile
    where is_super or tenant_id = tenant_value
    union all
    select 'organization', 'employee', 'employee', '员工', id,
           employee_no::text, employee_name::text, employment_status::text, update_time
    from public.mdm_employee
    where is_super or tenant_id = tenant_value
    union all
    select 'partner', 'partner', 'business_partner', '往来主体', id,
           coalesce(source_code, partner_code)::text, partner_name::text, status::text, update_time
    from public.mdm_business_partner
    where is_super or tenant_id = tenant_value
    union all
    select 'logistics', 'logistics', 'station', '站点', id,
           station_code::text, station_name::text,
           case when enabled then '启用' else '停用' end, update_time
    from public.mdm_station
    where is_super or tenant_id = tenant_value
    union all
    select 'logistics', 'logistics', 'cargo', '货物', id,
           cargo_code::text, cargo_name::text,
           case when enabled then '启用' else '停用' end, update_time
    from public.mdm_cargo
    where is_super or tenant_id = tenant_value
    union all
    select 'logistics', 'logistics', 'driver', '司机', id,
           ('DRV-' || left(id::text, 8))::text, driver_name::text,
           case when enabled then '启用' else '停用' end, update_time
    from public.mdm_driver
    where is_super or tenant_id = tenant_value
    union all
    select 'asset', 'vehicle', 'vehicle', '车辆', id,
           plate_no::text, plate_no::text, operation_status::text, update_time
    from public.mdm_vehicle
    where is_super or tenant_id = tenant_value
    union all
    select 'asset', 'equipment', 'equipment', '设备', id,
           equipment_code::text, equipment_name::text, status::text, update_time
    from public.mdm_equipment
    where is_super or tenant_id = tenant_value
    union all
    select 'asset', 'equipment', 'part', '备件', id,
           part_code::text, part_name::text, status::text, update_time
    from public.mdm_part
    where is_super or tenant_id = tenant_value
    union all
    select 'material', 'material', 'material', '物料', id,
           material_code::text, material_name::text, status::text, update_time
    from public.mdm_material
    where is_super or tenant_id = tenant_value
    union all
    select 'material', 'material', 'site', '场所', id,
           ('SITE-' || left(id::text, 8))::text, site_name::text,
           coalesce(category_code::text, '未分类'), update_time
    from public.mdm_site
    where is_super or tenant_id = tenant_value
    union all
    select 'material', 'material', 'storage_location', '存放位置', id,
           location_code::text, location_name::text, status::text, update_time
    from public.mdm_storage_location
    where is_super or tenant_id = tenant_value
  ),
  domain_counts as (
    select domain_key, count(*)::integer as record_count
    from catalog
    group by domain_key
  ),
  filtered_records as (
    select *
    from catalog
    where (normalized_scope is null or scope_key = normalized_scope)
      and (
        normalized_keyword is null
        or code ilike '%' || normalized_keyword || '%'
        or name ilike '%' || normalized_keyword || '%'
        or source_label ilike '%' || normalized_keyword || '%'
      )
    order by update_time desc nulls last, source_label, name
    limit 500
  )
  select jsonb_build_object(
    'domains', coalesce(
      (select jsonb_agg(jsonb_build_object(
        'key', domain_key,
        'recordCount', record_count
      ) order by domain_key) from domain_counts),
      '[]'::jsonb
    ),
    'records', coalesce(
      (select jsonb_agg(jsonb_build_object(
        'id', id,
        'code', coalesce(nullif(code, ''), '—'),
        'name', coalesce(nullif(name, ''), '未命名记录'),
        'status', coalesce(nullif(status, ''), '未标记'),
        'sourceType', source_type,
        'sourceLabel', source_label,
        'updateTime', update_time
      ) order by update_time desc nulls last, source_label, name) from filtered_records),
      '[]'::jsonb
    )
  ) into result_value;

  return result_value;
end;
$$;

comment on function public.mdm_get_governance_workspace_secure(text, text) is
  'Tenant-safe MDM governance read model. Returns only non-sensitive catalog identity fields and aggregate counts.';

revoke all on function public.mdm_get_governance_workspace_secure(text, text)
  from public, anon, authenticated;
grant execute on function public.mdm_get_governance_workspace_secure(text, text)
  to authenticated, service_role;

commit;
