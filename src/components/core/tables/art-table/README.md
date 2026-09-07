# ArtTable

项目共用数据表格，承接列配置、字典展示、加载/空态、分页及 Element Plus 表格属性。查询、筛选和专注模式由上层 `ArtTableQuery` 组合。

## 编辑表格必填列

编辑型表格通过列配置的 `required: true` 声明必填列。`ArtTable` 会在标题前统一渲染与表单一致的红色星号，并为辅助技术补充“必填”语义；不要在 `label` 中手写 `*`。

```ts
const columns: ColumnOption<EditableRow>[] = [
  { prop: 'quantity', label: '用量', required: true, formatter: renderQuantity },
  { prop: 'unitId', label: '单位', required: true, formatter: renderUnit }
]
```

`required` 同样支持分组子列和 `useHeaderSlot` 自定义表头。调用 `ArtTable` 暴露的 `validate()` 后，组件统一校验所有必填列、标红无效控件并聚焦第一处错误；用户修正字段后会即时移除对应错误状态。

需要业务规则时，通过列的 `rules` 传入校验器，表格只负责执行与展示，不包含领域规则：

```ts
{
  prop: 'quantity',
  label: '用量',
  required: true,
  requiredMessage: ({ rowIndex }) => `第 ${rowIndex + 1} 行用量不能为空`,
  rules: {
    validator: ({ value }) => Number(value) > 0,
    message: ({ rowIndex }) => `第 ${rowIndex + 1} 行用量必须大于 0`
  }
}
```

```ts
const result = await tableRef.value?.validate()
if (!result?.valid) ElMessage.warning(result?.firstError?.message)

tableRef.value?.clearValidate()
await tableRef.value?.validateField(['quantity', 'unitId'])
```

`validate()` 和 `validateField()` 返回 `{ valid, errors, firstError }`。集合级规则（例如至少一行、跨行去重）仍由业务组件负责；字段级必填、范围和条件校验统一交给 `ArtTable`。

## 窄容器与固定列

默认在实际表格容器宽度小于 640px 时解除列的固定定位，所有字段和操作仍按原顺序保留，通过表格内部横向滚动访问。容器恢复到 640px 及以上时恢复原配置；不修改用户的列选择、顺序或存储值。使用容器测量而不是窗口宽度，因此分栏、抽屉和专注模式也适用。

`fixed-column-min-width` 可以设置阈值；`0` 关闭这项行为，仅适用于已单独验证窄屏布局的表格。`ArtTableQuery` 可通过 `tableProps.fixedColumnMinWidth` 传入。该策略适用于 `columns` 配置渲染的普通列、分组列和全局序号列；直接通过插槽提供的原生 `ElTableColumn` 仍由调用方负责。

固定列不应遮住其他单元格。不得通过隐藏有效操作、覆盖全局 sticky 样式或把整页横向撑开解决窄屏问题。操作列宽度仍应与实际控件数量相符，响应式解除固定不能替代合理的列宽设计。

回归包含人员工作台中的姓名可读性、横向访问操作、容器缩放恢复，以及专注模式进入、按钮退出与 Esc 退出；使用浏览器隔离数据，不写入业务库。
