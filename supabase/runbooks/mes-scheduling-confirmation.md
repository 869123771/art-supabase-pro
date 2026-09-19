# MES 排产确认修复记录（2026-09-19）

目标项目：`ckbftoopuyophiebamwy`。

## 业务与数据约束

- `mes_operation_task.pending_schedule_quantity` 是生成列，表达式为 `greatest(planned_quantity - scheduled_quantity, 0)`。排产 RPC 只更新 `scheduled_quantity`，不直接写生成列。
- `public.mes_confirm_operation_task_schedule` 每次确认追加一条工作中心分配，并在任务行锁内校验本次数量不超过待排数量。已确认的分配继续保留；全部排完后待排数量为 0。
- `app_private.mes_allocate_operation_task` 仍用于“平均分配”的整体替换，已去除对生成列的直接赋值。
- 两个入口均要求 `MesOperationTask:Schedule`，写入限定到任务所属租户；普通用户的伪造租户请求头不能扩大写入范围。

## 回退资料

修改前的两个函数定义保存在 `app_private.codex_backup_mes_scheduling_20260919`，字段为 `function_signature`、`function_definition`、`backed_up_at`。回退前需先核对当前函数定义及依赖，再在事务中执行对应的原定义并验证。

## 验证

- 在事务中以有权限的租户用户确认 0.4，再确认 0.6：待排数量依次为 0.6、0；两条分配合计为 1。超量确认被拒绝。
- 在同一事务中验证“平均分配”可将两条分配替换为一条；事务回滚后，样本任务仍为已排 0、待排 1、无分配。
- 其他租户的有权限用户即使伪造目标租户请求头，仍无法修改样本任务。平台管理员在全部租户及选择其他租户的视图下均可操作明确指定的样本任务；测试事务均已回滚。
- MES 模块类型检查、相关文件 ESLint、排产规则单元测试和 Vite 生产构建通过。浏览器连接报错，修改后的页面尚未完成目视验证。
