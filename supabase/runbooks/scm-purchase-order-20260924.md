# 采购订单优化（2026-09-24）

## 范围

- 采购订单使用系统编号规则，按月生成三位流水号；现有单据编号保留。
- 订单支持项目、MDM 供应商、采购员与货主参选，按行保存来源单据、单位换算、仓库仓位、价格、折扣、赠品和交货计划。
- 订单列表支持导入、导出、选单、复制、状态操作以及按明细下推。收料通知单使用现有流程；采购入库、退料申请、委外收货、委外入库下推为可追溯的目标草稿。
- 已交货数量和最近交货日期根据确认后的库存入库记录计算，不计入草稿目标单据。

## 已应用的数据库变更

迁移依次为 `scm_purchase_order_monthly_number_20260924`、`scm_purchase_order_actions_20260924`、`scm_purchase_order_source_and_amount_guard_20260924`、`scm_purchase_order_masterdata_and_provenance_guard_20260924`、`scm_purchase_order_inbound_progress_20260924`、`scm_purchase_order_target_draft_tables_20260924`、`scm_purchase_order_push_targets_20260924`、`scm_purchase_order_target_menus_20260924`、`scm_order_target_fk_indexes_20260924`。变更前原始订单快照保存在 `app_private.purchase_order_backup_20260924`。

`scm_push_purchase_order_lines_secure` 在数据库内核对来源订单状态、行号、租户写入范围、订单下推和目标新增权限；目标草稿表只有按租户和菜单权限读取的 RLS 策略，客户端无直接写入权限。同一来源行在同一目标类型下只能下推一次。`scm_purchase_order_inbound_progress_secure` 只读取有订单查看权限且处于可读租户范围的实际确认入库记录。

## 验证

- 事务回滚测试覆盖月度编号、物料单位换算和赠品金额归零。
- 事务回滚测试覆盖一条已审核采购订单明细下推到四类目标草稿；每类生成一张目标单，价税合计与来源行一致。
- SCM `pnpm typecheck`、`pnpm build`、变更文件 ESLint，以及根工程 `pnpm permissions:audit`、`pnpm ui:audit`。

## 业务边界

四个新目标当前只有草稿登记、查看和来源追溯。目标单据的审批、收退货执行、库存记账和委外结算尚无原有业务流程可沿用，不能将草稿视为已完成入库或退料。收料通知单仍走既有确认及入库链路。

## 回退

先停用新菜单和下推入口，再按迁移的逆序撤销新 RPC、触发器、目标草稿表和权限记录。需要恢复旧订单时，核对 `app_private.purchase_order_backup_20260924` 中的记录后按单据 ID 回填；不要覆盖变更后新增的订单。编号规则回退前，检查当月是否已有新编号，避免编号重用。
