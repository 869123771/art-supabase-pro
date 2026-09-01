-- 将历史车辆供应商表提升为跨系统公用供应商主数据。
-- 保留物理表名 vehicle_supplier，避免破坏 VMS 既有外键、字段权限和 RPC 契约；
-- SMIS 通过独立的权限化 RPC 使用同一批记录和主键，不创建第二张供应商表。

alter table public.vehicle_supplier
  add column if not exists supplier_code text,
  add column if not exists supplier_category text not null default 'material_supplier',
  add column if not exists supplier_group text,
  add column if not exists supplier_type text not null default 'general',
  add column if not exists enterprise_nature text,
  add column if not exists industry text,
  add column if not exists region_adcode text,
  add column if not exists longitude numeric(11, 7),
  add column if not exists latitude numeric(10, 7),
  add column if not exists coordinate_system text not null default 'gcj02';

update public.vehicle_supplier
set supplier_code = 'SUP-' || upper(left(replace(id::text, '-', ''), 12))
where supplier_code is null or btrim(supplier_code) = '';

alter table public.vehicle_supplier
  alter column supplier_code set default (
    'SUP-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 12))
  ),
  alter column supplier_code set not null;

alter table public.vehicle_supplier
  add constraint vehicle_supplier_code_not_blank check (btrim(supplier_code) <> ''),
  add constraint vehicle_supplier_code_length check (char_length(supplier_code) <= 40),
  add constraint vehicle_supplier_name_length check (char_length(supplier_name) <= 120),
  add constraint vehicle_supplier_category_length check (char_length(supplier_category) <= 40),
  add constraint vehicle_supplier_group_length check (
    supplier_group is null or char_length(supplier_group) <= 80
  ),
  add constraint vehicle_supplier_type_length check (char_length(supplier_type) <= 40),
  add constraint vehicle_supplier_enterprise_nature_length check (
    enterprise_nature is null or char_length(enterprise_nature) <= 40
  ),
  add constraint vehicle_supplier_industry_length check (
    industry is null or char_length(industry) <= 40
  ),
  add constraint vehicle_supplier_contact_person_length check (
    contact_person is null or char_length(contact_person) <= 50
  ),
  add constraint vehicle_supplier_contact_phone_length check (
    contact_phone is null or char_length(contact_phone) <= 30
  ),
  add constraint vehicle_supplier_address_length check (
    address_detail is null or char_length(address_detail) <= 300
  ),
  add constraint vehicle_supplier_remark_length check (
    remark is null or char_length(remark) <= 500
  ),
  add constraint vehicle_supplier_coordinate_pair_check check (
    (longitude is null and latitude is null)
    or (longitude is not null and latitude is not null)
  ),
  add constraint vehicle_supplier_longitude_range check (
    longitude is null or longitude between -180 and 180
  ),
  add constraint vehicle_supplier_latitude_range check (
    latitude is null or latitude between -90 and 90
  ),
  add constraint vehicle_supplier_coordinate_system_check check (
    coordinate_system in ('gcj02', 'wgs84', 'bd09')
  );

comment on table public.vehicle_supplier is
  '跨 SMIS、VMS 及其他业务系统复用的租户级供应商公用主数据；历史表名为兼容既有车辆业务保留';
comment on column public.vehicle_supplier.supplier_code is '租户内唯一的供应商单位编码';
comment on column public.vehicle_supplier.supplier_name is '供应商单位名称';
comment on column public.vehicle_supplier.supplier_category is '供应商类别字典值';
comment on column public.vehicle_supplier.supplier_group is '租户自定义供应商分组';
comment on column public.vehicle_supplier.supplier_type is '供应商类型字典值';
comment on column public.vehicle_supplier.enterprise_nature is '企业性质字典值';
comment on column public.vehicle_supplier.industry is '所属行业字典值';
comment on column public.vehicle_supplier.coordinate_system is '地址坐标系：gcj02/wgs84/bd09';

create unique index if not exists vehicle_supplier_tenant_code_uq
  on public.vehicle_supplier(tenant_id, lower(btrim(supplier_code)));
