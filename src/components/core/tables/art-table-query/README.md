# ArtTableQuery

`ArtTableQuery` 是本项目标准的“查询 + 表格”组合组件，内部组合：

- `ArtSearchBar`：查询表单
- `ArtTableHeader`：表格工具栏、刷新、搜索区域显隐、列设置
- `ArtTable`：表格内容和分页
- `useTable`：可选的内部数据生命周期管理

标准 CRUD 列表页优先使用 `ArtTableQuery`，不要再重复手动拼 `ArtSearchBar + ArtTableHeader + ArtTable`。

## 基础用法

### 内管模式

传入 `apiFn` 后启用内管模式。组件内部负责 loading、data、pagination、columns、查询、重置、刷新、分页变化。

```vue
<ArtTableQuery
  ref="tableQueryRef"
  :api-fn="fetchTableData"
  :columns-factory="columnsFactory"
  :search-items="searchItems"
/>
```

```ts
import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
import type { ColumnOption } from '@/types'

interface Row {
  id: number
  name: string
}

const tableQueryRef = ref<ArtTableQueryExpose>()

const fetchTableData = (params: Record<string, any>) => {
  return fetchList(params)
}

const columnsFactory = (): ColumnOption<Row>[] => [
  { type: 'globalIndex', label: '序号', width: 80 },
  { prop: 'name', label: '名称' }
]

const searchItems = [
  {
    label: '名称',
    key: 'name',
    type: 'input',
    props: { clearable: true, placeholder: '请输入名称' }
  }
]
```

### 初始不请求接口

设置 `:immediate="false"`，组件挂载后不会自动调用 `apiFn`。需要加载时手动调用 `getData()` 或 `refreshData()`。

```vue
<ArtTableQuery
  ref="tableQueryRef"
  :api-fn="fetchTableData"
  :columns-factory="columnsFactory"
  :immediate="false"
/>
```

```ts
const load = () => {
  void tableQueryRef.value?.getData()
}
```

### 受控模式

不传 `apiFn` 时，组件只负责布局和事件转发，业务页自己维护 `useTable`。

```vue
<ArtTableQuery
  v-model="searchForm"
  v-model:columns="columnChecks"
  :loading="loading"
  :data="data"
  :table-columns="columns"
  :pagination="pagination"
  :search-items="searchItems"
  @search="handleSearch"
  @reset="resetSearchParams"
  @refresh="refreshData"
  @pagination:size-change="handleSizeChange"
  @pagination:current-change="handleCurrentChange"
/>
```

## 内管模式推荐传入

| Prop | 类型 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `apiFn` | `(params: any) => Promise<any>` | 是 | - | 列表接口函数，传入后启用内管模式。 |
| `columnsFactory` | `() => ColumnOption[]` | 是 | `() => []` | 表格列工厂。 |
| `searchItems` | `SearchFormItem[]` | 否 | `[]` | 查询表单项。没有查询项时搜索区域不渲染。 |
| `apiParams` | `Record<string, any>` | 否 | `{}` | 默认请求参数，会和 `{ current: 1, size: 20 }` 合并。 |
| `immediate` | `boolean` | 否 | `true` | 是否挂载后立即请求接口。 |

## Props API

### 顶层 Props

