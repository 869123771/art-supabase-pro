-- 二级目录不挂载布局组件，由动态路由按目录节点处理。
update public.sys_menu
set component = '', update_by = 'migration', update_time = now()
where name = 'SmisRiskControl'
  and type = 'folder';

-- can_execute_business_action 只供 SECURITY DEFINER 业务函数内部使用；
-- RLS 直接调用已向 authenticated 授权的 has_permission。
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_site', 'smis_area', 'smis_risk_point', 'smis_hazard_source',
    'smis_risk_assessment', 'smis_risk_assessment_item', 'smis_control_measure'
  ] loop
    execute format(
      'alter policy %I_select on public.%I using ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:View''))',
      v_table, v_table
    );
  end loop;

  foreach v_table in array array['smis_site', 'smis_area', 'smis_risk_point', 'smis_hazard_source'] loop
    execute format(
      'alter policy %I_insert on public.%I with check ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Add''))',
      v_table, v_table
    );
    execute format(
      'alter policy %I_update on public.%I using ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Edit'')) with check ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Edit''))',
      v_table, v_table
    );
    execute format(
      'alter policy %I_delete on public.%I using ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Delete''))',
      v_table, v_table
    );
  end loop;

  foreach v_table in array array[
    'smis_risk_assessment', 'smis_risk_assessment_item', 'smis_control_measure'
  ] loop
    execute format(
      'alter policy %I_insert on public.%I with check ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Assess''))',
      v_table, v_table
    );
    execute format(
      'alter policy %I_update on public.%I using ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Assess'')) with check ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Assess''))',
      v_table, v_table
    );
    execute format(
      'alter policy %I_delete on public.%I using ('
      || '(app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.has_permission(''SmisRiskPoint:Assess''))',
      v_table, v_table
    );
  end loop;
end;
$$;

alter policy smis_risk_assessment_event_select
on public.smis_risk_assessment_event
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisRiskPoint:View')
);

;
