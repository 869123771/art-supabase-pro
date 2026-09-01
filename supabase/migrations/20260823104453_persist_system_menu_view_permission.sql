do $migration$
declare
  parent_menu_id uuid;
  parent_app_code text;
  view_button_id uuid;
  matching_buttons integer;
begin
  select id, app_code
    into parent_menu_id, parent_app_code
  from public.sys_menu
  where name = 'Menu'
    and type = 'menu'
  limit 1;

  if parent_menu_id is null then
    raise exception 'System menu parent "Menu" was not found';
  end if;

  select count(*)
    into matching_buttons
  from public.sys_menu
  where name = 'System:Menu:View'
    and type = 'button';

  if matching_buttons > 1 then
    raise exception 'Duplicate System:Menu:View button permissions found';
  end if;

  select id
    into view_button_id
  from public.sys_menu
  where name = 'System:Menu:View'
    and type = 'button'
  limit 1;

  if view_button_id is null then
    insert into public.sys_menu (
      parent_id,
      name,
      path,
      component,
      type,
      app_code,
      sort,
      meta,
      create_by,
      create_time,
      update_by,
      update_time
    )
    values (
      parent_menu_id,
      'System:Menu:View',
      '',
      '',
      'button',
      parent_app_code,
      1,
      '{"icon":"","title":"查看菜单","is_enable":true,"is_auth_button":true,"roles":[]}'::jsonb,
      'codex-system-permission-reconciliation',
      now(),
      'codex-system-permission-reconciliation',
      now()
    )
    returning id into view_button_id;
  else
    update public.sys_menu
    set parent_id = parent_menu_id,
        path = '',
        component = '',
        app_code = parent_app_code,
        sort = 1,
        meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
          'title', '查看菜单',
          'is_enable', true,
          'is_auth_button', true,
          'roles', coalesce(meta -> 'roles', '[]'::jsonb)
        ),
        update_by = 'codex-system-permission-reconciliation',
        update_time = now()
    where id = view_button_id;
  end if;

  insert into public.sys_role_menu (
    role_id,
    menu_id,
    tenant_id,
    permission,
    create_by,
    create_time,
    update_by,
    update_time
  )
  select
    parent_grant.role_id,
    view_button_id,
    coalesce(parent_grant.tenant_id, role.tenant_id),
    '{}'::jsonb,
    'codex-system-permission-reconciliation',
    now(),
    'codex-system-permission-reconciliation',
    now()
  from public.sys_role_menu as parent_grant
  join public.sys_role as role on role.id = parent_grant.role_id
  where parent_grant.menu_id = parent_menu_id
  on conflict (role_id, menu_id) do nothing;
end
$migration$;;
