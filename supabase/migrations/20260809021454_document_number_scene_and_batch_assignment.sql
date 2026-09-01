-- Register the business feature behind each configurable number rule.
-- A scene is platform-owned metadata; tenant rule rows remain the runtime source of truth.

create table if not exists public.sys_document_number_scene (
  rule_key text primary key,
  rule_name text not null,
  field_label text not null,
  category text not null check (category in ('business_document', 'master_data', 'vehicle')),
  menu_id uuid not null references public.sys_menu(id) on delete restrict,
  target_table text not null,
  target_column text not null,
  default_template text not null,
  default_reset_cycle text not null check (default_reset_cycle in ('none', 'year', 'month', 'day')),
  manual_required boolean not null default true,
  enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null references public.sys_tenant(id) on delete restrict
);

create index if not exists idx_document_number_scene_menu
  on public.sys_document_number_scene(menu_id, enabled, rule_name);
create index if not exists idx_document_number_scene_tenant
  on public.sys_document_number_scene(tenant_id);

drop trigger if exists sys_document_number_scene_create_audit on public.sys_document_number_scene;
create trigger sys_document_number_scene_create_audit
before insert on public.sys_document_number_scene
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists sys_document_number_scene_update_audit on public.sys_document_number_scene;
create trigger sys_document_number_scene_update_audit
before update on public.sys_document_number_scene
for each row execute function public.trg_set_update_time_and_by();

alter table public.sys_document_number_scene enable row level security;

drop policy if exists document_number_scene_select on public.sys_document_number_scene;
create policy document_number_scene_select on public.sys_document_number_scene
for select to authenticated
using ((select app_private.is_platform_super()));

drop policy if exists document_number_scene_insert on public.sys_document_number_scene;
create policy document_number_scene_insert on public.sys_document_number_scene
for insert to authenticated
with check ((select app_private.is_platform_super()));

drop policy if exists document_number_scene_update on public.sys_document_number_scene;
create policy document_number_scene_update on public.sys_document_number_scene
for update to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));

drop policy if exists document_number_scene_delete on public.sys_document_number_scene;
create policy document_number_scene_delete on public.sys_document_number_scene
for delete to authenticated
using ((select app_private.is_platform_super()));

