-- Bulk-apply one registered numbering scene to multiple tenants in a single transaction.
-- Existing tenant rules are updated; missing tenant rules are created.

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
security invoker
set search_path to ''
as $function$
declare
  v_scene public.sys_document_number_scene%rowtype;
  v_tenant_ids uuid[];
  v_updated integer := 0;
  v_created integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using
      errcode = '42501',
      message = '仅平台超级管理员可以批量配置编号规则';
  end if;

  select array_agg(distinct tenant_id order by tenant_id)
    into v_tenant_ids
  from unnest(coalesce(p_tenant_ids, array[]::uuid[])) as selected(tenant_id)
  where tenant_id is not null;

  if coalesce(cardinality(v_tenant_ids), 0) = 0 then
    raise exception '请至少选择一个租户';
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

revoke all on function public.configure_document_number_rule_for_tenants(
  text, uuid[], boolean, text, text, bigint, text, text
) from public, anon;
grant execute on function public.configure_document_number_rule_for_tenants(
  text, uuid[], boolean, text, text, bigint, text, text
) to authenticated;

comment on function public.configure_document_number_rule_for_tenants(
  text, uuid[], boolean, text, text, bigint, text, text
) is 'Platform-super-only atomic bulk configuration for one registered numbering scene across tenants.';

-- The numbering-rule workspace is a platform-super administration surface.
delete from public.sys_role_menu role_menu
using public.sys_role role, public.sys_menu menu
where role_menu.role_id = role.id
  and role_menu.menu_id = menu.id
  and menu.name = 'DocumentNumberRule'
  and role.role_code <> 'R_SUPER';

with target_menu as (
  select id from public.sys_menu where name = 'DocumentNumberRule' limit 1
)
insert into public.sys_role_menu (
  role_id, menu_id, permission, create_by, update_by, tenant_id
)
select role.id,
       target_menu.id,
       '{}'::jsonb,
       'number-engine',
       'number-engine',
       role.tenant_id
from public.sys_role role
cross join target_menu
where role.role_code = 'R_SUPER'
  and not exists (
    select 1
    from public.sys_role_menu existing
    where existing.role_id = role.id
      and existing.menu_id = target_menu.id
  );

;