| Prop | 类型 | 模式 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `apiFn` | `(params: any) => Promise<any>` | 内管 | - | 列表接口函数。 |
| `apiParams` | `Record<string, any>` | 内管 | `{}` | 默认请求参数。组件会先合并 `{ current: 1, size: 20 }`。 |
| `immediate` | `boolean` | 内管 | `true` | 是否自动首次请求。 |
| `excludeParams` | `string[]` | 内管 | `[]` | 请求前排除指定字段。 |
| `paginationKey` | `{ current?: string; size?: string }` | 内管 | - | 自定义分页字段名。 |
| `columnsFactory` | `() => ColumnOption[]` | 内管 | - | 列工厂，传给内部 `useTable`。 |
| `enableCache` | `boolean` | 内管 | `false` | 是否启用请求缓存。 |
| `cacheTime` | `number` | 内管 | `300000` | 缓存时间，单位毫秒。 |
| `debounceTime` | `number` | 内管 | `300` | 搜索防抖时间，单位毫秒。 |
| `maxCacheSize` | `number` | 内管 | `50` | 最大缓存条数。 |
| `dataTransformer` | `(data: any[]) => any[]` | 内管 | - | 响应数据转换。 |
| `responseAdapter` | `(response: any) => ApiResponse` | 内管 | 默认适配器 | 接口响应适配器。 |
| `onSuccess` | `(data, response) => void` | 内管 | - | 请求成功回调。 |
| `onError` | `(error) => void` | 内管 | - | 请求失败回调。 |
| `onCacheHit` | `(data, response) => void` | 内管 | - | 缓存命中回调。 |
| `debug` | `boolean` | 内管 | `false` | 是否开启 `useTable` 调试日志。 |
| `searchItems` | `SearchFormItem[]` | 两种 | `[]` | 查询项配置，优先级高于 `searchBarProps.items`。 |
| `searchBarProps` | `ArtTableQuerySearchBarProps` | 两种 | `{}` | 透传给 `ArtSearchBar`。 |
| `tableHeaderProps` | `ArtTableQueryTableHeaderProps` | 两种 | `{}` | 透传给 `ArtTableHeader`。 |
| `tableProps` | `ArtTableQueryTableProps` | 两种 | `{}` | 透传给 `ArtTable` / `ElTable`。 |
| `loading` | `boolean` | 受控 | `false` | 外部 loading，内管模式忽略。 |
| `data` | `Record<string, any>[]` | 受控 | `[]` | 外部表格数据，内管模式忽略。 |
| `tableColumns` | `ColumnOption[]` | 受控 | `[]` | 外部表格列，内管模式忽略。 |
| `pagination` | `{ current: number; size: number; total: number }` | 受控 | - | 外部分页，内管模式忽略。 |

### searchBarProps

| Prop | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `items` | `SearchFormItem[]` | - | 查询项。推荐用顶层 `searchItems`。 |
| `span` | `number` | `6` | 查询项栅格宽度。 |
| `gutter` | `number` | `12` | 查询项间距。 |
| `isExpand` | `boolean` | `false` | 是否强制展开全部查询项。 |
| `defaultExpanded` | `boolean` | `false` | 默认是否展开。 |
| `labelPosition` | `'left' \| 'right' \| 'top'` | `'right'` | label 位置。 |
| `labelWidth` | `string \| number` | `'96px'` | label 宽度。 |
| `showExpand` | `boolean` | `true` | 是否显示展开/收起按钮。 |
| `buttonLeftLimit` | `number` | `2` | 查询项数量小于等于该值时按钮左对齐。 |
| `showReset` | `boolean` | `true` | 是否显示重置按钮。 |
| `showSearch` | `boolean` | `true` | 是否显示查询按钮。 |
| `disabledSearch` | `boolean` | `false` | 是否禁用查询按钮。 |
| `sanitizeOutput` | `Partial<ArtTableQuerySanitizeOutputOptions>` | - | 查询输出清洗策略。 |

### tableHeaderProps

| Prop | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `showZebra` | `boolean` | `true` | 是否显示斑马纹设置项。 |
| `showBorder` | `boolean` | `true` | 是否显示边框设置项。 |
| `showHeaderBackground` | `boolean` | `true` | 是否显示表头背景设置项。 |
| `fullClass` | `string` | `'art-page-view'` | 全屏容器 class。 |
| `layout` | `string` | `'search,refresh,size,fullscreen,columns,settings'` | 工具栏按钮布局。 |

### tableProps

`tableProps` 会透传给 `ArtTable`，而 `ArtTable` 又会透传给 Element Plus `ElTable`。组件内置默认值：

- `rowKey: 'id'`
- `tableLayout: 'fixed'`

不建议在 `tableProps` 里传 `data`、`columns`、`loading`、`pagination`，这些由 `ArtTableQuery` 接管。

