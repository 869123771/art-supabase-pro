begin;

do $test$
declare
  v_missing text[];
begin
  select array_agg(expected_name order by expected_name)
  into v_missing
  from unnest(array[
    'smis_hazardous_waste_warehouse',
    'smis_hazardous_waste_category',
    'smis_hazardous_waste_catalog',
    'smis_hazardous_waste_document',
    'smis_hazardous_waste_document_item'
  ]) expected_name
  where to_regclass('public.' || expected_name) is null;

  if v_missing is not null then
    raise exception '缺少危废管理数据表：%', array_to_string(v_missing, ', ');
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name like 'smis_hazardous_waste_%'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'authenticated 仍持有危废业务表直接写权限';
  end if;

  if (
    select count(distinct name)
    from public.sys_menu
    where name in (
      'SmisHazardousWasteWarehouseDefinition:View',
      'SmisHazardousWasteWarehouseDefinition:Add',
      'SmisHazardousWasteCatalog:AddCategory',
      'SmisHazardousWasteCatalog:Add',
      'SmisHazardousWasteInbound:Submit',
      'SmisHazardousWasteInbound:Review',
      'SmisHazardousWasteOutbound:Submit',
      'SmisHazardousWasteOutbound:Review'
    ) and type = 'button'
  ) <> 8 then
    raise exception '危废管理关键按钮权限未完整注册';
  end if;

  if (
    select count(distinct rule_key)
    from public.sys_document_number_scene
    where rule_key in ('smis.hazardous_waste_inbound', 'smis.hazardous_waste_outbound')
  ) <> 2 then
    raise exception '危废入出库编号场景未完整注册';
  end if;
end;
$test$;

rollback;
