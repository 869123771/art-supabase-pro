begin;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select
  'b2000000-0000-4000-8000-000000000018'::uuid,
  '自动入账核算维度来源',
  'fmsPostingAuxiliaryPayloadKey',
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  platform_tenant.id,
  'dictionary',
  218,
  '自动制证时用于匹配核算项目的业务实体字段'
from platform_tenant
on conflict (id) do update set
  name = excluded.name,
  code = excluded.code,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000161'::uuid, 'customer_id', '客户', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000162'::uuid, 'carrier_id', '承运商', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000163'::uuid, 'applicant_user_id', '报销申请人', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000164'::uuid, 'waybill_id', '运单', 4, 'primary'),
    ('c2000000-0000-4000-8000-000000000165'::uuid, 'driver_id', '司机', 5, 'danger'),
    ('c2000000-0000-4000-8000-000000000166'::uuid, 'expense_item_id', '费用项目', 6, 'info')
  ) as values_table(id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select
  item.id,
  'b2000000-0000-4000-8000-000000000018'::uuid,
  item.value,
  '1',
  item.value,
  item.label,
  item.sort,
  item.tag_type,
  '624944977@qq.com',
  '624944977@qq.com',
  platform_tenant.id
from platform_tenant
cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  status = excluded.status,
  value = excluded.value,
  label = excluded.label,
  sort = excluded.sort,
  tag_type = excluded.tag_type,
  update_by = excluded.update_by,
  update_time = now();

commit;;
