<template>
  <div class="tms-workspace-page art-full-height">
    <TmsWorkspaceHeader
      eyebrow="CUSTOMER MASTER DATA"
      title="客户资料"
      description="统一维护客户主体、行业等级、结算联系人与业务状态，为开单和对账提供可信主数据。"
      icon="ri:user-star-line"
      :tags="[
        { label: '客户主数据', type: 'primary' },
        { label: '业务可用性', type: 'success' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        emptyText: '暂无客户资料',
        emptyDescription: '可新增客户，或调整客户等级、行业、状态和关键字后重新查询。'
      }"
      focusable
    />

    <CustomerDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteCustomer,
    deleteCustomerBatch,
    exportCustomerList,
    fetchCustomerList,
    importCustomers
  } from '@/api/tms'
  import CustomerDialog from './modules/customer-dialog.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'

  defineOptions({ name: 'TmsCustomer' })

  const { confirmAction } = useArtFeedback()

  type Customer = Api.Tms.BasicData.Customer
  type SearchParams = Api.Tms.BasicData.CustomerSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface CustomerDialogExpose {
    handleOpen: (row?: Customer) => Promise<void>
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<CustomerDialogExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      customerLevel: '',
      industry: '',
      enabled: undefined,
      createTimeRange: [],
      keyword: ''
    }
  })

  const customerLevelOptions = computed(() => getDictMap.value.tmsCustomerLevel ?? [])
  const customerIndustryOptions = computed(() => getDictMap.value.tmsCustomerIndustry ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const customerExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'customerCode', title: '客户编号' },
    { key: 'customerName', title: '客户名称', required: true },
    { key: 'industry', title: '所属行业' },
    { key: 'customerLevel', title: '客户级别' },
    { key: 'contactName', title: '联系人' },
    { key: 'contactPhone', title: '手机号码' },
    { key: 'region', title: '区域' },
    { key: 'addressDetail', title: '公司地址' },
    { key: 'postalCode', title: '邮编' },
    { key: 'remark', title: '备注' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '客户级别',
      key: 'customerLevel',
      type: 'select',
      props: { options: customerLevelOptions.value, clearable: true }
    },
    {
      label: '所属行业',
      key: 'industry',
      type: 'select',
      props: { options: customerIndustryOptions.value, clearable: true }
    },
    {
      label: '客户状态',
      key: 'enabled',
      type: 'select',
      props: { options: commonBooleanOptions.value, clearable: true }
    },
    {
      label: '创建日期',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至'
      }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '客户名称、编号、联系人或电话' }
    }
  ])

  const columnsFactory = (): ColumnOption<Customer>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    { prop: 'customerCode', label: '客户编号', width: 140 },
    { prop: 'customerName', label: '客户名称', minWidth: 190, showOverflowTooltip: true },
    {
      prop: 'industry',
      label: '所属行业',
      width: 130,
      dict: { code: 'tmsCustomerIndustry', display: 'text' }
    },
    {
      prop: 'customerLevel',
      label: '客户级别',
      width: 120,
      dict: { code: 'tmsCustomerLevel', display: 'tag' }
    },
    {
      prop: 'tags',
      label: '客户标签',
      minWidth: 200,
      formatter: (row) => (
        <div class="flex flex-wrap gap-1">
          {(row.tags?.length ? row.tags : ['']).map((tag) => (
            <ArtDictDisplay
              key={tag || 'empty'}
              dictCode="tmsCustomerTag"
              value={tag}
              display={tag ? 'tag' : 'text'}
            />
          ))}
        </div>
      )
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    },
    { prop: 'contactName', label: '联系人', width: 110 },
    { prop: 'contactPhone', label: '手机号码', width: 140 },
    {
      prop: 'operation',
      label: '操作',
      width: 160,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable
            type="view"
            icon="ri:map-pin-line"
            onClick={() => openAddressManage(row)}
          />
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'import',
      importColumns: customerExcelColumns,
      importApi: async (rows) => {
        await importCustomers(rows as Customer[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS客户资料',
      exportSheetName: '客户管理',
      exportColumns: customerExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCustomerList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 个客户吗？关联地址也会一并删除。`,
      onClick: async ({ selectedRows }) => {
        await deleteCustomerBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCustomerList({ ...params, from, to })
  }

  const openDialog = (row?: Customer): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openAddressManage = (row: Customer): void => {
    if (!row.id) return
    void router.push({
      name: 'TmsCustomerAddress',
      query: {
        customerId: row.id,
        customerName: row.customerName
      }
    })
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Customer): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(
        `确定删除客户“${row.customerName}”吗？关联地址也会一并删除。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCustomer(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>
