-- Register System Management actions as assignable button permissions.
-- Tenant-scoped maintenance uses role permissions; platform control-plane writes
-- keep their existing platform-super boundary in RLS/RPC policies.

update public.sys_menu child
set name = case child.name
  when 'SystemParamAdd' then 'System:SystemParam:Add'
  when 'SystemParamEdit' then 'System:SystemParam:Edit'
  when 'SystemParamDelete' then 'System:SystemParam:Delete'
  else child.name
end,
update_by = 'codex-system-permission-migration',
update_time = now()
from public.sys_menu parent
where child.parent_id = parent.id
  and parent.name = 'SystemParam'
  and child.type = 'button'
  and child.name in ('SystemParamAdd', 'SystemParamEdit', 'SystemParamDelete');

do $migration$
declare
  permission_item record;
  parent_menu_id uuid;
begin
  for permission_item in
    select *
    from (values
      ('Organization', 'System:Organization:View', '查看治理详情', 1),
      ('Organization', 'System:Organization:Add', '新增组织', 2),
      ('Organization', 'System:Organization:Edit', '编辑组织', 3),
      ('Organization', 'System:Organization:Delete', '删除组织', 4),
      ('Menu', 'System:Menu:Add', '新增菜单', 1),
      ('Menu', 'System:Menu:Edit', '编辑菜单', 2),
      ('Menu', 'System:Menu:Delete', '删除菜单', 3),
      ('Tenant', 'System:Tenant:Add', '新增租户', 1),
      ('Tenant', 'System:Tenant:Edit', '编辑租户', 2),
      ('Tenant', 'System:Tenant:Delete', '停用租户', 3),
      ('SystemParam', 'System:SystemParam:Add', '新增参数', 1),
      ('SystemParam', 'System:SystemParam:Edit', '编辑参数', 2),
      ('SystemParam', 'System:SystemParam:Delete', '删除参数', 3),
      ('DocumentNumberRule', 'System:DocumentNumberRule:Add', '新增编号规则', 1),
      ('DocumentNumberRule', 'System:DocumentNumberRule:Edit', '编辑编号规则', 2),
      ('User', 'System:User:Add', '新增用户', 1),
      ('User', 'System:User:Edit', '编辑用户', 2),
      ('User', 'System:User:Delete', '注销用户', 3),
      ('User', 'System:User:AssignRole', '分配角色', 4),
      ('User', 'System:User:ResetPassword', '初始化密码', 5),
      ('Role', 'System:Role:Add', '新增角色', 1),
      ('Role', 'System:Role:Edit', '编辑角色', 2),
      ('Role', 'System:Role:Delete', '删除角色', 3),
      ('Role', 'System:Role:AssignPermission', '配置菜单权限', 4),
      ('WebsiteConfig', 'System:WebsiteConfig:Publish', '保存并发布配置', 1),
      ('AiConfiguration', 'System:AiConfiguration:Edit', '编辑 AI 配置', 1),
      ('AiPrompt', 'System:AiPrompt:Add', '新建 Prompt 版本', 1),
      ('AiPrompt', 'System:AiPrompt:Edit', '编辑 Prompt 草稿', 2),
      ('AiPrompt', 'System:AiPrompt:Publish', '发布或回滚 Prompt', 3),
      ('AiPrompt', 'System:AiPrompt:Clone', '复制 Prompt 版本', 4),
      ('AiPrompt', 'System:AiPrompt:Delete', '删除 Prompt 草稿', 5),
      ('AiProjectPlanner', 'System:AiProjectPlanner:ManageWorkflow', '推进建议状态', 1),
      ('GeofenceConfig', 'System:GeofenceConfig:Edit', '编辑电子围栏', 1),
      ('FieldPermission', 'System:FieldPermission:Manage', '维护字段权限', 1)
    ) as catalog(menu_name, permission_code, permission_title, permission_sort)
  loop
    select id
      into parent_menu_id
      from public.sys_menu
     where name = permission_item.menu_name
       and type is distinct from 'button'
     order by create_time
     limit 1;

    if parent_menu_id is null then
      raise exception 'System permission parent menu not found: %', permission_item.menu_name;
    end if;

    insert into public.sys_menu (
      id, parent_id, name, path, component, meta, sort, type,
      create_by, create_time, update_by, update_time
    )
    select
      gen_random_uuid(),
      parent_menu_id,
      permission_item.permission_code,
      '',
      '',
      jsonb_build_object(
        'icon', '',
        'link', '',
        'roles', '[]'::jsonb,
        'title', permission_item.permission_title,
        'is_hide', false,
        'fixed_tab', false,
        'is_enable', true,
        'is_iframe', false,
        'keep_alive', false,
        'show_badge', false,
        'active_path', '',
        'is_hide_tab', false,
        'is_full_page', false,
        'is_auth_button', true,
        'show_text_badge', ''
      ),
      permission_item.permission_sort,
      'button',
      'codex-system-permission-migration',
      now(),
      null,
      now()
    where not exists (
      select 1
      from public.sys_menu existing
      where existing.parent_id = parent_menu_id
        and existing.type = 'button'
        and existing.name = permission_item.permission_code
    );
  end loop;
end
$migration$;

-- Remove catalog rows that were discovered to have no corresponding UI action.
with stale_permission as (
  select id
  from public.sys_menu
  where type = 'button'
    and name in (
      'TmsCustomerAddress:Export',
      'TmsDriver:Export',
      'VehicleViolation:View'
    )
)
delete from public.sys_role_menu role_menu
using stale_permission
where role_menu.menu_id = stale_permission.id;

delete from public.sys_menu
where type = 'button'
  and name in (
    'TmsCustomerAddress:Export',
    'TmsDriver:Export',
    'VehicleViolation:View'
  );

