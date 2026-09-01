begin;

alter table public.smis_qualification_catalog
  add column if not exists work_category_id uuid;

with unique_category as (
  select tenant_id, min(id::text)::uuid as category_id
  from public.smis_qualification_catalog
  where catalog_type = 'work_category'
  group by tenant_id
  having count(*) = 1
)
update public.smis_qualification_catalog item
set work_category_id = category.category_id
from unique_category category
where item.tenant_id = category.tenant_id
  and item.catalog_type = 'permitted_operation_item'
  and item.work_category_id is null;

insert into public.smis_qualification_catalog (
  tenant_id,
  catalog_type,
  parent_id,
  work_category_id,
  item_code,
  item_name,
  sort,
  status,
  remark,
  create_by,
  update_by
)
select distinct
  item.tenant_id,
  'work_category',
  null::uuid,
  null::uuid,
  'UNCATEGORIZED',
  '待分类作业',
  999999,
  'enabled',
  '由准操项目类别关系整改自动创建，请完成归类后停用或删除。',
  '624944977@qq.com',
  '624944977@qq.com'
from public.smis_qualification_catalog item
where item.catalog_type = 'permitted_operation_item'
  and item.work_category_id is null
  and not exists (
    select 1
    from public.smis_qualification_catalog category
    where category.tenant_id = item.tenant_id
      and category.catalog_type = 'work_category'
      and upper(category.item_code) = 'UNCATEGORIZED'
  );

update public.smis_qualification_catalog item
set work_category_id = category.id
from public.smis_qualification_catalog category
where item.tenant_id = category.tenant_id
  and item.catalog_type = 'permitted_operation_item'
  and item.work_category_id is null
  and category.catalog_type = 'work_category'
  and upper(category.item_code) = 'UNCATEGORIZED';

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.smis_qualification_catalog'::regclass
      and conname = 'smis_qualification_catalog_work_category_fkey'
  ) then
    alter table public.smis_qualification_catalog
      add constraint smis_qualification_catalog_work_category_fkey
      foreign key (work_category_id, tenant_id)
      references public.smis_qualification_catalog (id, tenant_id)
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.smis_qualification_catalog'::regclass
      and conname = 'smis_qualification_catalog_work_category_required_check'
  ) then
    alter table public.smis_qualification_catalog
      add constraint smis_qualification_catalog_work_category_required_check
      check (
        (
          catalog_type = 'permitted_operation_item'
          and work_category_id is not null
        )
        or (
          catalog_type <> 'permitted_operation_item'
          and work_category_id is null
        )
      ) not valid;
  end if;
end;
$migration$;

alter table public.smis_qualification_catalog
  validate constraint smis_qualification_catalog_work_category_required_check;

create index if not exists smis_qualification_catalog_work_category_idx
  on public.smis_qualification_catalog (
    tenant_id,
    work_category_id,
    parent_id,
    sort
  );

drop index if exists public.smis_qualification_catalog_sibling_name_unique;

create unique index if not exists smis_qualification_catalog_sibling_name_unique
  on public.smis_qualification_catalog (
    tenant_id,
    catalog_type,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(item_name)
  )
  where catalog_type <> 'permitted_operation_item';

create unique index if not exists smis_qualification_catalog_permitted_sibling_name_unique
  on public.smis_qualification_catalog (
    tenant_id,
    catalog_type,
    work_category_id,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(item_name)
  )
  where catalog_type = 'permitted_operation_item';

