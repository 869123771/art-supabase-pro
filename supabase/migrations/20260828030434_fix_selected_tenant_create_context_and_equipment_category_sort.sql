create or replace function app_private.resolve_mutation_tenant_id(p_target_tenant_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_tenant_id uuid := app_private.auth_user_tenant_id();
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护租户数据' using errcode = '42501';
  end if;
  if v_actor_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    return coalesce(
      p_target_tenant_id,
      app_private.current_user_tenant_id(),
      v_actor_tenant_id
    );
  end if;

  return v_actor_tenant_id;
end;
$$;

revoke all on function app_private.resolve_mutation_tenant_id(uuid) from public, anon;
grant execute on function app_private.resolve_mutation_tenant_id(uuid) to authenticated, service_role;

comment on function app_private.resolve_mutation_tenant_id(uuid) is
  'Platform super mutations target an existing row tenant or the explicitly selected tenant; all-tenant creates and ordinary users fall back to the authenticated actor tenant.';

do $$
declare
  v_function_oid oid;
  v_definition text;
begin
  select procedure.oid into v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'smis_save_storage_location_secure'
    and pg_get_function_identity_arguments(procedure.oid) = 'p_id uuid, p_payload jsonb';

  if v_function_oid is null then
    raise exception 'Required RPC smis_save_storage_location_secure(uuid,jsonb) was not found';
  end if;

  v_definition := pg_get_functiondef(v_function_oid);
  v_definition := replace(
    v_definition,
    'v_tenant_id := v_actor_tenant_id;',
    'v_tenant_id := app_private.resolve_mutation_tenant_id(null);'
  );

  if v_definition not like '%v_tenant_id := app_private.resolve_mutation_tenant_id(null);%' then
    raise exception 'Storage-location create tenant resolver patch was not applied';
  end if;

  execute v_definition;
end;
$$;

alter table public.smis_equipment_category
  add column if not exists sort integer not null default 0;

with ranked as (
  select
    id,
    row_number() over (
      partition by tenant_id, parent_id
      order by sort, create_time, category_name, category_code, id
    ) * 10 as normalized_sort
  from public.smis_equipment_category
)
update public.smis_equipment_category category
set sort = ranked.normalized_sort
from ranked
where ranked.id = category.id
  and category.sort is distinct from ranked.normalized_sort;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.smis_equipment_category'::regclass
      and conname = 'smis_equipment_category_sort_range_check'
  ) then
    alter table public.smis_equipment_category
      add constraint smis_equipment_category_sort_range_check
      check (sort between 0 and 999999);
  end if;
end;
$$;

create index if not exists idx_smis_equipment_category_sibling_sort
  on public.smis_equipment_category(tenant_id, parent_id, sort, category_name, category_code);

do $$
declare
  v_function_oid oid;
  v_definition text;
