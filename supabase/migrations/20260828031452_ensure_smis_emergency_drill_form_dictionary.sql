-- 补齐应急演练形式字典。早期部署可能已创建演练页面，但缺少该字典，
-- 导致表单直接显示 onsite / desktop 等内部枚举值。
insert into public.sys_dict_type(
  id,
  name,
  code,
  status,
  create_by,
  update_by,
  remark,
  tenant_id,
  parent_id,
  node_type,
  sort
)
select
  gen_random_uuid(),
  '演练形式',
  'smisEmergencyDrillForm',
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  '现场演练、桌面演练',
  tenant.id,
  root.id,
  'dictionary',
  68
from public.sys_tenant tenant
join public.sys_dict_type root
  on root.tenant_id = tenant.id
 and root.code = 'smisManage'
where tenant.tenant_code = 'platform'
  and not exists (
    select 1
    from public.sys_dict_type existing
    where existing.code = 'smisEmergencyDrillForm'
  );

with items(code, value, label, color, tag_type, sort) as (
  values
    ('onsite', 'onsite', '现场演练', '#409eff', 'primary', 1::bigint),
    ('desktop', 'desktop', '桌面演练', '#909399', 'info', 2::bigint)
)
insert into public.sys_dictionary(
  id,
  type_id,
  code,
  status,
  create_by,
  update_by,
  value,
  label,
  color,
  tag_type,
  sort,
  tenant_id
)
select
  gen_random_uuid(),
  dict_type.id,
  item.code,
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  item.value,
  item.label,
  item.color,
  item.tag_type,
  item.sort,
  dict_type.tenant_id
from items item
join public.sys_dict_type dict_type
  on dict_type.code = 'smisEmergencyDrillForm'
where not exists (
  select 1
  from public.sys_dictionary existing
  where existing.type_id = dict_type.id
    and existing.value = item.value
);

update public.sys_dictionary dictionary
set
  label = item.label,
  color = item.color,
  tag_type = item.tag_type,
  sort = item.sort,
  status = '1',
  update_by = '624944977@qq.com',
  update_time = now()
from (
  values
    ('onsite', '现场演练', '#409eff', 'primary', 1::bigint),
    ('desktop', '桌面演练', '#909399', 'info', 2::bigint)
) as item(value, label, color, tag_type, sort)
join public.sys_dict_type dict_type
  on dict_type.code = 'smisEmergencyDrillForm'
where dictionary.type_id = dict_type.id
  and dictionary.value = item.value;

;
