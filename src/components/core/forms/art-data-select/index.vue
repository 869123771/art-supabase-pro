<template>
  <div class="art-data-select">
    <template v-if="!$slots.trigger">
      <ElInput
        v-if="!multiple"
        :model-value="singleDisplayLabel"
        :placeholder="placeholder"
        :disabled="disabled"
        readonly
        class="art-data-select__single-input"
        aria-haspopup="dialog"
        @click="open"
        @keydown.enter.prevent="open"
        @keydown.space.prevent="open"
      >
        <template #suffix>
          <button
            v-if="clearable && displayRows.length && !disabled"
            type="button"
            class="art-data-select__single-clear"
            aria-label="清空"
            @click.stop="clear"
          >
            <ElIcon>
              <CircleClose />
            </ElIcon>
          </button>
          <ElIcon v-else class="art-data-select__single-arrow">
            <ArrowDown />
          </ElIcon>
        </template>
      </ElInput>

      <ElInputTag
        v-else
        :model-value="multipleDisplayLabels"
        :max="displayRows.length"
        :placeholder="placeholder"
        :disabled="disabled"
        :clearable="clearable"
        collapse-tags
        :max-collapse-tags="maxTagCount"
        class="art-data-select__multiple-input"
        aria-haspopup="dialog"
        @click="open"
        @keydown.enter.prevent="open"
        @keydown.space.prevent="open"
        @remove-tag="handleRemoveDisplayTag"
        @clear="clear"
      >
        <template #suffix>
          <ElIcon class="art-data-select__multiple-arrow">
            <ArrowDown />
          </ElIcon>
        </template>
      </ElInputTag>
    </template>

    <slot
      v-else
      name="trigger"
      :open="open"
      :clear="clear"
      :selected-rows="displayRows"
      :selected-keys="confirmedKeys"
    />

    <ArtDialog
      ref="dialogRef"
      :subtitle="subtitle"
      :dialog-props="dialogProps"
      @opened="handleDialogOpened"
      @closed="handleDialogClosed"
    >
      <div class="art-data-select-dialog__body">
        <div
          v-if="showSearch"
          class="art-data-select-dialog__search"
          :class="{ 'has-filter': normalizedFilterOptions.length }"
        >
          <ElInput
            v-model="keyword"
            clearable
            :placeholder="searchPlaceholder"
            @keyup.enter="handleSearch"
            @clear="handleSearch"
          >
            <template #prefix>
              <ElIcon>
                <Search />
              </ElIcon>
            </template>
          </ElInput>
          <ElSelect
            v-if="normalizedFilterOptions.length"
            v-model="filterValue"
            clearable
            :placeholder="filterPlaceholder"
            @change="handleSearch"
            @clear="handleSearch"
          >
            <ElOption
              v-for="item in normalizedFilterOptions"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </ElSelect>
        </div>

        <div
          class="art-data-select-dialog__layout"
          :class="{ 'has-pagination': mode === 'table' && showPagination }"
        >
          <section class="art-data-select-dialog__main">
            <div
              class="art-data-select-dialog__content"
              :class="{ 'is-tree': mode === 'tree' }"
              v-loading="loading"
            >
              <ElTable
                v-if="mode === 'table'"
                ref="tableRef"
                :data="tableRows"
                :row-key="getTableRowKey"
                height="100%"
                :empty-text="emptyText"
                :row-class-name="getTableRowClassName"
                :highlight-current-row="!multiple"
                @row-click="handleTableRowClick"
                @selection-change="handleTableSelectionChange"
              >
                <ElTableColumn
                  v-if="multiple"
                  type="selection"
                  width="64"
                  align="center"
                  class-name="art-data-select-dialog__selection-cell"
                  :reserve-selection="reserveSelected"
                  :selectable="isRowSelectable"
                />
                <ElTableColumn
                  v-else
                  width="64"
                  align="center"
                  class-name="art-data-select-dialog__selection-cell"
                >
                  <template #default="{ row }">
                    <ElCheckbox
                      :model-value="isDraftSelected(row)"
                      :disabled="isRowDisabled(row)"
                      @click.stop
                      @change="() => setSingle(row)"
                    />
                  </template>
                </ElTableColumn>
                <ElTableColumn
                  v-for="column in normalizedColumns"
                  :key="column.prop"
                  :prop="column.prop"
                  :label="column.label"
                  :width="column.width"
                  :min-width="column.minWidth"
                  :align="column.align"
                  show-overflow-tooltip
                >
                  <template v-if="column.formatter || column.tagType" #default="{ row }">
                    <ElTag
                      v-if="column.tagType"
                      :type="getColumnTagType(column, row)"
                      size="small"
                      effect="light"
                    >
                      {{ getColumnValue(column, row) }}
                    </ElTag>
                    <template v-else>
                      <component
                        v-if="isComponentValue(column.formatter?.(row))"
                        :is="column.formatter?.(row)"
                      />
                      <span v-else>{{ column.formatter?.(row) }}</span>
                    </template>
                  </template>
                </ElTableColumn>
              </ElTable>

              <ElScrollbar v-else class="art-data-select-dialog__tree-scrollbar">
                <ElTree
                  ref="treeRef"
                  class="art-data-select-dialog__tree"
                  :data="tableRows"
                  :props="treeProps"
                  :node-key="treeNodeKey"
                  :show-checkbox="multiple"
                  :check-strictly="treeCheckStrictly"
                  :default-expand-all="true"
                  :expand-on-click-node="false"
                  :highlight-current="!multiple"
                  :empty-text="emptyText"
                  :filter-node-method="filterTreeNode"
                  @check="handleTreeCheck"
                  @node-click="handleTreeNodeClick"
                >
                  <template #default="{ data }">
                    <span
                      class="art-data-select-dialog__tree-node"
                      :class="{ 'is-disabled': isRowDisabled(data) }"
                    >
                      <span class="art-data-select-dialog__tree-label">{{
                        getRowLabel(data)
                      }}</span>
                      <ArtSvgIcon
                        v-if="!multiple && isDraftSelected(data)"
                        icon="ri:check-line"
                        class="art-data-select-dialog__tree-check"
                      />
                    </span>
                  </template>
                </ElTree>
              </ElScrollbar>
            </div>

            <div v-if="mode === 'table' && showPagination" class="art-data-select-dialog__pager">
              <span>共 {{ total }} 条</span>
              <ElPagination
                v-model:current-page="page"
                v-model:page-size="innerPageSize"
                background
                layout="prev, pager, next, sizes"
                :page-sizes="pageSizes"
                :total="total"
                @change="loadData"
              />
            </div>
          </section>

          <aside v-if="shouldShowSelectedPanel" class="art-data-select-dialog__selected">
            <div class="art-data-select-dialog__selected-header">
              <span>已选 {{ draftRows.length }}</span>
              <ElButton text type="primary" :disabled="!draftRows.length" @click="clearDraft">
                清空
              </ElButton>
            </div>
            <ElScrollbar class="art-data-select-dialog__selected-scrollbar">
              <ElEmpty v-if="!draftRows.length" description="暂无数据" :image-size="72" />
              <div
                v-for="row in draftRows"
                :key="getRowKey(row)"
                class="art-data-select-dialog__selected-item"
              >
                <div v-if="mode === 'table'" class="art-data-select-dialog__selected-icon">
                  <ArtSvgIcon icon="ri:building-4-line" />
                </div>
                <div class="art-data-select-dialog__selected-text">
                  <strong>{{ getRowLabel(row) }}</strong>
                  <span v-if="getRowDescription(row)">{{ getRowDescription(row) }}</span>
                </div>
                <ElButton
                  text
                  class="art-data-select-dialog__selected-remove"
                  @click="removeDraft(row)"
                >
                  <ArtSvgIcon icon="ri:close-line" />
                </ElButton>
              </div>
            </ElScrollbar>
          </aside>
        </div>
      </div>

      <template #footer-left>{{ selectionSummary }}</template>
    </ArtDialog>
  </div>
