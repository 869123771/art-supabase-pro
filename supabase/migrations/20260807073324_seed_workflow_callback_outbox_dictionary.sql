with platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), parent as (
  select id from public.sys_dict_type where code = 'workflowEngine' limit 1
)
insert into public.sys_dict_type(
  id, parent_id, name, code, status, node_type, sort,
  tenant_id, create_by, update_by
)
select gen_random_uuid(), parent.id, '业务回调状态', 'workflowCallbackStatus',
  '1', 'dictionary', 10, platform.id,
  '624944977@qq.com', '624944977@qq.com'
from platform cross join parent
where not exists (
  select 1 from public.sys_dict_type where code = 'workflowCallbackStatus'
);
with rows(value, label, sort, tag_type) as (values
  ('pending', '待投递', 1, 'info'),
  ('processing', '投递中', 2, 'primary'),
  ('retry_wait', '等待重试', 3, 'warning'),
  ('succeeded', '已成功', 4, 'success'),
  ('dead_letter', '死信', 5, 'danger')
), platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dict_type as (
  select id from public.sys_dict_type where code = 'workflowCallbackStatus' limit 1
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, sort, tag_type,
  tenant_id, create_by, update_by
)
select gen_random_uuid(), dict_type.id, 'workflowCallbackStatus_' || rows.value,
  '1', rows.value, rows.label, rows.sort, rows.tag_type,
  platform.id, '624944977@qq.com', '624944977@qq.com'
from rows cross join platform cross join dict_type
where not exists (
  select 1
  from public.sys_dictionary d
  where d.type_id = dict_type.id
    and d.value = rows.value
);
