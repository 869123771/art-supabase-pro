<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="CASH OPERATIONS"
      title="收付款管理"
      description="集中登记客户回款、承运商付款、银行流水与核销关系，让资金去向清晰可追踪。"
      icon="ri:exchange-cny-line"
      :tags="[
        { label: '资金流水', type: 'primary' },
        { label: '核销可追踪', type: 'success' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <MasterDeleteProcessingNotice
      v-if="customerDeleteContext.active"
      :customer-id="customerDeleteContext.customerId"
      :customer-name="customerDeleteContext.customerName"
      action-hint="请先查看该流水的核销关系。财务流水仅支持按业务规则撤销核销或作废，不支持直接物理删除。"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无收付款记录',
        emptyDescription: '可登记回款或付款，或调整交易类型、状态、往来单位和日期后查询。'
      }"
      focusable
    />

    <CustomerReceiptDialog ref="dialogRef" @success="handleSaveSuccess" />
    <CarrierPaymentDialog ref="paymentDialogRef" @success="handleSaveSuccess" />
    <CashTransactionDetailDrawer ref="drawerRef" @changed="handleDetailChanged" />
    <CashBankBatchImportDialog ref="batchImportDialogRef" @success="handleSaveSuccess" />
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
    exportCashTransactionList,
    fetchCashTransactionList,
    fetchCarrierOptions,
    fetchCustomerOptions,
    voidCashTransaction
  } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    canEditField,
    canViewField,
    formatSensitiveNumber,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'
  import { financeRouteNames } from '@/router/business-paths'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import { fetchRecognitionArtifactDetail } from '@/api/intelligent-recognition'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'
  import { toCashVoucherOcrAnalyzeResponse } from '@/utils/intelligent-recognition'
  import CashTransactionDetailDrawer from './modules/cash-transaction-detail-drawer.vue'
  import CustomerReceiptDialog from './modules/customer-receipt-dialog.vue'
  import CarrierPaymentDialog from './modules/carrier-payment-dialog.vue'
  import CashBankBatchImportDialog from './modules/cash-bank-batch-import-dialog.vue'

  defineOptions({ name: 'FinanceCashTransaction' })

  type CashTransaction = Api.Fms.CashTransactionRecord
  type CashTransactionFieldKey = Api.Fms.CashTransactionFieldKey
  type SearchParams = Api.Fms.CashTransactionSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (transaction?: CashTransaction) => Promise<void>
    handleOpenFromOcr?: (result: Api.Fms.CashVoucherOcrAnalyzeResponse) => Promise<void>
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
  const { promptReason } = useArtFeedback()
  const { hasAuth } = useAuth()
  const route = useRoute()
  const router = useRouter()
  const customerDeleteContext = useMasterDataDeleteProcessingContext()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const paymentDialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const batchImportDialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const fieldAccess = ref<Api.Fms.CashTransactionFieldAccessMap>({})
  const currentRows = ref<CashTransaction[]>([])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      customerId: customerDeleteContext.value.customerId,
      carrierId: customerDeleteContext.value.carrierId,
      direction: typeof route.query.direction === 'string' ? route.query.direction : '',
      status: typeof route.query.status === 'string' ? route.query.status : '',
      dateRange: [],
      keyword: typeof route.query.keyword === 'string' ? route.query.keyword : '',
      recordId: customerDeleteContext.value.recordId
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
          placeholder: canViewListField('bankDetails')
            ? '收付款单号、往来单位、银行流水号或备注'
            : '收付款单号、往来单位或备注'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        auth: 'FinanceCashTransaction:Import',
        key: 'import',
        label: 'AI 批量导入流水',
        icon: 'ri-file-excel-2-line',
        buttonProps: { type: 'primary', plain: true },
        onClick: () => void batchImportDialogRef.value?.handleOpen()
      },
      {
        permission: 'FinanceCashTransaction:Add',
        type: 'add',
        label: '登记客户收款',
        onClick: () => void dialogRef.value?.handleOpen()
      },
      {
        auth: 'FinanceCashTransaction:CreatePayment',
        key: 'create-payment',
        label: '发起承运商付款申请',
        onClick: () => void router.push({ name: financeRouteNames.paymentApplication })
      },
      {
        permission: 'FinanceCashTransaction:Export',
        type: 'export',
        exportFilename: 'TMS收付款核销',
        exportSheetName: '收付款核销',
        exportColumns: excelColumns.value,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportCashTransactionList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ])
  })

  function formatMoney(value?: Api.Tms.BasicData.SensitiveNumber): string {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
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
    ...(canViewListField('transactionAmounts')
      ? [
          {
            prop: 'amount',
            label: '收付金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: CashTransaction) => formatMoney(row.amount)
          },
          {
            prop: 'allocatedAmount',
            label: '已核销',
            width: 135,
            align: 'right' as const,
            formatter: (row: CashTransaction) => formatMoney(row.allocatedAmount)
          },
          {
            prop: 'unallocatedAmount',
            label: '未核销',
            width: 135,
            align: 'right' as const,
            formatter: (row: CashTransaction) => formatMoney(row.unallocatedAmount)
          }
        ]
      : []),
    {
      prop: 'paymentMethod',
      label: '收付方式',
      width: 110,
      dict: { code: 'tmsCashPaymentMethod', display: 'text' }
    },
    ...(canViewListField('bankDetails')
      ? [
          {
            prop: 'fundAccount',
            label: '资金账户',
            minWidth: 180,
            formatter: (row: CashTransaction) =>
              row.fundAccount
                ? `${row.fundAccount.accountName} · ${row.fundAccount.accountNoMasked}`
                : '历史未关联'
          },
          {
            prop: 'bankReference',
            label: '银行流水号',
            minWidth: 155,
            showOverflowTooltip: true
          }
        ]
      : []),
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
          {hasAuth('FinanceCashTransaction:View') ? (
            <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
              查看
            </ElButton>
          ) : null}
          {row.direction === 'receipt' &&
            ['pending_allocation', 'partially_allocated'].includes(row.status) &&
            sensitiveNumberValue(row.unallocatedAmount) > 0 &&
            canEditField(row.fieldAccess, 'transactionAmounts') &&
            hasAuth('FinanceCashTransaction:Allocate') && (
              <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
                继续核销
              </ElButton>
            )}
          {row.direction === 'payment' &&
            ['pending_allocation', 'partially_allocated'].includes(row.status) &&
            sensitiveNumberValue(row.unallocatedAmount) > 0 &&
            canEditField(row.fieldAccess, 'transactionAmounts') &&
            hasAuth('FinanceCashTransaction:Allocate') && (
              <ElButton
                link
                type="primary"
                onClick={() => void paymentDialogRef.value?.handleOpen(row)}
              >
                继续核销
              </ElButton>
            )}
          {row.status === 'pending_allocation' &&
            sensitiveNumberValue(row.allocatedAmount) === 0 &&
            hasAuth('FinanceCashTransaction:Void') && (
              <ElButton link type="danger" onClick={() => void handleVoid(row)}>
                {row.direction === 'receipt' ? '作废收款' : '作废付款'}
              </ElButton>
            )}
        </div>
      )
    }
  ]

  const excelColumns = computed<ArtTableQueryExcelColumn[]>(() => [
    { key: 'transactionNo', title: '收付款单号' },
    { key: 'direction', title: '方向' },
    { key: 'counterpartyName', title: '往来单位' },
    { key: 'transactionDate', title: '收付日期' },
    ...(canViewListField('transactionAmounts')
      ? [
          { key: 'amount', title: '收付金额' },
          { key: 'allocatedAmount', title: '已核销金额' },
          { key: 'unallocatedAmount', title: '未核销金额' }
        ]
      : []),
    { key: 'paymentMethod', title: '收付方式' },
    ...(canViewListField('bankDetails')
      ? [
          { key: 'fundAccount.accountName', title: '资金账户' },
          { key: 'bankReference', title: '银行流水号' }
        ]
      : []),
    { key: 'status', title: '核销状态' },
    { key: 'createBy', title: '登记人' },
    { key: 'createTime', title: '登记时间' }
  ])

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchCashTransactionList({ ...params, from, to })
    const previousVisibility = getSensitiveColumnVisibility()
    fieldAccess.value = result.fieldAccess
    currentRows.value = result.data
    if (previousVisibility !== getSensitiveColumnVisibility()) {
      await nextTick()
      tableQueryRef.value?.resetColumns()
    }
    return result
  }

  const canViewListField = (field: CashTransactionFieldKey): boolean =>
    canViewField(
      mergeFieldAccessMaps(fieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess)),
      field
    )

  const getSensitiveColumnVisibility = (): string =>
    `${canViewListField('transactionAmounts')}:${canViewListField('bankDetails')}`

  function sensitiveNumberValue(value?: Api.Tms.BasicData.SensitiveNumber): number {
    const numeric = Number(value)
    return Number.isFinite(numeric) ? numeric : 0
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
      const reason = await promptReason(
        `作废后保留${row.direction === 'receipt' ? '收款' : '付款'}流水历史，但不能再进行核销。`,
        row.direction === 'receipt' ? '作废收款' : '作废付款',
        {
          confirmButtonText: '确认作废',
          placeholder: '请填写作废原因',
          emptyMessage: '作废原因不能为空'
        }
      )
      await voidCashTransaction(row.id, reason)
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

  async function restoreRecognitionDraft(): Promise<void> {
    const artifactId = typeof route.query.aiArtifactId === 'string' ? route.query.aiArtifactId : ''
    if (!artifactId || route.query.direction === 'payment') return

    const { data, error } = await fetchRecognitionArtifactDetail(artifactId)
    if (error || !data || data.feature !== 'cash_voucher_ocr') return
    if (data.status !== 'pending') {
      ElMessage.info('该识别任务已处理，已为你保留收付款台账页面')
      return
    }
    await dialogRef.value?.handleOpenFromOcr?.(toCashVoucherOcrAnalyzeResponse(data))
  }

  function syncCustomerDeleteRoute(forceRefresh = false): void {
    const context = customerDeleteContext.value
    if (!context.active) return
    const changed =
      table.searchQuery.customerId !== context.customerId ||
      table.searchQuery.carrierId !== context.carrierId ||
      table.searchQuery.recordId !== context.recordId
    Object.assign(table.searchQuery, {
      customerId: context.customerId,
      carrierId: context.carrierId,
      recordId: context.recordId
    })
    if (changed || forceRefresh) {
      void nextTick().then(() => tableQueryRef.value?.getData())
    }
  }

  watch(
    () => route.fullPath,
    () => syncCustomerDeleteRoute(),
    { flush: 'post' }
  )

  watch(
    () => [route.query.direction, route.query.status] as const,
    ([direction, status]) => {
      let changed = false
      if (typeof direction === 'string' && table.searchQuery.direction !== direction) {
        table.searchQuery.direction = direction
        changed = true
      }
      if (typeof status === 'string' && table.searchQuery.status !== status) {
        table.searchQuery.status = status
        changed = true
      }
      if (changed) void tableQueryRef.value?.getData()
    }
  )

  onActivated(() => syncCustomerDeleteRoute(true))

  onMounted(() => {
    void loadCustomerOptions()
    void loadCarrierOptions()
    void restoreRecognitionDraft()
  })
</script>
