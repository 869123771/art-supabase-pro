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
  import * as XLSX from 'xlsx'
  import FileSaver from 'file-saver'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import {
    deleteInsuranceCompany,
    deleteInsuranceCompanyBatch,
    fetchInsuranceCompanyList,
    importInsuranceCompanies
  } from '@/api/vehicle-mgt-sys'
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
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入保险公司名称'
      }
    },
    {
      label: '联系人',
      key: 'contactPerson',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入联系人'
      }
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '请输入联系电话'
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      //permission: 'add',
      onClick: () => openDialog()
    },
    {
      type: 'import',
      onImportSuccess: handleImportSuccess,
      onImportError: handleImportError
    },
    {
      type: 'export',
      // permission: 'export',
      onClick: handleExport
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
      minWidth: 180,
      showOverflowTooltip: true
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
      showOverflowTooltip: true,
      formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
    },
    {
      prop: 'remark',
      label: '备注',
      minWidth: 180,
      showOverflowTooltip: true
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

  const exportColumns: Record<keyof InsuranceCompany, string> = {
    id: 'ID',
    companyName: '保险公司名称',
    contactPerson: '联系人',
    contactPhone: '联系电话',
    region: '所在地区',
    addressDetail: '详细地址',
    remark: '备注',
    createTime: '创建时间',
    updateTime: '更新时间'
  }

  const normalizeImportRow = (row: Record<string, unknown>): InsuranceCompany | null => {
    const companyName = String(row['保险公司名称'] ?? row.companyName ?? '').trim()
    if (!companyName) return null

    return {
      companyName,
      contactPerson: String(row['联系人'] ?? row.contactPerson ?? '').trim(),
      contactPhone: String(row['联系电话'] ?? row.contactPhone ?? '').trim(),
      region: String(row['所在地区'] ?? row.region ?? '').trim(),
      addressDetail: String(row['详细地址'] ?? row.addressDetail ?? '').trim(),
      remark: String(row['备注'] ?? row.remark ?? '').trim()
    }
  }

  const handleImportSuccess = async (rows: Array<Record<string, unknown>>): Promise<void> => {
    const data = rows
      .map((row) => normalizeImportRow(row))
      .filter((row): row is InsuranceCompany => row !== null)

    if (!data.length) {
      ElMessage.warning('未读取到可导入的保险公司数据')
      return
    }

    await importInsuranceCompanies(data)
    await tableQueryRef.value?.refreshCreate()
  }

  const handleImportError = (): void => {
    ElMessage.error('导入文件解析失败')
  }

  const handleExport = async (ctx?: ArtTableQueryHeaderActionContext): Promise<void> => {
    const exportData = ctx?.selectedRows.length
      ? (ctx.selectedRows as InsuranceCompany[])
      : ((
          (await fetchInsuranceCompanyList({
            ...searchQuery.value,
            from: 0,
            to: 9999
          })) as { data?: InsuranceCompany[] }
        )?.data ?? [])

    const rows = exportData.map((row) => {
      const item: Record<string, string> = {}
      Object.entries(exportColumns).forEach(([key, title]) => {
        item[title] = String(row[key as keyof InsuranceCompany] ?? '')
      })
      return item
    })

    if (!rows.length) {
      ElMessage.warning('暂无可导出的保险公司数据')
      return
    }

    const worksheet = XLSX.utils.json_to_sheet(rows)
    const workbook = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(workbook, worksheet, '保险公司')
    const buffer = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' })
    FileSaver.saveAs(
      new Blob([buffer], { type: 'application/octet-stream' }),
      `保险公司_${new Date().toISOString().slice(0, 10)}.xlsx`
    )
  }
</script>
