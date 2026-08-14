<template>
  <div class="waybill-cost art-full-height" :class="{ 'is-focus-mode': focusMode }">
    <MasterDeleteProcessingNotice
      action-hint="当前费用已自动定位；请按审核、报销或支付状态完成处理。"
    />
    <header
      v-if="!focusMode"
      class="waybill-cost__hero art-card-xs"
      aria-labelledby="waybill-cost-title"
    >
      <div class="waybill-cost__hero-copy">
        <span class="waybill-cost__hero-icon"><ArtSvgIcon :icon="pageIdentity.icon" /></span>
        <div>
          <span>{{ pageIdentity.eyebrow }}</span>
          <h1 id="waybill-cost-title">{{ pageIdentity.title }}</h1>
          <p>{{ pageIdentity.description }}</p>
        </div>
      </div>
      <div class="waybill-cost__hero-actions">
        <ElButton v-if="activeTab === 'expense'" plain @click="void ocrLogDrawerRef?.handleOpen()">
          <ArtSvgIcon icon="ri:file-search-line" /> OCR 识别记录
        </ElButton>
        <ElButton v-if="activeTab === 'expense'" type="primary" @click="openExpenseDialog()">
          <ArtSvgIcon icon="ri:add-line" /> 新增运单费用
        </ElButton>
        <ElButton v-else type="primary" @click="openApprovedExpenses">
          <ArtSvgIcon icon="ri:exchange-cny-line" /> 选择已审费用
        </ElButton>
      </div>
    </header>

    <section v-if="!focusMode" class="waybill-cost__metrics" aria-label="费用处理概览">
      <article v-for="metric in metrics" :key="metric.label" class="art-card-xs">
        <span :class="metric.tone"><ArtSvgIcon :icon="metric.icon" /></span>
        <div>
          <small>{{ metric.label }}</small>
          <strong>{{ metric.value }}</strong>
          <p>{{ metric.hint }}</p>
        </div>
      </article>
    </section>

    <nav v-if="!focusMode" class="waybill-cost__workflow art-card-xs" aria-label="运单费用处理流程">
      <div v-for="(step, index) in workflowSteps" :key="step.title">
        <span>{{ index + 1 }}</span>
        <div
          ><strong>{{ step.title }}</strong
          ><small>{{ step.description }}</small></div
        >
        <ArtSvgIcon v-if="index < workflowSteps.length - 1" icon="ri:arrow-right-s-line" />
      </div>
    </nav>

    <ElTabs v-if="!focusMode" v-model="activeTab" class="waybill-cost__tabs">
      <ElTabPane label="费用台账" name="expense" />
      <ElTabPane label="报销与支付" name="reimbursement" />
    </ElTabs>

    <ArtTableQuery
      v-show="activeTab === 'expense'"
      ref="expenseTableRef"
      v-model="expenseTable.search"
      v-model:focus-mode="expenseFocusMode"
      :search-items="expenseTable.searchItems"
      :api-fn="fetchExpenseTableData"
      :columns-factory="expenseColumnsFactory"
      :header-actions="expenseTable.headerActions"
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

    <ArtTableQuery
      v-show="activeTab === 'reimbursement'"
      ref="reimbursementTableRef"
      v-model="reimbursementTable.search"
      v-model:focus-mode="reimbursementFocusMode"
      :search-items="reimbursementTable.searchItems"
      :api-fn="fetchReimbursementTableData"
      :columns-factory="reimbursementColumnsFactory"
      :header-actions="reimbursementTable.headerActions"
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

    <WaybillExpenseDialog ref="expenseDialogRef" @success="handleExpenseSaved" />
    <ReimbursementDialog ref="reimbursementDialogRef" @success="handleReimbursementCreated" />
    <PaymentDialog ref="paymentDialogRef" @success="handlePaymentSuccess" />
    <ReimbursementDetailDrawer ref="reimbursementDetailRef" />
    <OcrLogDrawer ref="ocrLogDrawerRef" />
    <WaybillCostAuditDrawer ref="costAuditDrawerRef" />
    <WorkflowBusinessHistoryDrawer ref="approvalHistoryRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElMessage } from 'element-plus'
  import type { ComputedRef } from 'vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
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
  } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import WaybillExpenseDialog from './modules/waybill-expense-dialog.vue'
  import ReimbursementDialog from './modules/reimbursement-dialog.vue'
  import PaymentDialog from './modules/payment-dialog.vue'
  import ReimbursementDetailDrawer from './modules/reimbursement-detail-drawer.vue'
  import OcrLogDrawer from './modules/ocr-log-drawer.vue'
  import WaybillCostAuditDrawer from './modules/waybill-cost-audit-drawer.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import WorkflowBusinessHistoryDrawer from '@/components/business/workflow-business-history/workflow-business-history-drawer.vue'
  import type { WorkflowBusinessHistoryDrawerExpose } from '@/components/business/workflow-business-history/types'
  import { validateReimbursementSelection } from './modules/reimbursement-selection'

  defineOptions({ name: 'TmsWaybillCost' })

  type Expense = Api.Tms.Finance.WaybillCostRecord
  type ExpenseSearch = Api.Tms.Finance.WaybillCostSearchParams
  type ExpenseTableParams = ExpenseSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type Reimbursement = Api.Tms.Finance.ExpenseReimbursementRecord
  type ReimbursementSearch = Api.Tms.Finance.ExpenseReimbursementSearchParams
  type ReimbursementTableParams = ReimbursementSearch &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

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
    handleOpen: (data?: { row?: Expense; orderId?: string }) => Promise<void>
  }

  interface ReimbursementDialogExpose {
    handleOpen: (expenses: Expense[]) => Promise<void>
  }

  interface PaymentDialogExpose {
    handleOpen: (row: Reimbursement) => Promise<void>
  }

  interface ReimbursementDetailExpose {
    handleOpen: (row: Reimbursement) => Promise<void>
  }

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const { confirmAction } = useArtFeedback()
  const activeTab = ref<'expense' | 'reimbursement'>(
    route.name === 'TmsExpenseReimbursement' ? 'reimbursement' : 'expense'
  )
  const expenseFocusMode = ref(false)
  const reimbursementFocusMode = ref(false)
  const focusMode = computed(() =>
    activeTab.value === 'expense' ? expenseFocusMode.value : reimbursementFocusMode.value
  )
  const expenseTableRef = ref<ArtTableQueryExpose>()
  const reimbursementTableRef = ref<ArtTableQueryExpose>()
  const expenseDialogRef = ref<ExpenseDialogExpose>()
  const reimbursementDialogRef = ref<ReimbursementDialogExpose>()
  const paymentDialogRef = ref<PaymentDialogExpose>()
  const reimbursementDetailRef = ref<ReimbursementDetailExpose>()
  const ocrLogDrawerRef = ref<{ handleOpen: () => Promise<void> }>()
  const costAuditDrawerRef = ref<{
    handleOpen: (data: { costId: string; waybillNo: string }) => Promise<void>
  }>()
  const approvalHistoryRef = ref<WorkflowBusinessHistoryDrawerExpose>()
  const overview = reactive<Api.Tms.Finance.WaybillCostOverview>({
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
  const metrics = computed(() => [
    {
      label: '累计申报',
      value: `${overview.totalCount} 笔`,
      hint: '所有运单费用记录',
      icon: 'ri:file-list-3-line',
      tone: 'is-primary'
    },
    {
      label: '待财务审核',
      value: `${overview.pendingReviewCount} 笔`,
      hint: '等待审批中心处理',
      icon: 'ri:time-line',
      tone: 'is-warning'
    },
    {
      label: '待转报销',
      value: `${overview.approvedUnconvertedCount} 笔`,
      hint: '已通过但未生成报销单',
      icon: 'ri:exchange-cny-line',
      tone: 'is-success'
    },
    {
      label: '待支付金额',
      value: money(overview.pendingPaymentAmount),
      hint: `已核销 ${money(overview.paidAmount)}`,
      icon: 'ri:secure-payment-line',
      tone: 'is-danger'
    }
  ])

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
      auditStatus: '',
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
          endPlaceholder: '结束日期'
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
      { type: 'add', label: '新增费用', onClick: () => openExpenseDialog() },
      {
        key: 'convert',
        label: '转费用报销',
        selectionRequired: true,
        buttonProps: {
          type: 'primary',
          plain: true,
          title: '支持单选，或多选同一个运单下的已审费用'
        },
        onClick: ({ selectedRows }) => handleReimbursementSelection(selectedRows as Expense[])
      },
      {
        key: 'ocrLogs',
        label: 'OCR 记录',
        buttonProps: { plain: true },
        onClick: () => void ocrLogDrawerRef.value?.handleOpen()
      }
    ])
  })

  const reimbursementTable = reactive<ReimbursementTableGroup>({
    search: { keyword: '', status: '', paymentMethod: '', plannedPaymentDateRange: [] },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '审批状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.tmsReimbursementApprovalStatus ?? [], clearable: true }
      },
      {
        label: '付款方式',
        key: 'paymentMethod',
        type: 'select',
        props: { options: getDictMap.value.tmsCashPaymentMethod ?? [], clearable: true }
      },
      {
        label: '计划付款日',
        key: 'plannedPaymentDateRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期'
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '报销单、收款人、运单、付款单或流水号' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        key: 'backToExpense',
        label: '从已审费用生成',
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
            href={router.resolve(expenseDetailPath(row.id)).href}
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
    {
      prop: 'amount',
      label: '申报金额',
      width: 130,
      align: 'right',
      formatter: (row) => money(row.amount)
    },
    {
      prop: 'occurredOn',
      label: '发生日期',
      width: 115,
      formatter: (row) => formatWithDayjs(row.occurredOn, 'YYYY-MM-DD')
    },
    {
      prop: 'providerName',
      label: '服务商',
      minWidth: 150,
      showOverflowTooltip: true,
      formatter: (row) => emptyText(row.providerName)
    },
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
      width: 150,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ArtButtonTable
            type="edit"
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
    { prop: 'reimbursementNo', label: '报销单号', width: 200, fixed: 'left' },
    { prop: 'applicantNameSnapshot', label: '申请人', width: 115 },
    { prop: 'payeeName', label: '收款人', minWidth: 150, showOverflowTooltip: true },
    { prop: 'waybillNos', label: '关联运单', minWidth: 210, showOverflowTooltip: true },
    { prop: 'itemCount', label: '费用笔数', width: 95, align: 'center' },
    {
      prop: 'totalAmount',
      label: '报销金额',
      width: 135,
      align: 'right',
      formatter: (row) => money(row.totalAmount)
    },
    {
      prop: 'paymentMethod',
      label: '付款方式',
      width: 115,
      dict: { code: 'tmsCashPaymentMethod', display: 'tag' }
    },
    { prop: 'plannedPaymentDate', label: '计划付款日', width: 120 },
    {
      prop: 'status',
      label: '审批/支付状态',
      width: 135,
      dict: { code: 'tmsReimbursementApprovalStatus', display: 'tag' }
    },
    {
      prop: 'paymentNo',
      label: '付款单号',
      width: 195,
      formatter: (row) => emptyText(row.paymentNo)
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
      width: 160,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ArtButtonTable
            type="view"
            onClick={() => void reimbursementDetailRef.value?.handleOpen(row)}
          />
          <ArtButtonMore
            list={reimbursementMoreActions(row)}
            onClick={(item: ButtonMoreItem) => handleReimbursementAction(item, row)}
          />
        </div>
      )
    }
  ]

  function fetchExpenseTableData(params: ExpenseTableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchWaybillCostList({ ...params, from, to })
  }

  function fetchReimbursementTableData(params: ReimbursementTableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchExpenseReimbursementList({ ...params, from, to })
  }

  function expenseDetailPath(id: string): string {
    return `/tms-transportation/finance-center/waybill-cost/detail/${id}`
  }

  function navigateToExpenseDetail(event: MouseEvent, id: string): void {
    event.preventDefault()
    event.stopPropagation()
    window.location.assign(router.resolve(expenseDetailPath(id)).href)
  }

  function emptyText(value: unknown): string {
    return String(value || '--')
  }

  function money(value?: number | null): string {
    return formatCurrencyValue(Number(value ?? 0))
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

  function openApprovedExpenses(): void {
    activeTab.value = 'expense'
    expenseTable.search.auditStatus = 'approved'
    expenseTable.search.settlementStatus = 'unsettled'
    void nextTick(() => expenseTableRef.value?.getData())
  }

  function expenseMoreActions(row: Expense): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      { key: 'aiAudit', label: 'AI 费用审核', icon: 'ri:sparkling-2-line' },
      { key: 'approvalHistory', label: '审批记录', icon: 'ri:file-history-line' }
    ]
    if (canEditExpense(row)) {
      actions.push({ key: 'submit', label: '提交财务审核', icon: 'ri:send-plane-line' })
      actions.push({
        key: 'delete',
        label: '删除草稿',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      })
    }
    if (canConvert(row)) {
      actions.push({ key: 'convert', label: '转费用报销', icon: 'ri:exchange-cny-line' })
    }
    return actions
  }

  function reimbursementMoreActions(row: Reimbursement): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [
      { key: 'approvalHistory', label: '审批记录', icon: 'ri:file-history-line' }
    ]
    if (['draft', 'rejected'].includes(row.status)) {
      actions.push({ key: 'submit', label: '提交报销审批', icon: 'ri:send-plane-line' })
      actions.push({
        key: 'delete',
        label: '删除并退回费用',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      })
    }
    if (row.status === 'approved') {
      actions.push({ key: 'pay', label: '出纳付款', icon: 'ri:secure-payment-line' })
    }
    return actions
  }

  function handleExpenseAction(item: ButtonMoreItem, row: Expense): void {
    const actions: Record<string, () => void> = {
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
      pay: () => void paymentDialogRef.value?.handleOpen(row),
      approvalHistory: () =>
        void openApprovalHistory('tms_expense_reimbursement', row.id, row.reimbursementNo)
    }
    actions[String(item.key)]?.()
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
    const { data } = await fetchWaybillCostOverview()
    if (data) Object.assign(overview, data)
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

  onMounted(() => {
    void Promise.all([userStore.fetchDictList(), loadOverview()])
  })

  watch(
    () => route.name,
    (name) => {
      if (name === 'TmsWaybillCost') activeTab.value = 'expense'
      if (name === 'TmsExpenseReimbursement') activeTab.value = 'reimbursement'
    }
  )

  watch(activeTab, (tab) => {
    if (!['TmsWaybillCost', 'TmsExpenseReimbursement'].includes(String(route.name))) return
    const targetName = tab === 'expense' ? 'TmsWaybillCost' : 'TmsExpenseReimbursement'
    if (route.name === targetName || !router.hasRoute(targetName)) return
    void router.replace({ name: targetName, query: route.query })
  })

  watch(
    () => route.fullPath,
    (orderId) => {
      if (typeof orderId === 'string' && orderId) void openFromOrderQuery()
    },
    { immediate: true }
  )

  watch(activeTab, async (value) => {
    await nextTick()
    if (value === 'reimbursement') await reimbursementTableRef.value?.getData()
  })
</script>

<style scoped lang="scss">
  .waybill-cost {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-4);
    min-width: 0;

    > .art-table-query {
      min-height: 0;
    }

    &.is-focus-mode {
      gap: 0;
    }

    &__hero {
      display: flex;
      gap: var(--art-space-5);
      align-items: center;
      justify-content: space-between;
      padding: var(--art-space-5);
    }

    &__hero-copy,
    &__hero-actions,
    &__workflow,
    &__workflow > div {
      display: flex;
      align-items: center;
    }

    &__hero-copy {
      gap: var(--art-space-4);
      min-width: 0;

      > div {
        min-width: 0;

        > span {
          font-size: 12px;
          font-weight: 700;
          color: rgb(var(--ui-primary));
          letter-spacing: 0.05em;
        }
      }

      h1 {
        margin: 2px 0 4px;
        font-size: 22px;
        line-height: 1.35;
        color: var(--art-text-gray-900);
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--art-text-gray-500);
      }
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 52px;
      place-items: center;
      width: 52px;
      height: 52px;
      font-size: 25px;
      color: rgb(var(--ui-primary));
      background: rgb(var(--ui-primary) / 10%);
      border-radius: var(--el-border-radius-base);
    }

    &__hero-actions {
      flex: 0 0 auto;
      flex-wrap: wrap;
      gap: var(--art-space-3);
      justify-content: flex-end;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: var(--art-space-3);

      > article {
        display: flex;
        gap: var(--art-space-3);
        align-items: center;
        min-width: 0;
        padding: var(--art-space-4);

        > span {
          display: grid;
          flex: 0 0 38px;
          place-items: center;
          width: 38px;
          height: 38px;
          border-radius: var(--el-border-radius-base);

          &.is-primary {
            color: var(--el-color-primary);
            background: var(--el-color-primary-light-9);
          }

          &.is-warning {
            color: var(--el-color-warning);
            background: var(--el-color-warning-light-9);
          }

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          &.is-danger {
            color: var(--el-color-danger);
            background: var(--el-color-danger-light-9);
          }
        }

        > div {
          min-width: 0;
        }

        small,
        p {
          color: var(--art-text-gray-500);
        }

        strong {
          display: block;
          margin: 2px 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 19px;
          font-variant-numeric: tabular-nums;
          color: var(--art-text-gray-900);
          white-space: nowrap;
        }

        p {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 11px;
          white-space: nowrap;
        }
      }
    }

    &__workflow {
      gap: 0;
      padding: var(--art-space-3) var(--art-space-4);

      > div {
        flex: 1;
        gap: var(--art-space-2);
        min-width: 0;

        > span {
          display: grid;
          flex: 0 0 26px;
          place-items: center;
          width: 26px;
          height: 26px;
          font-size: 12px;
          font-weight: 700;
          color: rgb(var(--ui-primary));
          background: rgb(var(--ui-primary) / 10%);
          border-radius: 50%;
        }

        > div {
          display: flex;
          flex-direction: column;
          min-width: 0;

          strong {
            font-size: 13px;
            color: var(--art-text-gray-800);
          }

          small {
            overflow: hidden;
            text-overflow: ellipsis;
            color: var(--art-text-gray-500);
            white-space: nowrap;
          }
        }

        > svg {
          margin-left: auto;
          color: var(--art-text-gray-300);
        }
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

    &__tabs {
      margin-bottom: calc(var(--art-space-4) * -1);
    }

    @media (width <= 1100px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__workflow {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-3);

        > div > svg {
          display: none;
        }
      }
    }

    @media (width <= 720px) {
      &__hero,
      &__hero-actions {
        flex-direction: column;
        align-items: stretch;
      }

      &__hero-actions > button {
        width: 100%;
      }

      &__metrics,
      &__workflow {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