create unique index if not exists vehicle_supplier_tenant_name_uq
  on public.vehicle_supplier(tenant_id, lower(btrim(supplier_name)));
create index if not exists vehicle_supplier_master_filter_idx
  on public.vehicle_supplier(tenant_id, supplier_category, supplier_type, industry);

drop policy if exists supplier_insert on public.vehicle_supplier;
create policy supplier_insert
on public.vehicle_supplier for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisSupplier:Add'))
    or (select app_private.has_permission('Supplier:Add'))
  )
);

drop policy if exists supplier_update on public.vehicle_supplier;
create policy supplier_update
on public.vehicle_supplier for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisSupplier:Edit'))
      or (select app_private.has_permission('Supplier:Edit'))
    )
  )
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisSupplier:Edit'))
    or (select app_private.has_permission('Supplier:Edit'))
  )
);

drop policy if exists supplier_delete on public.vehicle_supplier;
create policy supplier_delete
on public.vehicle_supplier for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisSupplier:Delete'))
      or (select app_private.has_permission('Supplier:Delete'))
    )
  )
);

create or replace function app_private.is_enabled_dictionary_value(
  p_type_code text,
  p_value text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.sys_dict_type dictionary_type
    join public.sys_dictionary dictionary_item
      on dictionary_item.type_id = dictionary_type.id
    where dictionary_type.code = p_type_code
      and dictionary_type.status = '1'
      and dictionary_item.status = '1'
      and dictionary_item.value = p_value
  );
$function$;

revoke all on function app_private.is_enabled_dictionary_value(text, text) from public;

create or replace function public.smis_list_suppliers_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_supplier_category text default null,
  p_supplier_type text default null,
  p_enterprise_nature text default null,
  p_industry text default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
  v_limit integer;
begin
  if p_purpose not in ('list', 'export') then
    raise exception '供应商读取用途无效' using errcode = '22023';
  end if;
  if p_purpose = 'export' then
    if not app_private.has_permission('SmisSupplier:Export') then
      raise exception '当前账号没有导出供应商的权限' using errcode = '42501';
    end if;
  elsif not (
    app_private.is_platform_super()
    or app_private.can_access_business_menu('SmisSupplier')
    or app_private.has_permission('SmisSupplier:View')
  ) then
    raise exception '当前账号没有查看供应商的权限' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception '当前租户不存在' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(v_to - v_from + 1, 1)
  );

  return jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(record_row) order by record_row."supplierName", record_row."supplierCode")
      from (
        select
          supplier.id,
          supplier.supplier_code as "supplierCode",
          supplier.supplier_name as "supplierName",
          supplier.supplier_category as "supplierCategory",
          supplier.supplier_group as "supplierGroup",
          supplier.supplier_type as "supplierType",
          supplier.enterprise_nature as "enterpriseNature",
          supplier.industry,
          supplier.contact_person as "contactPerson",
          supplier.contact_phone as "contactPhone",
          supplier.region,
          supplier.region_adcode as "regionAdcode",
          supplier.address_detail as "addressDetail",
          supplier.longitude,
          supplier.latitude,
          supplier.coordinate_system as "coordinateSystem",
          supplier.remark,
          supplier.create_by as "createBy",
          supplier.create_time as "createTime",
          supplier.update_by as "updateBy",
          supplier.update_time as "updateTime"
        from public.vehicle_supplier supplier
        where supplier.tenant_id = v_tenant_id
          and (p_ids is null or supplier.id = any(p_ids))
          and (p_supplier_category is null or supplier.supplier_category = p_supplier_category)
          and (p_supplier_type is null or supplier.supplier_type = p_supplier_type)
          and (p_enterprise_nature is null or supplier.enterprise_nature = p_enterprise_nature)
          and (p_industry is null or supplier.industry = p_industry)
          and (
            v_keyword is null
            or lower(supplier.supplier_code) like '%' || v_keyword || '%'
            or lower(supplier.supplier_name) like '%' || v_keyword || '%'
            or lower(coalesce(supplier.supplier_group, '')) like '%' || v_keyword || '%'
            or lower(coalesce(supplier.contact_person, '')) like '%' || v_keyword || '%'
            or lower(coalesce(supplier.contact_phone, '')) like '%' || v_keyword || '%'
            or lower(coalesce(supplier.address_detail, '')) like '%' || v_keyword || '%'
          )
        order by supplier.supplier_name, supplier.supplier_code
        offset v_from
        limit v_limit
      ) record_row
    ), '[]'::jsonb),
    'total', (
      select count(*)
      from public.vehicle_supplier supplier
      where supplier.tenant_id = v_tenant_id
        and (p_ids is null or supplier.id = any(p_ids))
        and (p_supplier_category is null or supplier.supplier_category = p_supplier_category)
        and (p_supplier_type is null or supplier.supplier_type = p_supplier_type)
        and (p_enterprise_nature is null or supplier.enterprise_nature = p_enterprise_nature)
        and (p_industry is null or supplier.industry = p_industry)
        and (
          v_keyword is null
          or lower(supplier.supplier_code) like '%' || v_keyword || '%'
          or lower(supplier.supplier_name) like '%' || v_keyword || '%'
          or lower(coalesce(supplier.supplier_group, '')) like '%' || v_keyword || '%'
          or lower(coalesce(supplier.contact_person, '')) like '%' || v_keyword || '%'
          or lower(coalesce(supplier.contact_phone, '')) like '%' || v_keyword || '%'
          or lower(coalesce(supplier.address_detail, '')) like '%' || v_keyword || '%'
        )
    ),
    'overview', (
      select jsonb_build_object(
        'total', count(*),
        'keySuppliers', count(*) filter (where supplier.supplier_type = 'key'),
        'categoryCount', count(distinct supplier.supplier_category),
        'contactComplete', count(*) filter (
          where supplier.contact_person is not null and supplier.contact_phone is not null
        )
      )
      from public.vehicle_supplier supplier
      where supplier.tenant_id = v_tenant_id
    )
  );
