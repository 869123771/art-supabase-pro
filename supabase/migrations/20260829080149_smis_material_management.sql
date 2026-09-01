-- Protective equipment material category and material master data.

create table public.smis_material_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  category_code text not null,
  category_name text not null,
  sort integer not null default 10,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_material_category_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_material_category_id_tenant_unique unique (id, tenant_id),
  constraint smis_material_category_parent_fkey
    foreign key (parent_id, tenant_id)
    references public.smis_material_category(id, tenant_id) on delete restrict,
  constraint smis_material_category_parent_check check (parent_id is null or parent_id <> id),
  constraint smis_material_category_code_check
    check (btrim(category_code) <> '' and char_length(category_code) <= 40),
  constraint smis_material_category_name_check
    check (btrim(category_name) <> '' and char_length(category_name) <= 80),
  constraint smis_material_category_sort_check check (sort between 0 and 999999),
  constraint smis_material_category_status_check check (status in ('enabled', 'disabled')),
  constraint smis_material_category_description_check
    check (description is null or char_length(description) <= 500)
);

create unique index smis_material_category_code_unique
  on public.smis_material_category (tenant_id, lower(btrim(category_code)));
create unique index smis_material_category_sibling_name_unique
  on public.smis_material_category (
    tenant_id,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(btrim(category_name))
  );
create index smis_material_category_parent_idx
  on public.smis_material_category (tenant_id, parent_id, sort, category_name);
create index smis_material_category_status_idx
  on public.smis_material_category (tenant_id, status);

create trigger smis_material_category_create_audit
before insert on public.smis_material_category
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger smis_material_category_update_audit
before update on public.smis_material_category
for each row execute function public.trg_set_update_time_and_by();

create table public.smis_material (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  material_code text not null,
  material_name text not null,
  specification_model text,
  drawing_no text,
  basic_unit text not null,
  material_type text not null,
  material_source text not null,
  brand text,
  material_composition text,
  place_of_origin text,
  image_urls jsonb not null default '[]'::jsonb,
  description text,
  status text not null default 'enabled',
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_material_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_material_category_fkey
    foreign key (category_id, tenant_id)
    references public.smis_material_category(id, tenant_id) on delete restrict,
  constraint smis_material_code_check
    check (btrim(material_code) <> '' and char_length(material_code) <= 60),
  constraint smis_material_name_check
    check (btrim(material_name) <> '' and char_length(material_name) <= 120),
  constraint smis_material_specification_check
    check (specification_model is null or char_length(specification_model) <= 120),
  constraint smis_material_drawing_no_check
    check (drawing_no is null or char_length(drawing_no) <= 80),
  constraint smis_material_basic_unit_check
    check (btrim(basic_unit) <> '' and char_length(basic_unit) <= 40),
  constraint smis_material_type_check
    check (material_type in ('protective_equipment', 'tool', 'office_supply')),
  constraint smis_material_source_check
    check (material_source in ('purchase', 'self_made')),
  constraint smis_material_brand_check check (brand is null or char_length(brand) <= 80),
  constraint smis_material_composition_check
    check (material_composition is null or char_length(material_composition) <= 120),
  constraint smis_material_origin_check
    check (place_of_origin is null or char_length(place_of_origin) <= 120),
  constraint smis_material_image_urls_check check (jsonb_typeof(image_urls) = 'array'),
  constraint smis_material_description_check
    check (description is null or char_length(description) <= 1000),
  constraint smis_material_status_check check (status in ('enabled', 'disabled')),
  constraint smis_material_sort_check check (sort between 0 and 999999)
);

create unique index smis_material_code_unique
  on public.smis_material (tenant_id, lower(btrim(material_code)));
create index smis_material_category_idx
  on public.smis_material (tenant_id, category_id, sort, material_name);
create index smis_material_type_status_idx
  on public.smis_material (tenant_id, material_type, status);
create index smis_material_source_idx
  on public.smis_material (tenant_id, material_source);

create trigger smis_material_create_audit
before insert on public.smis_material
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger smis_material_update_audit
before update on public.smis_material
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_material_category enable row level security;
alter table public.smis_material enable row level security;

