# MES 生产执行交付记录（2026-09-20）

目标项目：`ckbftoopuyophiebamwy`。数据库改动经 Supabase MCP 直接执行；本仓库不保存迁移 SQL。

## 业务边界

- 生产范围按租户、车间和工作中心筛选。生产报工、出勤、现场事件、缺陷原因和报工不良分别存储在 `mes_production_report`、`mes_execution_attendance`、`mes_execution_event`、`mes_defect_reason`、`mes_report_defect`。
- 工序任务和工单沿用已有 MES 主数据。报工审批采用一级审批；审批通过后才计入已审批数量。现场写入仅通过校验权限、租户、任务状态和数量的业务 RPC。
- 设备管理通过 `mes_list_pmis_equipment_tasks` 读取 PMIS 点检、巡检、保养任务；工作中心筛选覆盖设备直接归属和设备工作中心关联。MES 现场补充记录独立展示。
- 工序任务首次报工固定机台归属，后续报工沿用且不可改绑。`mes_operation_task` 保存设备 ID、锁定标记、编码和名称快照，`mes_production_report` 保存设备 ID；机台达成率以任务绑定的设备归集。没有关联可用设备的工作中心仍可报工，首次报工会固定为“未分配机台”；历史空值不回填到主设备。
- `mes_list_work_center_equipment` 只返回当前租户可读工作中心关联的启用、在用、正常设备。`mes_submit_production_report` 在服务器端重验设备租户、工作中心归属、状态及任务固定绑定，不能依赖前端下拉选项。

## 租户与权限

- 五张新增业务表均启用 RLS。`tenant_select` 按 `tenant_in_current_read_scope(tenant_id)` 和业务查看权限读取。
- 管理员跨租户写入使用单独的 INSERT、UPDATE、DELETE 策略，不再通过 `FOR ALL` 扩大 SELECT。生产执行与关联的工序任务、排产规则、生产工单等 11 张 MES 表的原策略保存在 `app_private.codex_backup_mes_execution_policies_20260920`，共 27 条策略快照。
- PMIS 读取 RPC 校验登录状态和 `MesEquipment:View`，对任务、计划、设备、部门及负责人关联强制同租户，并限制可读租户范围。仅 `authenticated` 可执行；`anon` 和 `PUBLIC` 无执行权限。
- 原报工提交函数定义保存在 `app_private.codex_backup_mes_equipment_binding_20260920`。新机台选项 RPC 仅授权 `authenticated` 执行，读范围与租户选择一致。

## 验证与回退

- `sys_menu` 中生产执行目录的图标从 `ri:factory-line` 调整为可见的 `ri:play-circle-line`。原 `meta` 已备份至 `app_private.codex_backup_mes_execution_menu_icon_20260920`；回退时按菜单 ID 从该表恢复 `meta`。
- 生产执行列表统一使用 `ArtTableQuery` 的搜索区、表格和分页；专注模式入口位于页头 `BusinessTableWorkspaceActions`，表格在专注模式下保留退出入口。范围面板统一使用 `ArtWorkspaceSplitter` 的拖拽和收起能力，工作中心与任务列表使用 `ElScrollbar`。表格不再叠套 `ArtSectionCard`，表头显示当前数量和生产范围；列表高度随记录数收合。
- 列表区移除单独的刷新按钮，页头保留仓库通用的图标刷新。查询区重置在异步请求中显示加载状态。生产报工的开始加工、工序报工和记录投料在任务信息区显示，并按按钮权限和任务状态控制；设备任务页将 PMIS 跳转、搜索和现场补充记录分层。
- 浏览器核对生产报工、杂项计件、报工明细、调机明细、不良原因配置、机台达成率和设备任务的宽屏布局、空状态、专注模式；约 1365 CSS 像素宽度下生产报工与杂项计件无页面级横向溢出。

- 策略先在事务中创建、检查并回滚，再直接应用。11 张目标表均只有租户限定的 SELECT 与各自的业务和管理员写策略；不存在 `FOR ALL` 策略。
- 使用事务内样本验证平台全部租户可见两租户数据，选定租户仅见其数据；普通用户伪造其他租户请求头后仍绑定本租户。样本数据已回滚。
- 对既有工序任务和工单验证平台全部、平台选定与普通用户伪造租户头的读取范围。报工机台列、外键、索引和 RPC 先经事务回滚检查，再应用；事务内验证有设备时必选、选定后不可改绑、后续报工继承，以及无可用设备时固定为未分配机台。测试报工均已回滚。
- PMIS RPC 在事务中先验证再应用；平台全部、平台选定、普通本租户和伪造租户头四种读取范围均通过。浏览器可见点检 18 条、巡检 9 条，保养当前 0 条。
- 前端 `vue-tsc`、生产执行文件定向 ESLint/Stylelint 与机台归集单元测试通过；浏览器核对设备任务和机台达成页，历史任务明确显示为“未分配机台”。模块全量 `pnpm check` 当前停在并行修改中的 `src/api/manufacturing.ts` 行尾格式，与生产执行文件无关。
- 回退 RLS 时根据备份表复核原策略定义，在事务中撤销新增三类写策略并恢复原策略；回退机台绑定时先恢复备份的报工函数，再移除新增 RPC 和设备字段、外键、索引；回退 PMIS 集成时移除 `mes_list_pmis_equipment_tasks` 函数。回退前应重新评估租户读取隔离，避免恢复跨租户读取问题。
- Supabase advisors 的全局告警仍包含历史 `pg_net` public 扩展和大量既有 SECURITY DEFINER 函数；本次两个只读 RPC 的已授权执行也被通用规则提示。业务表新建索引尚无使用量，属于初始空表状态。