| Prop | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `rowKey` | `string \| (row) => string` | `'id'` | 行 key。 |
| `tableLayout` | `'fixed' \| 'auto'` | `'fixed'` | 表格布局。 |
| `height` | `string \| number` | `'100%'` | 表格高度。 |
| `maxHeight` | `string \| number` | - | 表格最大高度。 |
| `stripe` | `boolean` | 全局设置 | 是否斑马纹。 |
| `border` | `boolean` | 全局设置 | 是否显示边框。 |
| `size` | `'small' \| 'default' \| 'large'` | 全局设置 | 表格尺寸。 |
| `fit` | `boolean` | `true` | 列宽是否自动撑开。 |
| `showHeader` | `boolean` | `true` | 是否显示表头。 |
| `highlightCurrentRow` | `boolean` | - | 是否高亮当前行。 |
| `currentRowKey` | `string \| number` | - | 当前行 key。 |
| `flexible` | `boolean` | - | 空数据时是否按最大高度撑开。 |
| `defaultExpandAll` | `boolean` | - | 是否默认展开所有行。 |
| `expandRowKeys` | `(string \| number)[]` | - | 默认展开行 key。 |
| `lazy` | `boolean` | - | 是否懒加载树形数据。 |
| `load` | `TableProps['load']` | - | 树形数据加载函数。 |
| `treeProps` | `TableProps['treeProps']` | - | 树形数据字段配置。 |
| `tooltipOptions` | `TableProps['tooltipOptions']` | - | tooltip 配置。 |
| `headerRowClassName` | `TableProps['headerRowClassName']` | - | 表头行 class。 |
| `headerRowStyle` | `TableProps['headerRowStyle']` | - | 表头行 style。 |
| `headerCellClassName` | `TableProps['headerCellClassName']` | - | 表头单元格 class。 |
| `headerCellStyle` | `TableProps['headerCellStyle']` | - | 表头单元格 style。 |
| `rowClassName` | `TableProps['rowClassName']` | - | 行 class。 |
| `rowStyle` | `TableProps['rowStyle']` | - | 行 style。 |
| `cellClassName` | `TableProps['cellClassName']` | - | 单元格 class。 |
| `cellStyle` | `TableProps['cellStyle']` | - | 单元格 style。 |
| `spanMethod` | `TableProps['spanMethod']` | - | 合并行列。 |
| `defaultSort` | `TableProps['defaultSort']` | - | 默认排序。 |
| `tooltipEffect` | `TableProps['tooltipEffect']` | - | tooltip 主题。 |
| `showOverflowTooltip` | `TableProps['showOverflowTooltip']` | - | 是否显示溢出 tooltip。 |
| `emptyHeight` | `string` | `'100%'` | 空数据表格高度。 |
| `emptyText` | `string` | `'暂无数据'` | 空数据文案。 |
| `showTableHeader` | `boolean` | `true` | 是否启用表头高度参与表格高度计算。 |
| `paginationOptions` | `ArtTableQueryPaginationOptions` | - | 分页器配置。 |

### paginationOptions

| Prop | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `pageSizes` | `number[]` | `[10, 20, 30, 50, 100]` | 每页条数选项。 |
| `align` | `'left' \| 'center' \| 'right'` | `'center'` | 分页器对齐方式。 |
| `layout` | `string` | 响应式默认值 | 分页器布局。 |
| `background` | `boolean` | `true` | 是否显示分页背景。 |
| `hideOnSinglePage` | `boolean` | `false` | 只有一页时是否隐藏分页。 |
| `size` | `'small' \| 'default' \| 'large'` | `'default'` | 分页器尺寸。 |
| `pagerCount` | `number` | `7 或 5` | 页码按钮数量。 |

## v-model

| Model | 类型 | 说明 |
| --- | --- | --- |
| `v-model` | `Record<string, unknown>` | 查询表单模型。内管模式通常不用传；需要外部默认值或动态联动时可传。 |
| `v-model:columns` | `ColumnOption[]` | 列显隐配置。内管模式通常不用传。 |
| `v-model:show-search-bar` | `boolean` | 搜索区域显隐状态。只有业务需要外部控制时传。 |

