# WMS 工单预留与 SN 锁定

2026-09-26 已在 Supabase 项目 `ckbftoopuyophiebamwy` 直接更新以下数据库触发函数。变更前函数定义保存在本机忽略目录 `.artifacts/`，没有提交迁移 SQL 文件。

## 生效逻辑

- `app_private.validate_wms_reservation`：指定批次预留时，除仓位汇总校验外，扣除该批次已绑定预留及同仓位未绑定批次的有效预留，阻止单批次超额占用。失效或零库存批次不能预留。
- `app_private.wms_work_order_reservation_guard`：工单确认自动分配批次时，对启用序列号管控的原料同步锁定等量在库 SN；SN 不足或数量非整数时，整笔确认回滚。结案或删除工单时，释放有效批次预留与尚未领用的 SN 锁定。

两项变更保持原有租户、库存组织、项目施工号及仓库类型校验。SN 仍只能从实际预留的批次选择。

## 验证

- 回滚事务：同仓位另有批次库存时，指定批次超额预留被拒；恰好等于可用量的预留成功。
- 回滚事务：缺少 SN 时工单确认被拒；补齐 SN 后批次与 SN 同时预留；结案后二者同时释放。
- 测试结束核对：工单恢复待确认，测试序列号和编码规则数量均为零；原有预留状态未变化。
- Supabase Security / Performance Advisor 已运行。项目已有的跨模块告警仍存在，本次修改没有新增公开 RPC、表或 RLS 策略。

关联前端：`modules/art-supabase-wms/src/views/receipt-issue/issue-request/modules/issue-request-post-dialog.vue` 将本工单预留 SN 排在前面并默认带入。
