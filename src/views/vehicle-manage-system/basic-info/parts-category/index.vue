<template>
  <div class="art-full-height">
    <div class="parts-category-layout">
      <ElSplitter class="parts-category-splitter">
        <ElSplitterPanel size="400px" min="400px" max="640px">
          <div class="parts-category-tree-panel">
            <PartsCategoryTree
              ref="treeRef"
              @tree-node-click="handleTreeNodeClick"
              @data-change="handleTreeDataChange"
            />
          </div>
        </ElSplitterPanel>

        <ElSplitterPanel>
          <div class="parts-category-table-panel">
            <ArtTableQuery
              ref="tableQueryRef"
              v-model="searchQuery"
              :search-items="searchItems"
              :api-fn="fetchTableData"
              :columns-factory="columnsFactory"
              :header-actions="headerActions"
              :search-bar-props="{ span: 8, labelWidth: 90 }"
              :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
            />
          </div>
        </ElSplitterPanel>
      </ElSplitter>
    </div>

    <PartsCategoryDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import {
    deletePartsCategory,
    deletePartsCategoryBatch,
    exportPartsCategoryList,
    fetchPartsCategoryList,
    importPartsCategories
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import PartsCategoryTree from './modules/parts-category-tree.vue'
  import PartsCategoryDialog from './modules/parts-category-dialog.vue'

  defineOptions({ name: 'PartsCategory' })

  type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
  type SearchParams = Api.VehicleMgtSys.BasicInfo.PartsCategorySearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: PartsCategory, parent?: PartsCategory) => Promise<void>
  }

  interface TreeExpose {
    getCurrentCategory: PartsCategory | undefined
    refreshTree: () => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const treeRef = ref<TreeExpose>()
  const dialogRef = ref<DialogExpose>()
  const currentCategory = shallowRef<PartsCategory>()
  const { getDictMap } = storeToRefs(useUserStore())

  const searchQuery = ref<SearchParams>({
    categoryName: '',
    categoryCode: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '类别名称',
      key: 'categoryName',
      type: 'input'
    },
    {
      label: '类别编码',
      key: 'categoryCode',
      type: 'input'
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.status ?? []
      }
    }
  ])

  const partsCategoryExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'categoryName', title: '类别名称', required: true },
    { key: 'categoryCode', title: '类别编码', required: true },
    { key: 'parentId', title: '上级类别ID' },
    { key: 'sort', title: '排序' },
    { key: 'status', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      onClick: () => openDialog(undefined, currentCategory.value)
    },
    {
      type: 'import',
      importColumns: partsCategoryExcelColumns,
      importApi: async (rows) => {
        await importPartsCategories(rows as PartsCategory[])
        await treeRef.value?.refreshTree()
      },
      onImportError: handleImportError
    },
    {
      type: 'export',
      exportFilename: '零部件类别',
      exportSheetName: '零部件类别',
      exportColumns: partsCategoryExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportPartsCategoryList({
          ...(searchParams as SearchParams),
          parentId: currentCategory.value?.id ?? null,
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
      type: 'delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定删除选中的 ${selectedCount} 个零部件类别吗？子类别会一并删除，删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows
          .map((row) => row.id)
          .filter((id): id is string => typeof id === 'string')
        await deletePartsCategoryBatch(ids)
        await treeRef.value?.refreshTree()
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchPartsCategoryList({
      ...params,
      parentId: currentCategory.value?.id ?? null,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<PartsCategory>[] => [
    {
      type: 'selection',
      width: 50,
      fixed: 'left',
      reserveSelection: true
    },
    {
      type: 'globalIndex',
      label: '序号',
      width: 80
    },
    {
      prop: 'categoryName',
      label: '类别名称',
      minWidth: 180
    },
    {
      prop: 'categoryCode',
      label: '类别编码',
      minWidth: 150
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'status', display: 'auto' }
    },
    {
      prop: 'remark',
      label: '备注',
      minWidth: 180
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonMore
            list={getMoreActions()}
            onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  const openDialog = (row?: PartsCategory, parent?: PartsCategory): void => {
    void dialogRef.value?.handleOpen(row, parent)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'add',
      label: '新增下级',
      icon: 'ri:add-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: PartsCategory): void => {
    if (item.key === 'add') {
      openDialog(undefined, row)
      return
    }
    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleTreeNodeClick = (node?: PartsCategory): void => {
    currentCategory.value = node
    void tableQueryRef.value?.getData()
  }

  const handleTreeDataChange = (): void => {
    void tableQueryRef.value?.refreshData()
  }

  const handleSaveSuccess = async (type: DialogType): Promise<void> => {
    await treeRef.value?.refreshTree()
    await (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: PartsCategory): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(
        `确定删除零部件类别“${row.categoryName}”吗？子类别会一并删除，删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deletePartsCategory(row.id)
      await treeRef.value?.refreshTree()
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时不需要额外提示。
    }
  }

  const handleImportError = (): void => {
    ElMessage.error('导入文件解析失败')
  }
</script>

<style scoped lang="scss">
  .parts-category-layout {
    width: 100%;
    height: 100%;
    min-height: 0;

    .parts-category-tree-panel,
    .parts-category-table-panel {
      display: flex;
      flex-direction: column;
      height: 100%;
      min-width: 0;
      min-height: 0;
    }

    .parts-category-tree-panel {
      padding-right: 8px;
    }

    .parts-category-table-panel {
      padding-left: 8px;
    }

    .parts-category-splitter {
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

      .parts-category-splitter {
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

      .parts-category-tree-panel {
        padding-right: 0;
        margin-bottom: 20px;
      }

      .parts-category-table-panel {
        padding-left: 0;
      }
    }
  }
</style>
