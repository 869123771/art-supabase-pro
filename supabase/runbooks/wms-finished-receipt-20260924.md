# 成品入库目标仓校验（2026-09-24）

- 项目：`ckbftoopuyophiebamwy`
- 规则：`production_in` 办理 `FERT` 物料入库时，优先使用物料主数据指定的、已启用且有业务应用范围的成品仓。未指定有效成品仓时，仅有一个合格成品仓才自动选用；零个或多个时阻止入库并提示配置。其他物料的原有入库规则保持不变。
- 前端：库存业务弹窗显示目标仓和配置提示；物料主数据的成品入库仓库选项只列出合格成品仓。后台 `public.wms_post_inventory_movement_secure(jsonb)` 同样验证目标仓，不能靠伪造请求绕过。

## 数据保护与验证

变更前将库存业务函数定义及所有者保存于 `app_private.codex_backup_wms_production_destination_20260924`，备份核验为 1 行、定义 10026 字符、所有者 `postgres`。替换函数及新增内部校验函数先在事务中执行并回滚，再正式执行。内部函数为 `SECURITY INVOKER`，`search_path` 为空，`anon` 与 `authenticated` 均无直接执行权限；库存业务函数保留原有认证、权限和租户校验。

当前租户的唯一成品仓 `DEMO-WMS-FIN` 是演示数据，业务应用范围为空，不会被自动选为正式成品入库目标。事务内测试覆盖无合格成品仓时拒绝、传入错误原料仓时拒绝、唯一合格成品仓时允许；测试期间临时启用演示仓范围，随后回滚。演示仓正式业务范围仍为空。安全和性能顾问未报告与本次函数有关的新发现。

恢复时可先在事务中用备份表的 `function_definition` 还原 `public.wms_post_inventory_movement_secure(jsonb)` 并验证，再正式恢复。仅在确认没有其他调用方后移除 `app_private.assert_wms_finished_receipt_destination(uuid,uuid,uuid)`；保留备份直到仓储规则整体验收。

## 工单参照与快照一致性

原 `mes_work_order_material_options` 和 `mes_work_order_guard` 直接采用物料档案的入库仓库，包括被错误设置为原料仓的成品物料。已在 `app_private.codex_backup_mes_finished_destination_20260924` 保存这两项函数、目标仓校验函数以及当前租户 5 条已确认成品工单的快照。备份核验为 1 行；函数定义长度依次为 7618、6316、1479 字符。

新增内部解析函数 `app_private.wms_resolve_finished_receipt_warehouse(uuid,uuid,boolean)`，统一服务于库存入库校验、MES 物料参照和新建／待确认工单快照。优先选择物料配置的合格成品仓，否则仅在唯一合格成品仓时自动选用。参照和工单编辑以非严格模式返回空目标，界面提示补齐成品仓；实际入库以严格模式阻止无目标或多目标的业务。新函数为 `SECURITY INVOKER`，无匿名及普通认证角色的直接执行权限。

先在事务内执行并回滚，验证无合格成品仓时显示为空且严格校验拒绝、临时启用唯一演示成品仓后解析结果、MES 物料参照和待确认工单快照均一致，再正式应用。现有已确认工单的仓库字段为历史快照，其中 3 条指向类型为原料仓的旧配置；没有重写历史记录，后续成品入库始终重新按当前规则校验。演示仓正式业务范围仍为空。

应用后核对：备份 1 行、演示成品仓业务范围仍为空、演示工单解析目标为空，新增内部函数不允许 `authenticated` 直接执行。MES 新建工单选择成品物料时，缺少合格成品仓的提示显示在物料选择框下方；隔离模拟会话的 1440 宽度 Playwright 测试 `mes-finished-warehouse-prompt.spec.ts` 通过并已目视检查截图。真实登录服务在本次视觉测试期间出现连接重置，因此没有把该模拟测试当作实时认证链路验证。
