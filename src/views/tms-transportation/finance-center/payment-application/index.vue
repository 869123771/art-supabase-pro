<template>
  <div class="tms-workspace-page art-full-height">
    <CustomerDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已自动定位付款申请；请按审批和财务规则处理后返回。"
    />
    <TmsWorkspaceHeader
      eyebrow="PAYMENT APPROVAL"
      title="付款申请"
      description="管理承运商付款申请、审核流转与执行结果，保障付款依据、金额和状态一致。"
      icon="ri:secure-payment-line"
      :tags="[
        { label: '付款审批', type: 'primary' },
        { label: '执行可追踪', type: 'warning' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 92, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无付款申请',
        emptyDescription: '可新建付款申请，或调整承运商、状态、申请人和日期后查询。'
      }"
      focusable
    />

    <PaymentApplicationDialog ref="dialogRef" @success="handleSaveSuccess" />
    <PaymentApplicationExecuteDialog ref="executeDialogRef" @success="handleExecuteSuccess" />
    <PaymentApplicationDetailDrawer ref="drawerRef" />
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
    cancelCarrierPaymentApplication,
    deleteCarrierPaymentApplication,
    exportCarrierPaymentApplicationList,
    fetchCarrierOptions,
    fetchCarrierPaymentApplicationList,
    submitCarrierPaymentApplication
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import PaymentApplicationDialog from './modules/payment-application-dialog.vue'
  import PaymentApplicationExecuteDialog from './modules/payment-application-execute-dialog.vue'
  import PaymentApplicationDetailDrawer from './modules/payment-application-detail-drawer.vue'
  import { useCustomerDeleteProcessingContext } from '@/views/tms-transportation/modules/use-customer-delete-processing'
  import CustomerDeleteProcessingNotice from '@/views/tms-transportation/modules/customer-delete-processing-notice.vue'

  defineOptions({ name: 'TmsCarrierPaymentApplication' })

  type Application = Api.Tms.Finance.CarrierPaymentApplicationRecord
  type SearchParams = Api.Tms.Finance.CarrierPaymentApplicationSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Application) => Promise<void>
  }

  interface ExecuteDialogExpose {
    handleOpen: (row: Application) => Promise<void>
  }

  interface DrawerExpose {
    handleOpen: (row: Application) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    carrierOptions: Array<{ label: string; value: string }>
  }

  const route = useRoute()
  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const { confirmAction, confirmDelete, promptReason } = useArtFeedback()
  const deleteContext = useCustomerDeleteProcessingContext()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const executeDialogRef = ref<ExecuteDialogExpose>()
  const drawerRef = ref<DrawerExpose>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      carrierId: deleteContext.value.carrierId,
      recordId: deleteContext.value.recordId,
      status: typeof route.query.status === 'string' ? route.query.status : '',
      plannedPaymentDateRange: [],
      keyword: ''
    },
    carrierOptions: [],
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '付款承运商',
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
        label: '申请状态',
        key: 'status',
        type: 'select',
        props: {
          options: getDictMap.value.tmsCarrierPaymentApplicationStatus ?? [],
          clearable: true
        }
      },
      {
        label: '计划付款日',
        key: 'plannedPaymentDateRange',
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
          placeholder: '申请单号、承运商、对账单或付款流水'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        label: '新建付款申请',
        onClick: () => void dialogRef.value?.handleOpen()
      },
      {
        type: 'export',
        exportFilename: 'TMS承运商付款申请',
        exportSheetName: '承运商付款申请',
        exportColumns: excelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportCarrierPaymentApplicationList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ])
  })

  const columnsFactory = (): ColumnOption<Application>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'applicationNo', label: '付款申请单号', width: 190 },
    { prop: 'carrierName', label: '付款承运商', minWidth: 190, showOverflowTooltip: true },
    {
      prop: 'amount',
      label: '申请金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.amount)
    },
    {
      prop: 'plannedPaymentDate',
      label: '计划付款日',
      width: 120
    },
    {
      prop: 'statementCount',
      label: '对账单',
      width: 90,
      align: 'center',
      formatter: (row) => `${row.statementCount} 份`
    },
    {
      prop: 'paymentMethod',
      label: '付款方式',
      width: 115,
      dict: { code: 'tmsCashPaymentMethod', display: 'text' }
    },
    {
      prop: 'status',
      label: '申请状态',
      width: 130,
      dict: { code: 'tmsCarrierPaymentApplicationStatus', display: 'tag' }
    },
    {
      prop: 'paidTransactionNo',
      label: '付款流水号',
      minWidth: 175,
      showOverflowTooltip: true
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 285,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
            查看
          </ElButton>
          {['draft', 'rejected'].includes(row.status) && (
            <>
              <ElButton link type="primary" onClick={() => void handleSubmit(row)}>
                提交审批
              </ElButton>
              <ElButton link type="primary" onClick={() => void dialogRef.value?.handleOpen(row)}>
                编辑
              </ElButton>
              <ElButton link type="danger" onClick={() => void handleDelete(row)}>
                删除
              </ElButton>
            </>
          )}
          {row.status === 'pending_review' && (
            <ElButton link type="primary" onClick={() => void openApprovalCenter()}>
              查看审批
            </ElButton>
          )}
          {row.status === 'approved' && (
            <>
              <ElButton
                link
                type="success"
                onClick={() => void executeDialogRef.value?.handleOpen(row)}
              >
                付款登记
              </ElButton>
              <ElButton link type="danger" onClick={() => void handleCancel(row)}>
                取消
              </ElButton>
            </>
          )}
          {row.status === 'paid' && row.paidTransactionNo && (
            <ElButton link type="primary" onClick={() => void openCashTransaction(row)}>
              查看付款
            </ElButton>
          )}
        </div>
      )
    }
  ]

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'applicationNo', title: '付款申请单号' },
    { key: 'carrierName', title: '付款承运商' },
    { key: 'plannedPaymentDate', title: '计划付款日期' },
    { key: 'amount', title: '申请金额' },
    { key: 'statementCount', title: '对账单数' },
    { key: 'statementNos', title: '关联对账单' },
    { key: 'paymentMethod', title: '付款方式' },
    { key: 'status', title: '申请状态' },
    { key: 'paidTransactionNo', title: '付款流水号' },
    { key: 'createBy', title: '申请人' },
    { key: 'createTime', title: '创建时间' }
  ]

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCarrierPaymentApplicationList({ ...params, from, to })
  }

  async function handleSubmit(row: Application): Promise<void> {
    try {
      await confirmAction(
        `提交后将占用 ${formatCurrencyValue(row.amount)} 可付款额度，并进入审批流程。`,
        '提交付款审批',
        { confirmButtonText: '提交审批', type: 'warning' }
      )
      await submitCarrierPaymentApplication(row)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消或提交失败时保持当前列表状态。
    }
  }

  async function handleDelete(row: Application): Promise<void> {
    try {
      await confirmDelete(`确定删除付款申请 ${row.applicationNo} 吗？删除后无法恢复。`)
      await deleteCarrierPaymentApplication(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleCancel(row: Application): Promise<void> {
    try {
      const reason = await promptReason(
        '取消后将释放已占用的可付款额度，且不能再执行本申请。',
        '取消付款申请',
        {
          confirmButtonText: '确认取消',
          placeholder: '请填写取消原因',
          emptyMessage: '取消原因不能为空'
        }
      )
      await cancelCarrierPaymentApplication(row.id, reason)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  function openApprovalCenter(): void {
    void router.push({ name: 'WorkflowWorkbench' })
  }

  function openCashTransaction(row: Application): void {
    void router.push({
      name: 'TmsCashTransaction',
      query: { direction: 'payment', keyword: row.paidTransactionNo ?? '' }
    })
  }

  function handleSaveSuccess(): void {
    void tableQueryRef.value?.refreshCreate()
  }

  function handleExecuteSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  async function loadCarrierOptions(): Promise<void> {
    const { data } = await fetchCarrierOptions()
    table.carrierOptions = (data ?? []).map((item) => ({
      label: item.companyName,
      value: item.id
    }))
  }

  function syncMasterDeleteRoute(forceRefresh = false): void {
    const context = deleteContext.value
    if (!context.active || !context.carrierId) return
    const changed =
      table.searchQuery.carrierId !== context.carrierId ||
      table.searchQuery.recordId !== context.recordId
    Object.assign(table.searchQuery, {
      carrierId: context.carrierId,
      recordId: context.recordId,
      keyword: ''
    })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteRoute(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteRoute(true))

  onMounted(() => void loadCarrierOptions())
</script>
