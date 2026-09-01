create table public.smis_equipment_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  category_code text not null,
  category_name text not null,
  category_short_name text,
  remark text,
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_category_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_category_id_tenant_unique unique (id, tenant_id),
  constraint smis_equipment_category_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_equipment_category(id, tenant_id) on delete restrict,
  constraint smis_equipment_category_not_self_parent check (parent_id is null or parent_id <> id),
  constraint smis_equipment_category_code_not_blank check (btrim(category_code) <> ''),
  constraint smis_equipment_category_name_not_blank check (btrim(category_name) <> ''),
  constraint smis_equipment_category_code_length check (char_length(category_code) <= 40),
  constraint smis_equipment_category_name_length check (char_length(category_name) <= 80),
  constraint smis_equipment_category_short_name_length check (
    category_short_name is null or char_length(category_short_name) <= 40
  ),
  constraint smis_equipment_category_remark_length check (
    remark is null or char_length(remark) <= 500
  ),
  constraint smis_equipment_category_status_check check (status in ('enabled', 'disabled'))
);

comment on table public.smis_equipment_category is
  '共享设备台账主数据：租户级树形设备分类';
comment on column public.smis_equipment_category.parent_id is
  '同租户上级设备分类，为空表示根分类';
comment on column public.smis_equipment_category.category_short_name is
  '设备分类在紧凑列表、标签等场景使用的简称';

create unique index smis_equipment_category_code_unique
  on public.smis_equipment_category(tenant_id, lower(btrim(category_code)));
create unique index smis_equipment_category_name_unique
  on public.smis_equipment_category(tenant_id, lower(btrim(category_name)));
create index smis_equipment_category_parent_idx
  on public.smis_equipment_category(tenant_id, parent_id, status, category_name);
create index smis_equipment_category_status_idx
  on public.smis_equipment_category(tenant_id, status, category_name);

create table public.smis_equipment_category_inspection (
  equipment_category_id uuid not null,
  inspection_category_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_category_inspection_pkey primary key (
    equipment_category_id, inspection_category_id
  ),
  constraint smis_equipment_category_inspection_equipment_fkey
    foreign key (equipment_category_id, tenant_id)
    references public.smis_equipment_category(id, tenant_id) on delete cascade,
  constraint smis_equipment_category_inspection_inspection_fkey
    foreign key (inspection_category_id, tenant_id)
    references public.smis_inspection_category(id, tenant_id) on delete restrict
);

comment on table public.smis_equipment_category_inspection is
  '设备分类与适用检验类别的租户级多对多关系';

create index smis_equipment_category_inspection_tenant_idx
  on public.smis_equipment_category_inspection(tenant_id, inspection_category_id);

create trigger smis_equipment_category_create_audit
before insert on public.smis_equipment_category
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger smis_equipment_category_update_audit
before update on public.smis_equipment_category
for each row execute function public.trg_set_update_time_and_by();

create trigger smis_equipment_category_inspection_create_audit
before insert on public.smis_equipment_category_inspection
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger smis_equipment_category_inspection_update_audit
before update on public.smis_equipment_category_inspection
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_equipment_category enable row level security;
alter table public.smis_equipment_category_inspection enable row level security;

create policy smis_equipment_category_select
on public.smis_equipment_category for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentCategory:View'))
  )
);

create policy smis_equipment_category_insert
on public.smis_equipment_category for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentCategory:Add'))
);

create policy smis_equipment_category_update
on public.smis_equipment_category for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentCategory:Edit'))
  )
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentCategory:Edit'))
);

create policy smis_equipment_category_delete
on public.smis_equipment_category for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentCategory:Delete'))
  )
);

create policy smis_equipment_category_inspection_select
on public.smis_equipment_category_inspection for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentCategory:View'))
  )
);

create policy smis_equipment_category_inspection_insert
on public.smis_equipment_category_inspection for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisEquipmentCategory:Add'))
    or (select app_private.has_permission('SmisEquipmentCategory:Edit'))
  )
);

create policy smis_equipment_category_inspection_update
on public.smis_equipment_category_inspection for update to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentCategory:Edit'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentCategory:Edit'))
);

