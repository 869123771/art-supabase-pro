begin;

update public.sys_menu
set sort = 5, update_time = now()
where name = 'FinanceTreasury';

insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values
  (
    'a1000000-0000-4000-8000-000000000029'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceSpecializedAccounting', 'specialized-accounting', '', 'folder', 4,
    jsonb_build_object(
      'icon', 'ri:briefcase-4-line', 'title', '专项核算', 'is_hide', false,
      'is_enable', true, 'menu_type', 'folder', 'keep_alive', false
    ),
    '624944977@qq.com', '624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000030'::uuid,
    'a1000000-0000-4000-8000-000000000029'::uuid,
    'FinanceCommercialBill', 'commercial-bill', '/fms/commercial-bill/index', 'menu', 1,
    jsonb_build_object(
      'icon', 'ri:bank-card-2-line', 'title', '票据管理', 'is_hide', false,
      'is_enable', true, 'menu_type', 'menu', 'keep_alive', true
    ),
    '624944977@qq.com', '624944977@qq.com'
  )
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();

with finance_roles as (
  select distinct role_id, tenant_id
  from public.sys_role_menu
  where menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
)
insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select r.role_id, m.menu_id, r.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from finance_roles r
cross join (values
  ('a1000000-0000-4000-8000-000000000029'::uuid),
  ('a1000000-0000-4000-8000-000000000030'::uuid)
) as m(menu_id)
on conflict (role_id, menu_id) do nothing;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), bill_menu as (
  select id from public.sys_menu where name = 'FinanceCommercialBill' limit 1
)
insert into public.sys_document_number_scene (
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark, tenant_id
)
select
  'fms.commercial_bill', '商业票据编号', '票据编号', 'business_document',
  m.id, 'fms_commercial_bill', 'bill_no', 'PJ{YYYYMM}-{SEQ:5}', 'month',
  false, true, '商业票据内部登记编号', p.id
from platform_tenant p cross join bill_menu m
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  category = excluded.category,
  menu_id = excluded.menu_id,
  target_table = excluded.target_table,
  target_column = excluded.target_column,
  default_template = excluded.default_template,
  default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required,
  enabled = excluded.enabled,
  remark = excluded.remark,
  update_time = now();

insert into public.sys_document_number_rule (
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select
  t.id, s.rule_key, s.rule_name, s.category, s.target_table, s.target_column,
  true, s.default_template, s.default_reset_cycle, 1, 'Asia/Shanghai',
  s.manual_required, true, true, s.remark, 'number-engine', 'number-engine'
from public.sys_tenant t
join public.sys_document_number_scene s on s.rule_key = 'fms.commercial_bill'
on conflict (tenant_id, rule_key) do nothing;

drop trigger if exists document_number_bill_no on public.fms_commercial_bill;
create trigger document_number_bill_no
before insert on public.fms_commercial_bill
for each row execute function app_private.trg_assign_configurable_number(
  'fms.commercial_bill', 'bill_no'
);

commit;

;
