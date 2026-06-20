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

    <InsuranceCompanyDialog ref="dialogRef" @success="handleSaveSuccess" />
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
    deleteInsuranceCompany,
    deleteInsuranceCompanyBatch,
    exportInsuranceCompanyList,
    fetchInsuranceCompanyList,
    importInsuranceCompanies
  } from '@/api/vehicle-manage-system'
  import InsuranceCompanyDialog from './modules/insurance-company-dialog.vue'

  defineOptions({ name: 'InsuranceCompany' })

  type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
  type SearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: InsuranceCompany) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()

  const searchQuery = ref<SearchParams>({
    companyName: '',
    contactPerson: '',
    contactPhone: ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '保险公司名称',
      key: 'companyName',
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

  const insuranceCompanyExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '保险公司名称', required: true },
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
      importColumns: insuranceCompanyExcelColumns,
      importApi: async (rows) => {
        await importInsuranceCompanies(rows as InsuranceCompany[])
      },
      onImportError: handleImportError
    },
    {
      type: 'export',
      // permission: 'export',
      exportFilename: '保险公司',
      exportSheetName: '保险公司',
      exportColumns: insuranceCompanyExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportInsuranceCompanyList({
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
        `确定删除选中的 ${selectedCount} 家保险公司吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows.map((row) => row.id).filter(Boolean)
        await deleteInsuranceCompanyBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchInsuranceCompanyList({
      ...params,
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<InsuranceCompany>[] => [
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
      prop: 'companyName',
      label: '保险公司名称',
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

  const openDialog = (row?: InsuranceCompany): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: InsuranceCompany): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(
        `确定删除保险公司“${row.companyName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteInsuranceCompany(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }

  const handleImportError = (): void => {
    ElMessage.error('导入文件解析失败')
  }
</script>
