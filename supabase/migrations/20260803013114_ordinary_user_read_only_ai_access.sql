-- AI capabilities are available to authenticated users, while database and
-- configuration writes remain restricted to the platform super administrator.

update public.sys_menu
set
  meta = jsonb_set(coalesce(meta, '{}'::jsonb), '{roles}', '[]'::jsonb, true),
  update_by = '624944977@qq.com',
  update_time = now()
where id = '62d9775f-3881-4878-83d8-be264908dd89';

insert into public.sys_role_menu (
  role_id,
  menu_id,
  permission,
  tenant_id,
  create_by,
  update_by
)
select
  role.id,
  menu.id,
  '{}'::jsonb,
  role.tenant_id,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role as role
cross join public.sys_menu as menu
where role.enabled
  and upper(role.role_code) <> 'R_SUPER'
  and menu.id in (
    '2d1fdeb6-b0e3-4b77-8968-923c7f59051f',
    '62d9775f-3881-4878-83d8-be264908dd89'
  )
on conflict (role_id, menu_id) do nothing;

drop policy if exists tenant_insert on public.ai_feature_config;
create policy tenant_insert
on public.ai_feature_config
for insert
to authenticated
with check ((select app_private.is_platform_super()));

drop policy if exists tenant_update on public.ai_feature_config;
create policy tenant_update
on public.ai_feature_config
for update
to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));

alter function public.ai_operations_overview(integer) security definer;
revoke all on function public.ai_operations_overview(integer) from public, anon;
grant execute on function public.ai_operations_overview(integer) to authenticated, service_role;

do $migration$
declare
  function_definition text;
  old_guard text := E'  if not public.current_is_super() then\n    raise exception ''Platform super administrator permission is required''\n      using errcode = ''42501'';\n  end if;';
  new_guard text := E'  if (select auth.uid()) is null or not exists (\n    select 1\n    from public.sys_user as app_user\n    where app_user.auth_user_id = (select auth.uid())\n      and app_user.status = ''1''\n  ) then\n    raise exception ''Active authenticated user permission is required''\n      using errcode = ''42501'';\n  end if;';
begin
  select pg_get_functiondef(proc.oid)
  into function_definition
  from pg_proc as proc
  join pg_namespace as namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'get_ai_project_catalog'
    and pg_get_function_identity_arguments(proc.oid) = 'p_action text, p_args jsonb';

  if function_definition is null or position(old_guard in function_definition) = 0 then
    raise exception 'Expected get_ai_project_catalog authorization guard was not found';
  end if;

  execute replace(function_definition, old_guard, new_guard);
end;
$migration$;

revoke all on function public.get_ai_project_catalog(text, jsonb) from public, anon;
grant execute on function public.get_ai_project_catalog(text, jsonb) to authenticated, service_role;

;
