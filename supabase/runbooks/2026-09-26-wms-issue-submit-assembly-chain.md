# WMS 领料提交权限与项目装配 SN 全链路验证

2026-09-26，目标 Supabase 项目：`ckbftoopuyophiebamwy`。

## 领料申请提交权限

领料申请当前状态机为 `draft → submitted → approved → fulfilled`。`WmsIssueRequest:Submit` 按钮菜单已存在，但缺少 `is_auth_button` 标记，也未授予角色；可创建及审核的普通业务账号因此无法提交草稿。

- 变更前的菜单和授权记录已备份至本地忽略文件 `.artifacts/wms-issue-submit-menu-before-20260926.json`。
- 在生产项目的事务中先执行 `BEGIN/ROLLBACK` 演练，再直接执行相同更新并提交：将菜单 `meta.is_auth_button` 设为 `true`；仅给同时拥有 `WmsIssueRequest:Create` 与 `WmsIssueRequest:Approve` 的角色补充提交权限。未扩大到其他角色。
- 变更后菜单存在且启用，两个既有角色取得提交授权。普通受权账号 `has_permission('WmsIssueRequest:Submit') = true`；同租户未授权账号及其他角色账号均为 `false`。普通账号伪造其他租户请求头后，权限仍由本人的角色决定。

## 装配制造验收

使用 `.artifacts/wms-assembly-chain-rollback-20260926.sql` 在 `BEGIN/ROLLBACK` 事务中完成完整链路：SCM 关键件采购收货与 SN 入库 → MES 工单确认、SN 预留 → WMS 领料申请提交、审核、领料出库 → MES 报工审核 → 主机 SN 生产入库及父子 SN 绑定 → SCM 销售发货与 WMS 销售出库 → 项目施工号 SN 追溯。

验收结果：领料申请 `fulfilled`，工单 `DLV`，发货通知 `shipped`，主机及子件 SN 均为 `out`；子件 `parent_serial_id` 指向主机，子件已消耗的工单、主机生产工单及两者项目施工号一致。项目 SN 查询返回主机与子件两条记录，主机包含子件编码；项目汇总包含两条 SN。关键件预留状态为 `consumed`，流水分别包含领料出库、生产入库和销售出库。

演练事务已回滚；`CHAIN-%` 测试 SN、`CHAIN-MEP-01` 施工号与 `SNCHAINTEST` 编码规则的残留数量均为零。Supabase 安全顾问无此次菜单数据变更新增项；当前项目仍有既存的 `pg_net` 位于 `public`、可由已登录用户调用的安全定义者函数，以及泄漏密码保护配置告警，详见 [Supabase 数据库检查说明](https://supabase.com/docs/guides/database/database-linter)。

## 普通非项目业务回归

同日重新执行 `.artifacts/wms-nonproject-chain-rollback-20260926.sql`，按当前状态机加入领料申请提交步骤。普通装配工单完成采购入库、确认下达、领料审核出库、七道工序报工、成品生产入库及销售发货；工单为 `DLV`，领料申请为 `fulfilled`，发货通知为 `shipped`。原料批次、工单、成品批次及领料/生产/销售流水的项目与施工号均为 `NULL`，不受项目库存隔离误拦截。事务回滚后 `CHAIN-PUBLIC-*` 工单、批次、采购单和发货单均无残留。