create policy smis_material_category_tenant_select on public.smis_material_category
for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.auth_user_tenant_id())
    and (select app_private.has_permission('SmisMaterialCategory:View'))
  )
);
create policy smis_material_category_tenant_insert on public.smis_material_category
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisMaterialCategory:Add'))
);
create policy smis_material_category_tenant_update on public.smis_material_category
for update to authenticated
using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialCategory:Edit'))
)
with check (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialCategory:Edit'))
);
create policy smis_material_category_tenant_delete on public.smis_material_category
for delete to authenticated
using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialCategory:Delete'))
);

create policy smis_material_tenant_select on public.smis_material
for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.auth_user_tenant_id())
    and (select app_private.has_permission('SmisMaterialInformation:View'))
  )
);
create policy smis_material_tenant_insert on public.smis_material
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisMaterialInformation:Add'))
);
create policy smis_material_tenant_update on public.smis_material
for update to authenticated
using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialInformation:Edit'))
)
with check (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialInformation:Edit'))
);
create policy smis_material_tenant_delete on public.smis_material
for delete to authenticated
using (
  ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()))
  and (select app_private.has_permission('SmisMaterialInformation:Delete'))
);

revoke all on public.smis_material_category, public.smis_material from anon;
grant select, insert, update, delete on public.smis_material_category, public.smis_material to authenticated;

create or replace function public.smis_list_material_categories_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看物料类别' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisMaterialCategory:View')) then
    raise exception '当前账号没有查看物料类别的权限' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态筛选值无效' using errcode = '22023';
  end if;
  if p_ancestor_id is not null and not exists (
    select 1 from public.smis_material_category category
    where category.id = p_ancestor_id
      and (app_private.current_read_tenant_id() is null or category.tenant_id = app_private.current_read_tenant_id())
  ) then
    raise exception '所选物料类别不存在或已删除' using errcode = 'P0002';
  end if;

  return (
    with recursive subtree(id) as (
      select category.id from public.smis_material_category category
      where category.id = p_ancestor_id
        and (app_private.current_read_tenant_id() is null or category.tenant_id = app_private.current_read_tenant_id())
      union all
      select child.id from public.smis_material_category child
      join subtree parent on parent.id = child.parent_id
      where app_private.current_read_tenant_id() is null
         or child.tenant_id = app_private.current_read_tenant_id()
    ), enriched as (
      select category.*, parent.category_name as parent_category_name,
        (select count(*)::integer from public.smis_material_category child
          where child.parent_id = category.id
            and (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())) as child_count,
        (select count(*)::integer from public.smis_material material
          where material.category_id = category.id
            and (app_private.current_read_tenant_id() is null or material.tenant_id = app_private.current_read_tenant_id())) as material_count
      from public.smis_material_category category
      left join public.smis_material_category parent
        on parent.id = category.parent_id and parent.tenant_id = category.tenant_id
      where app_private.current_read_tenant_id() is null
         or category.tenant_id = app_private.current_read_tenant_id()
    ), filtered as (
      select * from enriched
      where (p_ancestor_id is null or id in (select subtree.id from subtree))
        and (p_status is null or status = p_status)
        and (
          v_keyword is null
          or lower(category_code) like '%' || v_keyword || '%'
          or lower(category_name) like '%' || v_keyword || '%'
          or lower(coalesce(description, '')) like '%' || v_keyword || '%'
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data.sort, row_data."categoryName")
        from (
          select id, tenant_id as "tenantId", parent_id as "parentId",
            parent_category_name as "parentCategoryName", category_code as "categoryCode",
            category_name as "categoryName", sort, status, description,
            child_count as "childCount", material_count as "materialCount",
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from filtered order by sort, category_name, category_code
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'tree', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id, 'tenantId', tenant_id, 'parentId', parent_id,
          'categoryCode', category_code, 'categoryName', category_name,
          'sort', sort, 'status', status, 'childCount', child_count,
          'materialCount', material_count
        ) order by sort, category_name, category_code) from enriched
      ), '[]'::jsonb),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where status = 'enabled'),
        'rootCount', count(*) filter (where parent_id is null),
        'usedCount', count(*) filter (where material_count > 0)
      ) from enriched)
    )
  );
end;
$$;