create or replace function app_private.smis_validate_qualification_catalog_relation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE'
     and old.catalog_type = 'work_category'
     and new.catalog_type <> 'work_category'
     and exists (
       select 1
       from public.smis_qualification_catalog item
       where item.tenant_id = old.tenant_id
         and item.work_category_id = old.id
     ) then
    raise exception '已被准操项目使用的作业类别不能变更数据类型'
      using errcode = '23503';
  end if;

  if tg_op = 'UPDATE'
     and old.catalog_type = 'permitted_operation_item'
     and new.work_category_id is distinct from old.work_category_id
     and exists (
       select 1
       from public.smis_qualification_catalog child
       where child.tenant_id = old.tenant_id
         and child.parent_id = old.id
     ) then
    raise exception '存在下级准操项目时不能更换作业类别'
      using errcode = '23503';
  end if;

  if new.catalog_type = 'permitted_operation_item' then
    if new.work_category_id is null then
      raise exception '请选择作业类别' using errcode = '23514';
    end if;

    if not exists (
      select 1
      from public.smis_qualification_catalog category
      where category.id = new.work_category_id
        and category.tenant_id = new.tenant_id
        and category.catalog_type = 'work_category'
    ) then
      raise exception '所选作业类别不存在或不属于当前租户' using errcode = '23503';
    end if;
  elsif new.work_category_id is not null then
    raise exception '只有准操项目可以关联作业类别' using errcode = '23514';
  end if;

  if new.parent_id is not null then
    if not exists (
      select 1
      from public.smis_qualification_catalog parent
      where parent.id = new.parent_id
        and parent.tenant_id = new.tenant_id
        and parent.catalog_type = new.catalog_type
        and (
          new.catalog_type <> 'permitted_operation_item'
          or parent.work_category_id = new.work_category_id
        )
    ) then
      raise exception '上级节点不存在、类型不一致或不属于同一作业类别' using errcode = '23503';
    end if;

    if new.parent_id = new.id or exists (
      with recursive descendants(id) as (
        select child.id
        from public.smis_qualification_catalog child
        where child.tenant_id = new.tenant_id
          and child.parent_id = new.id
        union all
        select child.id
        from public.smis_qualification_catalog child
        join descendants parent on child.parent_id = parent.id
        where child.tenant_id = new.tenant_id
      )
      select 1
      from descendants
      where id = new.parent_id
    ) then
      raise exception '不能把节点移动到自身或下级节点' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function app_private.smis_validate_qualification_catalog_relation()
  from public, anon, authenticated;

drop trigger if exists smis_qualification_catalog_relation
  on public.smis_qualification_catalog;

create trigger smis_qualification_catalog_relation
before insert or update of tenant_id, catalog_type, parent_id, work_category_id
on public.smis_qualification_catalog
for each row
execute function app_private.smis_validate_qualification_catalog_relation();

drop function if exists public.smis_list_qualification_catalog_secure(
  text,
  integer,
  integer,
  text,
  text,
  uuid,
  text
);

