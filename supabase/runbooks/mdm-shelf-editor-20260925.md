# 货架整组编辑（2026-09-25）

- Supabase 项目：`ckbftoopuyophiebamwy`。
- 数据库新增 `public.mdm_update_warehouse_shelf_secure(uuid,uuid,text,text,integer,integer,boolean,numeric,uuid[])`。上线前确认该函数不存在；变更只增加函数与执行授权，不直接改动业务数据。若需回退，撤下前端入口并删除此签名的函数。
- 函数以 `SECURITY INVOKER` 运行，只有 `authenticated` 可执行；仓库读取遵守当前租户查看范围，库位增、改、删继续受表 RLS 约束。编辑需要 `MdmWarehouseBin:Edit`，增加格位需要 `MdmWarehouseBin:Add`，缩小货架需要 `MdmWarehouseBin:Delete`。
- 调用方提交打开弹窗时的全部顶层格位 ID。函数锁定目标货架并核对 ID 集合，防止用过期页面覆盖并发修改。改名、容量更新及层列增减在一个事务内执行；有子单元、库存或业务外键引用的格位不能移除。容量未选择统一修改时，现有格位保留原值，新格位不设置数量上限。

## 验证

- 先在 `BEGIN` / `ROLLBACK` 中创建函数并核对签名，随后直接创建并确认 `SECURITY INVOKER`、匿名角色不可执行、已登录角色可执行。
- 在回滚事务中，以平台超级管理员验证货架改名、扩层、缩层与容量更新；以选定租户的平台超级管理员验证当前租户编辑与其他租户拦截；以有编辑权限的普通用户验证本租户编辑，以及伪造其他租户请求头不改变其本租户范围。
- 验证后库位总数仍为 124，测试中使用的临时货架编码不存在。Supabase 安全顾问已运行；新函数没有引入 `SECURITY DEFINER` 告警，既有顾问告警另行处理。
- 浏览器回归覆盖编辑弹窗打开、编辑图标、层数请求参数、默认折叠、窄桌面和 2048px 布局。