create or replace function public.smis_save_material_category_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_parent_id uuid;
  v_category_code text := upper(btrim(coalesce(p_payload->>'category_code', '')));
  v_category_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_sort integer := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_description text := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护物料类别' using errcode = '42501'; end if;
  if p_id is null and not app_private.has_permission('SmisMaterialCategory:Add') then
    raise exception '当前账号没有新增物料类别的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisMaterialCategory:Edit') then
    raise exception '当前账号没有编辑物料类别的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_material_category target where target.id = p_id
  ));
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户' using errcode = '42501'; end if;

  begin
    v_parent_id := nullif(btrim(coalesce(p_payload->>'parent_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception '上级物料类别无效' using errcode = '22023';
  end;
  if v_category_code = '' then raise exception '请输入物料类别编码' using errcode = '22023'; end if;
  if v_category_code !~ '^[A-Z][A-Z0-9_]*$' then raise exception '物料类别编码须以字母开头，仅支持字母、数字和下划线' using errcode = '22023'; end if;
  if char_length(v_category_code) > 40 then raise exception '物料类别编码不能超过 40 个字符' using errcode = '22023'; end if;
  if v_category_name = '' then raise exception '请输入物料类别名称' using errcode = '22023'; end if;
  if char_length(v_category_name) > 80 then raise exception '物料类别名称不能超过 80 个字符' using errcode = '22023'; end if;
  if char_length(coalesce(v_description, '')) > 500 then raise exception '说明不能超过 500 个字符' using errcode = '22023'; end if;
  if v_sort not between 0 and 999999 then raise exception '显示顺序须在 0 到 999999 之间' using errcode = '22023'; end if;
  if v_status not in ('enabled', 'disabled') then raise exception '启用状态无效' using errcode = '22023'; end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_material_category parent
    where parent.id = v_parent_id and parent.tenant_id = v_tenant_id
      and (p_id is not null or parent.status = 'enabled')
  ) then raise exception '上级物料类别不存在、已停用或不属于当前租户' using errcode = 'P0002'; end if;
  if p_id is not null and v_parent_id = p_id then raise exception '上级物料类别不能选择当前类别' using errcode = '22023'; end if;
  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants(id) as (
      select child.id from public.smis_material_category child
      where child.tenant_id = v_tenant_id and child.parent_id = p_id
      union all
      select child.id from public.smis_material_category child
      join descendants parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant_id
    ) select 1 from descendants where id = v_parent_id
  ) then raise exception '不能将当前类别移动到自己的下级类别中' using errcode = '22023'; end if;

  if p_id is null then
    insert into public.smis_material_category(
      tenant_id, parent_id, category_code, category_name, sort, status, description
    ) values (
      v_tenant_id, v_parent_id, v_category_code, v_category_name, v_sort, v_status, v_description
    ) returning id into v_result;
  else
    update public.smis_material_category set
      parent_id = v_parent_id, category_code = v_category_code,
      category_name = v_category_name, sort = v_sort,
      status = v_status, description = v_description
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    if v_result is null then raise exception '物料类别不存在或已删除' using errcode = 'P0002'; end if;
  end if;
  return v_result;
exception
  when unique_violation then
    raise exception '同级物料类别名称或物料类别编码已存在' using errcode = '23505';
end;
$$;

create or replace function public.smis_delete_material_categories_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除物料类别' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisMaterialCategory:Delete') then
    raise exception '当前账号没有删除物料类别的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then raise exception '请选择要删除的物料类别' using errcode = '22023'; end if;
  if exists (
    select 1 from public.smis_material_category child
    where (app_private.is_platform_super() or child.tenant_id = app_private.auth_user_tenant_id())
      and child.parent_id = any(v_ids) and not child.id = any(v_ids)
  ) then raise exception '所选物料类别仍有下级类别，请先调整或删除下级类别' using errcode = '23503'; end if;
  delete from public.smis_material_category
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
exception when foreign_key_violation then
  raise exception '物料类别已被物料信息使用，请改为停用' using errcode = '23503';
end;
$$;