end;
$function$;

create or replace function public.smis_save_supplier_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_supplier_code text := upper(btrim(coalesce(p_payload->>'supplier_code', '')));
  v_supplier_name text := btrim(coalesce(p_payload->>'supplier_name', ''));
  v_supplier_category text := btrim(coalesce(p_payload->>'supplier_category', ''));
  v_supplier_group text := nullif(btrim(coalesce(p_payload->>'supplier_group', '')), '');
  v_supplier_type text := btrim(coalesce(p_payload->>'supplier_type', ''));
  v_enterprise_nature text := btrim(coalesce(p_payload->>'enterprise_nature', ''));
  v_industry text := btrim(coalesce(p_payload->>'industry', ''));
  v_contact_person text := nullif(btrim(coalesce(p_payload->>'contact_person', '')), '');
  v_contact_phone text := nullif(btrim(coalesce(p_payload->>'contact_phone', '')), '');
  v_region text := nullif(btrim(coalesce(p_payload->>'region', '')), '');
  v_region_adcode text := nullif(btrim(coalesce(p_payload->>'region_adcode', '')), '');
  v_address_detail text := nullif(btrim(coalesce(p_payload->>'address_detail', '')), '');
  v_longitude numeric(11, 7);
  v_latitude numeric(10, 7);
  v_coordinate_system text := btrim(coalesce(p_payload->>'coordinate_system', 'gcj02'));
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
begin
  if p_id is null and not app_private.has_permission('SmisSupplier:Add') then
    raise exception '当前账号没有新增供应商的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisSupplier:Edit') then
    raise exception '当前账号没有编辑供应商的权限' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception '当前租户不存在' using errcode = '42501';
  end if;
  if v_supplier_code = '' or v_supplier_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' then
    raise exception '单位编码仅支持字母、数字、短横线和下划线，且不能超过 40 个字符' using errcode = '22023';
  end if;
  if v_supplier_name = '' or char_length(v_supplier_name) > 120 then
    raise exception '请输入不超过 120 个字符的单位名称' using errcode = '22023';
  end if;
  if not app_private.is_enabled_dictionary_value('supplierCategory', v_supplier_category) then
    raise exception '供应商类别无效或已停用' using errcode = '22023';
  end if;
  if not app_private.is_enabled_dictionary_value('supplierType', v_supplier_type) then
    raise exception '供应商类型无效或已停用' using errcode = '22023';
  end if;
  if not app_private.is_enabled_dictionary_value('enterpriseNature', v_enterprise_nature) then
    raise exception '企业性质无效或已停用' using errcode = '22023';
  end if;
  if not app_private.is_enabled_dictionary_value('supplierIndustry', v_industry) then
    raise exception '行业无效或已停用' using errcode = '22023';
  end if;
  if char_length(coalesce(v_supplier_group, '')) > 80 then
    raise exception '供应商分组不能超过 80 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_contact_person, '')) > 50 then
    raise exception '联系人不能超过 50 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_contact_phone, '')) > 30 then
    raise exception '联系电话不能超过 30 个字符' using errcode = '22023';
  end if;
  if v_address_detail is null or char_length(v_address_detail) > 300 then
    raise exception '请输入不超过 300 个字符的详细地址' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 500 then
    raise exception '备注不能超过 500 个字符' using errcode = '22023';
  end if;
  if v_coordinate_system not in ('gcj02', 'wgs84', 'bd09') then
    raise exception '地址坐标系无效' using errcode = '22023';
  end if;

  begin
    v_longitude := nullif(p_payload->>'longitude', '')::numeric;
    v_latitude := nullif(p_payload->>'latitude', '')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception '经纬度格式无效' using errcode = '22023';
  end;
  if (v_longitude is null) <> (v_latitude is null) then
    raise exception '经度和纬度必须同时填写' using errcode = '22023';
  end if;
  if v_longitude is not null and (v_longitude < -180 or v_longitude > 180) then
    raise exception '经度应在 -180 到 180 之间' using errcode = '22023';
  end if;
  if v_latitude is not null and (v_latitude < -90 or v_latitude > 90) then
    raise exception '纬度应在 -90 到 90 之间' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.vehicle_supplier(
      tenant_id, supplier_code, supplier_name, supplier_category, supplier_group,
      supplier_type, enterprise_nature, industry, contact_person, contact_phone,
      region, region_adcode, address_detail, longitude, latitude, coordinate_system, remark
    ) values (
      v_tenant_id, v_supplier_code, v_supplier_name, v_supplier_category, v_supplier_group,
      v_supplier_type, v_enterprise_nature, v_industry, v_contact_person, v_contact_phone,
      v_region, v_region_adcode, v_address_detail, v_longitude, v_latitude,
      v_coordinate_system, v_remark
    ) returning id into v_id;
  else
    update public.vehicle_supplier
    set supplier_code = v_supplier_code,
        supplier_name = v_supplier_name,
        supplier_category = v_supplier_category,
        supplier_group = v_supplier_group,
        supplier_type = v_supplier_type,
        enterprise_nature = v_enterprise_nature,
        industry = v_industry,
        contact_person = v_contact_person,
        contact_phone = v_contact_phone,
        region = v_region,
        region_adcode = v_region_adcode,
        address_detail = v_address_detail,
        longitude = v_longitude,
        latitude = v_latitude,
        coordinate_system = v_coordinate_system,
        remark = v_remark
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_id;

    if v_id is null then
      raise exception '供应商不存在或已删除' using errcode = 'P0002';
    end if;
  end if;

  return v_id;
