# 销售合同优化：数据库变更与核验

## 数据与权限

- 在项目 `ckbftoopuyophiebamwy` 中新增月度编号场景 `scm.sales_contract`，格式为 `XSHT{YYYYMM}-{SEQ:3}`。已有 6 个租户均有规则；新增租户会自动获得规则。合同插入时由数据库生成编号。
- 增加税率、合同条款、合同状态字典。合同明细的折扣、未税金额、税额和含税金额由 `app_private.prepare_scm_sales_document` 复核；赠品金额归零。
- `scm_generate_sales_contract` 继承原销售报价单号和源行号。`scm_get_contract_statuses` 根据合同生命周期、有效销售订单及已关联的资金流水计算展示状态。`scm_list_salesperson_options` 只返回当前租户范围内的在职员工基础身份字段。
- 两个新的公开 RPC 只授予 `authenticated` 执行权，内部验证登录、SCM 权限及租户读取范围。

## 收款状态边界

现有财务客户收款记录的来源是收款交易，未有销售合同分配关系。状态接口只认 `source_type = 'scm_sales_contract'` 且 `source_id = 合同 ID` 的已过账资金流水；当前财务收款流程不会产生这种记录。因此现有流程可以由订单推进“执行中 / 部分完成”，但无法仅凭客户收款自动确认“全部完成”。不能按客户、金额或备注猜测归属，否则可能把其他合同的收款算入本合同。后续应在收款核销流程增加合同分配关系，再接入该状态接口。

## 核验与恢复

- 修改前快照位于 `app_private.scm_contract_backup_20260923`，含旧函数定义、编号配置和一条现存合同记录。任何恢复应先比对当前对象及后续写入，避免覆盖期间新增的合同或编号。
- 编号规则、税率、条款和状态字典回读数量分别为 6、7、5、7；报价溯源函数及状态接口已回读确认。
- 编号引擎在回滚事务中生成 `XSHT202609-001`，未消耗正式流水号。
- 金额函数在回滚事务中校验了 2 件、100 元未税单价、13% 税率、10% 折扣和赠品场景，结果为金额 177.40、税额 26.00、价税合计 203.40，赠品三项均为零。
- Supabase Advisor 对新 RPC 报告了 [`SECURITY DEFINER` 可由已登录用户调用](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)的通用提醒；此处为读取受限业务数据所需，函数内部执行登录、权限和租户校验。其余 `scm_sales_document` 索引及宽松策略提醒是原表已有问题，本次未改其策略。