create or replace function public.smis_list_materials_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_material_name text default null,
  p_material_code text default null,
  p_specification_model text default null,
  p_drawing_no text default null,
  p_category_id uuid default null,
  p_material_type text default null,
  p_material_source text default null,
  p_status text default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_material_name text := nullif(btrim(coalesce(p_material_name, '')), '');
  v_material_code text := nullif(btrim(coalesce(p_material_code, '')), '');
  v_specification_model text := nullif(btrim(coalesce(p_specification_model, '')), '');
  v_drawing_no text := nullif(btrim(coalesce(p_drawing_no, '')), '');
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看物料信息' using errcode = '42501'; end if;
  if p_purpose not in ('list', 'export') then raise exception '物料查询用途无效' using errcode = '22023'; end if;
  if p_purpose = 'export' and not app_private.has_permission('SmisMaterialInformation:Export') then
    raise exception '当前账号没有导出物料信息的权限' using errcode = '42501';
  end if;
  if p_purpose = 'list' and not (app_private.is_platform_super() or app_private.has_permission('SmisMaterialInformation:View')) then
    raise exception '当前账号没有查看物料信息的权限' using errcode = '42501';
  end if;

  return (
    with recursive category_scope(id) as (
      select category.id from public.smis_material_category category
      where category.id = p_category_id
        and (app_private.current_read_tenant_id() is null or category.tenant_id = app_private.current_read_tenant_id())
      union all
      select child.id from public.smis_material_category child
      join category_scope parent on parent.id = child.parent_id
      where app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id()
    ), filtered as (
      select material.*, category.category_code, category.category_name
      from public.smis_material material
      join public.smis_material_category category
        on category.id = material.category_id and category.tenant_id = material.tenant_id
      where (app_private.current_read_tenant_id() is null or material.tenant_id = app_private.current_read_tenant_id())
        and (p_ids is null or material.id = any(p_ids))
        and (p_category_id is null or material.category_id in (select id from category_scope))
        and (p_material_type is null or material.material_type = p_material_type)
        and (p_material_source is null or material.material_source = p_material_source)
        and (p_status is null or material.status = p_status)
        and (v_material_name is null or material.material_name ilike '%' || v_material_name || '%')
        and (v_material_code is null or material.material_code ilike '%' || v_material_code || '%')
        and (v_specification_model is null or coalesce(material.specification_model, '') ilike '%' || v_specification_model || '%')
        and (v_drawing_no is null or coalesce(material.drawing_no, '') ilike '%' || v_drawing_no || '%')
    ), category_tree as (
      select category.*,
        (select count(*)::integer from public.smis_material_category child
          where child.parent_id = category.id
            and (app_private.current_read_tenant_id() is null or child.tenant_id = app_private.current_read_tenant_id())) child_count,
        (select count(*)::integer from public.smis_material material
          where material.category_id = category.id
            and (app_private.current_read_tenant_id() is null or material.tenant_id = app_private.current_read_tenant_id())) material_count
      from public.smis_material_category category
      where app_private.current_read_tenant_id() is null or category.tenant_id = app_private.current_read_tenant_id()
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data.sort, row_data."materialName", row_data."materialCode")
        from (
          select id, tenant_id as "tenantId", category_id as "categoryId",
            material_code as "materialCode", material_name as "materialName",
            specification_model as "specificationModel", drawing_no as "drawingNo",
            basic_unit as "basicUnit", material_type as "materialType",
            material_source as "materialSource", brand,
            material_composition as "materialComposition", place_of_origin as "placeOfOrigin",
            image_urls as "imageUrls", description, status, sort,
            jsonb_build_object('id', category_id, 'categoryCode', category_code, 'categoryName', category_name) category,
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from filtered order by sort, material_name, material_code
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'categoryTree', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'tenantId', tenant_id, 'parentId', parent_id,
        'categoryCode', category_code, 'categoryName', category_name,
        'sort', sort, 'status', status, 'childCount', child_count,
        'materialCount', material_count
      ) order by sort, category_name, category_code) from category_tree), '[]'::jsonb),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where status = 'enabled'),
        'protectiveEquipment', count(*) filter (where material_type = 'protective_equipment'),
        'pictured', count(*) filter (where jsonb_array_length(image_urls) > 0)
      ) from public.smis_material material
        where app_private.current_read_tenant_id() is null or material.tenant_id = app_private.current_read_tenant_id())
    )
  );
end;
$$;

