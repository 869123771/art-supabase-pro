# 收料通知单优化记录（2026-09-24）

## 范围

- 收料通知单使用系统编号场景 `scm.receipt_notice`，按月重置，编号模板 `SLTZ{YYYYMM}-{SEQ:3}`。在现有系统编号规则中可按租户配置。
- 明细可参选同供应商、同项目且未交完的已审核采购订单行；来源记录采购订单编号及行号。库存、基本和辅助数量按物料单位换算。批号可从库存批号主档参选，启用批号管理的物料可按规则生成批号。
- 从已确认的通知单勾选明细，下推生成收料入库或资产应付草稿。同一通知单行在同一目标类型下只能下推一次。收料入库确认时按数据库物料单位换算写入 WMS 批次与库存流水；资产应付审核时形成已审核应付记录。
- 下推金额与通知单一致：折后金额、税额分别取两位小数再相加。极小金额预检中，折后基数 `0.045`、税率 `10%` 的价税合计为 `0.05`；旧算法会产生 `0.06`。
- 两类目标单据都有独立菜单、只读明细和状态动作。通知单的导入、选单、下推权限已增加，“获取最近采购价”权限已移除。

## 数据库与安全边界

- 扩展了 `app_private.trg_number_scm_purchase_contract()` 和 `app_private.guard_scm_purchase_document()`：分别负责通知单系统编号、逐行采购订单来源及未交数量验证。
- 新增 `app_private.scm_receipt_batch_counter` 与 `public.scm_generate_receipt_batch_no_secure`。计数器拒绝直接访问，生成函数检查物料批号管理、规则、租户与按钮权限。
- 新增 `public.scm_receipt_target_document`、`public.scm_receipt_target_line` 和两个安全函数 `scm_push_receipt_lines_secure`、`scm_transition_receipt_target_secure`。目标表仅开放按租户和目标菜单权限过滤的读取；写入只通过安全函数，函数验证当前写入租户及相应按钮权限。
- `app_private.scm_receipt_stock_quantity` 根据 MDM 物料采购单位与库存单位换算，确认入库时使用数据库计算值。WMS 批次补充货主类型与货主 ID，相同租户、仓库、仓位、物料、批号、货主的现有正常批次累加库存。
- 已为新增外键建立索引。目标单据和批号计数器均启用 RLS。

## 验证

- 编号规则、来源校验、批号生成、下推和确认函数均先在事务中创建并回滚预检，再应用到项目 `ckbftoopuyophiebamwy`。
- 回滚集成演练：将现有采购订单临时审核，创建并确认一张临时通知单；同一明细分别下推入库和应付，重复下推被唯一约束拒绝；入库确认写入 1000 库存单位及流水，应付审核状态正确。最终回滚后原订单仍为草稿，临时通知单和目标单据数量均为零。
- 金额边界回滚演练：临时采购订单与通知单的物料行设为单价 `0.05`、折扣 `10%`、税率 `10%`，下推资产应付后数据库实际金额为 `0.05`。事务回滚后原采购订单仍为草稿，收料通知单和目标单据均为零。
- 权限回滚演练：已授权普通租户角色拥有下推和目标新增权限；伪造跨租户写入、无角色账号下推、未登录下推均被拒绝。
- SCM 模块类型检查、根项目类型检查、UI 审计与修改文件 ESLint 通过。根项目复用审计有 4 处未涉及本改动的 MDM 仓储弹窗文本规范问题；WMS 模块类型检查有已存在的已安装平台包 `ArtApplicationSwitcher.vue` 缺少 `scm` 映射问题。
- 平台管理运行于 3006 端口，SCM 独立应用运行于 3021 端口。使用已授权账号在 3021 的真实浏览器核验了收料通知单列表、新增弹窗、项目与供应商参选、批量参选物料、10/20 行号、仓库参选，以及桌面和窄屏列表布局。当前租户没有可参选的已审核未交采购订单；选单弹窗现在仍会打开并显示空状态，已在浏览器复核。WMS 3018 与 FMS 3012 的登录后页面视觉核验未完成；按用户要求停止了临时启动的两个服务以减少电脑负载。用户已有 Chrome 无痕超级管理员会话并开启了扩展的无痕访问，但浏览器控制连接仍无法读取其页签；超级管理员页面实测未完成。
- 数据库顾问的 [安全函数提示](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) 对两条已授权 RPC 属于预期：函数内部校验按钮权限和当前写入租户。新增目标索引在空表上尚未被使用，属于 [未使用索引提示](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)。

## 恢复信息

原编号触发器、单据校验触发器和被删除的 `RecentPrice` 菜单授权记录已在变更前分别备份到：

- `C:/Users/EDY/AppData/Local/Temp/scm-receipt-number-backup-20260924.json`
- `C:/Users/EDY/AppData/Local/Temp/scm-receipt-guard-backup-20260924.json`
- `C:/Users/EDY/AppData/Local/Temp/scm-receipt-menu-backup-20260924.json`
- `C:/Users/EDY/AppData/Local/Temp/scm-receipt-push-before-rounding-20260924.sql`

恢复时先停用对应目标页面和下推操作，再按备份函数定义恢复触发器，最后清理本次新增且无业务数据的目标单据、批号计数器、菜单和编号规则。已有确认入库的库存流水必须先完成业务冲销，不能直接删除。
