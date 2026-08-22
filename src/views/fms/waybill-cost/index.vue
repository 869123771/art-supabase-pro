<template>
  <div
    class="waybill-cost business-workspace-page art-full-height"
    :class="{ 'is-focus-mode': focusMode }"
  >
    <div class="waybill-cost__page-content">
      <MasterDeleteProcessingNotice
        action-hint="当前费用已自动定位；请按审核、报销或支付状态完成处理。"
      />
      <BusinessWorkspaceHeader
        :eyebrow="pageIdentity.eyebrow"
        :title="pageIdentity.title"
        :description="pageIdentity.description"
        :icon="pageIdentity.icon"
        :metrics="metrics"
        @metric-click="handleMetricClick"
      >
        <template #actions>
          <BusinessTableWorkspaceActions :table="activeTableRef" />
        </template>
      </BusinessWorkspaceHeader>

      <nav class="waybill-cost__workflow art-card-xs" aria-label="运单费用处理流程">
        <ol>
          <li
            v-for="(step, index) in workflowSteps"
            :key="step.title"
            :class="{
              'is-complete': index + 1 < workflowStage,
              'is-current': index + 1 === workflowStage
            }"
            :aria-current="index + 1 === workflowStage ? 'step' : undefined"
          >
            <span class="waybill-cost__step-index">
              <ArtSvgIcon v-if="index + 1 < workflowStage" icon="ri:check-line" />
              <template v-else>{{ index + 1 }}</template>
            </span>
            <span class="waybill-cost__step-copy">
              <strong>{{ step.title }}</strong>
              <small>{{ step.description }}</small>
            </span>
            <ArtSvgIcon
              v-if="index < workflowSteps.length - 1"
              class="waybill-cost__step-arrow"
              icon="ri:arrow-right-s-line"
            />
          </li>
        </ol>
      </nav>

      <ElTabs v-model="activeTab" class="waybill-cost__tabs">
        <ElTabPane name="expense">
          <template #label>
            <span class="waybill-cost__tab-label">
              <ArtSvgIcon icon="ri:file-list-3-line" />
              <span>
                <strong>运单费用台账</strong>
                <small>费用采集、票据识别与财务审核</small>
              </span>
            </span>
          </template>

          <ArtTableQuery
            ref="expenseTableRef"
            v-model="expenseTable.search"
            v-model:focus-mode="expenseFocusMode"
            :search-items="expenseTable.searchItems"
            :api-fn="fetchExpenseTableData"
            :columns-factory="expenseColumnsFactory"
            :header-actions="expenseTable.headerActions"
            header-actions-placement="workspace"
            :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
            :table-props="{
              rowKey: 'id',
              tableLayout: 'fixed',
              emptyHeight: '224px',
              emptyText: '暂无运单费用',
              emptyDescription: '可新增首笔费用，或调整费用项目、审核和核销条件后查询。'
            }"
            focusable
          />
        </ElTabPane>

        <ElTabPane name="reimbursement">
          <template #label>
            <span class="waybill-cost__tab-label">
              <ArtSvgIcon icon="ri:secure-payment-line" />
              <span>
                <strong>费用报销与支付</strong>
                <small>费用归集、报销审批与出纳付款</small>
              </span>
            </span>
          </template>

          <ArtTableQuery
            ref="reimbursementTableRef"
            v-model="reimbursementTable.search"
            v-model:focus-mode="reimbursementFocusMode"
            :search-items="reimbursementTable.searchItems"
            :api-fn="fetchReimbursementTableData"
            :columns-factory="reimbursementColumnsFactory"
            :header-actions="reimbursementTable.headerActions"
            header-actions-placement="workspace"
            :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
            :table-props="{
              rowKey: 'id',
              tableLayout: 'fixed',
              emptyHeight: '224px',
              emptyText: '暂无费用报销单',
              emptyDescription: '已审核费用转为报销单后，将在这里继续完成审批与支付。'
            }"
            focusable
          />
        </ElTabPane>
      </ElTabs>
    </div>

    <WaybillExpenseDialog ref="expenseDialogRef" @success="handleExpenseSaved" />
    <ReimbursementDialog ref="reimbursementDialogRef" @success="handleReimbursementCreated" />
    <PaymentDialog ref="paymentDialogRef" @success="handlePaymentSuccess" />
    <OcrLogDrawer ref="ocrLogDrawerRef" />
    <WaybillCostAuditDrawer ref="costAuditDrawerRef" />
    <WorkflowBusinessHistoryDrawer ref="approvalHistoryRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage } from 'element-plus'
  import type { ComputedRef } from 'vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore from '@/components/core/forms/art-button-more/index.vue'
  import type { ButtonMoreItem } from '@/components/core/forms/art-button-more/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    deleteExpenseReimbursement,
    deleteWaybillCost,
    fetchExpenseReimbursementList,
    fetchExpenseItemTree,
    fetchWaybillCostList,
    fetchWaybillCostOverview,
    submitExpenseReimbursement,
    submitWaybillCost
  } from '@/api/fms'
  import { fetchRecognitionArtifactDetail } from '@/api/intelligent-recognition'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'
  import {
    canViewField,
    getFieldAccess,
    isMaskedValue,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'
  import {
    financeRouteNames,
    getExpenseReimbursementDetailPath,
    getWaybillCostDetailPath
  } from '@/router/business-paths'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import { toWaybillExpenseOcrAnalyzeResponse } from '@/utils/intelligent-recognition'
  import WaybillExpenseDialog from './modules/waybill-expense-dialog.vue'
  import ReimbursementDialog from './modules/reimbursement-dialog.vue'
  import PaymentDialog from './modules/payment-dialog.vue'
  import OcrLogDrawer from './modules/ocr-log-drawer.vue'
  import WaybillCostAuditDrawer from './modules/waybill-cost-audit-drawer.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import WorkflowBusinessHistoryDrawer from '@/components/business/workflow-business-history/workflow-business-history-drawer.vue'
  import type { WorkflowBusinessHistoryDrawerExpose } from '@/components/business/workflow-business-history/types'
  import { validateReimbursementSelection } from './modules/reimbursement-selection'

  defineOptions({ name: 'FinanceWaybillCost' })

  type Expense = Api.Fms.WaybillCostRecord
  type ExpenseSearch = Api.Fms.WaybillCostSearchParams
  type ExpenseTableParams = ExpenseSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type Reimbursement = Api.Fms.ExpenseReimbursementRecord
  type ReimbursementSearch = Api.Fms.ExpenseReimbursementSearchParams
  type ReimbursementTableParams = ReimbursementSearch &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type WorkspaceMetricKey =
    'all-expenses' | 'pending-review' | 'ready-reimbursement' | 'pending-payment'

  interface ExpenseTableGroup {
    search: ExpenseSearch
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  interface ReimbursementTableGroup {
    search: ReimbursementSearch
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  interface ExpenseDialogExpose {
    handleOpen: (data?: {
      row?: Expense
      orderId?: string
      ocrResult?: Api.Fms.WaybillExpenseOcrAnalyzeResponse
    }) => Promise<void>
  }

  interface ReimbursementDialogExpose {
    handleOpen: (expenses: Expense[]) => Promise<void>
  }

  interface PaymentDialogExpose {
    handleOpen: (row: Reimbursement) => Promise<void>
  }

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const { confirmAction } = useArtFeedback()
  const { hasAuth } = useAuth()
  const activeTab = ref<'expense' | 'reimbursement'>(
    route.name === financeRouteNames.expenseReimbursement ? 'reimbursement' : 'expense'
  )
  const expenseFocusMode = ref(false)
  const reimbursementFocusMode = ref(false)
  const overviewLoading = ref(true)
  const expenseFieldAccess = ref<Api.Fms.WaybillCostFieldAccessMap>({})
  const reimbursementBaseFieldAccess = ref<Api.Fms.ExpenseReimbursementFieldAccessMap>({})
  const reimbursementFieldAccess = ref<Api.Fms.ExpenseReimbursementFieldAccessMap>({})
  const focusMode = computed(() =>
    activeTab.value === 'expense' ? expenseFocusMode.value : reimbursementFocusMode.value
  )
  const expenseTableRef = ref<ArtTableQueryExpose>()
  const reimbursementTableRef = ref<ArtTableQueryExpose>()
  watch(
    () => [
      canViewField(expenseFieldAccess.value, 'costAmounts'),
      canViewField(expenseFieldAccess.value, 'paymentDetails')
    ],
    (nextVisibility, previousVisibility) => {
      if (nextVisibility.every((value, index) => value === previousVisibility?.[index])) return
      void nextTick(() => expenseTableRef.value?.resetColumns())
    }
  )
  watch(
    () => [
      canViewField(reimbursementFieldAccess.value, 'reimbursementAmounts'),
      canViewField(reimbursementFieldAccess.value, 'payeeDetails'),
      canViewField(reimbursementFieldAccess.value, 'paymentExecution')
    ],
    (nextVisibility, previousVisibility) => {
      if (nextVisibility.every((value, index) => value === previousVisibility?.[index])) return
      void nextTick(() => reimbursementTableRef.value?.resetColumns())
    }
  )
  const activeTableRef = computed(() =>
    activeTab.value === 'expense' ? expenseTableRef.value : reimbursementTableRef.value
  )
  const expenseDialogRef = ref<ExpenseDialogExpose>()
  const reimbursementDialogRef = ref<ReimbursementDialogExpose>()
  const paymentDialogRef = ref<PaymentDialogExpose>()
  const ocrLogDrawerRef = ref<{ handleOpen: () => Promise<void> }>()
  const costAuditDrawerRef = ref<{
    handleOpen: (data: { costId: string; waybillNo: string }) => Promise<void>
  }>()
  const approvalHistoryRef = ref<WorkflowBusinessHistoryDrawerExpose>()
  const overview = reactive<Api.Fms.WaybillCostOverview>({
    totalCount: 0,
    pendingReviewCount: 0,
    approvedUnconvertedCount: 0,
    pendingPaymentAmount: 0,
    paidAmount: 0
  })
  const pageIdentity = computed(() =>
    activeTab.value === 'expense'
      ? {
          eyebrow: '运单成本闭环',
          title: '运单费用',
          description:
            '统一登记承运、在途与其他项目费用，从票据识别、审核到报销付款形成完整成本台账。',
          icon: 'ri:money-cny-circle-line'
        }
      : {
          eyebrow: '费用报销闭环',
          title: '费用报销单',
          description: '汇总同一运单的已审费用，集中完成报销审批、出纳付款与逐笔核销。',
          icon: 'ri:refund-2-line'
        }
  )

  const workflowSteps = [
    { title: '费用上报', description: '绑定运单并上传票据' },
    { title: '财务审核', description: '按配置流程审批' },
    { title: '转报销单', description: '可合并多笔已审费用' },
    { title: '出纳支付', description: '登记凭证并逐笔核销' }
  ]
  const workflowStage = computed(() => {
    if (activeTab.value === 'reimbursement') {
      return reimbursementTable.search.status === 'approved' ? 4 : 3
    }
    if (
      expenseTable.search.auditStatus === 'approved' &&
      expenseTable.search.settlementStatus === 'unsettled'
    ) {
      return 3
    }
    return expenseTable.search.auditStatus === 'pending_review' ? 2 : 1
  })
  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const items: BusinessWorkspaceMetric[] = [
      {
        key: 'all-expenses',
        label: '费用总笔数',
        value: `${overview.totalCount} 笔`,
        description: '查看全部运单费用',
        icon: 'ri:file-list-3-line',
        tone: 'primary',
        interactive: true,
        selected:
          activeTab.value === 'expense' &&
          !expenseTable.search.auditStatus &&
          !expenseTable.search.settlementStatus,
        loading: overviewLoading.value
      },
      {
        key: 'pending-review',
        label: '待财务审核',
        value: `${overview.pendingReviewCount} 笔`,
        description: '点击筛选待审费用',
        icon: 'ri:time-line',
        tone: 'warning',
        interactive: true,
        selected:
          activeTab.value === 'expense' && expenseTable.search.auditStatus === 'pending_review',
        loading: overviewLoading.value
      },
      {
        key: 'ready-reimbursement',
        label: '待转报销',
        value: `${overview.approvedUnconvertedCount} 笔`,
        description: '点击选择已审费用',
        icon: 'ri:exchange-cny-line',
        tone: 'success',
        interactive: true,
        selected:
          activeTab.value === 'expense' &&
          expenseTable.search.auditStatus === 'approved' &&
          expenseTable.search.settlementStatus === 'unsettled',
        loading: overviewLoading.value
      }
    ]
    if (canViewField(overview.fieldAccess, 'costAmounts')) {
      items.push({
        key: 'pending-payment',
        label: '待支付金额',
        value: money(overview.pendingPaymentAmount),
        description: `进入付款队列 · 已付 ${money(overview.paidAmount)}`,
        icon: 'ri:secure-payment-line',
        tone: 'danger',
        interactive: true,
        selected:
          activeTab.value === 'reimbursement' && reimbursementTable.search.status === 'approved',
        loading: overviewLoading.value
      })
    }
    return items
  })

  const expenseTable = reactive<ExpenseTableGroup>({
    search: {
      recordId:
        route.query.fromMasterDelete === '1' && typeof route.query.recordId === 'string'
          ? route.query.recordId
          : '',
      orderId:
        route.query.fromMasterDelete === '1' && typeof route.query.orderId === 'string'
          ? route.query.orderId
          : '',
      keyword: '',
      expenseItemId: '',
      auditStatus: typeof route.query.auditStatus === 'string' ? route.query.auditStatus : '',
      settlementStatus: '',
      occurredOnRange: []
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '费用项目',
        key: 'expenseItemId',
        type: 'treeSelect',
        api: fetchExpenseItemTree,
        labelField: 'itemName',
        valueField: 'id',
        childrenField: 'children',
        props: { clearable: true, checkStrictly: true, defaultExpandAll: true }
      },
      {
        label: '审核状态',
        key: 'auditStatus',
        type: 'select',
        props: { options: getDictMap.value.tmsCostAuditStatus ?? [], clearable: true }
      },
      {
        label: '核销状态',
        key: 'settlementStatus',
        type: 'select',
        props: { options: getDictMap.value.tmsWaybillCostSettlementStatus ?? [], clearable: true }
      },
      {
        label: '发生日期',
        key: 'occurredOnRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          style: { width: '100%' }
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '费用单、运单、车牌、司机、票号' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        auth: 'FinanceWaybillCost:OcrLogs',
        key: 'ocrLogs',
        label: 'OCR 识别记录',
        buttonProps: { plain: true },
        onClick: () => void ocrLogDrawerRef.value?.handleOpen()
      },
      {
        permission: 'FinanceWaybillCost:Add',
        type: 'add',
        label: '新增运单费用',
        onClick: () => openExpenseDialog()
      },
      {
        auth: 'FinanceWaybillCost:Convert',
        key: 'convert',
        label: '转费用报销',
        selectionRequired: true,
        buttonProps: {
          type: 'primary',
          plain: true,
          title: '支持单选，或多选同一个运单下的已审费用'
        },
        onClick: ({ selectedRows }) => handleReimbursementSelection(selectedRows as Expense[])
      }
    ])
  })

  const reimbursementTable = reactive<ReimbursementTableGroup>({
    search: { keyword: '', status: '', paymentMethod: '', plannedPaymentDateRange: [] },
    searchItems: computed<SearchFormItem[]>(() => {
      const items: SearchFormItem[] = [
        {
          label: '审批状态',
          key: 'status',
          type: 'select',
          props: { options: getDictMap.value.tmsReimbursementApprovalStatus ?? [], clearable: true }
        }
      ]
      if (
        ['read', 'edit'].includes(
          getFieldAccess(reimbursementBaseFieldAccess.value, 'payeeDetails')
        )
      ) {
        items.push({
          label: '付款方式',
          key: 'paymentMethod',
          type: 'select',
          props: { options: getDictMap.value.tmsCashPaymentMethod ?? [], clearable: true }
        })
      }
      items.push(
        {
          label: '计划付款日',
          key: 'plannedPaymentDateRange',
          type: 'date',
          props: {
            type: 'daterange',
            valueFormat: 'YYYY-MM-DD',
            startPlaceholder: '开始日期',
            endPlaceholder: '结束日期',
            style: { width: '100%' }
          }
        },
        {
          label: '关键词',
          key: 'keyword',
          type: 'input',
          props: {
            clearable: true,
            placeholder: ['read', 'edit'].includes(
              getFieldAccess(reimbursementBaseFieldAccess.value, 'payeeDetails')
            )
              ? '报销单、申请人、收款人或运单'
              : '报销单、申请人、费用单或运单'
          }
        }
      )
      return items
    }),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        key: 'backToExpense',
        label: '选择已审费用',
        permission: 'FinanceWaybillCost:Convert',
        buttonProps: { type: 'primary', plain: true },
        onClick: openApprovedExpenses
      }
    ])
  })

  const expenseColumnsFactory = (): ColumnOption<Expense>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    {
      prop: 'costNo',
      label: '费用单号',
      width: 195,
      fixed: 'left',
      formatter: (row) =>
        row.id ? (
          <a
            class="waybill-cost__document-link"
            href={router.resolve(getWaybillCostDetailPath(row.id)).href}
            title={`查看费用单 ${row.costNo || row.id} 详情`}
            onClick={(event: MouseEvent) => navigateToExpenseDetail(event, row.id as string)}
          >
            {row.costNo || '--'}
          </a>
        ) : (
          <span>{row.costNo || '--'}</span>
        )
    },
    { prop: 'waybillNoSnapshot', label: '运单号', width: 180, fixed: 'left' },
    {
      prop: 'plateNoSnapshot',
      label: '车牌号',
      width: 120,
      formatter: (row) => emptyText(row.plateNoSnapshot)
    },
    {
      prop: 'driverNameSnapshot',
      label: '司机',
      width: 110,
      formatter: (row) => emptyText(row.driverNameSnapshot)
    },
    {
      prop: 'expenseItem.itemName',
      label: '费用项目',
      width: 150,
      formatter: (row) => emptyText(row.expenseItem?.itemName)
    },
    ...(canViewField(expenseFieldAccess.value, 'costAmounts')
      ? [
          {
            prop: 'amount',
            label: '申报金额',
            width: 130,
            align: 'right' as const,
            formatter: (row: Expense) => money(row.amount)
          }
        ]
      : []),
    {
      prop: 'occurredOn',
      label: '发生日期',
      width: 115,
      formatter: (row) => formatWithDayjs(row.occurredOn, 'YYYY-MM-DD')
    },
    ...(canViewField(expenseFieldAccess.value, 'paymentDetails')
      ? [
          {
            prop: 'providerName',
            label: '服务商',
            minWidth: 150,
            showOverflowTooltip: true,
            formatter: (row: Expense) => emptyText(row.providerName)
          }
        ]
      : []),
    {
      prop: 'auditStatus',
      label: '审核状态',
      width: 110,
      dict: { code: 'tmsCostAuditStatus', display: 'tag' }
    },
    {
      prop: 'settlementStatus',
      label: '核销状态',
      width: 105,
      dict: { code: 'tmsWaybillCostSettlementStatus', display: 'tag' }
    },
    {
      prop: 'ocrStatus',
      label: 'OCR',
      width: 105,
      dict: { code: 'tmsExpenseOcrStatus', display: 'tag' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="waybill-cost__row-actions">
          <ArtButtonTable
            type="edit"
            permission="FinanceWaybillCost:Edit"
            disabled={!canEditExpense(row)}
            onClick={() => openExpenseDialog(row)}
          />
          <ArtButtonMore
            list={expenseMoreActions(row)}
            onClick={(item: ButtonMoreItem) => handleExpenseAction(item, row)}
          />
        </div>
      )
    }
  ]

  const reimbursementColumnsFactory = (): ColumnOption<Reimbursement>[] => [
    {
      prop: 'reimbursementNo',
      label: '报销单号',
      width: 200,
      fixed: 'left',
      formatter: (row) =>
        row.id ? (
          <a
            class="waybill-cost__document-link"
            href={router.resolve(getExpenseReimbursementDetailPath(row.id)).href}
            title={`查看报销单 ${row.reimbursementNo} 详情`}
            onClick={(event: MouseEvent) => navigateToReimbursementDetail(event, row.id)}
          >
            {row.reimbursementNo || '--'}
          </a>
        ) : (
          <span>{row.reimbursementNo || '--'}</span>
        )
    },
    { prop: 'applicantNameSnapshot', label: '申请人', width: 115 },
    ...(canViewField(reimbursementFieldAccess.value, 'payeeDetails')
      ? [
          {
            prop: 'payeeName',
            label: '收款人',
            minWidth: 150,
            showOverflowTooltip: true
          }
        ]
      : []),
    { prop: 'waybillNos', label: '关联运单', minWidth: 210, showOverflowTooltip: true },
    { prop: 'itemCount', label: '费用笔数', width: 95, align: 'center' },
    ...(canViewField(reimbursementFieldAccess.value, 'reimbursementAmounts')
      ? [
          {
            prop: 'totalAmount',
            label: '报销金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: Reimbursement) => money(row.totalAmount)
          }
        ]
      : []),
    ...(canViewField(reimbursementFieldAccess.value, 'payeeDetails')
      ? [
          {
            prop: 'paymentMethod',
            label: '付款方式',
            width: 115,
            dict: { code: 'tmsCashPaymentMethod', display: 'tag' as const }
          }
        ]
      : []),
    { prop: 'plannedPaymentDate', label: '计划付款日', width: 120 },
    {
      prop: 'status',
      label: '审批/支付状态',
      width: 135,
      dict: { code: 'tmsReimbursementApprovalStatus', display: 'tag' }
    },
    ...(canViewField(reimbursementFieldAccess.value, 'paymentExecution')
      ? [
          {
            prop: 'paymentNo',
            label: '付款单号',
            width: 195,
            formatter: (row: Reimbursement) => emptyText(row.paymentNo)
          }
        ]
      : []),
    {
      prop: 'createTime',
      label: '创建时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 160,
      fixed: 'right',
      formatter: (row) => (
        <div class="waybill-cost__row-actions">
          <ArtButtonTable
            type="view"
            permission="FinanceWaybillCost:View"
            onClick={() => openReimbursementDetail(row)}
          />
          <ArtButtonMore
            list={reimbursementMoreActions(row)}
            onClick={(item: ButtonMoreItem) => handleReimbursementAction(item, row)}
          />
        </div>
      )
    }
  ]

  async function fetchExpenseTableData(params: ExpenseTableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchWaybillCostList({ ...params, from, to })
    expenseFieldAccess.value = mergeFieldAccessMaps(
      result.fieldAccess,
      ...(result.data ?? []).map((row) => row.fieldAccess)
    )
    return result
  }

  async function fetchReimbursementTableData(params: ReimbursementTableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchExpenseReimbursementList({ ...params, from, to })
    reimbursementBaseFieldAccess.value = result.fieldAccess
    reimbursementFieldAccess.value = mergeFieldAccessMaps(
      result.fieldAccess,
      ...(result.data ?? []).map((row) => row.fieldAccess)
    )
    return result
  }

  function navigateToExpenseDetail(event: MouseEvent, id: string): void {
    event.preventDefault()
    event.stopPropagation()
    window.location.assign(router.resolve(getWaybillCostDetailPath(id)).href)
  }

  function openExpenseDetail(row: Expense): void {
    if (!row.id) return
    window.location.assign(router.resolve(getWaybillCostDetailPath(row.id)).href)
  }

  function navigateToReimbursementDetail(event: MouseEvent, id: string): void {
    event.preventDefault()
    event.stopPropagation()
    window.location.assign(router.resolve(getExpenseReimbursementDetailPath(id)).href)
  }

  function openReimbursementDetail(row: Reimbursement): void {
    window.location.assign(router.resolve(getExpenseReimbursementDetailPath(row.id)).href)
  }

  function emptyText(value: unknown): string {
    return String(value || '--')
  }

  function money(value?: Api.Tms.BasicData.SensitiveNumber): string {
    if (isMaskedValue(value)) return value
    if (value === null || value === undefined) return '--'
    const numericValue = Number(value)
    return Number.isFinite(numericValue) ? formatCurrencyValue(numericValue) : '--'
  }

  function canEditExpense(row: Expense): boolean {
    return (
      ['draft', 'rejected'].includes(String(row.auditStatus)) &&
      row.settlementStatus === 'unsettled'
    )
  }

  function canConvert(row: Expense): boolean {
    return (
      Boolean(row.id) &&
      ['read', 'edit'].includes(getFieldAccess(row.fieldAccess, 'costAmounts')) &&
      row.auditStatus === 'approved' &&
      row.settlementStatus === 'unsettled' &&
      row.expenseItem?.reimbursementAllowed !== false
    )
  }

  function handleReimbursementSelection(expenses: Expense[]): void {
    const validation = validateReimbursementSelection(expenses)
    if (!validation.valid) {
      ElMessage.warning(validation.message)
      return
    }
    void reimbursementDialogRef.value?.handleOpen(expenses)
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    switch (metric.key) {
      case 'all-expenses':
      case 'pending-review':
      case 'ready-reimbursement':
      case 'pending-payment':
        void applyMetricFilter(metric.key)
    }
  }

  async function applyMetricFilter(key: WorkspaceMetricKey): Promise<void> {
    if (key === 'pending-payment') {
      activeTab.value = 'reimbursement'
      Object.assign(reimbursementTable.search, {
        keyword: '',
        status: 'approved',
        paymentMethod: '',
        plannedPaymentDateRange: []
      })
      await nextTick()
      await reimbursementTableRef.value?.getData()
      return
    }

    activeTab.value = 'expense'
    const statusFilters: Record<
      Exclude<WorkspaceMetricKey, 'pending-payment'>,
      Pick<ExpenseSearch, 'auditStatus' | 'settlementStatus'>
    > = {
      'all-expenses': { auditStatus: '', settlementStatus: '' },
      'pending-review': { auditStatus: 'pending_review', settlementStatus: '' },
      'ready-reimbursement': { auditStatus: 'approved', settlementStatus: 'unsettled' }
    }
    Object.assign(expenseTable.search, statusFilters[key])
    await nextTick()
    await expenseTableRef.value?.getData()
  }

  function openApprovedExpenses(): void {
    void applyMetricFilter('ready-reimbursement')
  }

  function expenseMoreActions(row: Expense): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      {
        auth: 'FinanceWaybillCost:View',
        key: 'view',
        label: '查看',
        icon: 'ri:eye-line',
        disabled: !row.id
      },
      {
        auth: 'FinanceWaybillCost:ApprovalHistory',
        key: 'approvalHistory',
        label: '审批记录',
        icon: 'ri:file-history-line'
      }
    ]
    const canReadAiEvidence = ['costAmounts', 'paymentDetails', 'expenseEvidence'].every((field) =>
      ['read', 'edit'].includes(
        getFieldAccess(row.fieldAccess, field as Api.Fms.WaybillCostFieldKey)
      )
    )
    if (canReadAiEvidence) {
      actions.splice(1, 0, {
        auth: 'FinanceWaybillCost:AiAudit',
        key: 'aiAudit',
        label: 'AI 费用审核',
        icon: 'ri:sparkling-2-line'
      })
    }
    if (
      canEditExpense(row) &&
      ['read', 'edit'].includes(getFieldAccess(row.fieldAccess, 'costAmounts'))
    ) {
      actions.push({
        auth: 'FinanceWaybillCost:Submit',
        key: 'submit',
        label: '提交财务审核',
        icon: 'ri:send-plane-line'
      })
      actions.push({
        auth: 'FinanceWaybillCost:Delete',
        key: 'delete',
        label: '删除草稿',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      })
    }
    if (canConvert(row)) {
      actions.push({
        auth: 'FinanceWaybillCost:Convert',
        key: 'convert',
        label: '转费用报销',
        icon: 'ri:exchange-cny-line'
      })
    }
    return actions
  }

  function reimbursementMoreActions(row: Reimbursement): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      {
        auth: 'FinanceWaybillCost:ApprovalHistory',
        key: 'approvalHistory',
        label: '审批记录',
        icon: 'ri:file-history-line'
      }
    ]
    if (['draft', 'rejected'].includes(row.status) && canSubmitReimbursement(row)) {
      actions.push({
        auth: 'FinanceWaybillCost:Submit',
        key: 'submit',
        label: '提交报销审批',
        icon: 'ri:send-plane-line'
      })
      actions.push({
        auth: 'FinanceWaybillCost:Delete',
        key: 'delete',
        label: '删除并退回费用',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      })
    }
    if (row.status === 'approved' && canPayReimbursement(row)) {
      actions.push({
        auth: 'FinanceWaybillCost:Pay',
        key: 'pay',
        label: '出纳付款',
        icon: 'ri:secure-payment-line'
      })
    }
    return actions
  }

  function canSubmitReimbursement(row: Reimbursement): boolean {
    return ['reimbursementAmounts', 'payeeDetails'].every((field) =>
      ['read', 'edit'].includes(
        getFieldAccess(row.fieldAccess, field as Api.Fms.ExpenseReimbursementFieldKey)
      )
    )
  }

  function canPayReimbursement(row: Reimbursement): boolean {
    return (
      canSubmitReimbursement(row) && getFieldAccess(row.fieldAccess, 'paymentExecution') === 'edit'
    )
  }

  function handleExpenseAction(item: ButtonMoreItem, row: Expense): void {
    const actions: Record<string, () => void> = {
      view: () => openExpenseDetail(row),
      submit: () => void handleExpenseSubmit(row),
      delete: () => void handleExpenseDelete(row),
      convert: () => handleReimbursementSelection([row]),
      aiAudit: () =>
        row.id
          ? void costAuditDrawerRef.value?.handleOpen({
              costId: row.id,
              waybillNo: row.waybillNoSnapshot || row.costNo || '运单费用'
            })
          : undefined,
      approvalHistory: () =>
        void openApprovalHistory('tms_waybill_cost', row.id, row.costNo || '运单费用')
    }
    actions[String(item.key)]?.()
  }

  function handleReimbursementAction(item: ButtonMoreItem, row: Reimbursement): void {
    const actions: Record<string, () => void> = {
      submit: () => void handleReimbursementSubmit(row),
      delete: () => void handleReimbursementDelete(row),
      pay: () => openPaymentDialog(row),
      approvalHistory: () =>
        void openApprovalHistory('tms_expense_reimbursement', row.id, row.reimbursementNo)
    }
    actions[String(item.key)]?.()
  }

  function openPaymentDialog(row: Reimbursement): void {
    if (!canPayReimbursement(row)) {
      ElMessage.warning('当前字段权限不足，无法读取报销金额、收款信息或登记付款结果')
      return
    }
    void paymentDialogRef.value?.handleOpen(row)
  }

  async function openApprovalHistory(
    businessType: 'tms_waybill_cost' | 'tms_expense_reimbursement',
    businessId: string | undefined,
    businessTitle: string
  ): Promise<void> {
    if (!businessId) return
    await approvalHistoryRef.value?.handleOpen({ businessType, businessId, businessTitle })
  }

  function openExpenseDialog(row?: Expense): void {
    if (row && !canEditExpense(row)) return
    void expenseDialogRef.value?.handleOpen({ row })
  }

  async function handleExpenseSubmit(row: Expense): Promise<void> {
    if (!row.id) return
    try {
      await confirmAction('提交后费用内容将锁定，并进入配置的财务审批流程。', '提交费用审核', {
        type: 'warning',
        confirmButtonText: '提交审核',
        cancelButtonText: '取消'
      })
      await submitWaybillCost(row.id)
      await Promise.all([expenseTableRef.value?.refreshUpdate(), loadOverview()])
    } catch {
      // User cancelled the confirmation.
    }
  }

  async function handleExpenseDelete(row: Expense): Promise<void> {
    if (!row.id) return
    try {
      await confirmAction('删除后票据与草稿关联将无法恢复。', '删除运单费用草稿', {
        type: 'warning',
        confirmButtonText: '确认删除',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteWaybillCost(row.id)
      await Promise.all([expenseTableRef.value?.refreshRemove(), loadOverview()])
    } catch {
      // User cancelled the confirmation.
    }
  }

  async function handleReimbursementSubmit(row: Reimbursement): Promise<void> {
    if (!canSubmitReimbursement(row)) {
      ElMessage.warning('当前字段权限不足，无法读取报销金额和收款信息并提交审批')
      return
    }
    try {
      await confirmAction('提交后报销内容将锁定，并进入配置的报销审批流程。', '提交报销审批', {
        type: 'warning',
        confirmButtonText: '提交审批',
        cancelButtonText: '取消'
      })
      await submitExpenseReimbursement(row)
      await reimbursementTableRef.value?.refreshUpdate()
    } catch {
      // User cancelled the confirmation.
    }
  }

  async function handleReimbursementDelete(row: Reimbursement): Promise<void> {
    try {
      await confirmAction('删除后，明细费用会退回“未转报销”状态。', '删除费用报销单', {
        type: 'warning',
        confirmButtonText: '删除并退回',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteExpenseReimbursement(row.id)
      await Promise.all([
        reimbursementTableRef.value?.refreshRemove(),
        expenseTableRef.value?.refreshUpdate(),
        loadOverview()
      ])
    } catch {
      // User cancelled the confirmation.
    }
  }

  function handleExpenseSaved(type: 'add' | 'edit'): void {
    void Promise.all([
      type === 'add'
        ? expenseTableRef.value?.refreshCreate()
        : expenseTableRef.value?.refreshUpdate(),
      loadOverview()
    ])
  }

  function handleReimbursementCreated(): void {
    activeTab.value = 'reimbursement'
    void nextTick(() =>
      Promise.all([
        reimbursementTableRef.value?.refreshCreate(),
        expenseTableRef.value?.refreshUpdate(),
        loadOverview()
      ])
    )
  }

  function handlePaymentSuccess(): void {
    void Promise.all([
      reimbursementTableRef.value?.refreshUpdate(),
      expenseTableRef.value?.refreshUpdate(),
      loadOverview()
    ])
  }

  async function loadOverview(): Promise<void> {
    overviewLoading.value = true
    try {
      const { data } = await fetchWaybillCostOverview()
      if (data) {
        Object.assign(overview, data, {
          pendingPaymentAmount: data.pendingPaymentAmount,
          paidAmount: data.paidAmount,
          fieldAccess: data.fieldAccess ?? {}
        })
      }
    } finally {
      overviewLoading.value = false
    }
  }

  async function openFromOrderQuery(): Promise<void> {
    const orderId = typeof route.query.orderId === 'string' ? route.query.orderId : ''
    if (!orderId) return
    if (route.query.fromMasterDelete === '1') {
      expenseTable.search.orderId = orderId
      expenseTable.search.recordId =
        typeof route.query.recordId === 'string' ? route.query.recordId : ''
      await nextTick()
      await expenseTableRef.value?.getData()
      return
    }
    await nextTick()
    await expenseDialogRef.value?.handleOpen({ orderId })
    const query = { ...route.query }
    delete query.orderId
    await router.replace({ query })
  }

  async function openFromRecognitionQuery(): Promise<void> {
    const artifactId =
      typeof route.query.aiArtifactId === 'string' ? route.query.aiArtifactId.trim() : ''
    if (!artifactId) return

    try {
      if (!hasAuth('FinanceWaybillCost:Add')) {
        ElMessage.warning('当前角色没有新增运单费用权限，可在识别记录中查看识别依据')
        return
      }

      const { data, error } = await fetchRecognitionArtifactDetail(artifactId)
      if (error) return
      if (!data) {
        ElMessage.warning('识别任务不存在或已无权访问')
        return
      }
      if (data.feature !== 'waybill_expense_ocr') {
        ElMessage.warning('该识别任务不属于运单费用票据')
        return
      }
      if (data.status !== 'pending') {
        ElMessage.warning('该识别任务已处理，请从识别记录查看最终结果')
        return
      }

      activeTab.value = 'expense'
      await nextTick()
      await expenseDialogRef.value?.handleOpen({
        ocrResult: toWaybillExpenseOcrAnalyzeResponse(data)
      })
    } finally {
      const query = { ...route.query }
      delete query.aiArtifactId
      await router.replace({ query })
    }
  }

  async function openFromRouteQuery(): Promise<void> {
    if (typeof route.query.aiArtifactId === 'string' && route.query.aiArtifactId.trim()) {
      await openFromRecognitionQuery()
      return
    }
    await openFromOrderQuery()
  }

  onMounted(() => {
    void Promise.all([userStore.fetchDictList(), loadOverview()])
  })

  watch(
    () => route.name,
    (name) => {
      if (name === financeRouteNames.waybillCost) activeTab.value = 'expense'
      if (name === financeRouteNames.expenseReimbursement) activeTab.value = 'reimbursement'
    }
  )

  watch(
    () => route.query.auditStatus,
    (value) => {
      if (typeof value !== 'string' || expenseTable.search.auditStatus === value) return
      activeTab.value = 'expense'
      expenseTable.search.auditStatus = value
      void expenseTableRef.value?.getData()
    }
  )

  watch(activeTab, (tab) => {
    const currentRouteName = String(route.name)
    if (
      currentRouteName !== financeRouteNames.waybillCost &&
      currentRouteName !== financeRouteNames.expenseReimbursement
    )
      return
    const targetName =
      tab === 'expense' ? financeRouteNames.waybillCost : financeRouteNames.expenseReimbursement
    if (route.name === targetName || !router.hasRoute(targetName)) return
    void router.replace({ name: targetName, query: route.query })
  })

  watch(
    () => route.fullPath,
    (fullPath) => {
      if (typeof fullPath === 'string' && fullPath) void openFromRouteQuery()
    },
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .waybill-cost {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-width: 0;
    min-height: 0;
    overflow: hidden;

    &.is-focus-mode {
      gap: 0;
    }

    &__page-content {
      display: flex;
      flex: 1 1 auto;
      flex-direction: column;
      gap: var(--art-space-3);
      min-width: 0;
      min-height: 0;
      overflow: hidden;
    }

    &__workflow {
      flex: 0 0 auto;
      min-width: 0;
      padding: var(--art-space-2) var(--art-space-4);

      ol {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        padding: 0;
        margin: 0;
        list-style: none;
      }

      li {
        position: relative;
        display: flex;
        gap: var(--art-space-2);
        align-items: center;
        min-width: 0;
        padding: var(--art-space-2);
        color: var(--art-text-gray-500);

        &.is-current {
          color: var(--theme-color);

          .waybill-cost__step-index {
            color: white;
            background: var(--theme-color);
            box-shadow: 0 6px 14px color-mix(in srgb, var(--theme-color) 22%, transparent);
          }

          strong {
            color: var(--art-text-gray-900);
          }
        }

        &.is-complete {
          .waybill-cost__step-index {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          strong {
            color: var(--art-text-gray-700);
          }
        }
      }
    }

    &__step-index {
      display: grid;
      flex: 0 0 28px;
      place-items: center;
      width: 28px;
      height: 28px;
      font-size: 12px;
      font-weight: 700;
      color: var(--art-text-gray-500);
      background: var(--el-fill-color-light);
      border-radius: 50%;
      transition:
        color 0.18s ease,
        background-color 0.18s ease,
        box-shadow 0.18s ease;
    }

    &__step-copy {
      display: flex;
      flex-direction: column;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-700);
      }

      small {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }
    }

    &__step-arrow {
      flex: 0 0 auto;
      margin-left: auto;
      color: var(--art-text-gray-300);
    }

    &__tabs {
      @include accounting.accounting-workspace-tabs;
    }

    &__tab-label {
      @include accounting.accounting-workspace-tab-label;
    }

    :deep(.waybill-cost__row-actions) {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }

    :deep(.waybill-cost__document-link) {
      display: inline-block;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 600;
      color: var(--theme-color);
      white-space: nowrap;
      text-decoration: none;

      &:hover {
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      &:focus-visible {
        outline: 2px solid var(--theme-color);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }

    @media (width <= 1100px) {
      &__workflow {
        ol {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        li:nth-child(2) .waybill-cost__step-arrow,
        li:last-child .waybill-cost__step-arrow {
          display: none;
        }
      }
    }

    @media (width <= 720px) {
      &__workflow {
        padding-inline: var(--art-space-2);

        ol {
          grid-template-columns: 1fr;
        }

        .waybill-cost__step-arrow {
          display: none;
        }
      }

      &__tab-label {
        > span small {
          display: none;
        }
      }
    }

    @media (width <= 640px) {
      overflow: visible;

      &__page-content {
        overflow: visible;
      }
    }

    @media (prefers-reduced-motion: reduce) {
      &__step-index {
        transition: none;
      }
    }
  }
</style>
