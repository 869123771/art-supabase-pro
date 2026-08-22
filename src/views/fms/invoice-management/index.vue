<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="INVOICE OPERATIONS"
      title="发票管理"
      description="统一管理销项与进项发票、业务关联、识别校验和状态流转，提升票据合规性。"
      icon="ri:receipt-line"
      :tags="[
        { label: '票据台账', type: 'primary' },
        { label: '合规校验', type: 'success' }
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
      action-hint="已定位到关联发票。草稿可直接删除；已复核、已开具或已作废发票属于财务历史，应保留并停用客户。"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无发票记录',
        emptyDescription: '可新增或识别发票，或调整类型、状态、往来单位和日期后查询。'
      }"
      focusable
    />

    <InvoiceDialog ref="dialogRef" @success="handleSaveSuccess" />
    <InvoiceDetailDrawer ref="drawerRef" />
    <InvoiceComplianceAuditDrawer ref="auditDrawerRef" />
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
  } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    canViewField,
    formatSensitiveNumber,
    getFieldAccess,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'
  import { financePaths } from '@/router/business-paths'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'
  import InvoiceDialog from './modules/invoice-dialog.vue'
  import InvoiceComplianceAuditDrawer from './modules/invoice-compliance-audit-drawer.vue'
  import InvoiceDetailDrawer from './modules/invoice-detail-drawer.vue'

  defineOptions({ name: 'FinanceInvoiceManagement' })

  type Invoice = Api.Fms.InvoiceRecord
  type InvoiceFieldKey = Api.Fms.InvoiceFieldKey
  type SearchParams = Api.Fms.InvoiceSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Invoice) => Promise<void>
    handleOpenFromOcr: (
      result: Api.Fms.InvoiceOcrAnalyzeResponse,
      direction: Api.Fms.InvoiceDirection
    ) => Promise<void>
    handleOpenFromArtifact: (artifactId: string) => Promise<boolean>
  }

  interface DrawerExpose {
    handleOpen: (row: Invoice) => Promise<void>
  }

  interface AuditDrawerExpose {
    handleOpen: (data: { invoiceId: string; invoiceRecordNo: string }) => Promise<void>
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
  const { hasAuth } = useAuth()
  const route = useRoute()
  const customerDeleteContext = useMasterDataDeleteProcessingContext()
  const invoiceManagementPath = financePaths.invoiceManagement
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const auditDrawerRef = ref<AuditDrawerExpose>()
  const fieldAccess = ref<Api.Fms.InvoiceFieldAccessMap>({})
  const currentRows = ref<Invoice[]>([])
  let openedRouteArtifactId = ''

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      direction: typeof route.query.direction === 'string' ? route.query.direction : '',
      status: typeof route.query.status === 'string' ? route.query.status : '',
      invoiceType: '',
      customerId: customerDeleteContext.value.customerId,
      carrierId: customerDeleteContext.value.carrierId,
      recordId: customerDeleteContext.value.recordId,
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
        permission: 'FinanceInvoiceManagement:Add',
        type: 'add',
        label: '登记发票',
        onClick: () => void dialogRef.value?.handleOpen()
      },
      {
        permission: 'FinanceInvoiceManagement:Export',
        type: 'export',
        exportFilename: 'TMS发票台账',
        exportSheetName: '发票台账',
        exportColumns: excelColumns.value,
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

  const formatMoney = (value?: Api.Tms.BasicData.SensitiveNumber): string => {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
  }

  const renderStatusActions = (row: Invoice) => {
    if (row.status === 'draft')
      return (
        <>
          {hasAuth('FinanceInvoiceManagement:Edit') ? (
            <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
              编辑
            </ElButton>
          ) : null}
          {hasAuth('FinanceInvoiceManagement:Submit') ? (
            <ElButton link type="primary" onClick={() => void handleStatusAction(row, 'submit')}>
              提交复核
            </ElButton>
          ) : null}
          {hasAuth('FinanceInvoiceManagement:Delete') ? (
            <ElButton link type="danger" onClick={() => void handleDelete(row)}>
              删除
            </ElButton>
          ) : null}
        </>
      )
    if (row.status === 'pending_review')
      return (
        <>
          {hasAuth('FinanceInvoiceManagement:Approve') ? (
            <ElButton link type="success" onClick={() => void handleStatusAction(row, 'approve')}>
              审核通过
            </ElButton>
          ) : null}
          {hasAuth('FinanceInvoiceManagement:Reject') ? (
            <ElButton link type="danger" onClick={() => void handleRemarkAction(row, 'reject')}>
              驳回
            </ElButton>
          ) : null}
        </>
      )
    if (row.status === 'issued' || row.status === 'certified')
      return hasAuth('FinanceInvoiceManagement:Void') ? (
        <ElButton link type="danger" onClick={() => void handleRemarkAction(row, 'void')}>
          作废
        </ElButton>
      ) : null
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
    ...(canViewListField('invoiceAmounts')
      ? [
          {
            prop: 'totalAmount',
            label: '价税合计',
            width: 135,
            align: 'right' as const,
            formatter: (row: Invoice) => formatMoney(row.totalAmount)
          },
          {
            prop: 'linkedAmount',
            label: '已关联对账',
            width: 135,
            align: 'right' as const,
            formatter: (row: Invoice) => formatMoney(row.linkedAmount)
          },
          {
            prop: 'unlinkedAmount',
            label: '未关联金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: Invoice) => formatMoney(row.unlinkedAmount)
          }
        ]
      : []),
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
      width: 320,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          {hasAuth('FinanceInvoiceManagement:View') ? (
            <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
              查看
            </ElButton>
          ) : null}
          {row.status !== 'voided' &&
          hasAuth('FinanceInvoiceManagement:AiAudit') &&
          canAuditInvoice(row) ? (
            <ElButton
              link
              type="primary"
              onClick={() =>
                void auditDrawerRef.value?.handleOpen({
                  invoiceId: row.id,
                  invoiceRecordNo: row.invoiceNo || row.invoiceRecordNo
                })
              }
            >
              AI审核
            </ElButton>
          ) : null}
          {renderStatusActions(row)}
        </div>
      )
    }
  ]

  const excelColumns = computed<ArtTableQueryExcelColumn[]>(() => [
    { key: 'invoiceRecordNo', title: '登记单号' },
    { key: 'invoiceNo', title: '发票号码' },
    { key: 'direction', title: '方向' },
    { key: 'invoiceType', title: '发票类型' },
    { key: 'counterpartyNameSnapshot', title: '往来单位' },
    { key: 'invoiceTitle', title: '发票抬头' },
    ...(canViewListField('taxIdentity') ? [{ key: 'taxNumber', title: '税号' }] : []),
    { key: 'issueDate', title: '开票日期' },
    ...(canViewListField('invoiceAmounts')
      ? [
          { key: 'amountExcludingTax', title: '不含税金额' },
          { key: 'taxAmount', title: '税额' },
          { key: 'totalAmount', title: '价税合计' },
          { key: 'linkedAmount', title: '已关联对账金额' },
          { key: 'unlinkedAmount', title: '未关联金额' }
        ]
      : []),
    { key: 'status', title: '状态' }
  ])

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchInvoiceList({ ...params, from, to })
    const previousVisibility = getSensitiveColumnVisibility()
    fieldAccess.value = result.fieldAccess
    currentRows.value = result.data
    if (previousVisibility !== getSensitiveColumnVisibility()) {
      await nextTick()
      tableQueryRef.value?.resetColumns()
    }
    return result
  }

  const canViewListField = (field: InvoiceFieldKey): boolean =>
    canViewField(
      mergeFieldAccessMaps(fieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess)),
      field
    )

  const getSensitiveColumnVisibility = (): string =>
    `${canViewListField('invoiceAmounts')}:${canViewListField('taxIdentity')}`

  const canAuditInvoice = (row: Invoice): boolean =>
    isReadableAccess(getFieldAccess(row.fieldAccess, 'invoiceAmounts')) &&
    isReadableAccess(getFieldAccess(row.fieldAccess, 'taxIdentity')) &&
    isReadableAccess(getFieldAccess(row.fieldAccess, 'invoiceAttachments'))

  const isReadableAccess = (access: Api.Tms.BasicData.FieldAccessLevel): boolean =>
    access === 'read' || access === 'edit'

  async function handleStatusAction(row: Invoice, statusAction: Api.Fms.InvoiceStatusAction) {
    const label = statusAction === 'submit' ? '提交复核' : '审核通过'
    try {
      await confirmAction(`确定${label}发票 ${row.invoiceNo || row.invoiceRecordNo} 吗？`, label, {
        type: 'warning'
      })
      await updateInvoiceStatus({
        id: row.id,
        action: statusAction,
        businessTitle: `发票 ${row.invoiceNo || row.invoiceRecordNo}`
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消或业务校验未通过
    }
  }

  async function handleRemarkAction(
    row: Invoice,
    statusAction: Extract<Api.Fms.InvoiceStatusAction, 'reject' | 'void'>
  ) {
    const label = statusAction === 'reject' ? '驳回发票' : '作废发票'
    try {
      const reason = await promptReason(`请填写${label}原因`, label, {
        confirmButtonText: statusAction === 'reject' ? '确认驳回' : '确认作废',
        placeholder: `请填写${label}原因`
      })
      await updateInvoiceStatus({
        id: row.id,
        action: statusAction,
        remark: reason,
        businessTitle: `发票 ${row.invoiceNo || row.invoiceRecordNo}`
      })
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

  function getRouteArtifactId(): string {
    return typeof route.query.aiArtifactId === 'string' ? route.query.aiArtifactId : ''
  }

  function isCurrentRecognitionRoute(artifactId: string): boolean {
    return route.path === invoiceManagementPath && getRouteArtifactId() === artifactId
  }

  async function restoreRecognitionDraft(artifactId: string): Promise<void> {
    openedRouteArtifactId = artifactId
    await nextTick()
    if (!isCurrentRecognitionRoute(artifactId)) return
    const restored = await dialogRef.value?.handleOpenFromArtifact(artifactId)
    if (!restored && isCurrentRecognitionRoute(artifactId)) openedRouteArtifactId = ''
  }

  function syncRecognitionRouteContext(): void {
    if (route.path !== invoiceManagementPath) {
      openedRouteArtifactId = ''
      return
    }

    const artifactId = getRouteArtifactId()
    if (!artifactId || artifactId === openedRouteArtifactId) return
    void restoreRecognitionDraft(artifactId)
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
    () => {
      syncRecognitionRouteContext()
      syncCustomerDeleteRoute()
    },
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

  onActivated(() => {
    syncRecognitionRouteContext()
    syncCustomerDeleteRoute(true)
  })

  onMounted(() => {
    void loadCounterpartyOptions()
    syncRecognitionRouteContext()
  })
</script>