create function public.smis_list_qualification_catalog_secure(
  p_catalog_type text,
  p_from integer default 0,
  p_to integer default 99,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null,
  p_purpose text default 'list',
  p_work_category_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 99), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
  v_permission text := app_private.smis_catalog_permission(p_catalog_type, 'View');
  v_can_view boolean;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看安全资质基础数据' using errcode = '42501';
  end if;

  if p_purpose not in ('list', 'export', 'option') then
    raise exception '查询用途无效' using errcode = '22023';
  end if;

  if p_work_category_id is not null
     and p_catalog_type <> 'permitted_operation_item' then
    raise exception '只有准操项目支持按作业类别筛选' using errcode = '22023';
  end if;

  v_can_view := (select app_private.is_platform_super())
    or app_private.has_permission(v_permission)
    or (
      p_purpose = 'option'
      and app_private.has_permission('SmisPersonnelCertificateLedger:View')
    );

  if v_permission is null or not v_can_view then
    raise exception '当前账号没有查看该基础数据的权限' using errcode = '42501';
  end if;

  if p_purpose = 'export'
     and not app_private.has_permission(
       app_private.smis_catalog_permission(p_catalog_type, 'Export')
     ) then
    raise exception '当前账号没有导出该基础数据的权限' using errcode = '42501';
  end if;

  return (
    with recursive source as (
      select
        catalog.*,
        (
          select count(*)
          from public.smis_qualification_catalog child
          where child.tenant_id = catalog.tenant_id
            and child.parent_id = catalog.id
        )::integer as child_count,
        (
          select parent.item_name
          from public.smis_qualification_catalog parent
          where parent.id = catalog.parent_id
            and parent.tenant_id = catalog.tenant_id
        ) as parent_name,
        category.item_name as work_category_name,
        category.status as work_category_status
      from public.smis_qualification_catalog catalog
      left join public.smis_qualification_catalog category
        on category.id = catalog.work_category_id
       and category.tenant_id = catalog.tenant_id
       and category.catalog_type = 'work_category'
      where catalog.tenant_id = app_private.current_read_tenant_id()
        and catalog.catalog_type = p_catalog_type
    ), subtree as (
      select id
      from source
      where id = p_ancestor_id
      union all
      select child.id
      from source child
      join subtree parent on child.parent_id = parent.id
    ), filtered as (
      select *
      from source
      where (p_ancestor_id is null or id in (select id from subtree))
        and (p_work_category_id is null or work_category_id = p_work_category_id)
        and (p_status is null or status = p_status)
        and (
          p_purpose <> 'option'
          or p_catalog_type <> 'permitted_operation_item'
          or (status = 'enabled' and work_category_status = 'enabled')
        )
        and (
          v_keyword is null
          or lower(item_code) like '%' || v_keyword || '%'
          or lower(item_name) like '%' || v_keyword || '%'
          or lower(coalesce(remark, '')) like '%' || v_keyword || '%'
          or lower(coalesce(work_category_name, '')) like '%' || v_keyword || '%'
        )
    ), work_categories as (
      select
        category.id,
        category.tenant_id,
        category.parent_id,
        category.catalog_type,
        category.item_code,
        category.item_name,
        category.sort,
        category.status,
        category.remark,
        (
          select count(*)
          from public.smis_qualification_catalog child
          where child.tenant_id = category.tenant_id
            and child.parent_id = category.id
        )::integer as child_count
      from public.smis_qualification_catalog category
      where p_catalog_type = 'permitted_operation_item'
        and category.tenant_id = app_private.current_read_tenant_id()
        and category.catalog_type = 'work_category'
        and (p_purpose <> 'option' or category.status = 'enabled')
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(record) order by record.sort, record."itemName")
        from (
          select
            id,
            tenant_id as "tenantId",
            parent_id as "parentId",
            parent_name as "parentName",
            work_category_id as "workCategoryId",
            work_category_name as "workCategoryName",
            work_category_status as "workCategoryStatus",
            catalog_type as "catalogType",
            item_code as "itemCode",
            item_name as "itemName",
            sort,
            status,
            remark,
            child_count as "childCount",
            create_by as "createBy",
            create_time as "createTime",
            update_by as "updateBy",
            update_time as "updateTime"
          from filtered
          offset v_from
          limit v_to - v_from + 1
        ) record
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'tree', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id,
          'parentId', parent_id,
          'workCategoryId', work_category_id,
          'workCategoryName', work_category_name,
          'workCategoryStatus', work_category_status,
          'catalogType', catalog_type,
          'itemCode', item_code,
          'itemName', item_name,
          'sort', sort,
          'status', status,
          'childCount', child_count
        ) order by sort, item_name)
        from source
      ), '[]'::jsonb),
      'workCategories', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id,
          'parentId', parent_id,
          'catalogType', catalog_type,
          'itemCode', item_code,
          'itemName', item_name,
          'sort', sort,
          'status', status,
          'remark', remark,
          'childCount', child_count
        ) order by sort, item_name)
        from work_categories
      ), '[]'::jsonb),
      'overview', (
        select jsonb_build_object(
          'total', count(*),
          'enabled', count(*) filter (where status = 'enabled'),
          'disabled', count(*) filter (where status = 'disabled'),
          'rootCount', count(*) filter (where parent_id is null)
        )
        from source
      )
    )
  );
end;
$function$;

