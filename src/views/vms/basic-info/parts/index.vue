<template>
  <div class="parts-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="PARTS MASTER DATA"
      title="零部件资料"
      description="维护零部件编码、类别、品牌与供应关系，为车辆维保和寿命管理建立统一数据底座。"
      icon="ri:settings-3-line"
      :tags="[
        { label: '分类可追溯', type: 'primary' },
        { label: '供应关系联动', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 8, labelWidth: 90 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无零部件资料',
        emptyDescription: '可新增零部件，或调整名称、编码、类别、品牌和状态后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <PartsDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import TreeUtils from '@/utils/tree'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteParts,
    deletePartsBatch,
    exportPartsList,
    fetchPartsCategoryTree,
    fetchPartsList,
    importParts
  } from '@/api/vms'
  import PartsDialog from './modules/parts-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'

  defineOptions({ name: 'VehicleParts' })

  const { confirmAction } = useArtFeedback()

  type Parts = Api.Vms.BasicInfo.Parts
  type SearchParams = Api.Vms.BasicInfo.PartsSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type PartsCategory = Api.Vms.BasicInfo.PartsCategory

  interface DialogExpose {
    handleOpen: (row?: Parts) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const categoryTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })
  const overview = reactive<{ total: number; rows: Parts[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '零部件总数',
      value: overview.total,
      description: '当前筛选条件下的主数据',
      icon: 'ri:database-2-line'
    },
    {
      label: '本页分类完整',
      value: overview.rows.filter((row) => row.category?.categoryName).length,
      description: '已关联标准零部件类别',
      icon: 'ri:git-branch-line',
      tone: 'success'
    },
    {
      label: '本页供应关系待补',
      value: overview.rows.filter((row) => !row.supplier?.supplierName).length,
      description: '尚未关联供应厂商',
      icon: 'ri:link-unlink-m',
      tone: 'warning'
    }
  ])

  const searchQuery = ref<SearchParams>({
    partName: '',
    partCode: '',
    categoryId: undefined,
    brand: '',
    status: undefined
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '零部件名称',
      key: 'partName',
      type: 'input'
    },
    {
      label: '零部件编码',
      key: 'partCode',
      type: 'input'
    },
    {
      label: '零部件类别',
      key: 'categoryId',
      type: 'treeSelect',
      api: fetchPartsCategoryTree,
      afterFetch: (result: unknown) => {
        const records = (result as { data?: PartsCategory[] })?.data ?? []
        return categoryTreeUtils.listToTree(records) as PartsCategory[]
      },
      labelField: 'categoryName',
      valueField: 'id',
      childrenField: 'children',
      props: {
        checkStrictly: true,
        renderAfterExpand: false
      }
    },
    {
      label: '品牌',
      key: 'brand',
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

  const partsImportColumns: ArtTableQueryExcelColumn[] = [
    { key: 'partName', title: '零部件名称', required: true },
    { key: 'partCode', title: '零部件编码', required: true },
    { key: 'categoryId', title: '类别ID' },
    { key: 'brand', title: '品牌' },
    { key: 'model', title: '型号' },
    { key: 'unit', title: '单位' },
    { key: 'isConsumable', title: '是否易损/耗件' },
    { key: 'warrantyMileage', title: '质保里程' },
    { key: 'warrantyDuration', title: '质保时长（月）' },
    { key: 'serviceLife', title: '使用年限（年）' },
    { key: 'serviceMileage', title: '使用里程' },
    { key: 'manufacturer', title: '生产厂商' },
    { key: 'supplierId', title: '供应厂商ID' },
    { key: 'supplierContact', title: '供应商联系人' },
    { key: 'status', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const partsExportColumns: ArtTableQueryExcelColumn[] = [
    { key: 'partName', title: '零部件名称' },
    { key: 'partCode', title: '零部件编码' },
    { key: 'categoryId', title: '类别ID' },
    {
      key: 'categoryName',
      title: '类别名称',
      formatter: (_value, row) => (row as Parts).category?.categoryName ?? ''
    },
    { key: 'brand', title: '品牌' },
    { key: 'model', title: '型号' },
    { key: 'unit', title: '单位' },
    { key: 'isConsumable', title: '是否易损/耗件' },
    { key: 'warrantyMileage', title: '质保里程' },
    { key: 'warrantyDuration', title: '质保时长（月）' },
    { key: 'serviceLife', title: '使用年限（年）' },
    { key: 'serviceMileage', title: '使用里程' },
    { key: 'manufacturer', title: '生产厂商' },
    { key: 'supplierId', title: '供应厂商ID' },
    {
      key: 'supplierName',
      title: '供应厂商',
      formatter: (_value, row) => (row as Parts).supplier?.supplierName ?? ''
    },
    { key: 'supplierContact', title: '供应商联系人' },
    { key: 'status', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { permission: 'Parts:Add', type: 'add', onClick: () => openDialog() },
    {
      permission: 'Parts:Import',
      type: 'import',
      importColumns: partsImportColumns,
      importApi: async (rows) => {
        await importParts(rows as Parts[])
      },
      onImportError: handleImportError
    },
    {
      permission: 'Parts:Export',
      type: 'export',
      exportFilename: '零部件',
      exportSheetName: '零部件',
      exportColumns: partsExportColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportPartsList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
      permission: 'Parts:Delete',
      type: 'delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定删除选中的 ${selectedCount} 个零部件吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows
          .map((row) => row.id)
          .filter((id): id is string => typeof id === 'string')
        await deletePartsBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchPartsList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<Parts>[] => [
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
      prop: 'partName',
      label: '零部件名称',
      minWidth: 180
    },
    {
      prop: 'partCode',
      label: '零部件编码',
      minWidth: 160
    },
    {
      prop: 'category',
      label: '类别',
      minWidth: 140,
      formatter: (row) => row.category?.categoryName || '-'
    },
    {
      prop: 'brandModel',
      label: '品牌 / 型号',
      minWidth: 170,
      formatter: (row) => [row.brand, row.model].filter(Boolean).join(' / ') || '-'
    },
    {
      prop: 'unit',
      label: '单位',
      width: 90
    },
    {
      prop: 'supplier',
      label: '供应厂商',
      minWidth: 160,
      formatter: (row) => row.supplier?.supplierName || '-'
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="parts-page__operation">
          <ArtButtonTable type="edit" permission="Parts:Edit" onClick={() => openDialog(row)} />
          <ArtButtonTable
            type="delete"
            permission="Parts:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as Parts[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: Parts): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Parts): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(`确定删除零部件“${row.partName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteParts(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }

  const handleImportError = (): void => {
    ElMessage.error('导入文件解析失败')
  }
</script>

<style scoped lang="scss">
  .parts-page {
    gap: 12px;
    min-width: 0;

    :deep(.parts-page__operation) {
      display: flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }
  }
</style>
