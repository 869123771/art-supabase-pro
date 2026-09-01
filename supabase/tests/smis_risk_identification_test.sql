begin;

create temporary table smis_risk_identification_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

insert into smis_risk_identification_test_result(check_name, passed, detail)
values
  (
    'risk_point_schema',
    to_regclass('public.smis_risk_point') is not null
      and to_regclass('public.smis_risk_point_organization') is not null
      and to_regclass('public.smis_risk_activity') is not null
      and to_regclass('public.smis_risk_item_activity') is not null,
    '风险点、辨识单位、作业活动与危害关联表已建立'
  ),
  (
    'secure_rpc_contract',
    to_regprocedure('public.smis_list_risk_points_secure(integer,integer,text,uuid,uuid,text,text,text)') is not null
      and to_regprocedure('public.smis_save_risk_point_secure(uuid,jsonb,uuid[])') is not null
      and to_regprocedure('public.smis_save_risk_activity_secure(uuid,uuid,text,text,integer)') is not null
      and to_regprocedure('public.smis_save_risk_hazard_secure(uuid,uuid,jsonb,uuid[])') is not null,
    '列表、风险点、作业活动和危害因素安全 RPC 已注册'
  ),
  (
    'numbering_constraints',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.smis_risk_point'::regclass
        and conname = 'smis_risk_point_no_check'
    ) and exists (
      select 1 from pg_constraint
      where conrelid = 'public.smis_risk_item'::regclass
        and conname = 'smis_risk_item_no_check'
    ),
    '风险点 5 位流水码与 WHYS 3 位后缀约束已启用'
  ),
  (
    'tenant_rls',
    (select relrowsecurity from pg_class where oid = 'public.smis_risk_point'::regclass)
      and (select relrowsecurity from pg_class where oid = 'public.smis_risk_activity'::regclass)
      and (select relrowsecurity from pg_class where oid = 'public.smis_risk_item_activity'::regclass),
    '风险辨识主表与关联表已开启 RLS'
  ),
  (
    'automatic_level_summary',
    position(
      'case when level.level_code = ''medium'' then ''general'''
      in pg_get_functiondef(
        'public.smis_list_risk_points_secure(integer,integer,text,uuid,uuid,text,text,text)'::regprocedure
      )
    ) > 0,
    '风险点等级由危害评价结果自动汇总并对齐字典编码'
  ),
  (
    'risk_point_type_dictionary',
    exists (
      select 1
      from public.sys_dict_type dict_type
      where dict_type.code = 'smisRiskPointType'
        and 4 = (
          select count(*) from public.sys_dictionary dictionary
          where dictionary.type_id = dict_type.id
            and dictionary.value in ('unset', 'location', 'equipment', 'activity')
        )
    ),
    '风险点类型字典包含未选择、部位场所、设备设施、作业活动'
  ),
  (
    'managed_button_permissions',
    10 = (
      select count(*)
      from public.sys_menu button
      join public.sys_menu page on page.id = button.parent_id
      where page.name = 'SmisDualControlRiskIdentification'
        and button.type = 'button'
        and button.name in (
          'SmisDualControlRiskIdentification:View',
          'SmisDualControlRiskIdentification:Add',
          'SmisDualControlRiskIdentification:Edit',
          'SmisDualControlRiskIdentification:Delete',
          'SmisDualControlRiskIdentification:Copy',
          'SmisDualControlRiskIdentification:Generate',
          'SmisDualControlRiskIdentification:Import',
          'SmisDualControlRiskIdentification:Export',
          'SmisDualControlRiskIdentification:MaintainHazards',
          'SmisDualControlRiskIdentification:Void'
        )
    ),
    '风险辨识业务动作均具备可分配按钮权限'
  );

do $assertions$
declare
  v_failed text;
begin
  select string_agg(check_name || ': ' || detail, E'\n')
  into v_failed
  from smis_risk_identification_test_result
  where not passed;

  if v_failed is not null then
    raise exception 'SMIS risk identification contract failed:%', E'\n' || v_failed;
  end if;
end
$assertions$;

select check_name, passed, detail
from smis_risk_identification_test_result
order by check_name;

rollback;
