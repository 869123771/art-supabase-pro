# 独立业务应用架构

## 仓库边界

| 应用代码 | 仓库 | 负责范围 |
| --- | --- | --- |
| `platform` | `art-supabase-pro` | Auth、租户、用户、组织、菜单、角色权限、数据中心与共享数据库契约 |
| `finance` | `art-supabase-finance` | Finance 独立应用预留边界 |
| `fms` | `art-supabase-fms` | FMS 财务管理 |
| `hr` | `art-supabase-hr` | HR 人力资源 |
| `smis` | `art-supabase-smis` | SMIS 安全生产 |
| `vms` | `art-supabase-vms` | VMS 车辆管理 |

每个前端通过 `VITE_APP_CODE` 声明运行身份，通过 `get_menus_for_current_application(app_code)` 获取自己的菜单。平台超级用户可以进入全部已启用应用；普通租户用户只能进入其角色拥有菜单的应用。

## 数据交互原则

1. 业务表仍位于同一 Supabase 项目，登录态、租户上下文和事务边界保持一致。
2. 表的写入只归领域所有者。其他模块不得直接写该领域表，也不得导入该模块的前端 API 实现。
3. 跨域读取使用用途明确的 RPC / Read Model。契约在数据库边界校验 `auth.uid()`、租户、业务菜单权限与字段可见性。
4. Realtime 仅用于“数据已变化”的失效通知；收到通知后重新调用只读契约，不把事件负载当作授权后的业务数据。

VMS 实验包含两类真实契约：

- VMS 通过 TMS 的安全引用数据 RPC 获取承运商、司机；TMS 仍拥有源数据和字段脱敏规则。
- `vms_list_hr_employee_options_secure` 向 VMS 提供 HR 在职员工的最小只读投影，不返回身份证、联系方式等非必要敏感字段。

## 部署与回滚

- 每个仓独立安装依赖、执行质量门禁、构建和发布。
- `sys_application.base_url` 是应用切换地址，可按环境配置为同域子路径或独立域名。
- 前端发布与数据库契约保持向后兼容：先发布新增契约，再发布消费者；回滚时先回滚消费者，确认无调用后再移除契约。
- 基座不依赖业务仓源码。业务应用允许依赖稳定的平台契约，但不能通过相对路径、Git 子模块或源码别名反向引用其他业务仓。
