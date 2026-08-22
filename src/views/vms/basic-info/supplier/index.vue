<template>
  <div class="supplier-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="SUPPLY NETWORK"
      title="供应厂商"
      description="统一管理车辆零部件供应网络与联系人信息，为采购、维保和追溯提供可靠基础数据。"
      icon="ri:store-2-line"
      :tags="[{ label: '供应链主数据', type: 'primary' }]"
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
      :on-success="handleTableSuccess"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无供应厂商',
        emptyDescription: '可新增合作厂商，或调整名称、联系人和电话后重新查询。'
      }"
      focusable
    />

    <SupplierDialog ref="dialogRef" @success="handleSaveSuccess" />
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
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import {
    deleteSupplier,
    deleteSupplierBatch,
    exportSupplierList,
    fetchSupplierList,
    importSuppliers
  } from '@/api/vms'
  import SupplierDialog from './modules/supplier-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { canViewField, getFieldAccess, mergeFieldAccessMaps } from '@/utils/field-permission'

  defineOptions({ name: 'Supplier' })

  const { confirmAction } = useArtFeedback()

  type Supplier = Api.Vms.BasicInfo.Supplier
  type SearchParams = Api.Vms.BasicInfo.SupplierSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Supplier) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ total: number; rows: Supplier[] }>({ total: 0, rows: [] })
  const listFieldAccess = ref<Api.Vms.BasicInfo.SupplierFieldAccessMap>({})
  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...overview.rows.map((row) => row.fieldAccess))
  )
  const columnAccessSignature = computed(() =>
    (['contactDetails', 'addressDetails', 'internalNotes'] as const)
      .map((field) => `${field}:${getFieldAccess(effectiveFieldAccess.value, field)}`)
      .join('|')
  )
  const visibleContactRows = computed(() =>
    overview.rows.filter((row) => canViewField(row.fieldAccess, 'contactDetails'))
  )
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '供应厂商',
      value: overview.total,
      description: '当前筛选条件下的厂商总数',
      icon: 'ri:store-3-line'
    },
    ...(visibleContactRows.value.length
      ? [
          {
            label: '本页可见联络信息完整',
            value: visibleContactRows.value.filter((row) => row.contactPerson && row.contactPhone)
              .length,
            description: '仅统计当前有权查看的联络信息',
            icon: 'ri:contacts-book-2-line',
            tone: 'success' as const
          },
          {
            label: '本页可见联络信息待完善',
            value: visibleContactRows.value.filter((row) => !row.contactPerson || !row.contactPhone)
              .length,
            description: '仅统计当前有权查看的记录',
            icon: 'ri:user-search-line',
            tone: 'warning' as const
          }
        ]
      : [])
  ])

  const searchQuery = ref<SearchParams>({
    supplierName: '',
    contactPerson: '',
    contactPhone: ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '供应厂商名称',
      key: 'supplierName',
      type: 'input'
    },
    ...(getFieldAccess(listFieldAccess.value, 'contactDetails') === 'read' ||
    getFieldAccess(listFieldAccess.value, 'contactDetails') === 'edit'
      ? ([
          { label: '联系人', key: 'contactPerson', type: 'input' },
          { label: '联系电话', key: 'contactPhone', type: 'input' }
        ] as SearchFormItem[])
      : [])
  ])

  const supplierImportColumns: ArtTableQueryExcelColumn[] = [
    { key: 'supplierName', title: '供应厂商名称', required: true },
    { key: 'contactPerson', title: '联系人' },
    { key: 'contactPhone', title: '联系电话' },
    { key: 'region', title: '所在地区' },
    { key: 'addressDetail', title: '详细地址' },
    { key: 'remark', title: '备注' }
  ]
  const supplierExportColumns = computed<ArtTableQueryExcelColumn[]>(() => [
    { key: 'supplierName', title: '供应厂商名称', required: true },
    ...(canViewField(effectiveFieldAccess.value, 'contactDetails')
      ? [
          { key: 'contactPerson', title: '联系人' },
          { key: 'contactPhone', title: '联系电话' }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'addressDetails')
      ? [
          { key: 'region', title: '所在地区' },
          { key: 'addressDetail', title: '详细地址' }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'internalNotes')
      ? [{ key: 'remark', title: '备注' }]
      : [])
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'Supplier:Add',
      type: 'add',
      // permission: 'add',
      onClick: () => openDialog()
    },
    {
      permission: 'Supplier:Import',
      type: 'import',
      importColumns: supplierImportColumns,
      importApi: async (rows) => {
        await importSuppliers(rows as Supplier[])
      },
      onImportError: handleImportError
    },
    {
      permission: 'Supplier:Export',
      type: 'export',
      // permission: 'export',
      exportFilename: '供应厂商',
      exportSheetName: '供应厂商',
      exportColumns: supplierExportColumns.value,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportSupplierList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
      permission: 'Supplier:Delete',
      type: 'delete',
      // permission: 'delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定删除选中的 ${selectedCount} 家供应厂商吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows.map((row) => row.id).filter(Boolean)
        await deleteSupplierBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = async (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    const result = await fetchSupplierList({
      ...params,
      from,
      to
    })
    listFieldAccess.value = result.fieldAccess ?? {}
    return result
  }

  const columnsFactory = (): ColumnOption<Supplier>[] => [
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
      prop: 'supplierName',
      label: '供应厂商名称',
      minWidth: 180
    },
    ...(canViewField(effectiveFieldAccess.value, 'contactDetails')
      ? ([
          { prop: 'contactPerson', label: '联系人', width: 130 },
          { prop: 'contactPhone', label: '联系电话', width: 160 }
        ] as ColumnOption<Supplier>[])
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'addressDetails')
      ? ([
          {
            prop: 'address',
            label: '联系地址',
            minWidth: 260,
            formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
          }
        ] as ColumnOption<Supplier>[])
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'internalNotes')
      ? ([{ prop: 'remark', label: '备注', minWidth: 180 }] as ColumnOption<Supplier>[])
      : []),
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="supplier-page__operation">
          <ArtButtonTable type="edit" permission="Supplier:Edit" onClick={() => openDialog(row)} />
          <ArtButtonTable
            type="delete"
            permission="Supplier:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  watch(columnAccessSignature, () => {
    nextTick(() => tableQueryRef.value?.resetColumns())
  })

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as Supplier[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: Supplier): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Supplier): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(`确定删除供应厂商“${row.supplierName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteSupplier(row.id)
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
  .supplier-page {
    gap: 12px;
    min-width: 0;

    :deep(.supplier-page__operation) {
      display: flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }
  }
</style>
