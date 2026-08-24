do $$
declare
  target_menu_ids uuid[];
begin
  select coalesce(array_agg(target.id), '{}'::uuid[])
  into target_menu_ids
  from (
    with recursive workflow_analytics_menu as (
      select id
      from public.sys_menu
      where name = 'WorkflowAnalytics'
        or (path = 'analytics' and component = '/workflow/analytics')

      union all

      select child.id
      from public.sys_menu child
      join workflow_analytics_menu parent on child.parent_id = parent.id
    )
    select distinct id
    from workflow_analytics_menu
  ) target;

  if cardinality(target_menu_ids) = 0 then
    return;
  end if;

  if exists (
    select 1
    from public.sys_document_number_scene
    where menu_id = any(target_menu_ids)
  ) then
    raise exception 'Cannot remove WorkflowAnalytics menus while document-number scenes still reference them';
  end if;

  delete from public.sys_role_menu
  where menu_id = any(target_menu_ids);

  delete from public.sys_menu
  where id = any(target_menu_ids);
end
$$;