create policy smis_equipment_category_inspection_delete
on public.smis_equipment_category_inspection for delete to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisEquipmentCategory:Edit'))
    or (select app_private.has_permission('SmisEquipmentCategory:Delete'))
  )
);

revoke all on table public.smis_equipment_category from public, anon, authenticated;
revoke all on table public.smis_equipment_category_inspection from public, anon, authenticated;
grant all on table public.smis_equipment_category to service_role;
grant all on table public.smis_equipment_category_inspection to service_role;

create or replace function public.smis_list_equipment_categories_secure(
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
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if not (
    app_private.is_platform_super()
    or app_private.has_permission('SmisEquipmentCategory:View')
  ) then
    raise exception '当前账号没有查看设备分类的权限' using errcode = '42501';
  end if;

  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态筛选值无效' using errcode = '22023';
  end if;

  if p_ancestor_id is not null and not exists (
    select 1 from public.smis_equipment_category category
    where category.id = p_ancestor_id and category.tenant_id = v_tenant_id
  ) then
    raise exception '所选设备分类节点不存在或已删除' using errcode = 'P0002';
  end if;

  return (
    with recursive subtree(id) as (
      select category.id
      from public.smis_equipment_category category
      where category.tenant_id = v_tenant_id and category.id = p_ancestor_id
      union all
      select child.id
      from public.smis_equipment_category child
      join subtree parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant_id
    ), enriched as (
      select
        category.id,
        category.parent_id,
        category.category_code,
        category.category_name,
        category.category_short_name,
        category.remark,
        category.status,
        category.create_by,
        category.create_time,
        category.update_by,
        category.update_time,
        parent.category_name as parent_category_name,
        (
          select count(*)::integer
          from public.smis_equipment_category child
          where child.tenant_id = v_tenant_id and child.parent_id = category.id
        ) as child_count,
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', inspection.id,
              'categoryCode', inspection.category_code,
              'categoryName', inspection.category_name,
              'status', inspection.status
            ) order by inspection.category_name, inspection.category_code
          )
          from public.smis_equipment_category_inspection relation
          join public.smis_inspection_category inspection
            on inspection.id = relation.inspection_category_id
           and inspection.tenant_id = relation.tenant_id
          where relation.tenant_id = v_tenant_id
            and relation.equipment_category_id = category.id
        ), '[]'::jsonb) as inspection_categories
      from public.smis_equipment_category category
      left join public.smis_equipment_category parent
        on parent.id = category.parent_id and parent.tenant_id = category.tenant_id
      where category.tenant_id = v_tenant_id
    ), filtered as (
      select enriched.*
      from enriched
      where (p_ancestor_id is null or enriched.id in (select subtree.id from subtree))
        and (p_status is null or enriched.status = p_status)
        and (
          v_keyword is null
          or lower(enriched.category_code) like '%' || v_keyword || '%'
          or lower(enriched.category_name) like '%' || v_keyword || '%'
          or lower(coalesce(enriched.category_short_name, '')) like '%' || v_keyword || '%'
          or lower(coalesce(enriched.remark, '')) like '%' || v_keyword || '%'
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(record_row) order by record_row."categoryName", record_row."categoryCode")
        from (
          select
            filtered.id,
            filtered.parent_id as "parentId",
            filtered.parent_category_name as "parentCategoryName",
            filtered.category_code as "categoryCode",
            filtered.category_name as "categoryName",
            filtered.category_short_name as "categoryShortName",
            filtered.remark,
            filtered.status,
            filtered.child_count as "childCount",
            filtered.inspection_categories as "inspectionCategories",
            filtered.create_by as "createBy",
            filtered.create_time as "createTime",
            filtered.update_by as "updateBy",
            filtered.update_time as "updateTime"
          from filtered
          order by filtered.category_name, filtered.category_code
          offset v_from
          limit v_to - v_from + 1
        ) record_row
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'tree', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', enriched.id,
            'parentId', enriched.parent_id,
            'categoryCode', enriched.category_code,
            'categoryName', enriched.category_name,
            'categoryShortName', enriched.category_short_name,
            'status', enriched.status,
            'childCount', enriched.child_count
          ) order by enriched.category_name, enriched.category_code
        )
        from enriched
      ), '[]'::jsonb),
      'inspectionOptions', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', inspection.id,
            'categoryCode', inspection.category_code,
            'categoryName', inspection.category_name,
            'status', inspection.status
          ) order by inspection.status, inspection.category_name, inspection.category_code
        )
        from public.smis_inspection_category inspection
        where inspection.tenant_id = v_tenant_id
      ), '[]'::jsonb),
      'overview', (
        select jsonb_build_object(
          'total', count(*),
          'enabled', count(*) filter (where enriched.status = 'enabled'),
          'rootCount', count(*) filter (where enriched.parent_id is null),
          'linkedCount', count(*) filter (
            where jsonb_array_length(enriched.inspection_categories) > 0
          )
        )
        from enriched
      )
    )
  );
