<!-- 查询表格组合组件：整合 ArtSearchBar + ArtTableHeader + ArtTable -->
<template>
  <div class="art-table-query">
    <ArtSearchBar
      v-if="hasSearchBar"
      v-show="showSearchBar"
      v-model="searchModel"
      v-bind="resolvedSearchBarProps"
      @search="handleSearch"
      @reset="handleReset"
    >
      <template v-for="slotName in searchBarSlotNames" :key="slotName" #[slotName]="slotProps">
        <slot :name="`search-${slotName}`" v-bind="slotProps" />
      </template>
    </ArtSearchBar>

    <ElCard
      class="art-table-card"
      shadow="never"
      :style="{ marginTop: hasSearchBar && showSearchBar ? '12px' : '0' }"
    >
      <div v-if="$slots['table-header-top']" class="art-table-query__header-top">
        <slot
          name="table-header-top"
          :selected-rows="selectedRows"
          :selected-count="selectedRows.length"
        />
      </div>

      <ArtTableHeader
        v-model:columns="resolvedColumnsModel"
        v-bind="mergedTableHeaderProps"
        :show-search-bar="hasSearchBar ? showSearchBar : undefined"
        @update:show-search-bar="handleShowSearchBarChange"
        @refresh="handleRefresh"
        @search="emit('header-search')"
      >
        <template #left>
          <div
            v-if="visibleHeaderActions.length || $slots['header-left']"
            class="art-table-query__header-left"
          >
            <template v-for="action in visibleHeaderActions" :key="getHeaderActionKey(action)">
              <span :class="getHeaderActionClass()">
                <slot
                  v-if="action.slot"
                  :name="action.slot"
                  v-bind="getHeaderActionSlotProps(action)"
                />
                <component
                  v-else-if="action.render"
                  :is="action.render"
                  v-bind="getHeaderActionSlotProps(action)"
                />
                <ArtExcelImport
                  v-else-if="action.type === 'import'"
                  v-auth="action.permission"
                  :button-props="getHeaderActionButtonProps(action)"
                  :disabled="isHeaderActionDisabled(action)"
                  :icon="getHeaderActionIcon(action)"
                  @import-success="handleHeaderActionImportSuccess(action, $event)"
                  @import-error="handleHeaderActionImportError(action, $event)"
                >
                  <component
                    v-if="typeof getHeaderActionLabel(action) !== 'string'"
                    :is="getHeaderActionLabel(action)"
                  />
                  <span v-else>{{ getHeaderActionLabel(action) }}</span>
                </ArtExcelImport>
                <ElButton
                  v-else
                  v-auth="action.permission"
                  v-bind="getHeaderActionButtonProps(action)"
                  :disabled="isHeaderActionDisabled(action)"
                  @click="handleHeaderActionClick(action, $event)"
                  v-ripple
                >
                  <template v-if="getHeaderActionIcon(action)" #icon>
                    <component
                      v-if="typeof getHeaderActionIcon(action) !== 'string'"
                      :is="getHeaderActionIcon(action)"
                    />
                    <ArtSvgIcon v-else :icon="String(getHeaderActionIcon(action))" />
                  </template>
                  <component
                    v-if="typeof getHeaderActionLabel(action) !== 'string'"
                    :is="getHeaderActionLabel(action)"
                  />
                  <span v-else>{{ getHeaderActionLabel(action) }}</span>
                </ElButton>
              </span>
            </template>
            <slot
              name="header-left"
              :selected-rows="selectedRows"
              :selected-count="selectedRows.length"
            />
          </div>
        </template>
        <template v-if="$slots['header-right']" #right>
          <slot name="header-right" />
        </template>
      </ArtTableHeader>

      <ArtTable
        ref="tableRef"
        v-bind="artTableBindings"
        @row-drag-start="handleRowDragStart"
        @row-drag-update="handleRowDragUpdate"
        @row-drag-end="handleRowDragEnd"
      >
        <template v-for="slotName in tableSlotNames" :key="slotName" #[slotName]="slotProps">
          <slot :name="slotName" v-bind="slotProps" />
        </template>
        <template v-if="$slots.default" #default>
          <slot />
        </template>
      </ArtTable>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import {
    computed,
    h,
    onMounted,
    nextTick,
    ref,
    type Component,
    type VNode,
    type VNodeChild
  } from 'vue'
  import type { TableProps } from 'element-plus'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ArtTableInstance } from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { useTable } from '@/hooks/core/useTable'
  import type { ApiResponse } from '@/utils/table/tableCache'
  import {
    defaultResponseAdapter,
    extractTableData,
    type TableError
  } from '@/utils/table/tableUtils'
  import { exportExcel, mapExcelRowsToRecords, type ExcelColumn } from '@/utils/file'

  defineOptions({ name: 'ArtTableQuery' })

  export interface ArtTableQuerySanitizeOutputOptions {
    /** 移除空字符串 */
    removeEmptyString: boolean
    /** 移除空数组 */
    removeEmptyArray: boolean
    /** 移除清洗后为空的对象 */
    removeEmptyObject: boolean
    /** 移除空富文本占位内容 */
    removeEmptyRichText: boolean
    /** 保留数字 0 */
    keepZero: boolean
    /** 保留 boolean false */
    keepFalse: boolean
  }

  /** ArtSearchBar 除 modelValue 外的 props */
  export interface ArtTableQuerySearchBarProps {
    /** 查询表单项，推荐优先使用 ArtTableQuery.searchItems */
    items?: SearchFormItem[]
    /** 默认列宽，基于 24 栅格 */
    span?: number
    /** 表单项间距 */
    gutter?: number
    /** 是否强制展开所有查询项 */
    isExpand?: boolean
    /** 默认是否展开 */
    defaultExpanded?: boolean
    /** label 位置 */
    labelPosition?: 'left' | 'right' | 'top'
    /** label 宽度 */
    labelWidth?: string | number
    /** 是否显示展开/收起 */
    showExpand?: boolean
    /** 查询项数量小于等于该值时按钮左对齐 */
    buttonLeftLimit?: number
    /** 是否显示重置按钮 */
    showReset?: boolean
    /** 是否显示查询按钮 */
    showSearch?: boolean
    /** 是否禁用查询按钮 */
    disabledSearch?: boolean
    /** 查询输出清洗策略 */
    sanitizeOutput?: Partial<ArtTableQuerySanitizeOutputOptions>
  }

  /** ArtTableHeader 除 columns、showSearchBar、loading 外的 props */
  export interface ArtTableQueryTableHeaderProps {
    /** 是否显示斑马纹设置项 */
    showZebra?: boolean
    /** 是否显示边框设置项 */
    showBorder?: boolean
    /** 是否显示表头背景设置项 */
    showHeaderBackground?: boolean
    /** 全屏容器 class */
    fullClass?: string
    /** 工具栏布局，逗号分隔，如 search,refresh,size,fullscreen,columns,settings */
    layout?: string
  }

  export type ArtTableQueryTableSize = 'small' | 'default' | 'large'

  export interface ArtTableQueryPaginationOptions {
    /** 每页条数选项 */
    pageSizes?: number[]
    /** 分页对齐方式 */
    align?: 'left' | 'center' | 'right'
    /** 分页布局 */
    layout?: string
    /** 是否显示分页背景 */
    background?: boolean
    /** 只有一页时是否隐藏分页 */
    hideOnSinglePage?: boolean
    /** 分页尺寸 */
    size?: ArtTableQueryTableSize
    /** 页码按钮数量 */
    pagerCount?: number
  }

  type ElementTablePassThroughProps = Partial<Omit<TableProps<Record<string, any>>, 'data'>>

  /**
   * 透传给 ArtTable / Element Plus ElTable 的属性。
   * data、columns、loading、pagination 由 ArtTableQuery 接管，不建议在 tableProps 里传。
   */
  export interface ArtTableQueryTableProps extends ElementTablePassThroughProps {
    /** 行数据 key，默认 id */
    rowKey?: string | ((row: Record<string, any>) => string)
    /** 表格布局，默认 fixed */
    tableLayout?: 'fixed' | 'auto'
    /** 表格高度 */
    height?: string | number
    /** 表格最大高度 */
    maxHeight?: string | number
    /** 是否带斑马纹；未传时使用全局表格设置 */
    stripe?: boolean
    /** 是否带边框；未传时使用全局表格设置 */
    border?: boolean
    /** 表格尺寸；未传时使用全局表格设置 */
    size?: ArtTableQueryTableSize
    /** 列宽是否自动撑开 */
    fit?: boolean
    /** 是否显示表头 */
    showHeader?: boolean
    /** 是否高亮当前行 */
    highlightCurrentRow?: boolean
    /** 当前行 key */
    currentRowKey?: string | number
    /** 空数据时是否按最大高度撑开 */
    flexible?: boolean
    /** 是否默认展开所有行 */
    defaultExpandAll?: boolean
    /** 默认展开行 key */
    expandRowKeys?: string[]
    /** 树形数据懒加载 */
    lazy?: boolean
    /** 树形数据加载函数 */
    load?: TableProps<Record<string, any>>['load']
    /** 树形数据配置 */
    treeProps?: TableProps<Record<string, any>>['treeProps']
    /** tooltip 配置 */
    tooltipOptions?: TableProps<Record<string, any>>['tooltipOptions']
    /** 表头行 class */
    headerRowClassName?: TableProps<Record<string, any>>['headerRowClassName']
    /** 表头行 style */
    headerRowStyle?: TableProps<Record<string, any>>['headerRowStyle']
    /** 表头单元格 class */
    headerCellClassName?: TableProps<Record<string, any>>['headerCellClassName']
    /** 表头单元格 style */
    headerCellStyle?: TableProps<Record<string, any>>['headerCellStyle']
    /** 行 class */
    rowClassName?: TableProps<Record<string, any>>['rowClassName']
    /** 行 style */
    rowStyle?: TableProps<Record<string, any>>['rowStyle']
    /** 单元格 class */
    cellClassName?: TableProps<Record<string, any>>['cellClassName']
    /** 单元格 style */
    cellStyle?: TableProps<Record<string, any>>['cellStyle']
    /** 合并行列 */
    spanMethod?: TableProps<Record<string, any>>['spanMethod']
    /** 默认排序 */
    defaultSort?: TableProps<Record<string, any>>['defaultSort']
    /** tooltip effect */
    tooltipEffect?: TableProps<Record<string, any>>['tooltipEffect']
    /** 是否显示溢出 tooltip */
    showOverflowTooltip?: TableProps<Record<string, any>>['showOverflowTooltip']
    /** 空数据表格高度，默认 100% */
    emptyHeight?: string
    /** 空数据文案 */
    emptyText?: string
    /** 是否启用表头高度参与表格高度计算，默认 true */
    showTableHeader?: boolean
    /** 分页器配置 */
    paginationOptions?: ArtTableQueryPaginationOptions
  }

  export type ArtTableQueryApiFn = (params: any) => Promise<any>
  export type ArtTableQueryResponseAdapter<TRecord = Record<string, any>, TResponse = any> = (
    response: TResponse
  ) => ApiResponse<TRecord>
  export type ArtTableQueryDataTransformer<TRecord = Record<string, any>> = (
    data: TRecord[]
  ) => TRecord[]
  export type ArtTableQueryHeaderActionType = 'add' | 'delete' | 'import' | 'export'
  export type ArtTableQueryHeaderActionContent =
    | string
    | Component
    | ((ctx: ArtTableQueryHeaderActionContext) => VNodeChild)
  export type ArtTableQueryExcelColumn = ExcelColumn<Record<string, any>>
  export type ArtTableQueryExcelColumns =
    | ArtTableQueryExcelColumn[]
    | ((ctx: ArtTableQueryHeaderActionContext) => ArtTableQueryExcelColumn[])
  export interface ArtTableQueryExportApiParams {
    selectedRows: Record<string, any>[]
    selectedIds: Array<string | number>
    selectedCount: number
    searchParams: Record<string, unknown>
    columns: ArtTableQueryExcelColumn[]
    maxRows: number
  }

  export interface ArtTableQueryHeaderActionContext {
    action: ArtTableQueryHeaderAction
    selectedRows: Record<string, any>[]
    selectedCount: number
    event?: MouseEvent
    api: Pick<
      ArtTableQueryExpose,
      'refreshData' | 'refreshCreate' | 'refreshUpdate' | 'refreshRemove' | 'getData'
    >
  }

  export interface ArtTableQueryHeaderAction {
    /** 唯一标识，未传时使用 type 或数组索引 */
    key?: string
    /** 预制类型；不传 type 时可使用 slot/render 自定义 */
    type?: ArtTableQueryHeaderActionType
    /** 是否隐藏，支持按当前选中行动态判断 */
    hidden?: boolean | ((ctx: ArtTableQueryHeaderActionContext) => boolean)
    /** 按钮文本；未传时使用预制类型默认文案 */
    label?: string | Component
    /** 点击回调；批量删除确认后才会触发 */
    onClick?: (ctx: ArtTableQueryHeaderActionContext) => void | Promise<void>
    /** Excel 导入成功回调，仅 type=import 时生效 */
    onImportSuccess?: (
      data: Array<Record<string, unknown>>,
      ctx: ArtTableQueryHeaderActionContext
    ) => void | Promise<void>
    importColumns?: ArtTableQueryExcelColumns
    importTransformer?: (
      rows: Array<Record<string, unknown>>,
      ctx: ArtTableQueryHeaderActionContext
    ) => Array<Record<string, any>> | Promise<Array<Record<string, any>>>
    importApi?: (
      rows: Array<Record<string, any>>,
      ctx: ArtTableQueryHeaderActionContext
    ) => void | Promise<void>
    /** Excel 导入失败回调，仅 type=import 时生效 */
    onImportError?: (error: Error, ctx: ArtTableQueryHeaderActionContext) => void | Promise<void>
    /** 确认框内容；delete 默认启用确认框 */
    content?: ArtTableQueryHeaderActionContent
    /** 权限标识，会透传给 v-auth */
    permission?: string
    /** 图标；字符串使用 ArtSvgIcon，组件直接渲染 */
    icon?: string | Component
    /** 是否禁用，支持按当前选中行动态判断 */
    disabled?: boolean | ((ctx: ArtTableQueryHeaderActionContext) => boolean)
    /** 是否需要选中行；delete 默认 true */
    selectionRequired?: boolean
    /** 是否点击前确认；delete 默认 true，其他默认 false */
    confirm?: boolean
    /** 确认框标题 */
    confirmTitle?: string
    /** 自定义 slot 名；传入后不渲染默认按钮 */
    slot?: string
    /** 自定义渲染组件；传入后不渲染默认按钮 */
    render?: Component
    /** 透传给 ElButton 的属性 */
    buttonProps?: Record<string, any>
    exportColumns?: ArtTableQueryExcelColumns
    exportFilename?: string | ((ctx: ArtTableQueryHeaderActionContext) => string)
    exportSheetName?: string
    exportMaxRows?: number
    exportApi?: (
      params: ArtTableQueryExportApiParams,
      ctx: ArtTableQueryHeaderActionContext
    ) => unknown | Promise<unknown>
    exportResponseAdapter?: ArtTableQueryResponseAdapter
    exportData?: (
      ctx: ArtTableQueryHeaderActionContext
    ) => Array<Record<string, any>> | Promise<Array<Record<string, any>>>
  }

  interface PaginationConfig {
    current: number
    size: number
    total: number
  }

  interface ArtTableExpose {
    elTableRef?: ArtTableInstance | null
  }

  export interface ArtTableQueryProps {
    /** 外部受控模式的加载状态；传 apiFn 时由组件内部 useTable 接管。 */
    loading?: boolean
    /** 外部受控模式的表格数据；传 apiFn 时由组件内部 useTable 接管。 */
    data?: Record<string, any>[]
    /** 外部受控模式的表格列配置；传 columnsFactory 时由组件内部 useTable 接管。 */
    tableColumns?: ColumnOption[]
    /** 外部受控模式的分页状态；传 apiFn 时由组件内部 useTable 接管。 */
    pagination?: PaginationConfig
    /** 查询表单项配置。推荐常规页面使用该属性，复杂场景再使用 searchBarProps.items。 */
    searchItems?: SearchFormItem[]
    /** 表格头部左侧操作按钮配置，内置 add/delete/import/export 四类预制按钮。 */
    headerActions?: ArtTableQueryHeaderAction[]
    /** 内管模式的数据接口。传入后 ArtTableQuery 会内部创建 useTable 并接管查询、分页、刷新。 */
    apiFn?: ArtTableQueryApiFn
    /** 内管模式的默认接口参数，默认会合并 { current: 1, size: 20 }。 */
    apiParams?: Record<string, any>
    /** 内管模式是否挂载后立即请求接口，默认 true。false 时可通过 ref.getData()/refreshData() 手动加载。 */
    immediate?: boolean
    /** 请求前从 apiParams / 搜索参数中排除的字段 */
    excludeParams?: string[]
    /** 自定义分页字段名，默认 current / size */
    paginationKey?: { current?: string; size?: string }
    /** 是否启用 useTable 缓存 */
    enableCache?: boolean
    /** 缓存时间，单位毫秒 */
    cacheTime?: number
    /** 搜索防抖时间，单位毫秒 */
    debounceTime?: number
    /** 最大缓存条数 */
    maxCacheSize?: number
    /** 数据转换函数 */
    dataTransformer?: ArtTableQueryDataTransformer
    /** 响应适配器，用于把接口响应转成 records/total/current/size */
    responseAdapter?: ArtTableQueryResponseAdapter
    /** 请求成功回调 */
    onSuccess?: (data: Record<string, any>[], response: ApiResponse<Record<string, any>>) => void
    /** 请求失败回调 */
    onError?: (error: TableError) => void
    /** 缓存命中回调 */
    onCacheHit?: (data: Record<string, any>[], response: ApiResponse<Record<string, any>>) => void
    /** 是否开启 useTable 调试日志 */
    debug?: boolean
    /** 内管模式的列工厂函数，用法同 useTable.core.columnsFactory。 */
    columnsFactory?: () => ColumnOption[]
    /** 透传给 ArtSearchBar 的额外配置，例如 labelWidth、span、showExpand。 */
    searchBarProps?: ArtTableQuerySearchBarProps
    /** 透传给 ArtTableHeader 的额外配置，例如 layout、showBorder。 */
    tableHeaderProps?: ArtTableQueryTableHeaderProps
    /** 透传给 ArtTable 的额外配置，默认已内置 rowKey: 'id'、tableLayout: 'fixed'。 */
    tableProps?: ArtTableQueryTableProps
  }

  const props = withDefaults(defineProps<ArtTableQueryProps>(), {
    loading: false,
    data: () => [],
    tableColumns: () => [],
    searchItems: () => [],
    headerActions: () => [],
    apiParams: () => ({}),
    immediate: true,
    excludeParams: () => [],
    enableCache: false,
    cacheTime: 5 * 60 * 1000,
    debounceTime: 300,
    maxCacheSize: 50,
    debug: false,
    searchBarProps: () => ({}),
    tableHeaderProps: () => ({}),
    tableProps: () => ({})
  })

  const searchModel = defineModel<Record<string, unknown>>({ default: () => ({}) })
  const columnsModel = defineModel<ColumnOption[]>('columns', { default: () => [] })
  const showSearchBar = defineModel<boolean>('showSearchBar', { default: true })
  const initialSearchModel = ref<Record<string, unknown>>({})
  const tableRef = ref<ArtTableExpose | null>(null)
  const selectedRows = ref<Record<string, any>[]>([])
  const selectedRowMap = ref(new Map<string | number, Record<string, any>>())

  export interface ArtTableQueryEmits {
    /** 点击查询按钮时触发。内管模式下组件会先自动 replaceSearchParams + getData。 */
    search: [Record<string, unknown>]
    /** 点击重置按钮时触发。内管模式下组件会先自动 resetSearchParams。 */
    reset: []
    /** 点击表格头部刷新按钮时触发。内管模式下组件会先自动 refreshData。 */
    refresh: []
    /** 点击表格头部搜索显隐按钮时触发。 */
    'header-search': []
    /** ElTable selection-change 透传。 */
    'selection-change': [any[]]
    /** 行拖拽开始透传。 */
    'row-drag-start': [Record<string, any>]
    /** 行拖拽位置更新透传。 */
    'row-drag-update': [Record<string, any>]
    /** 行拖拽结束透传。 */
    'row-drag-end': [Record<string, any>]
    /** 分页 page-size 改变时触发。内管模式下组件会先自动处理分页。 */
    'pagination:size-change': [number]
    /** 分页 current-page 改变时触发。内管模式下组件会先自动处理分页。 */
    'pagination:current-change': [number]
    /** 点击头部操作按钮时触发。 */
    'header-action-click': [
      action: ArtTableQueryHeaderAction,
      ctx: ArtTableQueryHeaderActionContext
    ]
  }

  const emit = defineEmits<ArtTableQueryEmits>()

  export interface ArtTableQueryHeaderLeftSlotProps {
    /** 当前跨页选中的完整行 */
    selectedRows: Record<string, any>[]
    /** 当前跨页选中数量 */
    selectedCount: number
  }

  export interface ArtTableQuerySlots {
    /** 工具栏左侧扩展区，渲染在 headerActions 后 */
    'header-left'?: (props: ArtTableQueryHeaderLeftSlotProps) => any
    /** 工具栏右侧扩展区 */
    'header-right'?: () => any
    /** 透传给 ArtTable 的默认插槽 */
    default?: () => any
    /** 动态表格列插槽和 search-{key} 查询项插槽 */
    [name: string]: ((props: any) => any) | undefined
  }

  const slots = defineSlots<ArtTableQuerySlots>()
  const isManaged = computed(() => !!props.apiFn)
  const managedTable = useTable<Record<string, any>>({
    core: {
      apiFn: (params: Record<string, any>) => {
        if (!props.apiFn) {
          return Promise.resolve({ records: [], total: 0, current: 1, size: 20 })
        }
        return props.apiFn(params)
      },
      apiParams: {
        current: 1,
        size: 20,
        ...props.apiParams
      },
      excludeParams: props.excludeParams,
      immediate: !!props.apiFn && props.immediate,
      paginationKey: props.paginationKey,
      columnsFactory: () => props.columnsFactory?.() ?? []
    },
    transform: {
      dataTransformer: props.dataTransformer,
      responseAdapter: props.responseAdapter
    },
    performance: {
      enableCache: props.enableCache,
      cacheTime: props.cacheTime,
      debounceTime: props.debounceTime,
      maxCacheSize: props.maxCacheSize
    },
    hooks: {
      onSuccess: props.onSuccess,
      onError: props.onError,
      onCacheHit: props.onCacheHit
    },
    debug: {
      enableLog: props.debug
    }
  })

  const resolvedSearchItems = computed(() =>
    props.searchItems.length > 0 ? props.searchItems : props.searchBarProps.items
  )

  const hasSearchBar = computed(() => (resolvedSearchItems.value?.length ?? 0) > 0)

  const resolvedSearchBarProps = computed(() => ({
    labelWidth: '96px',
    ...props.searchBarProps,
    items: resolvedSearchItems.value ?? []
  }))

  const resolvedTableProps = computed(() => ({
    rowKey: 'id',
    tableLayout: 'fixed',
    ...props.tableProps
  }))

  const getRowIdentity = (row: Record<string, any>): string | number | undefined => {
    const rowKey = resolvedTableProps.value.rowKey
    if (typeof rowKey === 'function') return rowKey(row)
    if (typeof rowKey === 'string') return row[rowKey]
    return row.id
  }

  const syncSelectedRows = (): void => {
    selectedRows.value = Array.from(selectedRowMap.value.values())
  }

  const clearSelectedRows = (): void => {
    selectedRowMap.value.clear()
    selectedRows.value = []
    void nextTick(() => {
      tableRef.value?.elTableRef?.clearSelection()
    })
  }

  const resolvedColumnsModel = computed({
    get: () => (isManaged.value ? managedTable.columnChecks.value : columnsModel.value),
    set: (value) => {
      if (isManaged.value) {
        managedTable.columnChecks.value = value
      } else {
        columnsModel.value = value
      }
    }
  })

  const resolvedLoading = computed(() =>
    isManaged.value ? managedTable.loading.value : props.loading
  )

  const resolvedData = computed(() => (isManaged.value ? managedTable.data.value : props.data))

  const resolvedColumns = computed(() =>
    isManaged.value ? managedTable.columns.value : props.tableColumns
  )

  const resolvedPagination = computed(() =>
    isManaged.value ? managedTable.pagination : props.pagination
  )

  const artTableBindings = computed(
    () =>
      ({
        ...resolvedTableProps.value,
        loading: resolvedLoading.value,
        data: resolvedData.value,
        columns: resolvedColumns.value,
        pagination: resolvedPagination.value,
        'onSelection-change': handleSelectionChange,
        'onPagination:size-change': handleSizeChange,
        'onPagination:current-change': handleCurrentChange
        // ArtTable 组合透传时，vue-tsc 对含冒号的事件名推断不完整，运行时正常。
      }) as any
  )

  const mergedTableHeaderProps = computed(() => ({
    ...props.tableHeaderProps,
    loading: resolvedLoading.value
  }))

  const reservedSlotNames = new Set(['header-left', 'header-right', 'default'])

  const searchBarSlotNames = computed(() => {
    return resolvedSearchItems.value?.map((item) => item.key) ?? []
  })

  const tableSlotNames = computed(() => {
    return Object.keys(slots).filter((name) => {
      return !reservedSlotNames.has(name) && !name.startsWith('search-')
    })
  })

  const headerActionDefaults: Record<
    ArtTableQueryHeaderActionType,
    {
      label: string
      icon: string
      buttonProps: Record<string, any>
      selectionRequired?: boolean
      confirm?: boolean
      confirmTitle?: string
    }
  > = {
    add: {
      label: '新增',
      icon: 'ri:add-line',
      buttonProps: { type: 'primary', plain: true }
    },
    delete: {
      label: '批量删除',
      icon: 'ri:delete-bin-line',
      buttonProps: { type: 'danger', plain: true },
      selectionRequired: true,
      confirm: true,
      confirmTitle: '删除确认'
    },
    import: {
      label: '导入',
      icon: 'ri:upload-2-line',
      buttonProps: { type: 'success', plain: true }
    },
    export: {
      label: '导出',
      icon: 'ri:download-2-line',
      buttonProps: { type: 'warning', plain: true }
    }
  }

  const headerActionApi = computed<ArtTableQueryHeaderActionContext['api']>(() => ({
    refreshData: managedTable.refreshData,
    refreshCreate: managedTable.refreshCreate,
    refreshUpdate: managedTable.refreshUpdate,
    refreshRemove: managedTable.refreshRemove,
    getData: managedTable.getData
  }))

  const createHeaderActionContext = (
    action: ArtTableQueryHeaderAction,
    event?: MouseEvent
  ): ArtTableQueryHeaderActionContext => ({
    action,
    selectedRows: selectedRows.value,
    selectedCount: selectedRows.value.length,
    event,
    api: headerActionApi.value
  })

  const visibleHeaderActions = computed(() => {
    return props.headerActions.filter((action) => {
      if (typeof action.hidden === 'function') {
        return !action.hidden(createHeaderActionContext(action))
      }
      return !action.hidden
    })
  })

  const getHeaderActionKey = (action: ArtTableQueryHeaderAction): string => {
    return action.key || action.type || `${props.headerActions.indexOf(action)}`
  }

  const getHeaderActionClass = () => ({
    'art-table-query__header-action': true
  })

  const getHeaderActionDefault = (action: ArtTableQueryHeaderAction) => {
    return action.type ? headerActionDefaults[action.type] : undefined
  }

  const getHeaderActionLabel = (action: ArtTableQueryHeaderAction): string | Component => {
    if (action.label) return action.label
    const defaultLabel = getHeaderActionDefault(action)?.label || '操作'
    if (action.type === 'delete' && selectedRows.value.length > 0) {
      return `${defaultLabel}(${selectedRows.value.length})`
    }
    return defaultLabel
  }

  const getHeaderActionIcon = (
    action: ArtTableQueryHeaderAction
  ): string | Component | undefined => {
    return action.icon || getHeaderActionDefault(action)?.icon
  }

  const getHeaderActionButtonProps = (action: ArtTableQueryHeaderAction) => ({
    ...(getHeaderActionDefault(action)?.buttonProps ?? {}),
    ...(action.buttonProps ?? {})
  })

  const isHeaderActionSelectionRequired = (action: ArtTableQueryHeaderAction): boolean => {
    return action.selectionRequired ?? getHeaderActionDefault(action)?.selectionRequired ?? false
  }

  const isHeaderActionDisabled = (action: ArtTableQueryHeaderAction): boolean => {
    const ctx = createHeaderActionContext(action)
    const disabled = typeof action.disabled === 'function' ? action.disabled(ctx) : action.disabled
    return (
      !!disabled || (isHeaderActionSelectionRequired(action) && selectedRows.value.length === 0)
    )
  }

  const getHeaderActionSlotProps = (action: ArtTableQueryHeaderAction) =>
    createHeaderActionContext(action)

  const resolveHeaderActionContent = (
    action: ArtTableQueryHeaderAction,
    ctx: ArtTableQueryHeaderActionContext
  ): string | VNode | undefined => {
    const content =
      action.content ||
      (action.type === 'delete'
        ? `确定删除选中的 ${ctx.selectedCount} 条数据吗？删除后无法恢复。`
        : '')

    const resolvedContent =
      typeof content === 'function'
        ? (content as (ctx: ArtTableQueryHeaderActionContext) => VNodeChild)(ctx)
        : content

    if (resolvedContent == null || typeof resolvedContent === 'boolean') return undefined
    if (typeof resolvedContent === 'string') return resolvedContent
    if (typeof resolvedContent === 'number') return String(resolvedContent)
    if (Array.isArray(resolvedContent)) return h('div', resolvedContent)
    if (typeof resolvedContent === 'object' && '__v_isVNode' in resolvedContent) {
      return resolvedContent as VNode
    }

    return h(resolvedContent as Component, ctx)
  }

  const shouldConfirmHeaderAction = (action: ArtTableQueryHeaderAction): boolean => {
    return action.confirm ?? getHeaderActionDefault(action)?.confirm ?? false
  }

  const isExcelColumn = (column: ColumnOption): boolean => {
    return (
      !!column.prop &&
      column.prop !== 'operation' &&
      column.exportable !== false &&
      !['selection', 'expand', 'index', 'globalIndex'].includes(String(column.type)) &&
      typeof column.label === 'string'
    )
  }

  const resolveExcelColumns = (
    columns: ArtTableQueryExcelColumns | undefined,
    ctx: ArtTableQueryHeaderActionContext
  ): ArtTableQueryExcelColumn[] => {
    if (typeof columns === 'function') return columns(ctx)
    if (Array.isArray(columns) && columns.length) return columns

    return resolvedColumns.value.filter(isExcelColumn).map((column: ColumnOption) => ({
      key: column.prop as string,
      title: String(column.label),
      width: typeof column.width === 'number' ? column.width : undefined,
      formatter: column.formatter
        ? (_value: unknown, row: Record<string, any>) => {
            const formattedValue = column.formatter?.(row)
            if (formattedValue && typeof formattedValue === 'object') return ''
            return formattedValue as string | number | boolean | null | undefined
          }
        : undefined
    }))
  }

  const getActionFilename = (
    action: ArtTableQueryHeaderAction,
    ctx: ArtTableQueryHeaderActionContext
  ): string => {
    if (typeof action.exportFilename === 'function') return action.exportFilename(ctx)
    return action.exportFilename || '表格数据'
  }

  const fetchExportRows = async (
    action: ArtTableQueryHeaderAction,
    ctx: ArtTableQueryHeaderActionContext
  ): Promise<Record<string, any>[]> => {
    const maxRows = action.exportMaxRows || 10000
    const columns = resolveExcelColumns(action.exportColumns, ctx)

    if (action.exportApi) {
      const selectedIds = ctx.selectedRows
        .map((row) => getRowIdentity(row))
        .filter((id): id is string | number => id !== undefined)
      const response = await action.exportApi(
        {
          selectedRows: ctx.selectedRows,
          selectedIds,
          selectedCount: ctx.selectedCount,
          searchParams: cloneSearchModel(searchModel.value),
          columns,
          maxRows
        },
        ctx
      )

      if (Array.isArray(response)) return response as Record<string, any>[]

      const adapter =
        action.exportResponseAdapter || props.responseAdapter || defaultResponseAdapter
      return extractTableData(adapter(response))
    }

    if (action.exportData) return await action.exportData(ctx)
    if (ctx.selectedRows.length) return ctx.selectedRows
    if (!props.apiFn) return resolvedData.value

    const currentKey = props.paginationKey?.current || 'current'
    const sizeKey = props.paginationKey?.size || 'size'
    const response = await props.apiFn({
      ...searchModel.value,
      [currentKey]: 1,
      [sizeKey]: maxRows
    })
    const adapter = props.responseAdapter || defaultResponseAdapter
    return extractTableData(adapter(response))
  }

  const handleDefaultExport = async (
    action: ArtTableQueryHeaderAction,
    ctx: ArtTableQueryHeaderActionContext
  ): Promise<void> => {
    const rows = await fetchExportRows(action, ctx)
    if (!rows.length) {
      ElMessage.warning('暂无可导出的数据')
      return
    }

    exportExcel({
      data: rows,
      columns: resolveExcelColumns(action.exportColumns, ctx),
      filename: getActionFilename(action, ctx),
      sheetName: action.exportSheetName || getActionFilename(action, ctx),
      maxRows: action.exportMaxRows
    })
  }

  const resolveImportRows = async (
    action: ArtTableQueryHeaderAction,
    rows: Array<Record<string, unknown>>,
    ctx: ArtTableQueryHeaderActionContext
  ): Promise<Array<Record<string, any>>> => {
    if (action.importTransformer) return await action.importTransformer(rows, ctx)
    return mapExcelRowsToRecords(rows, resolveExcelColumns(action.importColumns, ctx))
  }

  const handleHeaderActionImportSuccess = async (
    action: ArtTableQueryHeaderAction,
    data: Array<Record<string, unknown>>
  ): Promise<void> => {
    const ctx = createHeaderActionContext(action)
    emit('header-action-click', action, ctx)
    const rows =
      action.importApi || action.importTransformer || action.importColumns
        ? await resolveImportRows(action, data, ctx)
        : data

    if (action.importApi) {
      if (!rows.length) {
        ElMessage.warning('未读取到可导入的数据')
        return
      }
      await action.importApi(rows as Array<Record<string, any>>, ctx)
      if (isManaged.value) {
        await managedTable.refreshCreate()
      }
    }

    await action.onImportSuccess?.(rows, ctx)
  }

  const handleHeaderActionImportError = async (
    action: ArtTableQueryHeaderAction,
    error: Error
  ): Promise<void> => {
    await action.onImportError?.(error, createHeaderActionContext(action))
  }

  const handleHeaderActionClick = async (
    action: ArtTableQueryHeaderAction,
    event: MouseEvent
  ): Promise<void> => {
    if (isHeaderActionDisabled(action)) return

    const ctx = createHeaderActionContext(action, event)

    if (shouldConfirmHeaderAction(action)) {
      try {
        await ElMessageBox.confirm(
          resolveHeaderActionContent(action, ctx),
          action.confirmTitle || '操作确认',
          {
            type: action.type === 'delete' ? 'warning' : 'info',
            confirmButtonText: '确定',
            cancelButtonText: '取消',
            confirmButtonClass: action.type === 'delete' ? 'el-button--danger' : undefined
          }
        )
      } catch {
        return
      }
    }

    emit('header-action-click', action, ctx)
    if (action.type === 'export' && !action.onClick) {
      await handleDefaultExport(action, ctx)
    } else {
      await action.onClick?.(ctx)
    }
    if (action.type === 'delete') {
      clearSelectedRows()
    }
  }

  const cloneSearchModel = (value: Record<string, unknown> | undefined) => {
    if (!value) return {}
    return JSON.parse(JSON.stringify(value)) as Record<string, unknown>
  }

  const resetSearchModel = (): void => {
    searchModel.value = cloneSearchModel(initialSearchModel.value)
  }

  onMounted(() => {
    initialSearchModel.value = cloneSearchModel(searchModel.value)
  })

  const handleSearch = (params: Record<string, unknown>): void => {
    clearSelectedRows()
    if (isManaged.value) {
      managedTable.replaceSearchParams(params)
      void managedTable.getData()
    }
    emit('search', params)
  }

  const handleReset = (): void => {
    clearSelectedRows()
    resetSearchModel()
    if (isManaged.value) {
      void managedTable.resetSearchParams()
    }
    emit('reset')
  }

  const handleRefresh = (): void => {
    if (isManaged.value) {
      void managedTable.refreshData()
    }
    emit('refresh')
  }

  const refreshRemove = async (): Promise<void> => {
    clearSelectedRows()
    await managedTable.refreshRemove()
  }

  const handleSelectionChange = (selection: Record<string, any>[]): void => {
    const currentPageKeys = new Set(
      resolvedData.value
        .map((row) => getRowIdentity(row))
        .filter((key): key is string | number => key !== undefined)
    )
    const currentSelectionKeys = new Set(
      selection
        .map((row) => getRowIdentity(row))
        .filter((key): key is string | number => key !== undefined)
    )

    currentPageKeys.forEach((key) => {
      if (!currentSelectionKeys.has(key)) {
        selectedRowMap.value.delete(key)
      }
    })

    selection.forEach((row) => {
      const key = getRowIdentity(row)
      if (key !== undefined) {
        selectedRowMap.value.set(key, row)
      }
    })

    syncSelectedRows()
    emit('selection-change', selectedRows.value)
  }

  const handleRowDragStart = (payload: Record<string, any>): void => {
    emit('row-drag-start', payload)
  }

  const handleRowDragUpdate = (payload: Record<string, any>): void => {
    emit('row-drag-update', payload)
  }

  const handleRowDragEnd = (payload: Record<string, any>): void => {
    emit('row-drag-end', payload)
  }

  const handleSizeChange = (val: number): void => {
    if (isManaged.value) {
      void managedTable.handleSizeChange(val)
    }
    emit('pagination:size-change', val)
  }

  const handleCurrentChange = (val: number): void => {
    if (isManaged.value) {
      void managedTable.handleCurrentChange(val)
    }
    emit('pagination:current-change', val)
  }

  const handleShowSearchBarChange = (value: boolean): void => {
    showSearchBar.value = value
  }

  export interface ArtTableQueryExpose {
    /** 全量刷新，适用于工具栏手动刷新。 */
    refreshData: () => Promise<void>
    /** 新增后刷新，默认回到第一页。 */
    refreshCreate: () => Promise<void>
    /** 编辑后刷新，默认保留当前页。 */
    refreshUpdate: () => Promise<void>
    /** 删除后刷新，当前页为空时自动回退上一页。 */
    refreshRemove: () => Promise<void>
    /** 查询数据，默认按搜索语义回到第一页。 */
    getData: () => Promise<unknown>
    /** 清空查询表单模型并重置内部查询参数。 */
    resetSearchParams: () => Promise<void>
  }

  const resetSearchParams = async (): Promise<void> => {
    resetSearchModel()
    if (isManaged.value) {
      await managedTable.resetSearchParams()
    }
  }

  const getData = async (): Promise<unknown> => {
    if (isManaged.value) {
      managedTable.replaceSearchParams(cloneSearchModel(searchModel.value))
    }
    return await managedTable.getData()
  }

  defineExpose<ArtTableQueryExpose>({
    refreshData: managedTable.refreshData,
    refreshCreate: managedTable.refreshCreate,
    refreshUpdate: managedTable.refreshUpdate,
    refreshRemove,
    getData,
    resetSearchParams
  })
</script>

<style scoped lang="scss">
  .art-table-query {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-height: 0;
  }

  :deep(.art-table-card) {
    min-height: 0;
  }

  :deep(.art-table-card > .el-card__body) {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-height: 0;
  }

  .art-table-query__header-left {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }

  .art-table-query__header-top {
    margin-bottom: 12px;
  }

  .art-table-query__header-action {
    display: inline-flex;
  }
</style>