with platform as (
  select id from public.sys_tenant where lower(tenant_code) = 'platform' limit 1
), scenes as (
  select * from (values
    ('tms.order', '运输订单号', '运单号', 'business_document', 'TmsOrderOpen', 'tms_order', 'order_no', 'YD{YYYYMM}-{SEQ:3}', 'month', true, '开单页面运输订单号'),
    ('tms.order_cargo', '订单货号', '货号', 'business_document', 'TmsOrderOpen', 'tms_order', 'cargo_no', 'HH{YYYYMM}-{SEQ:3}', 'month', false, '开单页面订单级内部货号'),
    ('tms.contract', '合同编号', '合同编号', 'business_document', 'TmsContract', 'tms_contract', 'contract_no', 'HT{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.carrier_payment_application', '承运商付款申请号', '申请单号', 'business_document', 'TmsCarrierPaymentApplication', 'tms_carrier_payment_application', 'application_no', 'FK{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.carrier_statement', '承运商对账单号', '对账单号', 'business_document', 'TmsCarrierSettlement', 'tms_carrier_statement', 'statement_no', 'CYSDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.customer_statement', '客户对账单号', '对账单号', 'business_document', 'TmsCustomerSettlement', 'tms_customer_statement', 'statement_no', 'KHDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.cash_transaction', '收支流水号', '收支流水号', 'business_document', 'TmsCashTransaction', 'tms_cash_transaction', 'transaction_no', 'SZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.expense_payment', '费用付款单号', '付款单号', 'business_document', 'TmsInTransitExpense', 'tms_expense_payment', 'payment_no', 'FYZF{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.expense_reimbursement', '费用报销单号', '报销单号', 'business_document', 'TmsInTransitExpense', 'tms_expense_reimbursement', 'reimbursement_no', 'FYBX{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.in_transit_expense', '在途费用单号', '费用单号', 'business_document', 'TmsInTransitExpense', 'tms_in_transit_expense', 'expense_no', 'ZTFY{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.invoice_record', '开票登记号', '开票登记号', 'business_document', 'TmsInvoiceManagement', 'tms_invoice', 'invoice_record_no', 'FPDJ{YYYYMM}-{SEQ:4}', 'month', true, '外部发票代码和号码不使用本规则'),
    ('tms.receipt_exception', '回单异常工单号', '异常工单号', 'business_document', 'TmsDeliveryManagement', 'tms_receipt_exception_work_order', 'work_order_no', 'HDYC{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.customer', '客户编码', '客户编码', 'master_data', 'TmsCustomer', 'tms_customer', 'customer_code', 'KH{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.carrier', '承运商编码', '承运商编码', 'master_data', 'TmsCarrier', 'tms_carrier', 'carrier_code', 'CYS{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.cargo', '货物编码', '货物编码', 'master_data', 'TmsCargo', 'tms_cargo', 'cargo_code', 'HW{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.station', '站点编码', '站点编码', 'master_data', 'TmsStation', 'tms_station', 'station_code', 'ZD{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.archive_self', '车辆自编号', '车辆自编号', 'vehicle', 'VehicleArchiveEntry', 'vehicle_archive', 'self_no', 'ZBH{YYYYMM}-{SEQ:4}', 'month', false, '车牌号和车架号等外部标识不使用本规则'),
    ('vehicle.inspection', '车辆年检单号', '年检单号', 'vehicle', 'VehicleInspection', 'vehicle_inspection', 'inspection_no', 'NJ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.maintenance', '车辆维修单号', '维修单号', 'vehicle', 'VehicleMaintenance', 'vehicle_maintenance_record', 'maintenance_no', 'WX{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.part', '配件编码', '配件编码', 'vehicle', 'Parts', 'vehicle_parts', 'part_code', 'LP{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.part_category', '配件分类编码', '分类编码', 'vehicle', 'PartsCategory', 'vehicle_parts_category', 'category_code', 'LPLB{YYYYMM}-{SEQ:3}', 'month', true, null),
    ('vehicle.routine_inspection', '车辆例检单号', '例检单号', 'vehicle', 'VehicleRoutineInspection', 'vehicle_routine_inspection_record', 'routine_inspection_no', 'LJ{YYYYMM}-{SEQ:4}', 'month', true, null)
  ) as v(rule_key, rule_name, field_label, category, menu_name, target_table, target_column, default_template, default_reset_cycle, manual_required, remark)
)
insert into public.sys_document_number_scene (
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, update_by, tenant_id
)
select s.rule_key, s.rule_name, s.field_label, s.category, m.id, s.target_table, s.target_column,
       s.default_template, s.default_reset_cycle, s.manual_required, true, s.remark,
       '624944977@qq.com', '624944977@qq.com', p.id
from scenes s
join public.sys_menu m on m.name = s.menu_name
cross join platform p
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
  update_by = excluded.update_by;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sys_document_number_rule_scene_key_fkey'
      and conrelid = 'public.sys_document_number_rule'::regclass
  ) then
    alter table public.sys_document_number_rule
      add constraint sys_document_number_rule_scene_key_fkey
      foreign key (rule_key) references public.sys_document_number_scene(rule_key)
      on update cascade on delete restrict;
  end if;
end
$block$;

revoke all on public.sys_document_number_scene from anon;
grant select on public.sys_document_number_scene to authenticated;
grant insert (
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone,
  manual_required, builtin, enabled, remark
) on public.sys_document_number_rule to authenticated;

comment on table public.sys_document_number_scene is
  'Platform registry that binds a configurable number rule to a visible menu feature and database field.';

;
