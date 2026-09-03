begin;

create temporary table smis_special_operation_configuration_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

insert into smis_special_operation_configuration_test_result(check_name, passed, detail)
values
  (
    'configuration_schema',
    to_regclass('public.smis_special_operation_type') is not null
      and to_regclass('public.smis_special_operation_field_definition') is not null
      and to_regclass('public.smis_special_operation_catalog_item') is not null,
    '作业类型、专有字段和三类配置项数据表已建立'
  ),
  (
    'secure_rpc_contract',
    to_regprocedure('public.smis_list_special_operation_types_secure(integer,integer,text,text,text,uuid)') is not null
      and to_regprocedure('public.smis_save_special_operation_type_secure(uuid,jsonb,uuid)') is not null
      and to_regprocedure('public.smis_void_special_operation_types_secure(uuid[],uuid)') is not null
      and to_regprocedure('public.smis_list_special_operation_catalog_secure(text,integer,integer,text,uuid,text,text,text,uuid)') is not null
      and to_regprocedure('public.smis_save_special_operation_catalog_secure(uuid,jsonb,uuid)') is not null
      and to_regprocedure('public.smis_void_special_operation_catalog_secure(text,uuid[],uuid)') is not null,
    '作业类型与配置项查询、保存、作废安全 RPC 已注册'
  ),
  (
    'tenant_rls',
    (select relrowsecurity from pg_class where oid = 'public.smis_special_operation_type'::regclass)
      and (select relrowsecurity from pg_class where oid = 'public.smis_special_operation_field_definition'::regclass)
      and (select relrowsecurity from pg_class where oid = 'public.smis_special_operation_catalog_item'::regclass),
    '全部特殊作业配置表已开启租户级 RLS'
  ),
  (
    'foreign_key_indexes',
    to_regclass('public.smis_special_operation_field_type_sort_idx') is not null
      and to_regclass('public.smis_special_operation_catalog_filter_idx') is not null,
    '作业类型外键与高频筛选列已建立复合索引'
  ),
  (
    'record_type_dictionary',
    exists (
      select 1
      from public.sys_dict_type dict_type
      where dict_type.code = 'smisSpecialOperationRecordType'
        and 3 = (
          select count(*)
          from public.sys_dictionary dictionary
          where dictionary.type_id = dict_type.id
            and dictionary.value in ('text', 'number', 'single')
        )
    ),
    '现场分析记录类型包含文本、数值和单选'
  ),
  (
    'managed_button_permissions',
    24 = (
      select count(*)
      from public.sys_menu button
      join public.sys_menu page on page.id = button.parent_id
      where page.name in (
        'SmisSpecialOperationType',
        'SmisSpecialOperationSafetyChecklist',
        'SmisSpecialOperationHazardFactor',
        'SmisSpecialOperationSiteAnalysisForm'
      )
        and button.type = 'button'
        and split_part(button.name, ':', 2) in ('View', 'Add', 'Edit', 'Delete', 'Export', 'Void')
    ),
    '四个页面的查看、新增、编辑、删除、导出和作废权限均可分配'
  );

do $assertions$
declare
  v_failed text;
begin
  select string_agg(check_name || ': ' || detail, E'\n')
  into v_failed
  from smis_special_operation_configuration_test_result
  where not passed;

  if v_failed is not null then
    raise exception '特殊作业配置数据库测试失败：\n%', v_failed;
  end if;
end;
$assertions$;

select *
from smis_special_operation_configuration_test_result
order by check_name;

rollback;
