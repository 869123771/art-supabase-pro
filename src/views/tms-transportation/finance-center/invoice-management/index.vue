<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <InvoiceDialog ref="dialogRef" @success="handleSaveSuccess" />
    <InvoiceDetailDrawer ref="drawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    deleteInvoice,
    exportInvoiceList,
    fetchCarrierOptions,
    fetchCustomerOptions,
    fetchInvoiceList,
    updateInvoiceStatus
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import InvoiceDialog from './modules/invoice-dialog.vue'
  import InvoiceDetailDrawer from './modules/invoice-detail-drawer.vue'

  defineOptions({ name: 'TmsInvoiceManagement' })

  type Invoice = Api.Tms.Finance.InvoiceRecord
  type SearchParams = Api.Tms.Finance.InvoiceSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Invoice) => Promise<void>
  }

  interface DrawerExpose {
    handleOpen: (row: Invoice) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    customerOptions: Array<{ label: string; value: string }>
    carrierOptions: Array<{ label: string; value: string }>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const { promptReason, confirmAction } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      direction: '',
      status: '',
      invoiceType: '',
      customerId: '',
      carrierId: '',
      issueDateRange: [],
      keyword: ''
    },
    searchItems: computed(() => [
      {
        label: '发票方向',
        key: 'direction',
        type: 'select',
        props: { options: getDictMap.value.tmsInvoiceDirection ?? [], clearable: true }
      },
      {
        label: '发票状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.tmsInvoiceStatus ?? [], clearable: true }
      },
      {
        label: '发票类型',
        key: 'invoiceType',
        type: 'select',
        props: { options: getDictMap.value.tmsInvoiceType ?? [], clearable: true }
      },
      {
        label: '开票客户',
        key: 'customerId',
        type: 'select',
        props: { options: table.customerOptions, filterable: true, clearable: true }
      },
      {
        label: '来票承运商',
        key: 'carrierId',
        type: 'select',
        props: { options: table.carrierOptions, filterable: true, clearable: true }
      },
      {
        label: '开票日期',
        key: 'issueDateRange',
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
        props: { clearable: true, placeholder: '登记号、发票号码、往来单位或抬头' }
      }
    ]),
    headerActions: computed(() => [
      {
        type: 'add',
        label: '登记发票',
        onClick: () => void dialogRef.value?.handleOpen()
      },
      {
        type: 'export',
        exportFilename: 'TMS发票台账',
        exportSheetName: '发票台账',
        exportColumns: excelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportInvoiceList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ]),
    customerOptions: [],
    carrierOptions: []
  })

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const renderStatusActions = (row: Invoice) => {
    if (row.status === 'draft')
      return (
        <>
          <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
            编辑
          </ElButton>
          <ElButton link type="primary" onClick={() => void handleStatusAction(row, 'submit')}>
            提交复核
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleDelete(row)}>
            删除
          </ElButton>
        </>
      )
    if (row.status === 'pending_review')
      return (
        <>
          <ElButton link type="success" onClick={() => void handleStatusAction(row, 'approve')}>
            审核通过
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleRemarkAction(row, 'reject')}>
            驳回
          </ElButton>
        </>
      )
    if (row.status === 'issued' || row.status === 'certified')
      return (
        <ElButton link type="danger" onClick={() => void handleRemarkAction(row, 'void')}>
          作废
        </ElButton>
      )
    return null
  }

  const columnsFactory = (): ColumnOption<Invoice>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'invoiceRecordNo', label: '登记单号', width: 190 },
    { prop: 'invoiceNo', label: '发票号码', width: 190, formatter: (row) => row.invoiceNo || '-' },
    {
      prop: 'direction',
      label: '方向',
      width: 105,
      dict: { code: 'tmsInvoiceDirection', display: 'tag' }
    },
    {
      prop: 'invoiceType',
      label: '发票类型',
      width: 150,
      dict: { code: 'tmsInvoiceType', display: 'text' }
    },
    {
      prop: 'counterpartyNameSnapshot',
      label: '往来单位',
      minWidth: 210,
      showOverflowTooltip: true
    },
    { prop: 'issueDate', label: '开票日期', width: 110 },
    {
      prop: 'totalAmount',
      label: '价税合计',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.totalAmount)
    },
    {
      prop: 'linkedAmount',
      label: '已关联对账',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.linkedAmount)
    },
    {
      prop: 'unlinkedAmount',
      label: '未关联金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.unlinkedAmount)
    },
    {
      prop: 'status',
      label: '状态',
      width: 110,
      dict: { code: 'tmsInvoiceStatus', display: 'tag' }
    },
    {
      prop: 'createTime',
      label: '登记时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 260,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
            查看
          </ElButton>
          {renderStatusActions(row)}
        </div>
      )
    }
  ]

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'invoiceRecordNo', title: '登记单号' },
    { key: 'invoiceNo', title: '发票号码' },
    { key: 'direction', title: '方向' },
    { key: 'invoiceType', title: '发票类型' },
    { key: 'counterpartyNameSnapshot', title: '往来单位' },
    { key: 'invoiceTitle', title: '发票抬头' },
    { key: 'taxNumber', title: '税号' },
    { key: 'issueDate', title: '开票日期' },
    { key: 'amountExcludingTax', title: '不含税金额' },
    { key: 'taxAmount', title: '税额' },
    { key: 'totalAmount', title: '价税合计' },
    { key: 'linkedAmount', title: '已关联对账金额' },
    { key: 'unlinkedAmount', title: '未关联金额' },
    { key: 'status', title: '状态' }
  ]

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchInvoiceList({ ...params, from, to })
  }

  async function handleStatusAction(
    row: Invoice,
    statusAction: Api.Tms.Finance.InvoiceStatusAction
  ) {
    const label = statusAction === 'submit' ? '提交复核' : '审核通过'
    try {
      await confirmAction(`确定${label}发票 ${row.invoiceNo || row.invoiceRecordNo} 吗？`, label, {
        type: 'warning'
      })
      await updateInvoiceStatus({ id: row.id, action: statusAction })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消或业务校验未通过
    }
  }

  async function handleRemarkAction(
    row: Invoice,
    statusAction: Extract<Api.Tms.Finance.InvoiceStatusAction, 'reject' | 'void'>
  ) {
    const label = statusAction === 'reject' ? '驳回发票' : '作废发票'
    try {
      const reason = await promptReason(`请填写${label}原因`, label, {
        confirmButtonText: statusAction === 'reject' ? '确认驳回' : '确认作废',
        placeholder: `请填写${label}原因`
      })
      await updateInvoiceStatus({ id: row.id, action: statusAction, remark: reason })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消或业务校验未通过
    }
  }

  async function handleDelete(row: Invoice) {
    try {
      await confirmAction('仅草稿发票可以删除，删除后无法恢复。', '删除发票', {
        type: 'warning'
      })
      await deleteInvoice(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消或业务校验未通过
    }
  }

  async function loadCounterpartyOptions() {
    const [customerResponse, carrierResponse] = await Promise.all([
      fetchCustomerOptions(),
      fetchCarrierOptions()
    ])
    table.customerOptions = (customerResponse.data ?? []).map((item) => ({
      label: item.customerName,
      value: item.id
    }))
    table.carrierOptions = (carrierResponse.data ?? []).map((item) => ({
      label: item.companyName,
      value: item.id
    }))
  }

  function handleSaveSuccess() {
    void tableQueryRef.value?.refreshCreate()
  }

  onMounted(() => void loadCounterpartyOptions())
</script>
