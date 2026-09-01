-- Register expense item codes in the unified document number engine.
insert into public.sys_document_number_scene (
  rule_key,
  rule_name,
  field_label,
  category,
  menu_id,
  target_table,
  target_column,
  default_template,
  default_reset_cycle,
  manual_required,
  enabled,
  remark,
  create_by,
  update_by,
  tenant_id
)
select
  'tms.expense_item',
  '费用项目编码',
  '项目编码',
  'master_data',
  menu.id,
  'tms_expense_item',
  'item_code',
  'FYXM{YYYYMM}-{SEQ:4}',
  'month',
  true,
  true,
  '费用项目主数据编码，默认按月从 1 开始自动编号',
  'number-engine',
  'number-engine',
  platform_tenant.id
from public.sys_tenant platform_tenant
join public.sys_menu menu
  on menu.name = 'TmsExpenseItem'
where platform_tenant.tenant_code = 'platform'
on conflict (rule_key) do update
set rule_name = excluded.rule_name,
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
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id;

create or replace function app_private.seed_document_number_rules(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.sys_document_number_rule (
    tenant_id,
    rule_key,
    rule_name,
    category,
    target_table,
    target_column,
    auto_enabled,
    template,
    reset_cycle,
    sequence_start,
    timezone,
    manual_required,
    builtin,
    enabled,
    remark,
    create_by,
    update_by
  )
  select
    p_tenant_id,
    item.rule_key,
    item.rule_name,
    item.category,
    item.target_table,
    item.target_column,
    true,
    item.template,
    item.reset_cycle,
    1,
    'Asia/Shanghai',
    item.manual_required,
    true,
    true,
    item.remark,
    'number-engine',
    'number-engine'
  from (
    values
      ('tms.order', '运输订单号', 'business_document', 'tms_order', 'order_no', 'YD{YYYYMM}-{SEQ:3}', 'month', true, '运单沿用订单号，不单独取号'),
      ('tms.order_cargo', '订单货号', 'business_document', 'tms_order', 'cargo_no', 'HH{YYYYMM}-{SEQ:3}', 'month', false, '订单级内部货号'),
      ('tms.contract', '合同编号', 'business_document', 'tms_contract', 'contract_no', 'HT{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.carrier_price', '承运商报价单号', 'business_document', 'tms_carrier_price', 'quote_no', 'CYSBJ{YYYYMM}-{SEQ:4}', 'month', true, '承运商价格维护报价单号'),
      ('tms.carrier_payment_application', '承运商付款申请号', 'business_document', 'tms_carrier_payment_application', 'application_no', 'FK{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.carrier_statement', '承运商对账单号', 'business_document', 'tms_carrier_statement', 'statement_no', 'CYSDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.customer_statement', '客户对账单号', 'business_document', 'tms_customer_statement', 'statement_no', 'KHDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.cash_transaction', '收支流水号', 'business_document', 'tms_cash_transaction', 'transaction_no', 'SZ{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.expense_item', '费用项目编码', 'master_data', 'tms_expense_item', 'item_code', 'FYXM{YYYYMM}-{SEQ:4}', 'month', true, '费用项目主数据编码'),
      ('tms.expense_payment', '费用付款单号', 'business_document', 'tms_expense_payment', 'payment_no', 'FYZF{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.expense_reimbursement', '费用报销单号', 'business_document', 'tms_expense_reimbursement', 'reimbursement_no', 'FYBX{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('tms.waybill_cost', '运单费用单号', 'business_document', 'tms_waybill_cost', 'cost_no', 'YDFY{YYYYMM}-{SEQ:4}', 'month', true, '运单费用统一台账编号'),
      ('tms.invoice_record', '开票登记号', 'business_document', 'tms_invoice', 'invoice_record_no', 'FPDJ{YYYYMM}-{SEQ:4}', 'month', true, '发票代码和发票号码属于外部法定号码，不在本规则内'),
      ('tms.receipt_exception', '回单异常工单号', 'business_document', 'tms_receipt_exception_work_order', 'work_order_no', 'HDYC{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('master.customer', '客户编码', 'master_data', 'tms_customer', 'customer_code', 'KH{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('master.carrier', '承运商编码', 'master_data', 'tms_carrier', 'carrier_code', 'CYS{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('master.cargo', '货物编码', 'master_data', 'tms_cargo', 'cargo_code', 'HW{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('master.station', '站点编码', 'master_data', 'tms_station', 'station_code', 'ZD{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('vehicle.archive_self', '车辆自编号', 'vehicle', 'vehicle_archive', 'self_no', 'ZBH{YYYYMM}-{SEQ:4}', 'month', false, '车牌号、车架号等外部标识不在本规则内'),
      ('vehicle.inspection', '车辆年检单号', 'vehicle', 'vehicle_inspection', 'inspection_no', 'NJ{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('vehicle.maintenance', '车辆维修单号', 'vehicle', 'vehicle_maintenance_record', 'maintenance_no', 'WX{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('vehicle.part', '配件编码', 'vehicle', 'vehicle_parts', 'part_code', 'LP{YYYYMM}-{SEQ:4}', 'month', true, null),
      ('vehicle.part_category', '配件分类编码', 'vehicle', 'vehicle_parts_category', 'category_code', 'LPLB{YYYYMM}-{SEQ:3}', 'month', true, null),
      ('vehicle.routine_inspection', '车辆例检单号', 'vehicle', 'vehicle_routine_inspection_record', 'routine_inspection_no', 'LJ{YYYYMM}-{SEQ:4}', 'month', true, null)
  ) as item(
    rule_key,
    rule_name,
    category,
    target_table,
    target_column,
    template,
    reset_cycle,
    manual_required,
    remark
  )
  on conflict (tenant_id, rule_key) do nothing;
end;
$function$;

insert into public.sys_document_number_rule (
  tenant_id,
  rule_key,
  rule_name,
  category,
  target_table,
  target_column,
  auto_enabled,
  template,
  reset_cycle,
  sequence_start,
  timezone,
  manual_required,
  builtin,
  enabled,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  scene.rule_key,
  scene.rule_name,
  scene.category,
  scene.target_table,
  scene.target_column,
  true,
  scene.default_template,
  scene.default_reset_cycle,
  1,
  'Asia/Shanghai',
  scene.manual_required,
  true,
  true,
  scene.remark,
  'number-engine',
  'number-engine'
from public.sys_tenant tenant
cross join public.sys_document_number_scene scene
where scene.rule_key = 'tms.expense_item'
on conflict (tenant_id, rule_key) do nothing;

drop trigger if exists document_number_item_code on public.tms_expense_item;

create trigger document_number_item_code
before insert on public.tms_expense_item
for each row
execute function app_private.trg_assign_configurable_number('tms.expense_item', 'item_code');

;
