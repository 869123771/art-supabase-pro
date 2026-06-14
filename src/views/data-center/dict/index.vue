<template>
  <div class="art-full-height">
    <div class="dict-layout">
      <ElSplitter class="dict-splitter">
        <ElSplitterPanel size="232px" min="280px" max="420px">
          <div class="dict-tree-panel">
            <TypeTree ref="typeTreeRef" @tree-node-click="handleTreeNodeClick" />
          </div>
        </ElSplitterPanel>

        <ElSplitterPanel>
          <div class="dict-table-panel">
            <ArtTableQuery
              ref="tableQueryRef"
              v-model="searchQuery"
              :search-items="searchItems"
              :api-fn="fetchTableData"
              :columns-factory="columnsFactory"
              :header-actions="headerActions"
              :immediate="false"
              :search-bar-props="{ span: 8, labelWidth: 100 }"
              :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
            />
          </div>
        </ElSplitterPanel>
      </ElSplitter>
    </div>

    <DictDialog ref="dictDialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { isEmpty } from 'lodash-es'
  import { ElMessage, ElMessageBox, ElTag } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import { deleteDict, deleteDictBatch, fetchGetDictListByTypeId } from '@/api/data-center'
  import TypeTree from './modules/type-tree.vue'
  import DictDialog from './modules/dict-dialog.vue'

  defineOptions({ name: 'dict' })

  type DictListItem = Api.DataCenter.DictListItem
  type SearchParams = Partial<Pick<DictListItem, 'label' | 'code' | 'i18nScope' | 'status'>>
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type DictQueryParams = Partial<DictListItem> & Api.Common.CommonSearchParams
  type DictDialogOpenData = Partial<DictListItem> & { dictTypeName?: string }
  type DictTypeItem = Pick<DictListItem, 'id' | 'name'>

  interface TypeTreeExpose {
    getCurrentDictType: DictTypeItem
  }

  interface DictDialogExpose {
    handleOpen: (data?: DictDialogOpenData) => Promise<void>
  }

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const typeTreeRef = ref<TypeTreeExpose>()
  const dictDialogRef = ref<DictDialogExpose>()

  const searchQuery = ref<SearchParams>({
    label: '',
    code: '',
    i18nScope: '',
    status: ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
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
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
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
        await deleteDictBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const columnsFactory = (): ColumnOption<DictListItem>[] => [
    {
      type: 'selection',
      width: 50,
      fixed: 'left',
      reserveSelection: true
    },
    {
      prop: 'label',
      label: '字典名称'
    },
    {
      prop: 'code',
      label: '字典编码'
    },
    {
      prop: 'value',
      label: '字典值'
    },
    {
      prop: 'i18n',
      label: '国际化'
    },
    {
      prop: 'i18nScope',
      label: '国际化范围',
      formatter: (row) => {
        const label = userStore.getDictLabelByValue('i18nScope', row.i18nScope)
        return <span>{label}</span>
      }
    },
    {
      prop: 'status',
      label: '状态',
      formatter: (row) => {
        const tag = userStore.getDictTagByValue('status', row.status)
        return (
          <ElTag type={tag.type}>
            <span>{tag.label}</span>
          </ElTag>
        )
      }
    },
    {
      prop: 'color',
      label: '文字颜色'
    },
    {
      prop: 'sort',
      label: '排序'
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="edit" onClick={() => handleEdit(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const fetchTableData = (params: TableParams) => {
    const currentDictType = typeTreeRef.value?.getCurrentDictType
    if (isEmpty(currentDictType) || !currentDictType?.id) {
      return Promise.resolve({
        records: [],
        total: 0,
        current: params.current,
        size: params.size
      })
    }

    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchGetDictListByTypeId({
      typeId: currentDictType.id,
      ...params,
      from,
      to
    } satisfies DictQueryParams)
  }

  const handleTreeNodeClick = (): void => {
    void tableQueryRef.value?.getData()
  }

  const handleAdd = (): void => {
    const currentDictType = typeTreeRef.value?.getCurrentDictType
    if (isEmpty(currentDictType) || !currentDictType?.id) {
      ElMessage.warning('请选择字典类型')
      return
    }

    void dictDialogRef.value?.handleOpen({
      typeId: currentDictType.id,
      dictTypeName: currentDictType.name
    })
  }

  const handleEdit = (row: DictListItem): void => {
    const currentDictType = typeTreeRef.value?.getCurrentDictType
    void dictDialogRef.value?.handleOpen({
      ...row,
      dictTypeName: currentDictType?.name
    })
  }

  const handleDelete = async (row: DictListItem): Promise<void> => {
    try {
      await ElMessageBox.confirm('确定要删除该字典项吗？', '删除字典项', {
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
      height: 100%;
      min-width: 0;
      min-height: 0;
    }

    .dict-tree-panel {
      padding-right: 8px;
    }

    .dict-table-panel {
      padding-left: 8px;
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
        opacity: 0;
        transition:
          opacity 0.18s ease,
          background-color 0.18s ease,
          box-shadow 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger::before) {
        width: 3px;
        height: 32px;
        border-radius: 999px;
        background: var(--el-color-primary);
      }

      :deep(.el-splitter-bar:hover::before),
      :deep(.el-splitter-bar:has(.el-splitter-bar__dragger-active)::before) {
        opacity: 1;
        background: var(--el-color-primary-light-7);
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger),
      :deep(.el-splitter-bar__dragger-active) {
        opacity: 1;
      }
    }

    @media (width <= 768px) {
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