## Events

内管模式下事件仍会 emit，但组件会先执行默认行为。

| Event | Payload | 说明 |
| --- | --- | --- |
| `search` | `Record<string, unknown>` | 点击查询后触发。内管模式先更新查询参数并重新查询。 |
| `reset` | 无 | 点击重置后触发。内管模式先恢复查询表单初始值并重置查询参数。 |
| `refresh` | 无 | 点击工具栏刷新后触发。内管模式先刷新数据。 |
| `header-search` | 无 | 点击工具栏搜索区域显隐按钮后触发。 |
| `selection-change` | `any[]` | 透传表格选择变化。 |
| `pagination:size-change` | `number` | page size 改变后触发。内管模式先处理分页并重新查询。 |
| `pagination:current-change` | `number` | current page 改变后触发。内管模式先处理分页并重新查询。 |

## Slots

| Slot | 说明 |
| --- | --- |
| `header-left` | 工具栏左侧，一般放新增、批量操作。 |
| `header-right` | 工具栏右侧扩展区域。 |
| `default` | 额外表格内容。 |
| 表格列 slot | 除 `header-left`、`header-right`、`default`、`search-*` 外的 slot 会透传给 `ArtTable`。 |
| `search-{key}` | 自定义查询项内容，例如 `search-status` 对应查询项 `key: 'status'`。 |

## Expose

```ts
interface ArtTableQueryExpose {
  refreshData: () => Promise<void>
  refreshCreate: () => Promise<void>
  refreshUpdate: () => Promise<void>
  refreshRemove: () => Promise<void>
  getData: () => Promise<unknown>
  resetSearchParams: () => Promise<void>
}
```

| 方法                  | 使用场景                                     |
| --------------------- | -------------------------------------------- |
| `refreshCreate()`     | 新增成功后刷新，默认回到第一页。             |
| `refreshUpdate()`     | 编辑成功后刷新，默认保留当前页。             |
| `refreshRemove()`     | 删除成功后刷新，当前页为空时自动回退上一页。 |
| `refreshData()`       | 手动刷新或不区分场景的全量刷新。             |
| `getData()`           | 手动查询，搜索语义，默认回到第一页。         |
| `resetSearchParams()` | 外部主动清空查询表单并重置查询参数。         |

## 示例

### tableProps 提示示例

```vue
<ArtTableQuery
  :api-fn="fetchTableData"
  :columns-factory="columnsFactory"
  :table-props="{
    rowKey: 'uuid',
    height: '100%',
    border: true,
    stripe: true,
    size: 'default',
    emptyText: '暂无记录',
    paginationOptions: {
      align: 'right',
      pageSizes: [20, 50, 100]
    }
  }"
/>
```

### 自定义响应适配器

```vue
<ArtTableQuery
  :api-fn="fetchTableData"
  :columns-factory="columnsFactory"
  :response-adapter="responseAdapter"
/>
```

```ts
const responseAdapter = (response: any) => ({
  records: response.data.list,
  total: response.data.total,
  current: response.data.page,
  size: response.data.pageSize
})
```

### 动态查询项隐藏

```ts
const searchItems = computed<SearchFormItem[]>(() => [
  {
    label: '保险公司名称',
    key: 'companyName',
    type: 'input'
  },
  {
    label: '联系人',
    key: 'contactPerson',
    type: 'input',
    hidden: (model) => model.companyName !== '123'
  }
])
```

## 注意事项

- 标准 CRUD 页面优先使用内管模式。
- 内管模式中不要在 `search/reset/refresh/pagination` 事件里重复调用同一个刷新方法，否则会重复请求。
- `searchItems` 和 `searchBarProps.items` 同时存在时，优先使用 `searchItems`。
- `tableProps` 会在内部默认值之后合并，因此可以覆盖 `rowKey`、`tableLayout` 等默认配置。
- `immediate=false` 只阻止首次自动请求，不影响后续查询、分页、刷新。