-- System parameters may be extended by authorized tenant administrators.
-- Platform-owned rows stay read-only to ordinary tenants, and protected global
-- parameter keys cannot be shadowed by tenant-created duplicates.
drop policy if exists sys_param_platform_super_insert on public.sys_param;
drop policy if exists sys_param_platform_super_update on public.sys_param;
drop policy if exists sys_param_platform_super_delete on public.sys_param;

create policy sys_param_authorized_insert
on public.sys_param
for insert
to authenticated
with check (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:SystemParam:Add')
    and tenant_id = app_private.current_user_tenant_id()
    and param_key not in ('website.config', 'tms.geofence.config')
  )
);

create policy sys_param_authorized_update
on public.sys_param
for update
to authenticated
using (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:SystemParam:Edit')
    and tenant_id = app_private.current_user_tenant_id()
    and param_key not in ('website.config', 'tms.geofence.config')
  )
)
with check (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:SystemParam:Edit')
    and tenant_id = app_private.current_user_tenant_id()
    and param_key not in ('website.config', 'tms.geofence.config')
  )
);

create policy sys_param_authorized_delete
on public.sys_param
for delete
to authenticated
using (
  not builtin
  and (
    app_private.is_platform_super()
    or (
      app_private.has_permission('System:SystemParam:Delete')
      and tenant_id = app_private.current_user_tenant_id()
      and param_key not in ('website.config', 'tms.geofence.config')
    )
  )
);

drop policy if exists document_number_rule_insert on public.sys_document_number_rule;
drop policy if exists document_number_rule_update on public.sys_document_number_rule;

create policy document_number_rule_insert
on public.sys_document_number_rule
for insert
to authenticated
with check (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:DocumentNumberRule:Add')
    and tenant_id = app_private.current_user_tenant_id()
  )
);

create policy document_number_rule_update
on public.sys_document_number_rule
for update
to authenticated
using (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:DocumentNumberRule:Edit')
    and tenant_id = app_private.current_user_tenant_id()
  )
)
with check (
  app_private.is_platform_super()
  or (
    app_private.has_permission('System:DocumentNumberRule:Edit')
    and tenant_id = app_private.current_user_tenant_id()
  )
);

create or replace function public.configure_document_number_rule_for_tenants(
  p_rule_key text,
  p_tenant_ids uuid[],
  p_auto_enabled boolean,
  p_template text,
  p_reset_cycle text,
  p_sequence_start bigint default 1,
  p_timezone text default 'Asia/Shanghai',
  p_remark text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_scene public.sys_document_number_scene%rowtype;
  v_tenant_ids uuid[];
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_updated integer := 0;
  v_created integer := 0;
begin
  if not v_is_platform_super
    and not app_private.has_permission('System:DocumentNumberRule:Add') then
    raise exception '缺少新增编号规则权限' using errcode = '42501';
  end if;

  select array_agg(distinct tenant_id order by tenant_id)
    into v_tenant_ids
  from unnest(coalesce(p_tenant_ids, array[]::uuid[])) as selected(tenant_id)
  where tenant_id is not null;

  if coalesce(cardinality(v_tenant_ids), 0) = 0 then
    raise exception '请至少选择一个租户';
  end if;

  if not v_is_platform_super
    and (
      cardinality(v_tenant_ids) <> 1
      or v_tenant_ids[1] is distinct from v_current_tenant_id
    ) then
    raise exception '普通管理员只能维护当前租户的编号规则' using errcode = '42501';
  end if;

  select *
    into v_scene
  from public.sys_document_number_scene
  where rule_key = lower(btrim(p_rule_key))
    and enabled
  limit 1;

  if not found then
    raise exception '编号功能未注册或已停用：%', p_rule_key;
  end if;

  if exists (
    select 1
    from unnest(v_tenant_ids) as selected(tenant_id)
    left join public.sys_tenant tenant on tenant.id = selected.tenant_id
    where tenant.id is null
  ) then
    raise exception '所选租户中包含不存在的租户';
  end if;

  update public.sys_document_number_rule rule
  set auto_enabled = p_auto_enabled,
      template = p_template,
      reset_cycle = p_reset_cycle,
      sequence_start = p_sequence_start,
      timezone = p_timezone,
      remark = p_remark
  where rule.rule_key = v_scene.rule_key
    and rule.tenant_id = any(v_tenant_ids);
  get diagnostics v_updated = row_count;

  insert into public.sys_document_number_rule (
    tenant_id,
    rule_key,
    rule_name,
    category,
    target_table,
    target_column,
    auto_enabled,
    template,
    reset_cycle,
    sequence_start,
    timezone,
    manual_required,
    builtin,
    enabled,
    remark
  )
  select tenant_id,
         v_scene.rule_key,
         v_scene.rule_name,
         v_scene.category,
         v_scene.target_table,
         v_scene.target_column,
         p_auto_enabled,
         p_template,
         p_reset_cycle,
         p_sequence_start,
         p_timezone,
         v_scene.manual_required,
         false,
         true,
         p_remark
  from unnest(v_tenant_ids) as selected(tenant_id)
  where not exists (
    select 1
    from public.sys_document_number_rule existing
    where existing.tenant_id = selected.tenant_id
      and existing.rule_key = v_scene.rule_key
  );
  get diagnostics v_created = row_count;

  return jsonb_build_object(
    'created', v_created,
    'updated', v_updated,
    'assigned', v_created + v_updated
  );
end;
$function$;

comment on function public.configure_document_number_rule_for_tenants(
  text, uuid[], boolean, text, text, bigint, text, text
) is 'Platform super may configure multiple tenants; authorized tenant admins are restricted to their current tenant.';

;
