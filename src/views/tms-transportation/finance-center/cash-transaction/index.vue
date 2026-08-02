<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <CustomerReceiptDialog ref="dialogRef" @success="handleSaveSuccess" />
    <CarrierPaymentDialog ref="paymentDialogRef" @success="handleSaveSuccess" />
    <CashTransactionDetailDrawer ref="drawerRef" @changed="handleDetailChanged" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElMessageBox } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    exportCashTransactionList,
    fetchCashTransactionList,
    fetchCarrierOptions,
    fetchCustomerOptions,
    voidCashTransaction
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import CashTransactionDetailDrawer from './modules/cash-transaction-detail-drawer.vue'
  import CustomerReceiptDialog from './modules/customer-receipt-dialog.vue'
  import CarrierPaymentDialog from './modules/carrier-payment-dialog.vue'

  defineOptions({ name: 'TmsCashTransaction' })

  type CashTransaction = Api.Tms.Finance.CashTransactionRecord
  type SearchParams = Api.Tms.Finance.CashTransactionSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (transaction?: CashTransaction) => Promise<void>
  }

  interface DrawerExpose {
    handleOpen: (row: CashTransaction) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    customerOptions: Array<{ label: string; value: string }>
    carrierOptions: Array<{ label: string; value: string }>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const paymentDialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      customerId: '',
      carrierId: '',
      direction: '',
      status: '',
      dateRange: [],
      keyword: ''
    },
    customerOptions: [],
    carrierOptions: [],
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '往来承运商',
        key: 'carrierId',
        type: 'select',
        props: {
          options: table.carrierOptions,
          filterable: true,
          clearable: true,
          placeholder: '请选择承运商'
        }
      },
      {
        label: '往来客户',
        key: 'customerId',
        type: 'select',
        props: {
          options: table.customerOptions,
          filterable: true,
          clearable: true,
          placeholder: '请选择客户'
        }
      },
      {
        label: '收付方向',
        key: 'direction',
        type: 'select',
        props: { options: getDictMap.value.tmsCashDirection ?? [], clearable: true }
      },
      {
        label: '核销状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.tmsCashTransactionStatus ?? [], clearable: true }
      },
      {
        label: '收付日期',
        key: 'dateRange',
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
        props: {
          clearable: true,
          placeholder: '收付款单号、往来单位、银行流水号或备注'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        label: '登记客户收款',
        onClick: () => void dialogRef.value?.handleOpen()
      },
      {
        type: 'add',
        label: '登记承运商付款',
        onClick: () => void paymentDialogRef.value?.handleOpen()
      },
      {
        type: 'export',
        exportFilename: 'TMS收付款核销',
        exportSheetName: '收付款核销',
        exportColumns: excelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportCashTransactionList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ])
  })

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  const columnsFactory = (): ColumnOption<CashTransaction>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'transactionNo', label: '收付款单号', width: 190 },
    {
      prop: 'direction',
      label: '方向',
      width: 90,
      dict: { code: 'tmsCashDirection', display: 'tag' }
    },
    {
      prop: 'counterpartyName',
      label: '往来单位',
      minWidth: 190,
      showOverflowTooltip: true
    },
    { prop: 'transactionDate', label: '收付日期', width: 110 },
    {
      prop: 'amount',
      label: '收付金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.amount)
    },
    {
      prop: 'allocatedAmount',
      label: '已核销',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.allocatedAmount)
    },
    {
      prop: 'unallocatedAmount',
      label: '未核销',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.unallocatedAmount)
    },
    {
      prop: 'paymentMethod',
      label: '收付方式',
      width: 110,
      dict: { code: 'tmsCashPaymentMethod', display: 'text' }
    },
    {
      prop: 'bankReference',
      label: '银行流水号',
      minWidth: 155,
      showOverflowTooltip: true
    },
    {
      prop: 'status',
      label: '核销状态',
      width: 115,
      dict: { code: 'tmsCashTransactionStatus', display: 'tag' }
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
      width: 240,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
            查看
          </ElButton>
          {row.direction === 'receipt' &&
            ['pending_allocation', 'partially_allocated'].includes(row.status) &&
            row.unallocatedAmount > 0 && (
              <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
                继续核销
              </ElButton>
            )}
          {row.direction === 'payment' &&
            ['pending_allocation', 'partially_allocated'].includes(row.status) &&
            row.unallocatedAmount > 0 && (
              <ElButton
                link
                type="primary"
                onClick={() => void paymentDialogRef.value?.handleOpen(row)}
              >
                继续核销
              </ElButton>
            )}
          {row.status === 'pending_allocation' && row.allocatedAmount === 0 && (
            <ElButton link type="danger" onClick={() => void handleVoid(row)}>
              {row.direction === 'receipt' ? '作废收款' : '作废付款'}
            </ElButton>
          )}
        </div>
      )
    }
  ]

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'transactionNo', title: '收付款单号' },
    { key: 'direction', title: '方向' },
    { key: 'counterpartyName', title: '往来单位' },
    { key: 'transactionDate', title: '收付日期' },
    { key: 'amount', title: '收付金额' },
    { key: 'allocatedAmount', title: '已核销金额' },
    { key: 'unallocatedAmount', title: '未核销金额' },
    { key: 'paymentMethod', title: '收付方式' },
    { key: 'bankReference', title: '银行流水号' },
    { key: 'status', title: '核销状态' },
    { key: 'createBy', title: '登记人' },
    { key: 'createTime', title: '登记时间' }
  ]

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCashTransactionList({ ...params, from, to })
  }

  async function loadCustomerOptions(): Promise<void> {
    const { data } = await fetchCustomerOptions()
    table.customerOptions = (data ?? []).map((item) => ({
      label: item.customerName,
      value: item.id
    }))
  }

  async function handleVoid(row: CashTransaction): Promise<void> {
    try {
      const { value } = await ElMessageBox.prompt(
        `作废后保留${row.direction === 'receipt' ? '收款' : '付款'}流水历史，但不能再进行核销。`,
        row.direction === 'receipt' ? '作废收款' : '作废付款',
        {
          type: 'warning',
          confirmButtonText: '确认作废',
          cancelButtonText: '取消',
          inputType: 'textarea',
          inputPlaceholder: '请填写作废原因',
          inputValidator: (text) => Boolean(text?.trim()) || '作废原因不能为空'
        }
      )
      await voidCashTransaction(row.id, value.trim())
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  function handleSaveSuccess(): void {
    void tableQueryRef.value?.refreshCreate()
  }

  function handleDetailChanged(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  async function loadCarrierOptions(): Promise<void> {
    const { data } = await fetchCarrierOptions()
    table.carrierOptions = (data ?? []).map((item) => ({
      label: item.companyName,
      value: item.id
    }))
  }

  onMounted(() => {
    void loadCustomerOptions()
    void loadCarrierOptions()
  })
</script>
