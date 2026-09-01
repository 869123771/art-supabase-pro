create or replace function public.save_menu_tree_order(p_updates jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  item jsonb;
  target_id uuid;
  target_parent_id uuid;
  target_sort integer;
  current_parent_id uuid;
  current_sort integer;
  affected_rows integer;
  expected_rows integer;
begin
  if jsonb_typeof(p_updates) <> 'array' then
    raise exception '菜单树排序参数必须是数组';
  end if;

  select count(*) into expected_rows from public.sys_menu;

  if jsonb_array_length(p_updates) <> expected_rows then
    raise exception '菜单树排序必须提交完整节点，期望 % 个，实际 % 个',
      expected_rows, jsonb_array_length(p_updates);
  end if;

  if (
    select count(*)
    from jsonb_array_elements(p_updates) value
  ) <> (
    select count(distinct value->>'id')
    from jsonb_array_elements(p_updates) value
  ) then
    raise exception '菜单树排序包含重复节点';
  end if;

  for item in
    select value
    from jsonb_array_elements(p_updates)
  loop
    target_id := (item->>'id')::uuid;
    target_parent_id := nullif(item->>'parentId', '')::uuid;
    target_sort := (item->>'sort')::integer;

    if target_sort is null or target_sort < 1 then
      raise exception '菜单排序必须大于等于 1: %', item->>'id';
    end if;

    if target_parent_id = target_id then
      raise exception '菜单不能成为自己的父级: %', item->>'id';
    end if;

    select parent_id, sort
      into current_parent_id, current_sort
    from public.sys_menu
    where id = target_id;

    if not found then
      raise exception '菜单节点不存在: %', item->>'id';
    end if;

    if current_parent_id is distinct from target_parent_id
       or current_sort is distinct from target_sort then
      update public.sys_menu
      set
        parent_id = target_parent_id,
        sort = target_sort
      where id = target_id;

      get diagnostics affected_rows = row_count;
      if affected_rows <> 1 then
        raise exception '当前账号没有菜单排序权限: %', item->>'id';
      end if;
    end if;
  end loop;

  if exists (
    select 1
    from public.sys_menu child
    left join public.sys_menu parent on parent.id = child.parent_id
    where child.parent_id is not null
      and parent.id is null
  ) then
    raise exception '菜单树包含不存在的父级节点';
  end if;

  if exists (
    with recursive ancestry as (
      select
        menu.id,
        menu.parent_id,
        array[menu.id] as path,
        false as cycle
      from public.sys_menu menu

      union all

      select
        ancestry.id,
        parent.parent_id,
        ancestry.path || parent.id,
        parent.id = any(ancestry.path)
      from ancestry
      join public.sys_menu parent on parent.id = ancestry.parent_id
      where not ancestry.cycle
    )
    select 1
    from ancestry
    where cycle
  ) then
    raise exception '菜单树不能形成循环层级';
  end if;

  if exists (
    select 1
    from public.sys_menu
    group by parent_id, sort
    having count(*) > 1
  ) then
    raise exception '同一父级下存在重复排序值';
  end if;
end
$function$;

revoke execute on function public.save_menu_tree_order(jsonb) from public;
revoke execute on function public.save_menu_tree_order(jsonb) from anon;
grant execute on function public.save_menu_tree_order(jsonb) to authenticated;

comment on function public.save_menu_tree_order(jsonb) is
  'Atomically persists the complete menu tree parent and sibling order under caller RLS permissions.';;
