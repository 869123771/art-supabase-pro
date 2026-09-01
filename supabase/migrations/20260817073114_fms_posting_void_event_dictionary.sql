begin;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000171'::uuid, 'customer_statement:voided', '客户对账作废', 21, 'info'),
    ('c2000000-0000-4000-8000-000000000172'::uuid, 'carrier_statement:voided', '承运商对账作废', 22, 'info'),
    ('c2000000-0000-4000-8000-000000000173'::uuid, 'customer_receipt:voided', '客户收款作废', 23, 'info'),
    ('c2000000-0000-4000-8000-000000000174'::uuid, 'carrier_payment:voided', '承运商付款作废', 24, 'info'),
    ('c2000000-0000-4000-8000-000000000175'::uuid, 'invoice:voided', '发票作废', 25, 'info'),
    ('c2000000-0000-4000-8000-000000000176'::uuid, 'expense_reimbursement:voided', '报销付款撤销', 26, 'info'),
    ('c2000000-0000-4000-8000-000000000177'::uuid, 'waybill_cost:voided', '运单费用作废', 27, 'info')
  ) as values_table(id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select
  item.id,
  'b2000000-0000-4000-8000-000000000013'::uuid,
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
