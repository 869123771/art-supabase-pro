<!-- 表格组件 -->
<!-- 支持：el-table 全部属性、事件、插槽，同官方文档写法 -->
<!-- 扩展功能：分页组件、渲染自定义列、loading、表格全局边框、斑马纹、表格尺寸、表头背景配置 -->
<!-- 获取 ref：默认暴露了 elTableRef 外部通过 ref.value.elTableRef 可以调用 el-table 方法 -->
<template>
  <div
    class="art-table"
    :class="{ 'is-empty': isEmpty, 'is-row-selection-dragging': isRowSelectionDragging }"
    :style="containerHeight"
    @mousedown="handleTableMouseDown"
  >
    <ElTable ref="elTableRef" v-loading="!!loading" v-bind="mergedTableProps">
      <template v-for="col in columns" :key="col.prop || col.type">
        <!-- 渲染全局序号列 -->
        <ElTableColumn v-if="col.type === 'globalIndex'" v-bind="{ ...col }">
          <template #default="{ $index }">
            <span>{{ getGlobalIndex($index) }}</span>
          </template>
        </ElTableColumn>

        <!-- 渲染展开行 -->
        <ElTableColumn v-else-if="col.type === 'expand'" v-bind="cleanColumnProps(col)">
          <template #default="{ row }">
            <component :is="col.formatter ? col.formatter(row) : null" />
          </template>
        </ElTableColumn>

        <!-- 渲染分组列 -->
        <ElTableColumn
          v-else-if="Array.isArray(col.children) && col.children.length"
          v-bind="cleanColumnProps(col)"
        >
          <ElTableColumn
            v-for="child in col.children"
            :key="child.prop || child.label"
            v-bind="cleanColumnProps(child)"
          >
            <template v-if="child.useHeaderSlot && child.prop" #header="headerScope">
              <slot
                :name="child.headerSlotName || `${child.prop}-header`"
                v-bind="{ ...headerScope, prop: child.prop, label: child.label }"
              >
                {{ child.label }}
              </slot>
            </template>
            <template v-if="shouldUseCustomCellTemplate(child)" #default="slotScope">
              <div v-if="shouldRenderSlotScope(slotScope)" class="art-table__cell-content">
                <span class="art-table__cell-value">
                  <slot
                    v-if="child.useSlot && child.prop"
                    :name="child.slotName || child.prop"
                    v-bind="{
                      ...slotScope,
                      prop: child.prop,
                      value: child.prop ? getCellValue(slotScope.row, child.prop) : undefined
                    }"
                  />
                  <ArtDictDisplay
                    v-else-if="child.dict"
                    :dict-code="child.dict.code"
                    :value="getDictColumnValue(child, slotScope.row)"
                    :display="child.dict.display"
                  />
                  <component
                    v-else-if="isComponentCellContent(getColumnCellContent(child, slotScope))"
                    :is="getColumnCellContent(child, slotScope)"
                  />
                  <span v-else>{{ getColumnCellContent(child, slotScope) }}</span>
                </span>
              </div>
            </template>
          </ElTableColumn>
        </ElTableColumn>

        <!-- 渲染普通列 -->
        <ElTableColumn v-else v-bind="cleanColumnProps(col)">
          <template v-if="col.useHeaderSlot && col.prop" #header="headerScope">
            <slot
              :name="col.headerSlotName || `${col.prop}-header`"
              v-bind="{ ...headerScope, prop: col.prop, label: col.label }"
            >
              {{ col.label }}
            </slot>
          </template>
          <template v-if="shouldUseCustomCellTemplate(col)" #default="slotScope">
            <div v-if="shouldRenderSlotScope(slotScope)" class="art-table__cell-content">
              <button
                v-if="isColumnDraggable(col, slotScope.row)"
                type="button"
                class="art-table__drag-handle"
                :class="{ 'is-disabled': isColumnDragDisabled(col, slotScope.row) }"
                :disabled="isColumnDragDisabled(col, slotScope.row)"
                :data-row-key="getRowIdentity(slotScope.row)"
                :aria-label="isColumnDragDisabled(col, slotScope.row) ? '不可拖拽' : '拖拽排序'"
                :title="isColumnDragDisabled(col, slotScope.row) ? '不可拖拽' : '拖拽排序'"
              >
                <ArtSvgIcon :icon="col.dragIcon || 'ri:draggable'" />
              </button>
              <span class="art-table__cell-value">
                <slot
                  v-if="col.useSlot && col.prop"
                  :name="col.slotName || col.prop"
                  v-bind="{
                    ...slotScope,
                    prop: col.prop,
                    value: col.prop ? getCellValue(slotScope.row, col.prop) : undefined
                  }"
                />
                <ArtDictDisplay
                  v-else-if="col.dict"
                  :dict-code="col.dict.code"
                  :value="getDictColumnValue(col, slotScope.row)"
                  :display="col.dict.display"
                />
                <component
                  v-else-if="isComponentCellContent(getColumnCellContent(col, slotScope))"
                  :is="getColumnCellContent(col, slotScope)"
                />
                <span v-else>{{ getColumnCellContent(col, slotScope) }}</span>
              </span>
            </div>
          </template>
        </ElTableColumn>
      </template>

      <template v-if="$slots.default" #default><slot /></template>

      <template #empty>
        <div v-if="loading"></div>
        <ElEmpty v-else :description="emptyText" :image-size="120" />
      </template>
    </ElTable>

    <div
      class="pagination custom-pagination"
      v-if="showPagination"
      :class="mergedPaginationOptions?.align"
      ref="paginationRef"
    >
      <ElPagination
        v-bind="mergedPaginationOptions"
        :total="currentPagination?.total"
        :disabled="loading"
        :page-size="currentPagination?.size"
        :current-page="currentPagination?.current"
        @size-change="handleSizeChange"
        @current-change="handleCurrentChange"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
  import {
    ref,
    computed,
    nextTick,
    watch,
    watchEffect,
    getCurrentInstance,
    useAttrs,
    onMounted,
    onBeforeUnmount
  } from 'vue'
  import type { ComponentPublicInstance } from 'vue'
  import type { TableProps } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import { useDraggable, type DraggableEvent } from 'vue-draggable-plus'
  import { ColumnOption } from '@/types'
  import { useTableStore } from '@/store/modules/table'
  import { useCommon } from '@/hooks/core/useCommon'
  import { useTableHeight } from '@/hooks/core/useTableHeight'
  import { useResizeObserver, useWindowSize } from '@vueuse/core'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'

  defineOptions({ name: 'ArtTable' })

  export type ArtTableInstance = ComponentPublicInstance & {
    clearSelection: () => void
    toggleAllSelection: () => void
    toggleRowSelection: (row: unknown, selected?: boolean) => void
    setCurrentRow: (row?: unknown) => void
    clearSort: () => void
    clearFilter: (columnKeys?: string[]) => void
    doLayout: () => void
    sort: (prop: string, order: string) => void
    setScrollTop: (top?: number) => void
  }

  const { width } = useWindowSize()
  const elTableRef = ref<ArtTableInstance | null>(null)
  const paginationRef = ref<HTMLElement>()
  const tableHeaderRef = ref<HTMLElement>()
  const sortableTargetRef = ref<HTMLElement>()
  const rowKeysBeforeDrag = ref<string[]>([])
  const tableStore = useTableStore()
  const { isBorder, isZebra, tableSize, isFullScreen, isHeaderBackground } = storeToRefs(tableStore)

  interface RowDragPayload<T = Record<string, any>> {
    row?: T
    targetRow?: T
    oldIndex?: number
    newIndex?: number
    event: DraggableEvent<T>
  }

  /** 分页配置接口 */
  interface PaginationConfig {
    /** 当前页码 */
    current: number
    /** 每页显示条目个数 */
    size: number
    /** 总条目数 */
    total: number
  }

  /** 分页器配置选项接口 */
  interface PaginationOptions {
    /** 每页显示个数选择器的选项列表 */
    pageSizes?: number[]
    /** 分页器的对齐方式 */
    align?: 'left' | 'center' | 'right'
    /** 分页器的布局 */
    layout?: string
    /** 是否显示分页器背景 */
    background?: boolean
    /** 只有一页时是否隐藏分页器 */
    hideOnSinglePage?: boolean
    /** 分页器的大小 */
    size?: 'small' | 'default' | 'large'
    /** 分页器的页码数量 */
    pagerCount?: number
  }

  /** ArtTable 组件的 Props 接口 */
  interface ArtTableProps extends Partial<TableProps<Record<string, any>>> {
    /** 表格数据 */
    data?: Record<string, any>[]
    /** 加载状态 */
    loading?: boolean
    /** 列渲染配置 */
    columns?: ColumnOption[]
    /** 分页状态 */
    pagination?: PaginationConfig | false
    /** 分页配置 */
    paginationOptions?: PaginationOptions
    /** 空数据表格高度 */
    emptyHeight?: string
    /** 空数据时显示的文本 */
    emptyText?: string
    /** 是否开启 ArtTableHeader，解决表格高度自适应问题 */
    showTableHeader?: boolean
    /** 工具栏上方额外内容占用的高度 */
    additionalHeightOffset?: number
    /** 已选中行 key，用于选中行背景展示 */
    selectedRowKeys?: Array<string | number>
  }

  const props = withDefaults(defineProps<ArtTableProps>(), {
    columns: () => [],
    fit: true,
    showHeader: true,
    stripe: undefined,
    border: undefined,
    size: undefined,
    emptyHeight: '100%',
    emptyText: '暂无数据',
    showTableHeader: true,
    additionalHeightOffset: 0,
    selectedRowKeys: () => []
  })
  const instance = getCurrentInstance()
  const attrs = useAttrs()

  const LAYOUT = {
    MOBILE: 'prev, pager, next, sizes, jumper, total',
    IPAD: 'prev, pager, next, jumper, total',
    DESKTOP: 'total, prev, pager, next, sizes, jumper'
  }

  const layout = computed(() => {
    if (width.value < 768) {
      return LAYOUT.MOBILE
    } else if (width.value < 1024) {
      return LAYOUT.IPAD
    } else {
      return LAYOUT.DESKTOP
    }
  })

  // 默认分页常量
  const DEFAULT_PAGINATION_OPTIONS: PaginationOptions = {
    pageSizes: [10, 20, 30, 50, 100],
    align: 'center',
    background: true,
    layout: layout.value,
    hideOnSinglePage: false,
    size: 'default',
    pagerCount: width.value > 1200 ? 7 : 5
  }

  // 合并分页配置
  const mergedPaginationOptions = computed(() => ({
    ...DEFAULT_PAGINATION_OPTIONS,
    ...props.paginationOptions
  }))

  // 边框 (优先级：props > store)
  const border = computed(() => props.border ?? isBorder.value)
  // 斑马纹
  const stripe = computed(() => props.stripe ?? isZebra.value)
  // 表格尺寸
  const size = computed(() => props.size ?? tableSize.value)
  // 数据是否为空
  const isEmpty = computed(() => props.data?.length === 0)

  const paginationHeight = ref(0)
  const tableHeaderHeight = ref(0)
  const isRowSelectionDragging = ref(false)
  const rowSelectionDragStartRow = ref<Record<string, any>>()
  const rowSelectionDragMode = ref<'select' | 'deselect'>('select')
  const dragSelectedRowKeys = new Set<string>()

  // 使用 useResizeObserver 监听分页器高度变化
  useResizeObserver(paginationRef, (entries) => {
    const entry = entries[0]
    if (entry) {
      // 使用 requestAnimationFrame 避免 ResizeObserver loop 警告
      requestAnimationFrame(() => {
        paginationHeight.value = entry.contentRect.height
      })
    }
  })

  // 使用 useResizeObserver 监听表格头部高度变化
  useResizeObserver(tableHeaderRef, (entries) => {
    const entry = entries[0]
    if (entry) {
      // 使用 requestAnimationFrame 避免 ResizeObserver loop 警告
      requestAnimationFrame(() => {
        tableHeaderHeight.value = entry.contentRect.height
      })
    }
  })

  // 分页器与表格之间的间距常量（计算属性，响应 showTableHeader 变化）
  const PAGINATION_SPACING = computed(() => (props.showTableHeader ? 6 : 15))

  // 使用表格高度计算 Hook
  const { containerHeight } = useTableHeight({
    showTableHeader: computed(() => props.showTableHeader),
    additionalHeightOffset: computed(() => props.additionalHeightOffset),
    paginationHeight,
    tableHeaderHeight,
    paginationSpacing: PAGINATION_SPACING
  })

  // 表格高度逻辑
  const height = computed(() => {
    // 全屏模式下占满全屏
    if (isFullScreen.value) return '100%'
    // 空数据且非加载状态时固定高度
    if (isEmpty.value && !props.loading) return props.emptyHeight
    // 使用传入的高度
    if (props.height) return props.height
    // 默认占满容器高度
    return '100%'
  })

  // 表头背景颜色样式
  const headerCellStyle = computed(() => ({
    background: isHeaderBackground.value
      ? 'var(--el-fill-color-lighter)'
      : 'var(--default-box-color)',
    ...(props.headerCellStyle || {}) // 合并用户传入的样式
  }))

  // 只有显式传入时才覆盖 ElTable 的原生默认值，避免继承的 Boolean props 把官方默认值冲掉。
  const hasExplicitTableProp = (propName: string): boolean => {
    const rawProps = (instance?.vnode.props || {}) as Record<string, unknown>
    const kebabName = propName.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)
    return propName in rawProps || kebabName in rawProps
  }

  const mergedTableProps = computed(() => {
    const tableProps = {
      ...attrs,
      ...props
    } as Record<string, unknown>
    delete tableProps.selectedRowKeys

    return {
      ...tableProps,
      height: height.value,
      stripe: stripe.value,
      border: border.value,
      size: size.value,
      headerCellStyle: headerCellStyle.value,
      rowClassName: resolveRowClassName,
      onCellMouseEnter: handleCellMouseEnter,
      // Element Plus 默认值为 true，未显式传入时不应被 ArtTable 覆盖成 false。
      selectOnIndeterminate: hasExplicitTableProp('selectOnIndeterminate')
        ? props.selectOnIndeterminate
        : undefined
    }
  })

  // 是否显示分页器
  const currentPagination = computed(() =>
    props.pagination === false ? undefined : props.pagination
  )

  const showPagination = computed(() => !!currentPagination.value && !isEmpty.value)

  const hasDraggableColumn = computed(() =>
    props.columns.some(
      (column) => column.draggable === true || typeof column.draggable === 'function'
    )
  )

  const hasSelectionColumn = computed(() =>
    props.columns.some((column) => column.type === 'selection')
  )

  // Element Plus 在部分场景会先用 $index = -1 进行预渲染。
  // 这对普通展示无影响，但会让 ElForm 错误注册出 lineList.-1.xxx 这类字段。
  const shouldRenderSlotScope = (slotScope: { $index?: number }) => {
    return slotScope.$index === undefined || slotScope.$index >= 0
  }

  const shouldUseCustomCellTemplate = (col: ColumnOption) => {
    return (
      (col.useSlot && col.prop) ||
      !!col.dict ||
      col.draggable === true ||
      typeof col.draggable === 'function'
    )
  }

  const EMPTY_CELL_TEXT = '--'

  const isEmptyCellValue = (value: unknown) => {
    return (
      value === undefined || value === null || (typeof value === 'string' && value.trim() === '')
    )
  }

  const formatEmptyCellValue = (value: unknown) => {
    if (isEmptyCellValue(value)) return EMPTY_CELL_TEXT
    if (isComponentCellContent(value)) return value
    return value
  }

  const resolveColumnBoolean = (
    value: boolean | ((row: Record<string, any>) => boolean) | undefined,
    row: Record<string, any>,
    defaultValue = false
  ) => {
    if (typeof value === 'function') return value(row)
    return value ?? defaultValue
  }

  const isColumnDraggable = (col: ColumnOption, row: Record<string, any>) => {
    return resolveColumnBoolean(col.draggable, row)
  }

  const isColumnDragDisabled = (col: ColumnOption, row: Record<string, any>) => {
    return resolveColumnBoolean(col.dragDisabled, row)
  }

  const getCellValue = (row: Record<string, any>, prop: string) => {
    return prop.split('.').reduce<unknown>((value, key) => {
      if (value && typeof value === 'object') {
        return (value as Record<string, unknown>)[key]
      }
      return undefined
    }, row)
  }

  const getDictColumnValue = (col: ColumnOption, row: Record<string, any>) => {
    if (col.dict?.value) return col.dict.value(row)
    if (col.prop) return getCellValue(row, col.prop) as string | number | null | undefined
    return undefined
  }

  const getColumnCellContent = (
    col: ColumnOption,
    slotScope: { row: Record<string, any>; column: unknown; $index: number }
  ) => {
    if (col.formatter) return formatEmptyCellValue(col.formatter(slotScope.row))
    if (col.prop) return formatEmptyCellValue(getCellValue(slotScope.row, col.prop))
    return EMPTY_CELL_TEXT
  }

  const isComponentCellContent = (content: unknown) => {
    return content !== null && (typeof content === 'object' || typeof content === 'function')
  }

  const getRowIdentity = (row: Record<string, any>): string => {
    const rowKey = props.rowKey
    if (typeof rowKey === 'function') return String(rowKey(row))
    if (typeof rowKey === 'string') return String(getCellValue(row, rowKey) ?? '')
    return String(row.id ?? '')
  }

  const selectedRowKeySet = computed(
    () => new Set(props.selectedRowKeys.map((key) => String(key)).filter(Boolean))
  )

  const normalizeClassName = (value: unknown): string => {
    if (Array.isArray(value)) return value.map(normalizeClassName).filter(Boolean).join(' ')
    if (value && typeof value === 'object') {
      return Object.entries(value as Record<string, unknown>)
        .filter(([, enabled]) => Boolean(enabled))
        .map(([className]) => className)
        .join(' ')
    }
    return typeof value === 'string' ? value : ''
  }

  const resolveRowClassName = (scope: { row: Record<string, any>; rowIndex: number }) => {
    const customClassName =
      typeof props.rowClassName === 'function' ? props.rowClassName(scope) : props.rowClassName
    const classNames = [normalizeClassName(customClassName)]
    if (selectedRowKeySet.value.has(getRowIdentity(scope.row))) {
      classNames.push('is-art-selected-row')
    }
    return classNames.filter(Boolean).join(' ')
  }

  const callTableEventHandler = (handler: unknown, ...args: unknown[]): void => {
    if (Array.isArray(handler)) {
      handler.forEach((item) => callTableEventHandler(item, ...args))
      return
    }
    if (typeof handler === 'function') {
      handler(...args)
    }
  }

  const applyRowSelectionByDrag = (row: Record<string, any> | undefined): void => {
    if (!row) return
    const rowKey = getRowIdentity(row)
    if (!rowKey || dragSelectedRowKeys.has(rowKey)) return
    const selected = selectedRowKeySet.value.has(rowKey)
    const shouldSelect = rowSelectionDragMode.value === 'select'
    if (selected === shouldSelect) return
    dragSelectedRowKeys.add(rowKey)
    elTableRef.value?.toggleRowSelection(row, shouldSelect)
  }

  const startRowSelectionDrag = (row: Record<string, any>): void => {
    const startRow = rowSelectionDragStartRow.value
    if (!startRow) return
    isRowSelectionDragging.value = true
    applyRowSelectionByDrag(startRow)
    applyRowSelectionByDrag(row)
  }

  const endRowSelectionDrag = (): void => {
    isRowSelectionDragging.value = false
    rowSelectionDragStartRow.value = undefined
    dragSelectedRowKeys.clear()
  }

  const handleCellMouseEnter = (
    row: Record<string, any>,
    column: unknown,
    cell: HTMLTableCellElement,
    event: Event
  ): void => {
    callTableEventHandler(
      (attrs as Record<string, unknown>).onCellMouseEnter,
      row,
      column,
      cell,
      event
    )
    if (!rowSelectionDragStartRow.value) return
    if (!(event instanceof MouseEvent) || (event.buttons & 1) === 0) {
      endRowSelectionDrag()
      return
    }
    startRowSelectionDrag(row)
  }

  const ignoredDragStartSelector = [
    'button',
    'a',
    'input',
    'textarea',
    'select',
    '[role="button"]',
    '.el-button',
    '.el-switch',
    '.el-radio',
    '.el-input',
    '.el-select',
    '.el-dropdown',
    '.art-table__drag-handle'
  ].join(',')

  const getPointerRow = (event: MouseEvent): Record<string, any> | undefined => {
    const target = event.target
    if (!(target instanceof Element)) return undefined
    const rowElement = target.closest<HTMLTableRowElement>('tr.el-table__row')
    const tableBody = rowElement?.parentElement
    if (!rowElement || !tableBody) return undefined
    const rowElements = Array.from(
      tableBody.querySelectorAll<HTMLTableRowElement>('tr.el-table__row')
    )
    const rowIndex = rowElements.indexOf(rowElement)
    return flattenRows(props.data ?? [])[rowIndex]
  }

  const handleTableMouseDown = (event: MouseEvent): void => {
    if (event.button !== 0 || props.loading || !hasSelectionColumn.value) return
    const target = event.target
    if (!(target instanceof Element)) return
    if (!target.closest('.el-table__body-wrapper')) return
    if (target.closest('.el-checkbox')) return
    if (target.closest(ignoredDragStartSelector)) return

    const row = getPointerRow(event)
    if (!row) return
    rowSelectionDragStartRow.value = row
    rowSelectionDragMode.value = selectedRowKeySet.value.has(getRowIdentity(row))
      ? 'deselect'
      : 'select'
    dragSelectedRowKeys.clear()
  }

  onMounted(() => {
    window.addEventListener('mouseup', endRowSelectionDrag)
    window.addEventListener('blur', endRowSelectionDrag)
  })

  onBeforeUnmount(() => {
    window.removeEventListener('mouseup', endRowSelectionDrag)
    window.removeEventListener('blur', endRowSelectionDrag)
  })

  const flattenRows = (rows: Record<string, any>[] = []): Record<string, any>[] => {
    const result: Record<string, any>[] = []
    const walk = (items: Record<string, any>[]) => {
      items.forEach((item) => {
        result.push(item)
        if (Array.isArray(item.children)) {
          walk(item.children)
        }
      })
    }
    walk(rows)
    return result
  }

  const rowMap = computed(() => {
    const map = new Map<string, Record<string, any>>()
    flattenRows(props.data ?? []).forEach((row) => {
      const key = getRowIdentity(row)
      if (key) map.set(key, row)
    })
    return map
  })

  const getDragHandleRowKey = (rowElement: Element | undefined): string | undefined => {
    const handle = rowElement?.querySelector<HTMLElement>('.art-table__drag-handle')
    return handle?.dataset.rowKey || undefined
  }

  const getVisibleRowKeysFromDom = (): string[] => {
    const tableElement = elTableRef.value?.$el as HTMLElement | undefined
    return Array.from(
      tableElement?.querySelectorAll('.el-table__body-wrapper .el-table__row') ?? []
    )
      .map((rowElement) => getDragHandleRowKey(rowElement))
      .filter((key): key is string => !!key)
  }

  const buildRowDragPayload = (event: DraggableEvent<Record<string, any>>): RowDragPayload => {
    const snapshotKeys = rowKeysBeforeDrag.value.length
      ? rowKeysBeforeDrag.value
      : getVisibleRowKeysFromDom()
    const rowKey = snapshotKeys[event.oldIndex ?? -1]
    const targetRowKey = snapshotKeys[event.newIndex ?? -1]
    return {
      row: rowKey ? rowMap.value.get(rowKey) : undefined,
      targetRow: targetRowKey ? rowMap.value.get(targetRowKey) : undefined,
      oldIndex: event.oldIndex,
      newIndex: event.newIndex,
      event
    }
  }

  const handleRowDragStart = (event: DraggableEvent<Record<string, any>>) => {
    rowKeysBeforeDrag.value = getVisibleRowKeysFromDom()
    emit('row-drag-start', buildRowDragPayload(event))
  }

  const handleRowDragUpdate = (event: DraggableEvent<Record<string, any>>) => {
    emit('row-drag-update', buildRowDragPayload(event))
  }

  const handleRowDragEnd = (event: DraggableEvent<Record<string, any>>) => {
    emit('row-drag-end', buildRowDragPayload(event))
    rowKeysBeforeDrag.value = []
  }

  const rowDraggable = useDraggable<Record<string, any>>(sortableTargetRef, {
    immediate: false,
    handle: '.art-table__drag-handle:not(.is-disabled)',
    draggable: '.el-table__row',
    filter: '.art-table__drag-handle.is-disabled',
    preventOnFilter: false,
    animation: 150,
    ghostClass: 'art-table__drag-ghost',
    chosenClass: 'art-table__drag-chosen',
    onStart: handleRowDragStart,
    onUpdate: handleRowDragUpdate,
    onEnd: handleRowDragEnd
  })

  const syncRowDraggable = async () => {
    await nextTick()
    const tableElement = elTableRef.value?.$el as HTMLElement | undefined
    const target = tableElement?.querySelector<HTMLElement>('.el-table__body-wrapper tbody')

    if (target && sortableTargetRef.value !== target) {
      sortableTargetRef.value = target
      rowDraggable.start(target)
    }

    rowDraggable.option('disabled', !hasDraggableColumn.value || !!props.loading)
  }

  watch(
    () => [hasDraggableColumn.value, props.loading, props.data?.length],
    () => {
      void syncRowDraggable()
    },
    { immediate: true, flush: 'post' }
  )

  // 清理列属性，移除插槽相关的自定义属性，确保它们不会被 ElTableColumn 错误解释
  const cleanColumnProps = (col: ColumnOption) => {
    const columnProps = { ...col }
    const shouldDefaultOverflowTooltip =
      columnProps.showOverflowTooltip === undefined &&
      !['selection', 'expand', 'globalIndex'].includes(String(columnProps.type)) &&
      columnProps.prop !== 'operation'

    if (shouldDefaultOverflowTooltip) {
      columnProps.showOverflowTooltip = true
    }

    const shouldFormatEmptyValue =
      !columnProps.useSlot &&
      !columnProps.dict &&
      columnProps.prop &&
      !['selection', 'expand', 'globalIndex', 'index'].includes(String(columnProps.type))

    if (shouldFormatEmptyValue) {
      const userFormatter = columnProps.formatter
      columnProps.formatter = (row: Record<string, any>) => {
        const value = userFormatter
          ? userFormatter(row)
          : getCellValue(row, String(columnProps.prop))
        return formatEmptyCellValue(value)
      }
    }

    // 删除自定义的插槽控制属性
    delete columnProps.useHeaderSlot
    delete columnProps.headerSlotName
    delete columnProps.useSlot
    delete columnProps.slotName
    delete columnProps.draggable
    delete columnProps.dragDisabled
    delete columnProps.dragIcon
    delete columnProps.dict
    delete columnProps.children
    return columnProps
  }

  // 分页大小变化
  const handleSizeChange = (val: number) => {
    emit('pagination:size-change', val)
  }

  // 分页当前页变化
  const handleCurrentChange = (val: number) => {
    emit('pagination:current-change', val)
    scrollToTop() // 页码改变后滚动到表格顶部
  }

  const { scrollToTop: scrollPageToTop } = useCommon()

  // 滚动表格内容到顶部，并可以联动页面滚动到顶部
  const scrollToTop = () => {
    nextTick(() => {
      elTableRef.value?.setScrollTop(0) // 滚动 ElTable 内部滚动条到顶部
      scrollPageToTop() // 调用公共 composable 滚动页面到顶部
    })
  }

  // 全局序号
  const getGlobalIndex = (index: number) => {
    if (!currentPagination.value) return index + 1
    const { current, size } = currentPagination.value
    return (current - 1) * size + index + 1
  }

  const emit = defineEmits<{
    (e: 'pagination:size-change', val: number): void
    (e: 'pagination:current-change', val: number): void
    (e: 'row-drag-start', payload: RowDragPayload): void
    (e: 'row-drag-update', payload: RowDragPayload): void
    (e: 'row-drag-end', payload: RowDragPayload): void
  }>()

  // 查找并绑定当前表格所在卡片内的头部元素，避免多个表格共享全局 id 时算错高度。
  const findTableHeader = () => {
    if (!props.showTableHeader) {
      tableHeaderRef.value = undefined
      return
    }

    const tableElement = elTableRef.value?.$el as HTMLElement | undefined
    const tableBody = tableElement?.closest('.el-card__body')
    const tableHeader = tableBody?.querySelector<HTMLElement>('.art-table-header')

    if (tableHeader) {
      tableHeaderRef.value = tableHeader
    } else {
      tableHeaderRef.value = undefined
    }
  }

  watchEffect(
    () => {
      // 访问响应式数据以建立依赖追踪
      void props.data?.length // 追踪数据变化
      const shouldShow = props.showTableHeader

      // 只有在需要显示表格头部时才查找
      if (shouldShow) {
        nextTick(() => {
          findTableHeader()
        })
      } else {
        // 不显示时清空引用
        tableHeaderRef.value = undefined
      }
    },
    { flush: 'post' }
  )

  defineExpose({
    scrollToTop,
    elTableRef
  })
</script>

<style lang="scss" scoped>
  @use './style';
</style>