## headerActions

`headerActions` 用于配置 `ArtTableHeader` 左侧按钮。标准列表页优先使用它，不再手写 `#header-left`。

```vue
<ArtTableQuery
  :api-fn="fetchTableData"
  :columns-factory="columnsFactory"
  :header-actions="headerActions"
/>
```

```ts
const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
  {
    type: 'add',
    permission: 'add',
    onClick: () => openDialog()
  },
  {
    type: 'delete',
    permission: 'delete',
    content: ({ selectedCount }) => `确定删除选中的 ${selectedCount} 条数据吗？`,
    onClick: async ({ selectedRows, api }) => {
      await batchDelete(selectedRows.map((row) => row.id))
      await api.refreshRemove()
    }
  }
])
```

### 预制类型

| type | 默认文案 | 默认图标 | 默认按钮 | 行为 |
| --- | --- | --- | --- | --- |
| `add` | `新增` | `ri:add-line` | `primary plain` | 直接触发 `onClick`。 |
| `delete` | `批量删除` | `ri:delete-bin-line` | `danger plain` | 默认需要选中行，未选中禁用；选中后显示 `批量删除(n)`；点击先弹确认框。 |
| `import` | `导入` | `ri:upload-2-line` | `success plain` | 直接触发 `onClick`。 |
| `export` | `导出` | `ri:download-2-line` | `warning plain` | 直接触发 `onClick`。 |

### Action API

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `key` | `string` | 唯一标识，未传时使用 `type` 或索引。 |
| `type` | `'add' \| 'delete' \| 'import' \| 'export'` | 命中预制类型时使用默认文案、图标和行为。 |
| `hidden` | `boolean \| (ctx) => boolean` | 是否隐藏，支持按选中行动态判断。 |
| `label` | `string \| Component` | 自定义按钮文案或组件，不传时使用预设文案。 |
| `onClick` | `(ctx) => void \| Promise<void>` | 点击回调；`delete` 会在确认后触发。 |
| `content` | `string \| Component \| (ctx) => VNodeChild` | 确认框内容，主要用于批量删除。 |
| `permission` | `string` | 权限标识，会透传给 `v-auth`。 |
| `icon` | `string \| Component` | 自定义图标。字符串使用 `ArtSvgIcon`。 |
| `disabled` | `boolean \| (ctx) => boolean` | 是否禁用。 |
| `selectionRequired` | `boolean` | 是否需要勾选表格行；`delete` 默认 `true`。 |
| `confirm` | `boolean` | 点击前是否弹确认框；`delete` 默认 `true`。 |
| `confirmTitle` | `string` | 确认框标题。 |
| `slot` | `string` | 使用指定 slot 自定义渲染该 action。 |
| `render` | `Component` | 使用组件自定义渲染该 action。 |
| `buttonProps` | `Record<string, any>` | 透传给 `ElButton`，会覆盖预制按钮属性。 |

### onClick Context

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `action` | `ArtTableQueryHeaderAction` | 当前 action 配置。 |
| `selectedRows` | `Record<string, any>[]` | 当前表格选中行。 |
| `selectedCount` | `number` | 当前选中数量。 |
| `event` | `MouseEvent \| undefined` | 点击事件。 |
| `api` | `{ refreshData, refreshCreate, refreshUpdate, refreshRemove, getData }` | 表格刷新 API。 |

### 自定义渲染

如果预制按钮不满足，可以使用 `slot`：

```vue
<ArtTableQuery :header-actions="[{ key: 'custom', slot: 'custom-action' }]">
  <template #custom-action="{ selectedRows }">
    <ElButton @click="doSomething(selectedRows)">自定义按钮</ElButton>
  </template>
</ArtTableQuery>
```

也可以继续使用旧的 `#header-left`，它会渲染在 `headerActions` 后面：

```vue
<template #header-left="{ selectedRows, selectedCount }">
  <ElButton>额外按钮 {{ selectedCount }}</ElButton>
</template>
```