</template>

<script setup lang="ts">
  import { isEqual } from 'lodash-es'
  import type { Component } from 'vue'
  import type { ElTable, ElTree } from 'element-plus'
  import { ArrowDown, CircleClose, Search } from '@element-plus/icons-vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type {
    ArtDataSelectEmits,
    ArtDataSelectExpose,
    ArtDataSelectProps,
    DataSelectColumn,
    DataSelectKey,
    DataSelectModelValue,
    DataSelectRecord
  } from './types'

  defineOptions({ name: 'ArtDataSelect' })

  const props = withDefaults(defineProps<ArtDataSelectProps>(), {
    mode: 'table',
    multiple: false,
    data: () => [],
    selectedData: () => [],
    columns: () => [],
    title: '选择数据',
    subtitle: '',
    placeholder: '请选择',
    searchPlaceholder: '请输入关键词',
    filterPlaceholder: '请选择分类',
    filterKey: 'type',
    filterOptions: () => [],
    rowKey: 'id',
    labelKey: 'label',
    descriptionKey: undefined,
    disabledKey: 'disabled',
    childrenKey: 'children',
    resultField: 'data',
    totalField: 'total',
    dialogWidth: '1180px',
    fullscreen: false,
    pageSize: 10,
    pageSizes: () => [10, 20, 30, 50],
    showPagination: true,
    showSearch: true,
    showSelectedPanel: undefined,
    clearable: true,
    disabled: false,
    reserveSelected: true,
    treeCheckStrictly: true,
    maxTagCount: 2,
    emptyText: '暂无数据'
  })

  const emit = defineEmits<ArtDataSelectEmits>()

  const tableRef = ref<InstanceType<typeof ElTable>>()
  const treeRef = ref<InstanceType<typeof ElTree>>()
  const dialogRef = ref<ArtDialogExpose<void>>()
  const loading = ref(false)
  const keyword = ref('')
  const filterValue = ref<string | number>()
  const page = ref(1)
  const innerPageSize = ref(props.pageSize)
  const total = ref(0)
  const tableRows = ref<DataSelectRecord[]>([])
  const confirmedRows = ref<DataSelectRecord[]>([])
  const draftRows = ref<DataSelectRecord[]>([])
  const syncingSelection = ref(false)

  const dialogProps = {
    appendToBody: true,
    closeOnClickModal: false
  }

  const confirmedKeys = computed(() => confirmedRows.value.map((row) => getRowKey(row)))
  const draftKeys = computed(() => draftRows.value.map((row) => getRowKey(row)))
  const currentSingleKey = computed(() => draftRows.value[0] && getRowKey(draftRows.value[0]))
  const displayRows = computed(() => confirmedRows.value)
  const singleDisplayLabel = computed(() =>
    displayRows.value[0] ? getRowLabel(displayRows.value[0]) : ''
  )
  const multipleDisplayLabels = computed(() => displayRows.value.map((row) => getRowLabel(row)))
  const normalizedFilterOptions = computed(() => props.filterOptions ?? [])
  const normalizedFilterKey = computed(() => props.filterKey ?? 'type')
  const shouldShowSelectedPanel = computed(() => props.showSelectedPanel ?? props.multiple)
  const selectionSummary = computed(() => {
    if (props.multiple) return `当前已选择 ${draftRows.value.length} 项`
    return `当前选择：${draftRows.value[0] ? getRowLabel(draftRows.value[0]) : '暂无'}`
  })
  const treeNodeKey = computed(() => (typeof props.rowKey === 'string' ? props.rowKey : '__artKey'))
  const treeProps = computed(() => ({
    label: (data: DataSelectRecord) => getRowLabel(data),
    children: props.childrenKey,
    disabled: (data: DataSelectRecord) => isRowDisabled(data)
  }))

  const normalizedColumns = computed<DataSelectColumn[]>(() => {
    if (props.columns.length) return props.columns
    return [
      {
        prop: typeof props.labelKey === 'string' ? props.labelKey : 'label',
        label: '名称',
        minWidth: 180
      }
    ]
  })

  const isComponentValue = (value: unknown): value is Component => {
    return typeof value === 'object' || typeof value === 'function'
  }

  const getColumnValue = (column: DataSelectColumn, row: DataSelectRecord) => {
    return column.formatter?.(row) ?? getValueByPath(row, column.prop) ?? ''
  }

  const getColumnTagType = (column: DataSelectColumn, row: DataSelectRecord) => {
    return typeof column.tagType === 'function' ? column.tagType(row) : column.tagType
  }

  const getValueByPath = (source: unknown, path?: string): unknown => {
    if (!path) return source
    return path.split('.').reduce<unknown>((value, key) => {
      if (value == null || typeof value !== 'object') return undefined
      return (value as Record<string, unknown>)[key]
    }, source)
  }

  const getRowKey = (row: DataSelectRecord): DataSelectKey => {
    if (typeof props.rowKey === 'function') return props.rowKey(row)
    return getValueByPath(row, props.rowKey) as DataSelectKey
  }

  const getTableRowKey = (row: DataSelectRecord): string => String(getRowKey(row))

  const getRowLabel = (row: DataSelectRecord): string => {
    if (typeof props.labelKey === 'function') return props.labelKey(row)
    return String(getValueByPath(row, props.labelKey) ?? '')
  }

  const getRowDescription = (row: DataSelectRecord): string => {
    if (!props.descriptionKey) return ''
    if (typeof props.descriptionKey === 'function') return props.descriptionKey(row)
    return String(getValueByPath(row, props.descriptionKey) ?? '')
  }

  const isRowDisabled = (row: DataSelectRecord): boolean => {
    if (typeof props.disabledKey === 'function') return props.disabledKey(row)
    if (!props.disabledKey) return false
    return !!getValueByPath(row, props.disabledKey)
  }

  const isRowSelectable = (row: DataSelectRecord) => !isRowDisabled(row)
  const isDraftSelected = (row: DataSelectRecord) => draftKeys.value.includes(getRowKey(row))

  const getTableRowClassName = ({ row }: { row: DataSelectRecord }) => {
    return !props.multiple && isDraftSelected(row) ? 'is-selected-row' : ''
  }

  const flattenRows = (rows: DataSelectRecord[]): DataSelectRecord[] => {
    const result: DataSelectRecord[] = []
    const walk = (items: DataSelectRecord[]) => {
      items.forEach((item) => {
        result.push(item)
        const children = item[props.childrenKey]
        if (Array.isArray(children)) walk(children)
      })
    }
    walk(rows)
    return result
  }

  const uniqueRows = (rows: DataSelectRecord[]): DataSelectRecord[] => {
    const map = new Map<DataSelectKey, DataSelectRecord>()
    rows.forEach((row) => {
      const key = getRowKey(row)
      if (key !== undefined && key !== null && !map.has(key)) {
        map.set(key, row)
      }
    })
    return Array.from(map.values())
  }

  const normalizeModelKeys = (value: DataSelectModelValue): DataSelectKey[] => {
    if (Array.isArray(value)) return value
    return value === undefined || value === null || value === '' ? [] : [value]
  }

  const getModelValueFromRows = (rows: DataSelectRecord[]): DataSelectModelValue => {
    const keys = rows.map((row) => getRowKey(row))
    return props.multiple ? keys : keys[0]
  }

  const findRowsByKeys = (keys: DataSelectKey[], rows: DataSelectRecord[]) => {
    const rowMap = new Map<DataSelectKey, DataSelectRecord>()
    flattenRows(rows).forEach((row) => rowMap.set(getRowKey(row), row))
    return keys.map((key) => rowMap.get(key) ?? createFallbackRow(key))
  }

  const createFallbackRow = (key: DataSelectKey): DataSelectRecord => {
    if (typeof props.rowKey === 'string' && typeof props.labelKey === 'string') {
      return {
        [props.rowKey]: key,
        [props.labelKey]: String(key)
      }
    }
    return { id: key, label: String(key) }
  }

  const normalizeTreeRows = (rows: DataSelectRecord[]): DataSelectRecord[] => {
    return rows.map((row) => {
      const children = row[props.childrenKey]
      return {
        ...row,
        [treeNodeKey.value]: getRowKey(row),
        [props.childrenKey]: Array.isArray(children) ? normalizeTreeRows(children) : children
      }
    })
  }

  const syncConfirmedFromProps = () => {
    const keys = normalizeModelKeys(props.modelValue)
    const sourceRows = [
      ...props.selectedData,
      ...flattenRows(props.data),
      ...flattenRows(tableRows.value)
    ]
    confirmedRows.value = uniqueRows([
      ...findRowsByKeys(keys, sourceRows),
      ...props.selectedData
    ]).filter((row) => keys.includes(getRowKey(row)))
  }

  const applyDraftToControls = async () => {
    await nextTick()
    syncingSelection.value = true
    try {
      if (props.mode === 'table') {
        tableRef.value?.clearSelection?.()
        if (props.multiple) {
          tableRows.value.forEach((row) => {
            if (draftKeys.value.includes(getRowKey(row))) {
              tableRef.value?.toggleRowSelection?.(row, true)
            }
          })
        } else if (draftRows.value[0]) {
          tableRef.value?.setCurrentRow?.(draftRows.value[0])
        } else {
          tableRef.value?.setCurrentRow?.(null as never)
        }
        await nextTick()
        return
      }

      if (props.multiple) {
        treeRef.value?.setCheckedKeys?.(draftKeys.value as never[], false)
      } else {
        treeRef.value?.setCurrentKey?.(currentSingleKey.value as never)
      }
      await nextTick()
    } finally {
      syncingSelection.value = false
    }
  }

  const extractListFromResult = (result: unknown): DataSelectRecord[] => {
    if (Array.isArray(result)) return result
    const fieldValue = getValueByPath(result, props.resultField)
    if (Array.isArray(fieldValue)) return fieldValue
    if (result && typeof result === 'object') {
      const record = result as Record<string, unknown>
      if (Array.isArray(record.list)) return record.list as DataSelectRecord[]
      if (Array.isArray(record.records)) return record.records as DataSelectRecord[]
    }
    return []
  }

  const extractTotalFromResult = (result: unknown, list: DataSelectRecord[]): number => {
    const totalValue = getValueByPath(result, props.totalField)
    if (typeof totalValue === 'number') return totalValue
    if (result && typeof result === 'object') {
      const record = result as Record<string, unknown>
      if (typeof record.total === 'number') return record.total
      if (typeof record.count === 'number') return record.count
    }
    return list.length
  }

  const localFilterRows = () => {
    const allRows = props.data
    if (props.mode === 'tree') {
      tableRows.value = normalizeTreeRows(allRows)
      total.value = flattenRows(allRows).length
      return
    }

    const query = keyword.value.trim().toLowerCase()
    const filteredRows = flattenRows(allRows).filter((row) => {
      const matchesKeyword =
        !query ||
        normalizedColumns.value.some((column) =>
          String(getValueByPath(row, column.prop) ?? '')
            .toLowerCase()
            .includes(query)
        ) ||
        getRowLabel(row).toLowerCase().includes(query)
      const matchesFilter =
        filterValue.value === undefined ||
        filterValue.value === '' ||
        getValueByPath(row, normalizedFilterKey.value) === filterValue.value
      return matchesKeyword && matchesFilter
    })
    total.value = filteredRows.length
    const start = (page.value - 1) * innerPageSize.value
    tableRows.value = props.showPagination
      ? filteredRows.slice(start, start + innerPageSize.value)
      : filteredRows
  }

  const loadData = async () => {
    loading.value = true
    try {
      if (props.apiFn) {
        const result = await props.apiFn({
          keyword: keyword.value,
          page: page.value,
          pageSize: innerPageSize.value,
          filters: {
            [normalizedFilterKey.value]: filterValue.value
          }
        })
        const list = extractListFromResult(result)
        tableRows.value = props.mode === 'tree' ? normalizeTreeRows(list) : list
        total.value = extractTotalFromResult(result, list)
      } else {
        localFilterRows()
      }
      syncConfirmedFromProps()
      await applyDraftToControls()
      if (props.mode === 'tree') {
        treeRef.value?.filter?.(keyword.value)
      }
    } finally {
      loading.value = false
    }
  }

  const handleSearch = () => {
    page.value = 1
    void loadData()
  }

  const open = async () => {
    if (props.disabled) return
    draftRows.value = confirmedRows.value.map((row) => ({ ...row }))
    emit('open')
    await dialogRef.value?.handleOpen(undefined, {
      title: props.title,
      width: props.dialogWidth,
      fullscreen: props.fullscreen,
      showFooter: true,
      dialogProps,
      onOpen: loadData,
      onConfirm: confirm
    })
  }

  const close = () => {
    void dialogRef.value?.handleClose(true)
  }

  const reload = async () => {
    await loadData()
  }

  const handleDialogOpened = () => {
    void applyDraftToControls()
  }

  const handleDialogClosed = () => {
    keyword.value = ''
    filterValue.value = undefined
    page.value = 1
    emit('close')
  }

  const updateConfirmed = (
    rows: DataSelectRecord[],
    eventName: 'change' | 'confirm' = 'change'
  ) => {
    confirmedRows.value = uniqueRows(rows)
    const nextValue = getModelValueFromRows(confirmedRows.value)
    emit('update:modelValue', nextValue)
    emit('update:selectedData', confirmedRows.value)
    emit('change', nextValue, confirmedRows.value)
    if (eventName === 'confirm') {
      emit('confirm', nextValue, confirmedRows.value)
    }
  }

  const confirm = () => {
    updateConfirmed(draftRows.value, 'confirm')
    return true
  }

  const clear = () => {
    updateConfirmed([])
    draftRows.value = []
    emit('clear')
  }

  const clearDraft = () => {
    draftRows.value = []
    void applyDraftToControls()
  }

  const removeDraft = (row: DataSelectRecord) => {
    const key = getRowKey(row)
    draftRows.value = draftRows.value.filter((item) => getRowKey(item) !== key)
    void applyDraftToControls()
  }

  const removeConfirmed = (row: DataSelectRecord) => {
    const key = getRowKey(row)
    updateConfirmed(confirmedRows.value.filter((item) => getRowKey(item) !== key))
  }

  const handleRemoveDisplayTag = (_value: string, index: number) => {
    const row = displayRows.value[index]
    if (row) removeConfirmed(row)
  }

  const setSingle = (row: DataSelectRecord) => {
    if (isRowDisabled(row)) return
    draftRows.value = [row]
    void applyDraftToControls()
  }

  const toggleDraftRow = (row: DataSelectRecord) => {
    if (isRowDisabled(row)) return
    const key = getRowKey(row)
    if (props.multiple) {
      if (draftKeys.value.includes(key)) {
        draftRows.value = draftRows.value.filter((item) => getRowKey(item) !== key)
      } else {
        draftRows.value = uniqueRows([...draftRows.value, row])
      }
      void applyDraftToControls()
      return
    }
    setSingle(row)
  }

  const handleTableRowClick = (row: DataSelectRecord, _column: unknown, event: MouseEvent) => {
    if ((event.target as HTMLElement | null)?.closest('.el-checkbox')) return
    toggleDraftRow(row)
  }

  const handleTableSelectionChange = (rows: DataSelectRecord[]) => {
    if (!props.multiple || syncingSelection.value) return
    const pageKeys = tableRows.value.map((row) => getRowKey(row))
    const persistedRows = draftRows.value.filter((row) => !pageKeys.includes(getRowKey(row)))
    draftRows.value = uniqueRows([...persistedRows, ...rows])
  }

  const handleTreeCheck = () => {
    if (!props.multiple || syncingSelection.value) return
    const checkedRows = (treeRef.value?.getCheckedNodes?.(false, false) ?? []) as DataSelectRecord[]
    draftRows.value = uniqueRows(checkedRows)
  }

  const handleTreeNodeClick = (row: DataSelectRecord) => {
    if (props.multiple) return
    setSingle(row)
  }

  const filterTreeNode = (value: string, data: DataSelectRecord) => {
    if (!value) return true
    const normalizedValue = value.toLowerCase()
    return (
      getRowLabel(data).toLowerCase().includes(normalizedValue) ||
      getRowDescription(data).toLowerCase().includes(normalizedValue)
    )
  }

  watch(
    () => [props.modelValue, props.selectedData, props.data],
    () => {
      syncConfirmedFromProps()
    },
    { deep: true, immediate: true }
  )

  watch(
    () => props.pageSize,
    (value) => {
      innerPageSize.value = value
    }
  )

  watch(
    () => keyword.value,
    (value) => {
      if (props.mode === 'tree') {
        treeRef.value?.filter?.(value)
      }
    }
  )

  watch(
    () => confirmedRows.value,
    (rows) => {
      const nextValue = getModelValueFromRows(rows)
      if (!isEqual(nextValue, props.modelValue)) {
        emit('update:modelValue', nextValue)
      }
    },
    { deep: true }
  )

  defineExpose<ArtDataSelectExpose>({
    open,
    close,
    clear,
    reload
  })
