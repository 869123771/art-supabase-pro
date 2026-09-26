# WMS 入库与出库业务扩展

## 变更范围

- 在 WMS 初始化菜单之后新增“入库业务”和“出库业务”目录。
- 入库业务包含采购入库单、采购退货单、其他入库单、受托加工材料入库单、受托加工材料退料单。
- 出库业务包含销售出库单、销售退货单。
- 其他入库单与其他入库退回单复用 `wms_purchase_document` / `wms_purchase_document_line`。
- 销售出库单与销售退货单复用 `wms_sales_document` / `wms_sales_document_line`。

## 数据库对象

- 扩展 `wms_purchase_document_kind_check`，加入 `other_inbound`、`other_return`、`entrusted_processing_inbound`、`entrusted_processing_return`。
- 更新 `wms_save_purchase_document_secure`、`wms_change_purchase_document_status_secure` 和 `app_private.wms_post_purchase_document_stock`，加入新业务类型、权限和库存方向。
- 更新 `wms_save_sales_document_secure`、`wms_change_sales_document_status_secure`，支持日常销售出库和销售退货。
- 新增对应的 MDM 单据类型、业务类型、编号场景和月度三位流水号规则。
- 新增菜单、页面权限和按钮权限，并按已有 WMS 初始化角色授权关系同步授权。

## 验证数据

租户 `7529f951-938e-4e2c-ac0d-316c136ae1f9` 的已启用库存组织中，每个新增业务类型至少准备两张单据。退回和退货单据的数量以负数保存并在列表中醒目标识。

## 验证要点

1. 菜单名称不包含“【新增加】”，入库业务紧跟初始化菜单。
2. 其他入库列表同时展示入库和退回数据；退回行使用浅黄色背景，数量使用红色粗体。
3. 组合查询覆盖状态、供应商或客户、项目、物料描述和物料编码。
4. 其他入库单勾选一张已审核单据后，可通过“下推”生成其他入库退回草稿。
5. 新增、复制、编辑、查看、导入、导出、提交、审核、删除均执行独立按钮权限和服务端权限校验。
6. 赠品行金额、税额和价税合计归零；单价、含税单价、税率、折扣与金额由前后端共同复算。

## 回退说明

页面和菜单可通过禁用新增菜单项回退。数据库表为复用扩展，回退前应先处理新增 kind 的业务数据，再恢复约束和安全函数；不要直接删除共享业务表。
