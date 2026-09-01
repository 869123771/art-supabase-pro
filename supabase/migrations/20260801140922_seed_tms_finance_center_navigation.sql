-- TMS 财务结算中心第一阶段：菜单、管理员授权与前端所需字典。
-- 业务表、RLS 与真实结算逻辑将在第二阶段单独迁移。

insert into public.sys_menu
  (id, parent_id, name, path, component, type, sort, meta, create_by, update_by)
values
  ('a1000000-0000-4000-8000-000000000001', '5cb6af14-977a-4a51-8e4d-107db0f1af2e', 'TmsFinanceCenter', 'finance-center', '', 'folder', 9, '{"icon":"ri:money-cny-circle-line","title":"财务结算","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'TmsFinanceWorkbench', 'workbench', '/tms-transportation/finance-center/workbench', 'menu', 1, '{"icon":"ri:dashboard-3-line","title":"结算工作台","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', 'TmsCustomerSettlement', 'customer-settlement', '/tms-transportation/finance-center/customer-settlement', 'menu', 2, '{"icon":"ri:user-received-2-line","title":"客户对账","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001', 'TmsCarrierSettlement', 'carrier-settlement', '/tms-transportation/finance-center/carrier-settlement', 'menu', 3, '{"icon":"ri:truck-line","title":"承运商对账","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000001', 'TmsCashTransaction', 'cash-transaction', '/tms-transportation/finance-center/cash-transaction', 'menu', 4, '{"icon":"ri:exchange-cny-line","title":"收付款管理","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-000000000001', 'TmsInvoiceManagement', 'invoice-management', '/tms-transportation/finance-center/invoice-management', 'menu', 5, '{"icon":"ri:bill-line","title":"发票管理","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-000000000001', 'TmsWaybillCost', 'waybill-cost', '/tms-transportation/finance-center/waybill-cost', 'menu', 6, '{"icon":"ri:coins-line","title":"运单费用","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-000000000001', 'TmsWaybillProfit', 'waybill-profit', '/tms-transportation/finance-center/waybill-profit', 'menu', 7, '{"icon":"ri:line-chart-line","title":"运单利润","is_enable":true,"keep_alive":true}'::jsonb, '624944977@qq.com', '624944977@qq.com')
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

-- 财务菜单只授予管理员角色，不向注册用户或只读看板角色开放。
insert into public.sys_role_menu
  (role_id, menu_id, tenant_id, permission, create_by, update_by)
select r.id, m.id, r.tenant_id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role r
cross join public.sys_menu m
where r.role_code in ('R_SUPER', 'R_ADMIN', 'YQ_ADMIN')
  and m.id between 'a1000000-0000-4000-8000-000000000001'::uuid
               and 'a1000000-0000-4000-8000-000000000008'::uuid
on conflict (role_id, menu_id) do update set
  tenant_id = excluded.tenant_id,
  permission = excluded.permission,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_dict_type
  (id, name, code, status, tenant_id, parent_id, node_type, sort, create_by, update_by)
values
  ('b1000000-0000-4000-8000-000000000001', '财务结算', 'tmsFinance', '1', '028e6a68-a9db-4055-974c-1e05bfe94b0f', '938f0e35-650c-464b-8363-6d1b0b0ae0ce', 'directory', 5, '624944977@qq.com', '624944977@qq.com')
on conflict (code) do update set
  name = excluded.name, status = excluded.status, tenant_id = excluded.tenant_id,
  parent_id = excluded.parent_id, node_type = excluded.node_type, sort = excluded.sort,
  update_by = excluded.update_by, update_time = now();

with finance_directory as (
  select id from public.sys_dict_type where code = 'tmsFinance'
), dictionary_types(id, name, code, sort) as (
  values
    ('b1000000-0000-4000-8000-000000000002'::uuid, '结算类型', 'tmsSettlementType', 1),
    ('b1000000-0000-4000-8000-000000000003'::uuid, '对账状态', 'tmsSettlementStatus', 2),
    ('b1000000-0000-4000-8000-000000000004'::uuid, '收付方向', 'tmsCashDirection', 3),
    ('b1000000-0000-4000-8000-000000000005'::uuid, '收付款状态', 'tmsCashTransactionStatus', 4),
    ('b1000000-0000-4000-8000-000000000006'::uuid, '支付方式', 'tmsCashPaymentMethod', 5),
    ('b1000000-0000-4000-8000-000000000007'::uuid, '发票方向', 'tmsInvoiceDirection', 6),
    ('b1000000-0000-4000-8000-000000000008'::uuid, '发票状态', 'tmsInvoiceStatus', 7),
    ('b1000000-0000-4000-8000-000000000009'::uuid, '发票类型', 'tmsInvoiceType', 8),
    ('b1000000-0000-4000-8000-00000000000a'::uuid, '运单费用类型', 'tmsWaybillCostType', 9),
    ('b1000000-0000-4000-8000-00000000000b'::uuid, '费用审核状态', 'tmsCostAuditStatus', 10)
)
insert into public.sys_dict_type
  (id, name, code, status, tenant_id, parent_id, node_type, sort, create_by, update_by)
select d.id, d.name, d.code, '1', '028e6a68-a9db-4055-974c-1e05bfe94b0f', f.id,
       'dictionary', d.sort, '624944977@qq.com', '624944977@qq.com'
from dictionary_types d cross join finance_directory f
on conflict (code) do update set
  name = excluded.name, status = excluded.status, tenant_id = excluded.tenant_id,
  parent_id = excluded.parent_id, node_type = excluded.node_type, sort = excluded.sort,
  update_by = excluded.update_by, update_time = now();

with dictionary_items(id, type_code, value, label, tag_type, sort) as (
  values
    ('c1000000-0000-4000-8000-000000000001'::uuid, 'tmsSettlementType', 'customer_receivable', '客户应收', 'primary', 1),
    ('c1000000-0000-4000-8000-000000000002'::uuid, 'tmsSettlementType', 'carrier_payable', '承运商应付', 'warning', 2),
    ('c1000000-0000-4000-8000-000000000003'::uuid, 'tmsSettlementStatus', 'draft', '草稿', 'info', 1),
    ('c1000000-0000-4000-8000-000000000004'::uuid, 'tmsSettlementStatus', 'pending_review', '待审核', 'warning', 2),
    ('c1000000-0000-4000-8000-000000000005'::uuid, 'tmsSettlementStatus', 'confirmed', '已确认', 'primary', 3),
    ('c1000000-0000-4000-8000-000000000006'::uuid, 'tmsSettlementStatus', 'partially_settled', '部分结算', 'warning', 4),
    ('c1000000-0000-4000-8000-000000000007'::uuid, 'tmsSettlementStatus', 'settled', '已结清', 'success', 5),
    ('c1000000-0000-4000-8000-000000000008'::uuid, 'tmsSettlementStatus', 'voided', '已作废', 'danger', 6),
    ('c1000000-0000-4000-8000-000000000009'::uuid, 'tmsCashDirection', 'receipt', '收款', 'success', 1),
    ('c1000000-0000-4000-8000-00000000000a'::uuid, 'tmsCashDirection', 'payment', '付款', 'warning', 2),
    ('c1000000-0000-4000-8000-00000000000b'::uuid, 'tmsCashTransactionStatus', 'pending_allocation', '待核销', 'warning', 1),
    ('c1000000-0000-4000-8000-00000000000c'::uuid, 'tmsCashTransactionStatus', 'partially_allocated', '部分核销', 'primary', 2),
    ('c1000000-0000-4000-8000-00000000000d'::uuid, 'tmsCashTransactionStatus', 'allocated', '已核销', 'success', 3),
    ('c1000000-0000-4000-8000-00000000000e'::uuid, 'tmsCashTransactionStatus', 'voided', '已作废', 'danger', 4),
    ('c1000000-0000-4000-8000-00000000000f'::uuid, 'tmsCashPaymentMethod', 'bank_transfer', '银行转账', 'primary', 1),
    ('c1000000-0000-4000-8000-000000000010'::uuid, 'tmsCashPaymentMethod', 'cash', '现金', 'success', 2),
    ('c1000000-0000-4000-8000-000000000011'::uuid, 'tmsCashPaymentMethod', 'wechat', '微信', 'success', 3),
    ('c1000000-0000-4000-8000-000000000012'::uuid, 'tmsCashPaymentMethod', 'alipay', '支付宝', 'primary', 4),
    ('c1000000-0000-4000-8000-000000000013'::uuid, 'tmsCashPaymentMethod', 'other', '其他', 'info', 5),
    ('c1000000-0000-4000-8000-000000000014'::uuid, 'tmsInvoiceDirection', 'output', '销项发票', 'primary', 1),
    ('c1000000-0000-4000-8000-000000000015'::uuid, 'tmsInvoiceDirection', 'input', '进项发票', 'success', 2),
    ('c1000000-0000-4000-8000-000000000016'::uuid, 'tmsInvoiceStatus', 'draft', '草稿', 'info', 1),
    ('c1000000-0000-4000-8000-000000000017'::uuid, 'tmsInvoiceStatus', 'pending_review', '待复核', 'warning', 2),
    ('c1000000-0000-4000-8000-000000000018'::uuid, 'tmsInvoiceStatus', 'issued', '已开票', 'primary', 3),
    ('c1000000-0000-4000-8000-000000000019'::uuid, 'tmsInvoiceStatus', 'certified', '已认证', 'success', 4),
    ('c1000000-0000-4000-8000-00000000001a'::uuid, 'tmsInvoiceStatus', 'voided', '已作废', 'danger', 5),
    ('c1000000-0000-4000-8000-00000000001b'::uuid, 'tmsInvoiceType', 'vat_special', '增值税专用发票', 'primary', 1),
    ('c1000000-0000-4000-8000-00000000001c'::uuid, 'tmsInvoiceType', 'vat_ordinary', '增值税普通发票', 'success', 2),
    ('c1000000-0000-4000-8000-00000000001d'::uuid, 'tmsInvoiceType', 'electronic', '电子发票', 'info', 3),
    ('c1000000-0000-4000-8000-00000000001e'::uuid, 'tmsWaybillCostType', 'toll', '路桥费', 'primary', 1),
    ('c1000000-0000-4000-8000-00000000001f'::uuid, 'tmsWaybillCostType', 'parking', '停车费', 'info', 2),
    ('c1000000-0000-4000-8000-000000000020'::uuid, 'tmsWaybillCostType', 'fuel', '油费', 'warning', 3),
    ('c1000000-0000-4000-8000-000000000021'::uuid, 'tmsWaybillCostType', 'loading', '装卸费', 'primary', 4),
    ('c1000000-0000-4000-8000-000000000022'::uuid, 'tmsWaybillCostType', 'waiting', '等候费', 'warning', 5),
    ('c1000000-0000-4000-8000-000000000023'::uuid, 'tmsWaybillCostType', 'driver_expense', '司机报销', 'success', 6),
    ('c1000000-0000-4000-8000-000000000024'::uuid, 'tmsWaybillCostType', 'cargo_damage', '货损赔偿', 'danger', 7),
    ('c1000000-0000-4000-8000-000000000025'::uuid, 'tmsWaybillCostType', 'other', '其他费用', 'info', 8),
    ('c1000000-0000-4000-8000-000000000026'::uuid, 'tmsCostAuditStatus', 'draft', '草稿', 'info', 1),
    ('c1000000-0000-4000-8000-000000000027'::uuid, 'tmsCostAuditStatus', 'pending_review', '待审核', 'warning', 2),
    ('c1000000-0000-4000-8000-000000000028'::uuid, 'tmsCostAuditStatus', 'approved', '已审核', 'success', 3),
    ('c1000000-0000-4000-8000-000000000029'::uuid, 'tmsCostAuditStatus', 'rejected', '已驳回', 'danger', 4),
    ('c1000000-0000-4000-8000-00000000002a'::uuid, 'tmsCostAuditStatus', 'voided', '已作废', 'danger', 5)
)
insert into public.sys_dictionary
  (id, type_id, code, status, value, label, sort, tenant_id, tag_type, create_by, update_by)
select i.id, t.id, i.value, '1', i.value, i.label, i.sort,
       '028e6a68-a9db-4055-974c-1e05bfe94b0f', i.tag_type,
       '624944977@qq.com', '624944977@qq.com'
from dictionary_items i
join public.sys_dict_type t on t.code = i.type_code
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tenant_id = excluded.tenant_id, tag_type = excluded.tag_type,
  update_by = excluded.update_by, update_time = now();

;