</script>

<style scoped lang="scss">
  .art-data-select {
    width: 100%;
  }

  .art-data-select__single-input {
    cursor: pointer;

    :deep(.el-input__wrapper),
    :deep(.el-input__inner) {
      cursor: pointer;
    }
  }

  .art-data-select__single-clear {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    color: var(--el-text-color-placeholder);
    cursor: pointer;
    background: transparent;
    border: 0;
  }

  .art-data-select__single-arrow {
    color: var(--el-text-color-placeholder);
  }

  .art-data-select__multiple-input {
    cursor: pointer;

    :deep(.el-input-tag__wrapper),
    :deep(.el-input-tag__inner),
    :deep(.el-input-tag__input) {
      cursor: pointer;
    }
  }

  .art-data-select__multiple-arrow {
    color: var(--el-text-color-placeholder);
  }

  .art-data-select-dialog__search {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 16px;
    margin-bottom: 16px;

    &.has-filter {
      grid-template-columns: minmax(220px, 1fr) 260px;
    }

    :deep(.el-input__wrapper),
    :deep(.el-select__wrapper) {
      min-height: 36px;
      box-shadow: 0 0 0 1px #dfe5f0 inset;
    }
  }

  .art-data-select-dialog__layout {
    --art-data-select-dialog-panel-height: 438px;

    display: flex;
    gap: 20px;
    align-items: flex-start;
    min-height: 0;

    &.has-pagination {
      --art-data-select-dialog-panel-height: 500px;
    }
  }

  .art-data-select-dialog__main {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-width: 0;
    border: 1px solid #dfe5f0;
    border-radius: 4px;
  }

  .art-data-select-dialog__content {
    height: 438px;
    min-height: 0;

    &.is-tree {
      padding: 18px 12px 18px 24px;
    }

    :deep(.el-table) {
      --el-table-header-bg-color: #f8fafc;
      --el-table-header-text-color: #626883;
      --el-table-text-color: #3d425f;
      --el-table-row-hover-bg-color: #f0f0f3;
      --el-table-current-row-bg-color: #f0f0f3;

      font-size: 15px;
    }

    :deep(.el-table th.el-table__cell) {
      height: 54px;
      font-size: 15px;
      font-weight: 600;
    }

    :deep(.el-table td.el-table__cell) {
      height: 56px;
    }

    :deep(.el-table__row.is-selected-row td.el-table__cell) {
      background: #f0f0f3;
    }

    :deep(.el-table__row:hover > td.el-table__cell) {
      background: #f0f0f3;
    }

    :deep(.art-data-select-dialog__selection-cell .cell) {
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 0;
    }

    :deep(.art-data-select-dialog__selection-cell .el-checkbox) {
      height: auto;
      margin: 0;
    }
  }

  .art-data-select-dialog__tree-scrollbar {
    height: 100%;
  }

  .art-data-select-dialog__tree {
    color: #3d425f;

    --el-tree-node-hover-bg-color: transparent;

    :deep(.el-tree-node__content) {
      height: 44px;
      padding-right: 12px;
      margin: 4px 0;
      border-radius: 4px;
    }

    :deep(.el-tree-node__content:hover),
    :deep(.el-tree-node.is-current > .el-tree-node__content) {
      background: #f0f0f3;
    }

    :deep(.el-checkbox) {
      height: auto;
      margin-right: 10px;
    }
  }

  .art-data-select-dialog__tree-node {
    display: flex;
    flex: 1;
    gap: 8px;
    align-items: center;
    min-width: 0;
    font-size: 16px;
    line-height: 24px;

    &.is-disabled {
      color: var(--el-disabled-text-color);
      cursor: not-allowed;
    }
  }

  .art-data-select-dialog__tree-label {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .art-data-select-dialog__tree-check {
    flex: none;
    margin-left: auto;
    font-size: 20px;
    color: #7d8299;
  }

  .art-data-select-dialog__pager {
    display: flex;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    min-height: 62px;
    padding: 10px 24px;
    color: #7d8299;
    border-top: 1px solid #dfe5f0;
  }

  .art-data-select-dialog__selected {
    display: flex;
    flex: none;
    flex-direction: column;
    width: 300px;
    height: var(--art-data-select-dialog-panel-height);
    min-height: 0;
    max-height: var(--art-data-select-dialog-panel-height);
    overflow: hidden;
    border: 1px solid #dfe5f0;
    border-radius: 4px;
  }

  .art-data-select-dialog__selected-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 54px;
    padding: 0 18px 0 24px;
    font-size: 16px;
    font-weight: 600;
    color: #26294a;
    background: #f8fafc;
    border-bottom: 1px solid #dfe5f0;
  }

  .art-data-select-dialog__selected-scrollbar {
    flex: 1;
    height: 0;
    min-height: 0;

    :deep(.el-scrollbar__view) {
      min-height: 100%;
    }
  }

  .art-data-select-dialog__selected-item {
    display: flex;
    gap: 12px;
    align-items: center;
    min-height: 62px;
    padding: 12px 16px 12px 24px;
    border-bottom: 1px solid #eef1f6;
    transition: background-color 0.2s ease;

    &:hover {
      background: #f0f0f3;
    }
  }

  .art-data-select-dialog__selected-icon {
    display: inline-flex;
    flex: none;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    font-size: 20px;
    color: var(--el-color-primary);
    background: var(--el-color-primary-light-9);
    border-radius: 4px;
  }

  .art-data-select-dialog__selected-text {
    flex: 1;
    min-width: 0;

    strong,
    span {
      display: block;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      font-size: 15px;
      font-weight: 600;
      line-height: 22px;
      color: #30344f;
    }

    span {
      margin-top: 4px;
      font-size: 13px;
      line-height: 18px;
      color: #9aa0b5;
    }
  }

  .art-data-select-dialog__selected-remove {
    flex: none;
    width: 32px;
    height: 32px !important;
    padding: 0;
    font-size: 18px;
    color: #7d8299;
    border-radius: 4px;

    &:hover,
    &:focus-visible {
      color: #7d8299;
      background: var(--el-fill-color-light);
    }
  }

  @media (width <= 768px) {
    .art-data-select-dialog__search {
      &.has-filter {
        grid-template-columns: 1fr;
      }
    }

    .art-data-select-dialog__layout {
      flex-direction: column;
    }

    .art-data-select-dialog__content {
      height: 52vh;
    }

    .art-data-select-dialog__selected {
      width: auto;
      height: auto;
      max-height: 240px;
    }
  }
</style>
