
insert into public.sys_dictionary (
  type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
)
select
  type.id,
  'receivables_collection_advisor',
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  'receivables_collection_advisor',
  'AI 回款风险助手',
  60,
  type.tenant_id,
  'danger'
from public.sys_dict_type as type
where type.code = 'aiRunFeature'
  and type.tenant_id = app_private.platform_tenant_id()
  and not exists (
    select 1
    from public.sys_dictionary as dictionary
    where dictionary.type_id = type.id
      and dictionary.tenant_id = type.tenant_id
      and dictionary.value = 'receivables_collection_advisor'
  );
;