create or replace function public.smis_save_qualification_catalog_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_type text := p_payload->>'catalog_type';
  v_parent uuid;
  v_work_category uuid;
  v_existing_work_category uuid;
  v_code text := upper(btrim(coalesce(p_payload->>'item_code', '')));
  v_name text := btrim(coalesce(p_payload->>'item_name', ''));
  v_sort integer := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_result uuid;
  v_action text := case when p_id is null then 'Add' else 'Edit' end;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护安全资质基础数据' using errcode = '42501';
  end if;

  if v_type not in ('work_item', 'work_category', 'permitted_operation_item') then
    raise exception '基础数据类型无效' using errcode = '22023';
  end if;

  if not app_private.has_permission(
    app_private.smis_catalog_permission(v_type, v_action)
  ) then
    raise exception '当前账号没有维护该基础数据的权限' using errcode = '42501';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id(
    (select tenant_id from public.smis_qualification_catalog where id = p_id)
  );

  select work_category_id
  into v_existing_work_category
  from public.smis_qualification_catalog
  where id = p_id
    and tenant_id = v_tenant
    and catalog_type = v_type;

  begin
    v_parent := nullif(p_payload->>'parent_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception '上级节点无效' using errcode = '22023';
  end;

  if v_type = 'permitted_operation_item' then
    begin
      v_work_category := nullif(p_payload->>'work_category_id', '')::uuid;
    exception
      when invalid_text_representation then
        raise exception '作业类别无效' using errcode = '22023';
    end;

    if v_work_category is null then
      raise exception '请选择作业类别' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from public.smis_qualification_catalog category
      where category.id = v_work_category
        and category.tenant_id = v_tenant
        and category.catalog_type = 'work_category'
    ) then
      raise exception '所选作业类别不存在或不属于当前租户' using errcode = 'P0002';
    end if;

    if (p_id is null or v_existing_work_category is distinct from v_work_category)
       and not exists (
         select 1
         from public.smis_qualification_catalog category
         where category.id = v_work_category
           and category.tenant_id = v_tenant
           and category.catalog_type = 'work_category'
           and category.status = 'enabled'
       ) then
      raise exception '已停用的作业类别不能新增准操项目' using errcode = '22023';
    end if;

    if p_id is not null
       and v_existing_work_category is distinct from v_work_category
       and exists (
         select 1
         from public.smis_qualification_catalog child
         where child.tenant_id = v_tenant
           and child.parent_id = p_id
       ) then
      raise exception '存在下级准操项目时不能更换作业类别' using errcode = '22023';
    end if;
  else
    v_work_category := null;
  end if;

  if v_code = '' or char_length(v_code) > 50 then
    raise exception '请输入不超过 50 个字符的项目代号' using errcode = '22023';
  end if;

  if v_name = '' or char_length(v_name) > 120 then
    raise exception '请输入不超过 120 个字符的项目名称' using errcode = '22023';
  end if;

  if v_status not in ('enabled', 'disabled') then
    raise exception '启用状态无效' using errcode = '22023';
  end if;

  if v_parent is not null and not exists (
    select 1
    from public.smis_qualification_catalog parent
    where parent.id = v_parent
      and parent.tenant_id = v_tenant
      and parent.catalog_type = v_type
      and (
        v_type <> 'permitted_operation_item'
        or parent.work_category_id = v_work_category
      )
  ) then
    raise exception '上级节点不存在、类型不一致或不属于同一作业类别'
      using errcode = 'P0002';
  end if;

  if p_id is not null and (
    v_parent = p_id
    or exists (
      with recursive descendants(id) as (
        select id
        from public.smis_qualification_catalog
        where tenant_id = v_tenant
          and parent_id = p_id
        union all
        select child.id
        from public.smis_qualification_catalog child
        join descendants parent on child.parent_id = parent.id
        where child.tenant_id = v_tenant
      )
      select 1
      from descendants
      where id = v_parent
    )
  ) then
    raise exception '不能把节点移动到自身或下级节点' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_qualification_catalog (
      tenant_id,
      catalog_type,
      parent_id,
      work_category_id,
      item_code,
      item_name,
      sort,
      status,
      remark
    ) values (
      v_tenant,
      v_type,
      v_parent,
      v_work_category,
      v_code,
      v_name,
      v_sort,
      v_status,
      v_remark
    )
    returning id into v_result;
  else
    update public.smis_qualification_catalog
    set parent_id = v_parent,
        work_category_id = v_work_category,
        item_code = v_code,
        item_name = v_name,
        sort = v_sort,
        status = v_status,
        remark = v_remark
    where id = p_id
      and tenant_id = v_tenant
      and catalog_type = v_type
    returning id into v_result;

    if v_result is null then
      raise exception '基础数据不存在或已删除' using errcode = 'P0002';
    end if;
  end if;

  return v_result;
exception
  when unique_violation then
    raise exception '同类型项目代号或同级名称已存在' using errcode = '23505';
end;
$function$;

create or replace function public.smis_delete_qualification_catalog_secure(
  p_catalog_type text,
  p_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除基础数据' using errcode = '42501';
  end if;

  if not app_private.has_permission(
    app_private.smis_catalog_permission(p_catalog_type, 'Delete')
  ) then
    raise exception '当前账号没有删除该基础数据的权限' using errcode = '42501';
  end if;

  if cardinality(coalesce(p_ids, '{}'::uuid[])) = 0 then
    raise exception '请选择要删除的数据' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.smis_qualification_catalog
    where tenant_id = app_private.current_read_tenant_id()
      and parent_id = any(p_ids)
      and not id = any(p_ids)
  ) then
    raise exception '所选节点仍有下级，请先处理下级节点' using errcode = '23503';
  end if;

  delete from public.smis_qualification_catalog
  where tenant_id = app_private.current_read_tenant_id()
    and catalog_type = p_catalog_type
    and id = any(p_ids);

  get diagnostics v_count = row_count;
  return v_count;