exception
  when unique_violation then
    raise exception '单位编码或单位名称已存在，请更换后重试' using errcode = '23505';
end;
$function$;

create or replace function public.smis_delete_suppliers_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if not app_private.has_permission('SmisSupplier:Delete') then
    raise exception '当前账号没有删除供应商的权限' using errcode = '42501';
  end if;

  delete from public.vehicle_supplier
  where tenant_id = app_private.current_user_tenant_id()
    and id = any(coalesce(p_ids, array[]::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
exception
  when foreign_key_violation then
    raise exception '供应商已被业务记录使用，请先解除关联' using errcode = '23503';
end;
$function$;

revoke all on function public.smis_list_suppliers_secure(
  integer, integer, text, text, text, text, text, uuid[], text
) from public, anon;
revoke all on function public.smis_save_supplier_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_suppliers_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_suppliers_secure(
  integer, integer, text, text, text, text, text, uuid[], text
) to authenticated, service_role;
grant execute on function public.smis_save_supplier_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.smis_delete_suppliers_secure(uuid[])
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_types(code, name, remark, sort) as (values
  ('supplierCategory', '供应商类别', '跨系统供应商类别', 14),
  ('supplierType', '供应商类型', '跨系统供应商重要程度分类', 15),
  ('enterpriseNature', '企业性质', '跨系统企业性质分类', 16),
  ('supplierIndustry', '供应商行业', '跨系统供应商行业分类', 17)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), dictionary_types.name, dictionary_types.code, '1',
  '624944977@qq.com', '624944977@qq.com', dictionary_types.remark,
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'smisBasicData' limit 1),
  'dictionary', dictionary_types.sort
from dictionary_types
cross join platform_tenant
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark,
  parent_id = excluded.parent_id,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('supplierCategory', 'inspection_agency', '检验机构', 1, 'primary'),
  ('supplierCategory', 'installation_company', '安装单位', 2, 'success'),
  ('supplierCategory', 'repair_company', '维修单位', 3, 'warning'),
  ('supplierCategory', 'maintenance_company', '维保单位', 4, 'info'),
  ('supplierCategory', 'material_supplier', '材料供应商', 5, 'primary'),
  ('supplierType', 'general', '一般供应商', 1, 'info'),
  ('supplierType', 'key', '重点供应商', 2, 'warning'),
  ('enterpriseNature', 'state_owned', '国企', 1, 'primary'),
  ('enterpriseNature', 'central_state_owned', '央企', 2, 'success'),
  ('enterpriseNature', 'foreign_invested', '外资', 3, 'warning'),
  ('enterpriseNature', 'private', '民营', 4, 'info'),
  ('supplierIndustry', 'coal_mining', '煤炭矿业', 1, 'warning'),
  ('supplierIndustry', 'manufacturing', '生产制造业', 2, 'primary'),
  ('supplierIndustry', 'logistics_transportation', '物流运输', 3, 'success'),
  ('supplierIndustry', 'technology_services', '科技服务', 4, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id,
  items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', dictionary_type.name || '字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

update public.sys_menu
set component = '/smis/basic-data/supplier',
    meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
      'title', '供应商',
      'icon', 'ri:store-2-line',
      'is_hide', false,
      'is_enable', true
    ),
    sort = 8,
    app_code = 'smis',
    update_by = '624944977@qq.com',
    update_time = now()
where id = 'a1530000-0000-4000-8000-000000000012'::uuid;

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'a1530000-0000-4000-8000-000000000012'::uuid,
  seed.name, '', '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ), seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8121-000000000001'::uuid, 'SmisSupplier:View', '查看供应商', 1),
  ('a1530000-0000-4000-8121-000000000002'::uuid, 'SmisSupplier:Add', '新增供应商', 2),
  ('a1530000-0000-4000-8121-000000000003'::uuid, 'SmisSupplier:Edit', '编辑供应商', 3),
  ('a1530000-0000-4000-8121-000000000004'::uuid, 'SmisSupplier:Delete', '删除供应商', 4),
  ('a1530000-0000-4000-8121-000000000005'::uuid, 'SmisSupplier:Export', '导出供应商', 5)
) seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('a1530000-0000-4000-8121-000000000001'::uuid),
  ('a1530000-0000-4000-8121-000000000002'::uuid),
  ('a1530000-0000-4000-8121-000000000003'::uuid),
  ('a1530000-0000-4000-8121-000000000004'::uuid),
  ('a1530000-0000-4000-8121-000000000005'::uuid)
) button(id)
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000012'::uuid
on conflict (role_id, menu_id) do nothing;

notify pgrst, 'reload schema';

;
