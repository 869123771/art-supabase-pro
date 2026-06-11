<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
    />

    <SupplierDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage, ElMessageBox } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
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
  } from '@/api/vehicle-mgt-sys'
  import SupplierDialog from './modules/supplier-dialog.vue'

  defineOptions({ name: 'Supplier' })

  type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
  type SearchParams = Api.VehicleMgtSys.BasicInfo.SupplierSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Supplier) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()

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
    {
      label: '联系人',
      key: 'contactPerson',
      type: 'input'
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input'
    }
  ])

  const supplierExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'supplierName', title: '供应厂商名称', required: true },
    { key: 'contactPerson', title: '联系人' },
    { key: 'contactPhone', title: '联系电话' },
    { key: 'region', title: '所在地区' },
    { key: 'addressDetail', title: '详细地址' },
    { key: 'remark', title: '备注' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      // permission: 'add',
      onClick: () => openDialog()
    },
    {
      type: 'import',
      importColumns: supplierExcelColumns,
      importApi: async (rows) => {
        await importSuppliers(rows as Supplier[])
      },
      onImportError: handleImportError
    },
    {
      type: 'export',
      // permission: 'export',
      exportFilename: '供应厂商',
      exportSheetName: '供应厂商',
      exportColumns: supplierExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportSupplierList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
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

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchSupplierList({
      ...params,
      from,
      to
    })
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
    {
      prop: 'contactPerson',
      label: '联系人',
      width: 130
    },
    {
      prop: 'contactPhone',
      label: '联系电话',
      width: 160
    },
    {
      prop: 'address',
      label: '联系地址',
      minWidth: 260,
      formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
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
        <div>
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

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
      await ElMessageBox.confirm(
        `确定删除供应厂商“${row.supplierName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
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
