# WMS 菜单与视图目录对齐

2026-09-26 按 `views/<二级分类>/<页面>/index.vue` 整理 WMS：直接与分步调拨归入 `transfer-business`，库存盘点归入 `count-business`，库存调整与组装归入新增的 `adjustment-business`。原 `transfer-adjustment` 路径经 `resolveLegacyBusinessPath` 重定向到新地址。

菜单变更在 `.artifacts/wms-menu-hierarchy-before-20260926.json` 备份 5 条原菜单与 10 条角色授权后，使用 `2026-09-26-wms-menu-hierarchy.sql` 先回滚演练再提交。4 个原菜单改为可见并更新组件路径；新增“库存调整”分类与“分步调拨”入口，均按现有 WMS 分类和调拨菜单复制到 2 个租户角色。提交后核对：所有 WMS 叶子菜单的组件目录与父分类一致，新增两项各有 2 条角色授权。

验证：WMS `vue-tsc`、权限审计、UI 审计、复用审计、目标文件 ESLint、业务路径单元测试 5 项均通过。Playwright 模拟鉴权在桌面 1440 px 和移动 390 px 打开 5 个调整后的页面，均成功加载，无页面异常或横向溢出；截图保存在 `.artifacts/wms-menu-*-desktop.png` 和 `*-mobile.png`。

随后核对全部 33 个 WMS 页面菜单的组件文件：32 个标准 `/index` 路径均存在，工作台的 `/wms/workbench` 对应 `views/workbench/index.vue`。盘盈、盘亏独立单据页明确说明：盘点方案自动生成的凭证在同分类的“库存盘点”详情查看；桌面和移动端页面再次通过浏览器检查。

出库申请单原先通过 `outbound-business` 下的包装页引用 `receipt-issue/issue-request` 页面，目录仍与菜单不一致。现将页面及局部模块直接放到 `outbound-business/outbound-request`，工作台快捷入口和旧书签跳转同步更新；该页桌面、移动端加载与 WMS 类型检查再次通过。

使用浏览器分别对出库申请和库存组装弹窗执行“打开 → 关闭 → 再打开”，两者第二次均正常显示，未出现页面异常。

紧凑型业务页表头在桌面宽度扩大操作区：两个开关与主按钮保持同一行，按钮位于开关右侧；900 px 以下沿用整行换行布局。1440 px 桌面截图及 390 px 移动截图复核无横向溢出；盘盈单专注模式截图确认主按钮移到表格上方左侧（`.artifacts/wms-count-gain-focus-desktop.png`）。

根项目 `pnpm typecheck` 在默认 4 GB Node 堆限制处内存溢出，未得到全仓结果；WMS 子模块 `vue-tsc`、改动路径的单元测试与 ESLint 均通过。
