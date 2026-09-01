create or replace function public.smis_save_site_secure(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_organization_id uuid := nullif(p_payload->>'organization_id', '')::uuid;
  v_parent_id uuid := nullif(p_payload->>'parent_id', '')::uuid;
  v_employee_id uuid := nullif(p_payload->>'responsible_employee_id', '')::uuid;
  v_site_name text := btrim(coalesce(p_payload->>'site_name', ''));
  v_category text := btrim(coalesce(p_payload->>'category_code', ''));
begin
  if p_id is null and not app_private.has_permission('SmisSite:Add') then
    raise exception '当前账号没有新增场所的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisSite:Edit') then
    raise exception '当前账号没有编辑场所的权限' using errcode = '42501';
  end if;
  if v_site_name = '' then
    raise exception '请输入场所名称' using errcode = '22023';
  end if;
  if v_category = '' then
    raise exception '请选择属性类别' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type
      on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisSiteCategory'
      and dictionary_type.status = '1'
      and dictionary_item.status = '1'
      and btrim(dictionary_item.value) = v_category
  ) and not (
    p_id is not null
    and exists (
      select 1
      from public.smis_site existing_site
      where existing_site.id = p_id
        and existing_site.tenant_id = v_tenant_id
        and existing_site.category_code = v_category
    )
  ) then
    raise exception '属性类别无效或已停用' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.sys_organization
    where id = v_organization_id
      and tenant_id = v_tenant_id
      and status = '1'
  ) then
    raise exception '请选择当前租户的有效部门' using errcode = '22023';
  end if;
  if v_employee_id is not null and not exists (
    select 1
    from public.hr_employee
    where id = v_employee_id
      and tenant_id = v_tenant_id
      and employment_status in ('active', 'probation')
  ) then
    raise exception '责任人不是当前租户的有效员工' using errcode = '22023';
  end if;
  if v_parent_id is not null and not exists (
    select 1
    from public.smis_site
    where id = v_parent_id
      and tenant_id = v_tenant_id
  ) then
    raise exception '上级场所不存在或已删除' using errcode = '22023';
  end if;
  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants as (
      select id
      from public.smis_site
      where parent_id = p_id
        and tenant_id = v_tenant_id
      union all
      select child.id
      from public.smis_site child
      join descendants parent on child.parent_id = parent.id
      where child.tenant_id = v_tenant_id
    )
    select 1
    from descendants
    where id = v_parent_id
  ) then
    raise exception '上级场所不能选择当前场所的下级节点' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_site(
      tenant_id,
      organization_id,
      parent_id,
      site_name,
      category_code,
      sort,
      responsible_employee_id,
      address_detail,
      longitude,
      latitude,
      coordinate_system,
      image_urls,
      remark
    ) values (
      v_tenant_id,
      v_organization_id,
      v_parent_id,
      v_site_name,
      v_category,
      coalesce((p_payload->>'sort')::integer, 0),
      v_employee_id,
      nullif(btrim(p_payload->>'address_detail'), ''),
      nullif(p_payload->>'longitude', '')::numeric,
      nullif(p_payload->>'latitude', '')::numeric,
      coalesce(nullif(p_payload->>'coordinate_system', ''), 'gcj02'),
      coalesce(p_payload->'image_urls', '[]'::jsonb),
      nullif(btrim(p_payload->>'remark'), '')
    ) returning id into v_id;
  else
    update public.smis_site
    set organization_id = v_organization_id,
      parent_id = v_parent_id,
      site_name = v_site_name,
      category_code = v_category,
      sort = coalesce((p_payload->>'sort')::integer, 0),
      responsible_employee_id = v_employee_id,
      address_detail = nullif(btrim(p_payload->>'address_detail'), ''),
      longitude = nullif(p_payload->>'longitude', '')::numeric,
      latitude = nullif(p_payload->>'latitude', '')::numeric,
      coordinate_system = coalesce(nullif(p_payload->>'coordinate_system', ''), 'gcj02'),
      image_urls = coalesce(p_payload->'image_urls', '[]'::jsonb),
      remark = nullif(btrim(p_payload->>'remark'), '')
    where id = p_id
      and tenant_id = v_tenant_id
    returning id into v_id;
    if v_id is null then
      raise exception '场所记录不存在或已删除' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end;
$function$;

comment on function public.smis_save_site_secure(uuid, jsonb) is
  '新增或更新当前租户场所，并按启用中的 smisSiteCategory 字典校验属性类别。';

;