begin
  select procedure.oid into v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'smis_save_equipment_category_secure'
    and pg_get_function_identity_arguments(procedure.oid) = 'p_id uuid, p_payload jsonb';

  if v_function_oid is null then
    raise exception 'Required RPC smis_save_equipment_category_secure(uuid,jsonb) was not found';
  end if;

  v_definition := pg_get_functiondef(v_function_oid);
  if v_definition not like '%v_sort integer%' then
    v_definition := replace(
      v_definition,
      'v_status text := btrim(coalesce(p_payload->>''status'', ''enabled''));',
      'v_status text := btrim(coalesce(p_payload->>''status'', ''enabled''));' || chr(10) ||
      '  v_sort integer := coalesce(nullif(p_payload->>''sort'', '''')::integer, 0);'
    );
    v_definition := replace(
      v_definition,
      'if v_status not in (''enabled'', ''disabled'') then' || chr(10) ||
      '    raise exception ''启用状态无效'' using errcode = ''22023'';' || chr(10) ||
      '  end if;',
      'if v_status not in (''enabled'', ''disabled'') then' || chr(10) ||
      '    raise exception ''启用状态无效'' using errcode = ''22023'';' || chr(10) ||
      '  end if;' || chr(10) ||
      '  if v_sort < 0 or v_sort > 999999 then' || chr(10) ||
      '    raise exception ''排序须在 0 到 999999 之间'' using errcode = ''22023'';' || chr(10) ||
      '  end if;'
    );
    v_definition := replace(
      v_definition,
      'category_short_name, remark, status' || chr(10) ||
      '    ) values (',
      'category_short_name, remark, status, sort' || chr(10) ||
      '    ) values ('
    );
    v_definition := replace(
      v_definition,
      'v_category_short_name, v_remark, v_status' || chr(10) ||
      '    ) returning id into v_id;',
      'v_category_short_name, v_remark, v_status, v_sort' || chr(10) ||
      '    ) returning id into v_id;'
    );
    v_definition := replace(
      v_definition,
      'remark = v_remark,' || chr(10) ||
      '        status = v_status',
      'remark = v_remark,' || chr(10) ||
      '        status = v_status,' || chr(10) ||
      '        sort = v_sort'
    );
  end if;

  if v_definition not like '%sort = v_sort%' or v_definition not like '%v_status, v_sort%' then
    raise exception 'Equipment-category save sort patch was not applied';
  end if;

  execute v_definition;
end;
$$;

do $$
declare
  v_function_oid oid;
  v_definition text;
begin
  select procedure.oid into v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'smis_list_equipment_categories_secure'
    and pg_get_function_identity_arguments(procedure.oid) =
      'p_from integer, p_to integer, p_keyword text, p_status text, p_ancestor_id uuid';

  if v_function_oid is null then
    raise exception 'Required RPC smis_list_equipment_categories_secure was not found';
  end if;

  v_definition := pg_get_functiondef(v_function_oid);
  if v_definition not like '%category.sort,%' then
    v_definition := replace(
      v_definition,
      'category.id,' || chr(10) || '        category.parent_id,',
      'category.id,' || chr(10) || '        category.tenant_id,' || chr(10) ||
      '        category.parent_id,'
    );
    v_definition := replace(
      v_definition,
      'category.status,' || chr(10) || '        category.create_by,',
      'category.status,' || chr(10) || '        category.sort,' || chr(10) ||
      '        category.create_by,'
    );
    v_definition := replace(
      v_definition,
      'filtered.id,' || chr(10) || '            filtered.parent_id as "parentId",',
      'filtered.id,' || chr(10) || '            filtered.tenant_id as "tenantId",' || chr(10) ||
      '            filtered.parent_id as "parentId",'
    );
    v_definition := replace(
      v_definition,
      'filtered.status,' || chr(10) || '            filtered.child_count as "childCount",',
      'filtered.status,' || chr(10) || '            filtered.sort,' || chr(10) ||
      '            filtered.child_count as "childCount",'
    );
    v_definition := replace(
      v_definition,
      '''id'', enriched.id,' || chr(10) || '            ''parentId'', enriched.parent_id,',
      '''id'', enriched.id,' || chr(10) || '            ''tenantId'', enriched.tenant_id,' || chr(10) ||
      '            ''parentId'', enriched.parent_id,'
    );
    v_definition := replace(
      v_definition,
      '''status'', enriched.status,' || chr(10) || '            ''childCount'', enriched.child_count',
      '''status'', enriched.status,' || chr(10) || '            ''sort'', enriched.sort,' || chr(10) ||
      '            ''childCount'', enriched.child_count'
    );
    v_definition := replace(
      v_definition,
      '''id'', inspection.id,' || chr(10) || '            ''categoryCode'', inspection.category_code,',
      '''id'', inspection.id,' || chr(10) || '            ''tenantId'', inspection.tenant_id,' || chr(10) ||
      '            ''categoryCode'', inspection.category_code,'
    );
    v_definition := replace(
      v_definition,
      'order by record_row."categoryName", record_row."categoryCode"',
      'order by record_row.sort, record_row."categoryName", record_row."categoryCode"'
    );
    v_definition := replace(
      v_definition,
      'order by filtered.category_name, filtered.category_code',
      'order by filtered.sort, filtered.category_name, filtered.category_code'
    );
    v_definition := replace(
      v_definition,
      'order by enriched.category_name, enriched.category_code',
      'order by enriched.sort, enriched.category_name, enriched.category_code'
    );
  end if;

  if v_definition not like '%"tenantId"%' or v_definition not like '%filtered.sort%' then
    raise exception 'Equipment-category list tenant/sort patch was not applied';
  end if;

  execute v_definition;
end;
$$;

create or replace function public.smis_move_equipment_category_secure(
  p_id uuid,
  p_direction text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_tenant_id uuid := app_private.auth_user_tenant_id();
  v_tenant_id uuid;
  v_parent_id uuid;
  v_target_sort integer;
  v_neighbor_id uuid;
  v_neighbor_sort integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再调整设备分类排序' using errcode = '42501';
  end if;
  if not (
    app_private.is_platform_super()
    or app_private.has_permission('SmisEquipmentCategory:Edit')
  ) then
    raise exception '当前账号没有编辑设备分类的权限' using errcode = '42501';
  end if;
  if p_direction not in ('up', 'down') then
    raise exception '排序方向无效' using errcode = '22023';
  end if;

  select category.tenant_id, category.parent_id
  into v_tenant_id, v_parent_id
  from public.smis_equipment_category category
  where category.id = p_id
    and (app_private.is_platform_super() or category.tenant_id = v_actor_tenant_id)
  for update;

  if not found then
    raise exception '设备分类不存在或无权访问' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':' || coalesce(v_parent_id::text, 'root'), 0)
  );

  with ordered as (
    select
      category.id,
      row_number() over (
        order by category.sort, category.category_name, category.category_code, category.id
      ) * 10 as normalized_sort
    from public.smis_equipment_category category
    where category.tenant_id = v_tenant_id
      and category.parent_id is not distinct from v_parent_id
  )
  update public.smis_equipment_category category
  set sort = ordered.normalized_sort
  from ordered
  where ordered.id = category.id
    and category.sort is distinct from ordered.normalized_sort;

  select category.sort into v_target_sort
  from public.smis_equipment_category category
  where category.id = p_id;

  if p_direction = 'up' then
    select category.id, category.sort
    into v_neighbor_id, v_neighbor_sort
    from public.smis_equipment_category category
    where category.tenant_id = v_tenant_id
      and category.parent_id is not distinct from v_parent_id
      and category.sort < v_target_sort
    order by category.sort desc, category.id desc
    limit 1;
  else
    select category.id, category.sort
    into v_neighbor_id, v_neighbor_sort
    from public.smis_equipment_category category
    where category.tenant_id = v_tenant_id
      and category.parent_id is not distinct from v_parent_id
      and category.sort > v_target_sort
    order by category.sort, category.id
    limit 1;
  end if;

  if v_neighbor_id is null then
    return false;
  end if;

  update public.smis_equipment_category category
  set sort = case
    when category.id = p_id then v_neighbor_sort
    else v_target_sort
  end
  where category.id in (p_id, v_neighbor_id);

  return true;
end;
$$;

revoke all on function public.smis_move_equipment_category_secure(uuid, text)
  from public, anon;
grant execute on function public.smis_move_equipment_category_secure(uuid, text)
  to authenticated, service_role;

comment on function public.smis_move_equipment_category_secure(uuid, text) is
  'Moves one equipment category up or down within the same tenant and parent sibling group.';

;