end;
$function$;

create or replace function public.smis_save_equipment_category_secure(
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
  v_parent_id uuid;
  v_category_code text := upper(btrim(coalesce(p_payload->>'category_code', '')));
  v_category_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_category_short_name text := nullif(btrim(coalesce(p_payload->>'category_short_name', '')), '');
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_status text := btrim(coalesce(p_payload->>'status', 'enabled'));
  v_inspection_ids uuid[] := array[]::uuid[];
  v_invalid_inspection_count integer;
begin
  if p_id is null and not app_private.has_permission('SmisEquipmentCategory:Add') then
    raise exception '当前账号没有新增设备分类的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisEquipmentCategory:Edit') then
    raise exception '当前账号没有编辑设备分类的权限' using errcode = '42501';
  end if;
  if v_category_code = '' then
    raise exception '请输入设备分类编码' using errcode = '22023';
  end if;
  if v_category_code !~ '^[A-Z][A-Z0-9_]{0,39}$' then
    raise exception '设备分类编码须以字母开头，仅支持大写字母、数字和下划线' using errcode = '22023';
  end if;
  if v_category_name = '' then
    raise exception '请输入设备分类名称' using errcode = '22023';
  end if;
  if char_length(v_category_name) > 80 then
    raise exception '设备分类名称不能超过 80 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_category_short_name, '')) > 40 then
    raise exception '设备分类简称不能超过 40 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 500 then
    raise exception '备注不能超过 500 个字符' using errcode = '22023';
  end if;
  if v_status not in ('enabled', 'disabled') then
    raise exception '启用状态无效' using errcode = '22023';
  end if;

  begin
    v_parent_id := nullif(btrim(coalesce(p_payload->>'parent_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception '上级设备分类无效' using errcode = '22023';
  end;

  if coalesce(jsonb_typeof(p_payload->'inspection_category_ids'), 'array') <> 'array' then
    raise exception '适用检验类别格式无效' using errcode = '22023';
  end if;

  begin
    select coalesce(array_agg(distinct item.value::uuid), array[]::uuid[])
    into v_inspection_ids
    from jsonb_array_elements_text(
      coalesce(p_payload->'inspection_category_ids', '[]'::jsonb)
    ) item(value);
  exception when invalid_text_representation then
    raise exception '适用检验类别包含无效数据' using errcode = '22023';
  end;

  if v_parent_id is not null and not exists (
    select 1 from public.smis_equipment_category parent
    where parent.id = v_parent_id and parent.tenant_id = v_tenant_id
  ) then
    raise exception '上级设备分类不存在或已删除' using errcode = 'P0002';
  end if;

  if p_id is not null and v_parent_id = p_id then
    raise exception '上级设备分类不能选择当前分类' using errcode = '22023';
  end if;

  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants(id) as (
      select child.id
      from public.smis_equipment_category child
      where child.tenant_id = v_tenant_id and child.parent_id = p_id
      union all
      select child.id
      from public.smis_equipment_category child
      join descendants parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant_id
    )
    select 1 from descendants where id = v_parent_id
  ) then
    raise exception '不能将当前分类移动到自己的下级分类中' using errcode = '22023';
  end if;

  select count(*) into v_invalid_inspection_count
  from unnest(v_inspection_ids) requested(id)
  where not exists (
    select 1 from public.smis_inspection_category inspection
    where inspection.id = requested.id and inspection.tenant_id = v_tenant_id
  );
  if v_invalid_inspection_count > 0 then
    raise exception '适用检验类别不存在或不属于当前租户' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_equipment_category(
      tenant_id, parent_id, category_code, category_name,
      category_short_name, remark, status
    ) values (
      v_tenant_id, v_parent_id, v_category_code, v_category_name,
      v_category_short_name, v_remark, v_status
    ) returning id into v_id;
  else
    update public.smis_equipment_category
    set parent_id = v_parent_id,
        category_code = v_category_code,
        category_name = v_category_name,
        category_short_name = v_category_short_name,
        remark = v_remark,
        status = v_status
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_id;

    if v_id is null then
      raise exception '设备分类不存在或已删除' using errcode = 'P0002';
    end if;

    delete from public.smis_equipment_category_inspection
    where tenant_id = v_tenant_id and equipment_category_id = v_id;
  end if;

  insert into public.smis_equipment_category_inspection(
    equipment_category_id, inspection_category_id, tenant_id
  )
  select v_id, inspection_id, v_tenant_id
  from unnest(v_inspection_ids) inspection_id;

  return v_id;
exception
  when unique_violation then
    raise exception '设备分类编码或名称已存在，请更换后重试' using errcode = '23505';
end;
$function$;

create or replace function public.smis_delete_equipment_categories_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if not app_private.has_permission('SmisEquipmentCategory:Delete') then
    raise exception '当前账号没有删除设备分类的权限' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.smis_equipment_category child
    where child.tenant_id = app_private.current_user_tenant_id()
      and child.parent_id = any(v_ids)
      and not child.id = any(v_ids)
  ) then
    raise exception '所选设备分类仍有下级分类，请先调整或删除下级分类' using errcode = '23503';
  end if;

  delete from public.smis_equipment_category
  where tenant_id = app_private.current_user_tenant_id() and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
exception
  when foreign_key_violation then
    raise exception '设备分类已被设备台账或其他业务记录使用，请改为停用' using errcode = '23503';
end;
$function$;

revoke all on function public.smis_list_equipment_categories_secure(integer, integer, text, text, uuid)
  from public, anon;
revoke all on function public.smis_save_equipment_category_secure(uuid, jsonb)
  from public, anon;
revoke all on function public.smis_delete_equipment_categories_secure(uuid[])
  from public, anon;
grant execute on function public.smis_list_equipment_categories_secure(integer, integer, text, text, uuid)
  to authenticated, service_role;
grant execute on function public.smis_save_equipment_category_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.smis_delete_equipment_categories_secure(uuid[])
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), '设备分类启用状态', 'smisEquipmentCategoryStatus', '1',
  '624944977@qq.com', '624944977@qq.com', '设备分类启停状态',
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1),
  'dictionary', 1