create or replace function public.smis_save_material_secure(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_category_id uuid;
  v_material_code text := upper(btrim(coalesce(p_payload->>'material_code', '')));
  v_material_name text := btrim(coalesce(p_payload->>'material_name', ''));
  v_specification_model text := nullif(btrim(coalesce(p_payload->>'specification_model', '')), '');
  v_drawing_no text := nullif(btrim(coalesce(p_payload->>'drawing_no', '')), '');
  v_basic_unit text := btrim(coalesce(p_payload->>'basic_unit', ''));
  v_material_type text := btrim(coalesce(p_payload->>'material_type', ''));
  v_material_source text := btrim(coalesce(p_payload->>'material_source', ''));
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_sort integer := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  v_image_urls jsonb := coalesce(p_payload->'image_urls', '[]'::jsonb);
  v_result uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护物料信息' using errcode = '42501'; end if;
  if p_id is null and not app_private.has_permission('SmisMaterialInformation:Add') then
    raise exception '当前账号没有新增物料信息的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisMaterialInformation:Edit') then
    raise exception '当前账号没有编辑物料信息的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_material target where target.id = p_id
  ));
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户' using errcode = '42501'; end if;
  begin
    v_category_id := nullif(btrim(coalesce(p_payload->>'category_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception '物料类别无效' using errcode = '22023';
  end;
  if v_category_id is null then raise exception '请选择物料类别' using errcode = '22023'; end if;
  if v_material_code = '' then raise exception '请输入物料编码' using errcode = '22023'; end if;
  if char_length(v_material_code) > 60 then raise exception '物料编码不能超过 60 个字符' using errcode = '22023'; end if;
  if v_material_name = '' then raise exception '请输入物料名称' using errcode = '22023'; end if;
  if char_length(v_material_name) > 120 then raise exception '物料名称不能超过 120 个字符' using errcode = '22023'; end if;
  if char_length(coalesce(v_specification_model, '')) > 120 then raise exception '规格型号不能超过 120 个字符' using errcode = '22023'; end if;
  if char_length(coalesce(v_drawing_no, '')) > 80 then raise exception '图号不能超过 80 个字符' using errcode = '22023'; end if;
  if not app_private.is_enabled_dictionary_value('smisMaterialUnit', v_basic_unit) then raise exception '基本单位无效或已停用' using errcode = '22023'; end if;
  if not app_private.is_enabled_dictionary_value('smisMaterialType', v_material_type) then raise exception '物料类型无效或已停用' using errcode = '22023'; end if;
  if not app_private.is_enabled_dictionary_value('smisMaterialSource', v_material_source) then raise exception '物料来源无效或已停用' using errcode = '22023'; end if;
  if v_status not in ('enabled', 'disabled') then raise exception '启用状态无效' using errcode = '22023'; end if;
  if v_sort not between 0 and 999999 then raise exception '显示顺序须在 0 到 999999 之间' using errcode = '22023'; end if;
  if jsonb_typeof(v_image_urls) <> 'array' then raise exception '物料图片格式无效' using errcode = '22023'; end if;
  if jsonb_array_length(v_image_urls) > 5 then raise exception '物料图片最多上传 5 张' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.smis_material_category category
    where category.id = v_category_id and category.tenant_id = v_tenant_id
      and (p_id is not null or category.status = 'enabled')
  ) then raise exception '所选物料类别不存在、已停用或不属于当前租户' using errcode = 'P0002'; end if;

  if p_id is null then
    insert into public.smis_material(
      tenant_id, category_id, material_code, material_name,
      specification_model, drawing_no, basic_unit, material_type, material_source,
      brand, material_composition, place_of_origin, image_urls,
      description, status, sort
    ) values (
      v_tenant_id, v_category_id, v_material_code, v_material_name,
      v_specification_model, v_drawing_no, v_basic_unit, v_material_type, v_material_source,
      nullif(btrim(p_payload->>'brand'), ''),
      nullif(btrim(p_payload->>'material_composition'), ''),
      nullif(btrim(p_payload->>'place_of_origin'), ''), v_image_urls,
      nullif(btrim(p_payload->>'description'), ''), v_status, v_sort
    ) returning id into v_result;
  else
    update public.smis_material set
      category_id = v_category_id, material_code = v_material_code,
      material_name = v_material_name, specification_model = v_specification_model,
      drawing_no = v_drawing_no, basic_unit = v_basic_unit,
      material_type = v_material_type, material_source = v_material_source,
      brand = nullif(btrim(p_payload->>'brand'), ''),
      material_composition = nullif(btrim(p_payload->>'material_composition'), ''),
      place_of_origin = nullif(btrim(p_payload->>'place_of_origin'), ''),
      image_urls = v_image_urls, description = nullif(btrim(p_payload->>'description'), ''),
      status = v_status, sort = v_sort
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    if v_result is null then raise exception '物料信息不存在或已删除' using errcode = 'P0002'; end if;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '物料编码已存在，请更换后重试' using errcode = '23505';
end;
$$;

create or replace function public.smis_delete_materials_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除物料信息' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisMaterialInformation:Delete') then
    raise exception '当前账号没有删除物料信息的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then raise exception '请选择要删除的物料信息' using errcode = '22023'; end if;
  delete from public.smis_material
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.smis_list_material_categories_secure(integer, integer, text, text, uuid) from public, anon;
revoke all on function public.smis_save_material_category_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_material_categories_secure(uuid[]) from public, anon;
revoke all on function public.smis_list_materials_secure(integer, integer, text, text, text, text, uuid, text, text, text, uuid[], text) from public, anon;
revoke all on function public.smis_save_material_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_materials_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_material_categories_secure(integer, integer, text, text, uuid) to authenticated;
grant execute on function public.smis_save_material_category_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_material_categories_secure(uuid[]) to authenticated;
grant execute on function public.smis_list_materials_secure(integer, integer, text, text, text, text, uuid, text, text, text, uuid[], text) to authenticated;
grant execute on function public.smis_save_material_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_materials_secure(uuid[]) to authenticated;

do $$
declare
  v_platform_tenant_id uuid;
  v_safety_root_id uuid;
  v_parent_type_id uuid;
  v_type_id uuid;
  v_menu record;
  v_button record;
begin
  select id into v_platform_tenant_id from public.sys_tenant where tenant_code = 'platform' limit 1;
  if v_platform_tenant_id is null then raise exception '平台租户不存在'; end if;

  select id into v_safety_root_id from public.sys_dict_type
  where tenant_id = v_platform_tenant_id and code = 'smisSafetyProduction' limit 1;

  select id into v_parent_type_id from public.sys_dict_type
  where tenant_id = v_platform_tenant_id and code = 'smisProtectiveEquipmentManagement' limit 1;
  if v_parent_type_id is null then
    insert into public.sys_dict_type(
      name, code, status, create_by, update_by, remark,
      tenant_id, parent_id, node_type, sort
    ) values (
      '防护用品管理', 'smisProtectiveEquipmentManagement', '1',
      '624944977@qq.com', '624944977@qq.com', '防护用品与物料主数据字典分组',
      v_platform_tenant_id, v_safety_root_id, 'directory', 80
    ) returning id into v_parent_type_id;
  end if;

  for v_menu in select * from (values
    ('smisMaterialEnableStatus', '物料启用状态', 1, '物料类别和物料信息启停状态'),
    ('smisMaterialType', '物料类型', 2, '防护用品管理物料类型'),
    ('smisMaterialSource', '物料来源', 3, '防护用品管理物料来源'),
    ('smisMaterialUnit', '计量单位', 4, '物料基本计量单位')
  ) as t(code, name, sort, remark)
  loop
    select id into v_type_id from public.sys_dict_type
    where tenant_id = v_platform_tenant_id and code = v_menu.code limit 1;
    if v_type_id is null then
      insert into public.sys_dict_type(
        name, code, status, create_by, update_by, remark,
        tenant_id, parent_id, node_type, sort
      ) values (
        v_menu.name, v_menu.code, '1', '624944977@qq.com', '624944977@qq.com',
        v_menu.remark, v_platform_tenant_id, v_parent_type_id, 'dictionary', v_menu.sort
      ) returning id into v_type_id;
    end if;

    if v_menu.code = 'smisMaterialEnableStatus' then
      insert into public.sys_dictionary(type_id, code, status, create_by, update_by, remark, value, label, i18n_scope, sort, tenant_id, tag_type)
      select v_type_id, item.code, '1', '624944977@qq.com', '624944977@qq.com', '', item.value, item.label, '1', item.sort, v_platform_tenant_id, item.tag_type
      from (values ('smisMaterialEnableStatus_enabled','enabled','启用',1::bigint,'success'),('smisMaterialEnableStatus_disabled','disabled','停用',2::bigint,'info')) item(code,value,label,sort,tag_type)
      where not exists (select 1 from public.sys_dictionary d where d.type_id = v_type_id and d.value = item.value);
    elsif v_menu.code = 'smisMaterialType' then
      insert into public.sys_dictionary(type_id, code, status, create_by, update_by, remark, value, label, i18n_scope, sort, tenant_id, tag_type)
      select v_type_id, item.code, '1', '624944977@qq.com', '624944977@qq.com', '', item.value, item.label, '1', item.sort, v_platform_tenant_id, item.tag_type
      from (values ('smisMaterialType_protective_equipment','protective_equipment','防护用品',1::bigint,'success'),('smisMaterialType_tool','tool','工器具',2::bigint,'warning'),('smisMaterialType_office_supply','office_supply','办公用品',3::bigint,'info')) item(code,value,label,sort,tag_type)
      where not exists (select 1 from public.sys_dictionary d where d.type_id = v_type_id and d.value = item.value);
    elsif v_menu.code = 'smisMaterialSource' then
      insert into public.sys_dictionary(type_id, code, status, create_by, update_by, remark, value, label, i18n_scope, sort, tenant_id, tag_type)
      select v_type_id, item.code, '1', '624944977@qq.com', '624944977@qq.com', '', item.value, item.label, '1', item.sort, v_platform_tenant_id, item.tag_type
      from (values ('smisMaterialSource_purchase','purchase','采购',1::bigint,'primary'),('smisMaterialSource_self_made','self_made','自制',2::bigint,'success')) item(code,value,label,sort,tag_type)
      where not exists (select 1 from public.sys_dictionary d where d.type_id = v_type_id and d.value = item.value);
    else
      insert into public.sys_dictionary(type_id, code, status, create_by, update_by, remark, value, label, i18n_scope, sort, tenant_id, tag_type)
      select v_type_id, 'smisMaterialUnit_' || item.value, '1', '624944977@qq.com', '624944977@qq.com', '', item.value, item.label, '1', item.sort, v_platform_tenant_id, 'info'
      from (values ('piece','个',1::bigint),('item','件',2::bigint),('set','套',3::bigint),('pair','双',4::bigint),('box','箱',5::bigint),('bottle','瓶',6::bigint),('roll','卷',7::bigint),('meter','米',8::bigint),('kg','千克',9::bigint),('unit','台',10::bigint)) item(value,label,sort)
      where not exists (select 1 from public.sys_dictionary d where d.type_id = v_type_id and d.value = item.value);
    end if;
  end loop;

  update public.sys_menu
  set meta = meta || jsonb_build_object(
    'icon', case name when 'SmisMaterialCategory' then 'ri:node-tree' else 'ri:archive-stack-line' end,
    'keep_alive', true, 'fixed_tab', false, 'is_iframe', false,
    'is_full_page', false, 'is_hide_tab', false, 'show_badge', false
  ), update_by = '624944977@qq.com', update_time = now()
  where app_code = 'smis' and name in ('SmisMaterialCategory', 'SmisMaterialInformation');

  for v_button in select * from (values
    ('SmisMaterialCategory','SmisMaterialCategory:View','查看物料类别',1),
    ('SmisMaterialCategory','SmisMaterialCategory:Add','新增物料类别',2),
    ('SmisMaterialCategory','SmisMaterialCategory:Edit','编辑物料类别',3),
    ('SmisMaterialCategory','SmisMaterialCategory:Delete','删除物料类别',4),
    ('SmisMaterialInformation','SmisMaterialInformation:View','查看物料信息',1),
    ('SmisMaterialInformation','SmisMaterialInformation:Add','新增物料信息',2),
    ('SmisMaterialInformation','SmisMaterialInformation:Edit','编辑物料信息',3),
    ('SmisMaterialInformation','SmisMaterialInformation:Delete','删除物料信息',4),
    ('SmisMaterialInformation','SmisMaterialInformation:Export','导出物料信息',5)
  ) as t(parent_name, button_name, title, sort)
  loop
    insert into public.sys_menu(
      id, name, path, component, meta, sort, create_by, update_by,
      parent_id, type, app_code
    )
    select gen_random_uuid(), v_button.button_name, '', '',
      jsonb_build_object('title', v_button.title, 'roles', jsonb_build_array(), 'is_hide', true, 'is_enable', true),
      v_button.sort, '624944977@qq.com', '624944977@qq.com', parent.id, 'button', 'smis'
    from public.sys_menu parent
    where parent.app_code = 'smis' and parent.name = v_button.parent_name
      and not exists (
        select 1 from public.sys_menu existing
        where existing.app_code = 'smis' and existing.name = v_button.button_name
      )
    order by parent.create_time limit 1;
  end loop;
end;
$$;

;