exception
  when foreign_key_violation then
    if p_catalog_type = 'work_category' then
      raise exception '作业类别已被准操项目使用，请先调整准操项目归属'
        using errcode = '23503';
    end if;
    raise exception '项目已被证件使用，请改为停用' using errcode = '23503';
end;
$function$;

revoke all on function public.smis_list_qualification_catalog_secure(
  text,
  integer,
  integer,
  text,
  text,
  uuid,
  text,
  uuid
) from public, anon;
revoke all on function public.smis_save_qualification_catalog_secure(uuid, jsonb)
  from public, anon;
revoke all on function public.smis_delete_qualification_catalog_secure(text, uuid[])
  from public, anon;

grant execute on function public.smis_list_qualification_catalog_secure(
  text,
  integer,
  integer,
  text,
  text,
  uuid,
  text,
  uuid
) to authenticated, service_role;
grant execute on function public.smis_save_qualification_catalog_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.smis_delete_qualification_catalog_secure(text, uuid[])
  to authenticated, service_role;

with category_seed(item_code, item_name, sort) as (
  values
    ('1', '电工作业', 10),
    ('2', '焊接与热切割作业', 20),
    ('3', '高处作业', 30),
    ('4', '制冷与空调作业', 40),
    ('5', '金属非金属矿山安全作业', 50),
    ('6', '冶金（有色）生产安全作业', 60)
), target_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'public-register'
)
insert into public.smis_qualification_catalog (
  tenant_id,
  catalog_type,
  parent_id,
  work_category_id,
  item_code,
  item_name,
  sort,
  status,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  'work_category',
  null,
  null,
  seed.item_code,
  seed.item_name,
  seed.sort,
  'enabled',
  null,
  '624944977@qq.com',
  '624944977@qq.com'
from target_tenant tenant
cross join category_seed seed
where not exists (
  select 1
  from public.smis_qualification_catalog existing
  where existing.tenant_id = tenant.id
    and existing.catalog_type = 'work_category'
    and upper(existing.item_code) = upper(seed.item_code)
);

with item_seed(category_code, item_code, item_name, sort) as (
  values
    ('1', '1.1', '高压电工作业', 10),
    ('1', '1.2', '低压电工作业', 20),
    ('1', '1.3', '防爆电气作业', 30),
    ('2', '2.1', '熔化焊接与热切割作业', 10),
    ('2', '2.2', '压力焊作业', 20),
    ('2', '2.3', '钎焊作业', 30),
    ('3', '3.1', '登高架设作业', 10),
    ('3', '3.2', '高处安装、维护、拆除作业', 20),
    ('4', '4.1', '制冷与空调设备运行操作作业', 10),
    ('4', '4.2', '制冷与空调设备安装修理作业', 20),
    ('5', '5.1', '金属非金属矿井通风作业', 10),
    ('5', '5.2', '尾矿作业', 20),
    ('5', '5.3', '金属非金属矿山安全检查作业', 30),
    ('5', '5.4', '金属非金属矿山提升机操作作业', 40),
    ('5', '5.5', '金属非金属矿山支柱作业', 50),
    ('5', '5.6', '金属非金属矿山井下电气作业', 60),
    ('5', '5.7', '金属非金属矿山排水作业', 70),
    ('5', '5.8', '金属非金属矿山爆破作业', 80),
    ('6', '6.1', '煤气作业', 10)
), target_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'public-register'
)
insert into public.smis_qualification_catalog (
  tenant_id,
  catalog_type,
  parent_id,
  work_category_id,
  item_code,
  item_name,
  sort,
  status,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  'permitted_operation_item',
  null,
  category.id,
  seed.item_code,
  seed.item_name,
  seed.sort,
  'enabled',
  null,
  '624944977@qq.com',
  '624944977@qq.com'
from target_tenant tenant
join item_seed seed on true
join public.smis_qualification_catalog category
  on category.tenant_id = tenant.id
 and category.catalog_type = 'work_category'
 and upper(category.item_code) = upper(seed.category_code)
where not exists (
  select 1
  from public.smis_qualification_catalog existing
  where existing.tenant_id = tenant.id
    and existing.catalog_type = 'permitted_operation_item'
    and upper(existing.item_code) = upper(seed.item_code)
);

commit;

;
