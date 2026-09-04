# MDM 主数据边界与迁移约定

## 应用承载

MDM 前端由独立子仓 `modules/art-supabase-mdm` 承载，应用代码为 `mdm`，默认开发端口为 `3017`。平台宿主可以按授权聚合其页面，独立发布路径为 `/art-supabase-mdm/`。

首版提供租户隔离的治理总览和只读统一目录。来源业务应用仍承担新增、修改、停用等写操作；等写契约和数据责任完成迁移后，再逐域把维护入口收敛到 MDM，避免过渡期双写。

## 目标

本项目将跨业务域复用、需要统一编码与租户隔离的稳定实体归入 `mdm_*`。交易、流程、台账、配置、权限与审计数据继续由原业务域负责，避免把 MDM 扩张成新的业务单体。

MDM 首先是共享数据库契约，同时由独立 MDM 应用承载跨域治理入口。现有 HR、TMS、VMS、SMIS 页面在迁移期继续承担维护入口，但读写目标必须使用实体 `mdm_*` 表或受控 RPC。

## 已落地模型

| 主数据域 | MDM 实体表 | 旧契约 |
| --- | --- | --- |
| 组织 | `mdm_organization` | `sys_organization` |
| 人员 | `mdm_employee`、`mdm_employee_assignment` | `hr_employee`、`hr_employee_assignment` |
| 岗位体系 | `mdm_job_family`、`mdm_grade`、`mdm_job_profile`、`mdm_position` | 对应 `hr_*` 表名 |
| 往来主体 | `mdm_business_partner`、`mdm_business_partner_role` | 新增统一身份与角色映射 |
| 客商角色 | `mdm_customer`、`mdm_customer_address`、`mdm_carrier`、`mdm_supplier`、`mdm_insurance_company`、`mdm_external_vendor` | 对应 TMS、VMS、HR 旧表名 |
| 司机 | `mdm_driver` | `tms_driver` |
| 运输基础资料 | `mdm_station`、`mdm_cargo`、`mdm_vehicle` | `tms_station`、`tms_cargo`、`vehicle_archive` |
| 备件 | `mdm_part_category`、`mdm_part` | `vehicle_parts_category`、`vehicle_parts` |
| 场所与库位 | `mdm_site`、`mdm_storage_location` | 对应 `smis_*` 旧表名 |
| 设备 | `mdm_equipment_category`、`mdm_equipment` | 对应 `smis_*` 旧表名 |
| 物料 | `mdm_material_category`、`mdm_material` | 对应 `smis_*` 旧表名 |

旧表名当前是 `security_invoker` 兼容视图，保留原有列结构和必要授权。数据库函数已经改为访问实体 `mdm_*` 表；应用新代码不得继续依赖旧名。外键约束名、RPC 名和工作流业务类型暂不改名，它们是外部契约，不代表数据所有权。

## 往来主体治理

`mdm_business_partner` 是客户、承运商、供应商、保险公司和外部供应商的统一身份层，`mdm_business_partner_role` 记录身份对应的角色明细表。现阶段角色表仍是业务维护入口，数据库触发器负责实时同步统一身份层，兼容现有权限和页面。

初始迁移不做基于名称的自动合并：名称并不是可靠身份标识。现有角色记录沿用原 UUID 作为主体 UUID，并保留来源代码。后续若要把同一法人跨角色合并，应以统一社会信用代码、税号和人工审核为准，形成单独的可审计合并流程。

## 访问与安全

- 所有实体表启用 RLS，租户数据以 `tenant_id` 隔离，平台超级管理员保留跨租户读取能力。
- 统一往来主体及角色映射只向普通认证用户开放租户内读取；写入由角色表同步触发器或 `service_role` 完成。
- 兼容视图使用调用者权限执行，不绕过底层 RLS。
- `anon` 不拥有 MDM 表权限；AI 普通用户能力只能做租户安全的只读访问，任何业务写入仍在 UI 和数据库边界校验平台超级管理员或既有业务权限。
- 新查询应优先使用租户列开头的索引；跨租户唯一性必须显式设计，不依赖应用层检查。

## 不纳入 MDM 的数据

- `sys_tenant`、`sys_user`、角色、菜单、字典、附件：属于平台身份、权限或基础设施。
- 运单、订单、合同、费用、发票、凭证、库存流水、维保记录：属于交易或台账。
- 工作流、审批、通知、AI 历史与审计：属于过程和审计数据。
- `fms_subject`、辅助核算、资金账户等：当前是账套配置，不是企业级共享主数据。
- 安全检查类型、危害因素、资质目录等：当前只在 SMIS 域内生效，先保留为领域参考数据；出现明确跨域消费者后再提升为 MDM。

## 开发约定

1. 新代码只引用 `mdm_*` 实体或受控 RPC；旧名仅用于迁移期兼容。
2. 历史单据继续保存名称、编码快照，不在回溯时用当前主数据覆盖历史事实。
3. 新增主数据必须具备主键、租户范围、业务编码、状态、审计列、RLS、明确授权和必要索引。
4. 业务表引用主数据时优先使用 `(id, tenant_id)` 复合外键，防止跨租户关联。
5. 兼容视图下线前必须确认应用、Edge Function、RPC、报表和外部集成均无旧名引用，并经过至少一个完整发布周期。
