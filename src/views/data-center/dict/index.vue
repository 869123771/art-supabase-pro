<template>
  <div class="art-full-height business-workspace-page">
    <MasterDeleteProcessingNotice
      action-hint="字典类型和关联字典项已自动定位；处理完成后可返回继续删除。"
    />
    <div class="dict-layout business-workspace-content">
      <ElSplitter class="dict-splitter">
        <ElSplitterPanel size="316px" min="288px" max="380px">
          <div class="dict-tree-panel">
            <TypeTree :target-node-id="deleteTargetTypeId" @tree-node-click="handleTreeNodeClick" />
          </div>
        </ElSplitterPanel>

        <ElSplitterPanel>
          <div class="dict-table-panel">
            <div v-if="isDictionarySelected" class="dict-selection-context art-card-xs">
              <div class="dict-selection-context__icon" aria-hidden="true">
                <ArtSvgIcon icon="ri:book-2-line" />
              </div>
              <div class="dict-selection-context__copy">
                <div class="dict-selection-context__heading">
                  <strong>{{ table.currentDictType?.name }}</strong>
                  <span>{{ table.currentDictType?.code }}</span>
                </div>
                <p>
                  {{
                    table.currentDictType?.remark || '维护该类型下的字典项、层级关系与展示样式。'
                  }}
                </p>
              </div>
            </div>

            <ArtTableQuery
              v-if="isDictionarySelected"
              ref="tableQueryRef"
              v-model="table.searchQuery"
              :search-items="table.searchItems"
              :api-fn="fetchTableData"
              :data-transformer="transformDictTree"
              :columns-factory="table.columnsFactory"
              :header-actions="table.headerActions"
              :immediate="false"
              :search-bar-props="table.searchBarProps"
              :table-props="table.props"
            />

            <div v-else class="dict-selection-empty art-card-xs">
              <ArtEmptyState
                :title="selectionEmptyTitle"
                :description="selectionEmptyDescription"
                :visual-size="104"
              />
            </div>
          </div>
        </ElSplitterPanel>
      </ElSplitter>
    </div>

    <DictDialog ref="dictDialogRef" @success="handleSaveSuccess" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import { ColumnOption } from '@/types'
  import TreeUtils from '@/utils/tree'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteDict,
    deleteDictBatch,
    fetchDictTypeIdByDictionaryId,
    fetchGetDictListByTypeId
  } from '@/api/data-center'
  import TypeTree from './modules/type-tree.vue'
  import DictDialog from './modules/dict-dialog.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'Dict' })

  const { confirmAction } = useArtFeedback()
  const route = useRoute()
  type DictListItem = Api.DataCenter.DictListItem
  type SearchParams = Partial<Pick<DictListItem, 'label' | 'code' | 'i18nScope' | 'status'>>
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type DictDialogOpenData = Partial<DictListItem> & { dictTypeName?: string }
  type DictTypeItem = Api.DataCenter.DictTypeItem

  interface DictDialogExpose {
    handleOpen: (data?: DictDialogOpenData) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  interface TableGroup {
    searchQuery: SearchParams
    currentDictType?: DictTypeItem
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<DictListItem>[]
    searchBarProps: {
      span: number
      labelWidth: number
    }
    props: {
      rowKey: string
      tableLayout: 'fixed'
      defaultExpandAll: boolean
      treeProps: {
        children: string
      }
      emptyText: string
      emptyDescription: string
    }
  }

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dictDialogRef = ref<DictDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const dictTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })
  const deleteTargetTypeId = ref('')

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      label: '',
      code: '',
      i18nScope: '',
      status: ''
    } as SearchParams,
    currentDictType: undefined as DictTypeItem | undefined,
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '字典标签',
        key: 'label',
        type: 'input',
        props: { placeholder: '请输入字典标签' }
      },
      {
        label: '字典编码',
        key: 'code',
        type: 'input',
        props: { placeholder: '请输入字典编码' }
      },
      {
        label: '国际化范围',
        key: 'i18nScope',
        type: 'select',
        props: {
          placeholder: '请选择国际化范围',
          options: getDictMap.value?.i18nScope ?? []
        }
      },
      {
        label: '状态',
        key: 'status',
        type: 'select',
        props: {
          placeholder: '请选择状态',
          options: getDictMap.value?.status ?? []
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        disabled: (): boolean => table.currentDictType?.nodeType !== 'dictionary',
        onClick: () => handleAdd()
      },
      {
        type: 'delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定要删除选中的 ${selectedCount} 个字典项吗？`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows
            .map((row) => row.id)
            .filter((id): id is string => typeof id === 'string')
          const blocked = await deleteGuardRef.value?.inspect({
            resourceType: 'dictionary',
            resourceLabel: '字典项',
            resources: (selectedRows as DictListItem[])
              .filter((row) => Boolean(row.id))
              .map((row) => ({ id: String(row.id), label: row.label || row.name || row.code }))
          })
          if (blocked) return
          await deleteDictBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: (): ColumnOption<DictListItem>[] => [
      {
        type: 'selection',
        width: 50,
        fixed: 'left',
        reserveSelection: true
      },
      {
        prop: 'identity',
        label: '字典项',
        minWidth: 220,
        formatter: (row) => (
          <div class="dict-identity-cell">
            <strong title={row.label || row.name}>{row.label || row.name || '--'}</strong>
            <span title={row.code}>{row.code || '未设置编码'}</span>
          </div>
        )
      },
      {
        prop: 'value',
        label: '字典值',
        minWidth: 140,
        showOverflowTooltip: true
      },
      {
        prop: 'status',
        label: '状态',
        width: 90,
        dict: { code: 'status', display: 'auto' }
      },
      {
        prop: 'appearance',
        label: '呈现方式',
        minWidth: 170,
        formatter: (row) => (
          <div class="dict-appearance-cell">
            {row.color ? <ArtDictDisplay item={row} display="badge" /> : null}
            {row.tagType ? <ArtDictDisplay item={row} display="tag" /> : null}
            {!row.color && !row.tagType ? (
              <span class="dict-cell-placeholder">默认文本</span>
            ) : null}
          </div>
        )
      },
      {
        prop: 'sort',
        label: '排序',
        width: 72,
        align: 'center'
      },
      {
        prop: 'operation',
        label: '操作',
        width: 104,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="edit" onClick={() => handleEdit(row)} />
            <ArtButtonMore
              list={getRowMoreActions()}
              onClick={(item: ButtonMoreItem) => handleRowMoreAction(item, row)}
            />
          </div>
        )
      }
    ],
    searchBarProps: {
      span: 8,
      labelWidth: 100
    },
    props: {
      rowKey: 'id',
      tableLayout: 'fixed' as const,
      defaultExpandAll: true,
      treeProps: {
        children: 'children'
      },
      emptyText: '该类型下暂无字典项',
      emptyDescription: '可新增首个字典项，或调整筛选条件后重新查询。'
    }
  })

  const isDictionarySelected = computed(
    () => table.currentDictType?.nodeType === 'dictionary' && Boolean(table.currentDictType.id)
  )
  const selectionEmptyTitle = computed(() =>
    table.currentDictType?.nodeType === 'directory' ? '请选择具体的字典类型' : '先选择一个字典类型'
  )
  const selectionEmptyDescription = computed(() =>
    table.currentDictType?.nodeType === 'directory'
      ? `「${table.currentDictType.name}」是目录，请从其下级选择需要维护的字典类型。`
      : '从左侧目录中选择字典类型后，可查看并维护对应字典项。'
  )

  const fetchTableData = (params: TableParams) => {
    if (table.currentDictType?.nodeType !== 'dictionary' || !table.currentDictType.id) {
      return Promise.resolve({
        records: [],
        total: 0,
        current: params.current,
        size: params.size
      })
    }

    return fetchGetDictListByTypeId({
      typeId: table.currentDictType.id,
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : undefined,
      ...params
    })
  }

  const transformDictTree = (records: unknown[]): DictListItem[] =>
    dictTreeUtils.listToTree(
      records as DictListItem[],
      (a, b) => Number(a.sort || 0) - Number(b.sort || 0)
    ) as DictListItem[]

  const handleTreeNodeClick = async (node: DictTypeItem): Promise<void> => {
    table.currentDictType = node
    if (node.nodeType !== 'dictionary') return

    await nextTick()
    await tableQueryRef.value?.getData()
  }

  const handleAdd = (parent?: DictListItem): void => {
    if (table.currentDictType?.nodeType !== 'dictionary' || !table.currentDictType.id) {
      ElMessage.warning('请选择字典类型')
      return
    }

    void dictDialogRef.value?.handleOpen({
      typeId: table.currentDictType.id,
      parentId: parent?.id,
      dictTypeName: table.currentDictType.name
    })
  }

  const handleEdit = (row: DictListItem): void => {
    void dictDialogRef.value?.handleOpen({
      ...row,
      dictTypeName: table.currentDictType?.name
    })
  }

  const getRowMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'add',
      label: '新增下级',
      icon: 'ri:add-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-line',
      color: 'var(--el-color-danger)'
    }
  ]

  const handleRowMoreAction = (item: ButtonMoreItem, row: DictListItem): void => {
    if (item.key === 'add') {
      handleAdd(row)
      return
    }

    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleDelete = async (row: DictListItem): Promise<void> => {
    try {
      if (!row.id) return
      const blocked = await deleteGuardRef.value?.inspect({
        resourceType: 'dictionary',
        resourceLabel: '字典项',
        resources: [{ id: row.id, label: row.label || row.name || row.code }]
      })
      if (blocked) return

      await confirmAction('确定要删除该字典项吗？', '删除字典项', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteDict(row)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }

  const handleSaveSuccess = (): void => {
    void tableQueryRef.value?.refreshData()
  }

  const syncDeleteRouteTarget = async (): Promise<void> => {
    const dependencyCode = String(route.query.dependencyCode || '')
    const recordId = String(route.query.recordId || '')
    if (dependencyCode === 'dict_type_child') {
      deleteTargetTypeId.value = recordId
      return
    }
    if (typeof route.query.dictTypeId === 'string') {
      deleteTargetTypeId.value = route.query.dictTypeId
      return
    }
    deleteTargetTypeId.value = recordId ? (await fetchDictTypeIdByDictionaryId(recordId)) || '' : ''
  }

  watch(
    () => route.fullPath,
    async () => {
      await syncDeleteRouteTarget()
      if (table.currentDictType?.id) await tableQueryRef.value?.getData()
    },
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .dict-layout {
    width: 100%;
    height: 100%;
    min-height: 0;

    .dict-tree-panel,
    .dict-table-panel {
      display: flex;
      flex-direction: column;
      min-width: 0;
      height: 100%;
      min-height: 0;
    }

    .dict-tree-panel {
      padding-right: 8px;
    }

    .dict-table-panel {
      padding-left: 8px;

      :deep(.pagination) {
        display: none;
      }
    }

    .dict-selection-context {
      position: relative;
      display: flex;
      flex: none;
      gap: 12px;
      min-width: 0;
      padding: 14px 16px;
      margin-bottom: 12px;
      overflow: hidden;

      &::before {
        position: absolute;
        inset: 0;
        pointer-events: none;
        content: '';
        background: linear-gradient(110deg, var(--el-color-primary-light-9), transparent 60%);
      }

      > * {
        position: relative;
      }

      &__icon {
        display: grid;
        flex: 0 0 38px;
        place-items: center;
        width: 38px;
        height: 38px;
        font-size: 18px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border: 1px solid var(--el-color-primary-light-7);
        border-radius: var(--art-control-radius);
      }

      &__copy {
        min-width: 0;

        p {
          margin: 4px 0 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 12px;
          line-height: 1.5;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }
      }

      &__heading {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 15px;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }

        span {
          flex: none;
          padding: 2px 7px;
          font-size: 11px;
          line-height: 18px;
          color: var(--el-text-color-secondary);
          background: var(--el-fill-color-light);
          border: 1px solid var(--el-border-color-lighter);
          border-radius: 999px;
        }
      }
    }

    .dict-selection-empty {
      display: grid;
      flex: 1;
      place-items: center;
      min-height: 360px;
    }

    :deep(.dict-identity-cell) {
      display: grid;
      min-width: 0;
      line-height: 20px;

      strong,
      span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-weight: 600;
        color: var(--el-text-color-primary);
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.dict-appearance-cell) {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      align-items: center;
      min-width: 0;
    }

    :deep(.dict-cell-placeholder) {
      font-size: 12px;
      color: var(--el-text-color-placeholder);
    }

    .dict-splitter {
      :deep(.el-splitter-panel) {
        overflow: hidden;
      }

      :deep(.el-splitter-bar) {
        width: 16px;
        cursor: col-resize;
      }

      :deep(.el-splitter-bar::before) {
        position: absolute;
        top: 0;
        bottom: 0;
        left: 50%;
        width: 1px;
        content: '';
        background: var(--el-border-color);
        opacity: 0;
        transform: translateX(-50%);
        transition:
          opacity 0.18s ease,
          background-color 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger) {
        width: 16px;
        height: 56px;
        border-radius: 999px;
        opacity: 0.28;
        transition:
          opacity 0.18s ease,
          background-color 0.18s ease,
          box-shadow 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger::before) {
        width: 3px;
        height: 32px;
        background: var(--el-color-primary);
        border-radius: 999px;
      }

      :deep(.el-splitter-bar:hover::before),
      :deep(.el-splitter-bar:has(.el-splitter-bar__dragger-active)::before) {
        background: var(--el-color-primary-light-7);
        opacity: 1;
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger),
      :deep(.el-splitter-bar__dragger-active) {
        opacity: 1;
      }
    }

    @media (width <= 960px) {
      height: auto;

      .dict-splitter {
        display: block;

        :deep(.el-splitter-panel) {
          width: 100% !important;
          height: auto;
          overflow: visible;
        }

        :deep(.el-splitter-bar) {
          display: none;
        }
      }

      .dict-tree-panel {
        padding-right: 0;
        margin-bottom: 20px;
      }

      .dict-table-panel {
        padding-left: 0;
      }
    }
  }
</style>
