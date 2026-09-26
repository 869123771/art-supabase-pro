# WMS 调拨与盘点业务交付记录

## 范围

- WMS 菜单按“出库业务、调拨业务、盘点业务”连续排列。
- 调拨业务新增调拨申请单。
- 盘点业务新增盘盈单、盘亏单。
- 初始化、入库、出库、调拨、盘点中的组织选择统一使用组织树。
- 调拨申请、盘盈、盘亏支持全屏抽屉、按钮式物料多选、只读详情布局。
- 盘盈、盘亏数量只在数量单元格显示浅黄色背景和红色加粗文字。
- 列表中的库存类型、库存状态等代码显示为中文业务名称。

## 数据库对象

- `wms_transfer_request_document`
- `wms_transfer_request_line`
- `wms_transfer_request_list`
- `wms_count_adjustment_document`
- `wms_count_adjustment_line`
- `wms_count_adjustment_list`
- `wms_save_transfer_request_secure`
- `wms_change_transfer_request_status_secure`
- `wms_push_transfer_request_secure`
- `wms_save_count_adjustment_secure`
- `wms_change_count_adjustment_status_secure`

业务写入、状态变更和下推由安全 RPC 完成。列表视图仅向已登录用户开放，并依赖租户范围策略过滤业务数据。

## 编号规则

- 调拨申请：按月三位流水。
- 盘盈单：按月三位流水。
- 盘亏单：按月三位流水。

## 流程验证

2026-09-26 使用租户 `7529f951-938e-4e2c-ac0d-316c136ae1f9` 的真实组织、物料、单位、仓库、项目和员工数据完成验证：

| 模块 | 单据 | 单据数 | 明细数 | 验证结果 |
| --- | --- | ---: | ---: | --- |
| 调拨申请 | `DBSQ202609-901`、`DBSQ202609-902` | 2 | 4 | 暂存、提交、审核、直接调拨/调出在途下推通过 |
| 盘盈单 | `PYRK202609-901`、`PYRK202609-902` | 2 | 4 | 暂存、提交、审核通过 |
| 盘亏单 | `PKCK202609-901`、`PKCK202609-902` | 2 | 4 | 提交、审核通过 |

使用普通 `authenticated` 身份读取列表视图验证通过：调拨申请 4 行、盘盈 4 行、盘亏 4 行。

## 前端验证

- WMS 模块边界审计通过。
- WMS UI 审计通过。
- WMS TypeScript 类型检查通过。
- WMS ESLint 通过。
- WMS 生产构建通过。
- 根仓库权限审计、复用审计、UI 审计、TypeScript、ESLint 和单元测试通过。

## Advisor 复核

执行 Supabase Security Advisor 与 Performance Advisor。当前报告仍包含项目历史范围的 `pg_net` public schema、已登录用户可执行的安全定义函数和未覆盖索引提示；本次新增业务对象采用现有安全 RPC 与租户边界设计，未发现本次流程验证阻断项。
