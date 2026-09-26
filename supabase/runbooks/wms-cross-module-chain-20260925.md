# WMS 跨模块链路核对（2026-09-25）

项目：`ckbftoopuyophiebamwy`。本仓不保存数据库迁移历史；数据库对象以该项目当前实际定义为准。
`wms-count-adjustment-20260925.md` 记录的是领料申请表和菜单上线前的历史检查，本文件更新该环节的当前状态。

## 已核对的业务顺序

| 来源 | 业务前置 | WMS 执行 | 服务端边界 |
| --- | --- | --- | --- |
| MDM 仓库与物料 | 有效物料、启用仓库、所属组织、业务范围及库位策略 | 所有仓储作业 | 租户、仓库类型、业务范围、库位和物料身份由受控 RPC 复核 |
| SCM 采购收料 | 采购收料明细下推入库草稿 | 收料入库确认 | 来源明细、数量和租户关系复核；确认后形成库存流水 |
| MES 工单领料 | 已下达工单；领料仓库包含「拣货」，且组织和仓库类型匹配 | 申请、审核、分批领料 | 申请余额与出库流水一并核销 |
| MES 完工 | 已审核生产报工 | 生产入库 | 入库累计量不超过已审核完工量；物料和项目归属复核 |
| SCM 发货通知 | 已提交发货通知 | 销售出库 | 通知行及剩余数量复核；出库更新来源单据状态 |

本次补充了 SCM 采购下推后直达入库草稿、SCM 发货通知直达销售出库、MES 工单直达领料申请，以及 WMS 工作台的领料申请入口。深链接只负责预选，服务端仍独立验证租户、权限、来源和数量。
跨模块办理人需同时取得来源页面和目标 WMS 作业的权限；不因拥有 SCM 或 MES 权限而自动获得库存过账权限。

## 数据库与权限

- 新增动态菜单 `WmsIssueRequest`，组件 `/wms/receipt-issue/issue-request/index`，附带 `View`、`Create`、`Approve`、`Issue`、`Cancel` 按钮权限。沿用 WMS 库存作业现有授权角色，菜单与按钮各有 2 个角色关联。
- `public.wms_work_order_options_secure(uuid,text)` 允许持有 `WmsIssueRequest:Create` 的用户选择工单，并返回 `organizationId` 和 `allowedIssueWarehouseTypes` 供页面筛选；函数本身继续校验登录、权限和仓库租户读取范围。数据库函数保持 `SECURITY DEFINER`、空 `search_path` 和原有授权。
- 已核对 `wms_issue_request`、`wms_issue_request_line`、`wms_issue_request_allocation` 三表均启用 RLS，仅给 authenticated 角色 SELECT，读取策略均为 `app_private.tenant_in_current_read_scope(tenant_id)`。创建、审核、过账、取消 RPC 均存在且仅通过受控函数写入。
- 直接核对 `wms_work_order_options_secure` 函数定义、上述菜单和角色、三表 RLS/授权及四个领料申请 RPC。函数变更前定义存于本地忽略目录 `.artifacts/`，用于现场回滚参考。

## 尚无共同业务契约的环节

TMS 运单/装车与 SCM 发货通知、WMS 出库之间尚无共同来源 ID、交接回执及数量冲销契约。当前销售链路已到库存出库，不能把出库视作承运交接完成。到货预约、波次拣选和复核也不是现有直接出入库页面的等价功能；需先明确单据状态机、幂等键及承运责任边界，再接入真实过账。

## 验证

- 前端：根项目 `typecheck`、`build`、`ui:audit`、`permissions:audit`、`reuse:audit` 均通过；WMS、SCM、MES 子仓类型检查和改动文件 ESLint 均通过。
- 数据库：菜单、RPC、RLS 与 SELECT/EXECUTE 授权查询已核对。Supabase Security Advisor 仍报告项目既有的 `pg_net` public 扩展及大量可调用的 `SECURITY DEFINER` 函数警告；需按具体函数权限判断，不属于本次新建宽授权。
- 浏览器：使用已有测试会话及模拟菜单运行 `mdm-wms-mes.smoke.spec.ts` 的 WMS 工作台用例，1440 px 页面、空权限提示及无横向溢出检查通过，截图已人工检查。新浏览器会话仍停在登录页；完整跨模块点击和普通租户角色流程还需有效业务会话验收。
- 当前项目数据中领料申请和销售出库流水均为 0 条，因此没有用生产数据伪造一次成功过账；上述校验为对象、权限、前端构建和服务端定义检查。