from platform_tenant
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
), items(value, label, sort, tag_type) as (values
  ('enabled', '启用', 1, 'success'),
  ('disabled', '停用', 2, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id,
  'smisEquipmentCategoryStatus_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '设备分类启停状态字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type
  on dictionary_type.code = 'smisEquipmentCategoryStatus'
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'a1530000-0000-4000-8000-000000000013'::uuid,
  seed.name, '', '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ), seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8130-000000000001'::uuid, 'SmisEquipmentCategory:View', '查看设备分类', 1),
  ('a1530000-0000-4000-8130-000000000002'::uuid, 'SmisEquipmentCategory:Add', '新增设备分类', 2),
  ('a1530000-0000-4000-8130-000000000003'::uuid, 'SmisEquipmentCategory:Edit', '编辑设备分类', 3),
  ('a1530000-0000-4000-8130-000000000004'::uuid, 'SmisEquipmentCategory:Delete', '删除设备分类', 4)
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
  ('a1530000-0000-4000-8130-000000000001'::uuid),
  ('a1530000-0000-4000-8130-000000000002'::uuid),
  ('a1530000-0000-4000-8130-000000000003'::uuid),
  ('a1530000-0000-4000-8130-000000000004'::uuid)
) button(id)
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000013'::uuid
on conflict (role_id, menu_id) do nothing;

;
