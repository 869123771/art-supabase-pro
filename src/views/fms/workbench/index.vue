<template>
  <ArtPageShell
    :loading="overview.loading"
    :error="loadError"
    class="finance-workbench"
    @retry="loadWorkbench"
  >
    <BusinessWorkspaceHeader
      eyebrow="FINANCE OPERATIONS"
      title="财务工作台"
      description="集中查看应收、应付、开票、回款与费用审核进度"
      icon="ri:money-cny-box-line"
      :tags="workspaceTags"
      :metrics="overview.metrics"
      class="finance-workbench__header"
    >
      <template #actions>
        <ElButton type="primary" @click="openCollectionAdvisor">
          <ArtSvgIcon icon="ri:sparkling-2-line" />AI 回款风险研判
        </ElButton>
      </template>
    </BusinessWorkspaceHeader>

    <AccountingReadinessPanel />

    <div class="finance-workbench__content">
      <ArtPageSection
        title="财务待办"
        subtitle="按优先级集中处理当前未完成事项"
        class="finance-workbench__panel"
      >
        <ArtTable
          :data="overview.tasks"
          :columns="taskColumns"
          :pagination="false"
          table-layout="fixed"
          empty-text="当前没有待办事项"
        >
          <template #urgency="{ row }">
            <ElTag :type="urgencyType(row.urgency)">{{ row.urgency }}</ElTag>
          </template>
          <template #operation="{ row }">
            <ElButton link type="primary" @click="handleTask(row)">去处理</ElButton>
          </template>
        </ArtTable>
      </ArtPageSection>

      <ArtPageSection
        title="业务完成率"
        subtitle="跟踪本月关键财务流程推进情况"
        class="finance-workbench__panel"
      >
        <div class="finance-workbench__progress-list">
          <div
            v-for="item in overview.progressItems"
            :key="item.label"
            class="finance-workbench__progress-item"
          >
            <div>
              <span>{{ item.label }}</span>
              <strong>{{ item.value }}</strong>
            </div>
            <ElProgress :percentage="item.percent" :stroke-width="10" :color="item.color" />
          </div>
        </div>
      </ArtPageSection>
    </div>

    <ArtPageSection
      title="本月经营概览"
      subtitle="本月运输收入、成本、毛利及资金核销概况"
      class="finance-workbench__panel"
    >
      <ArtDescriptions :data="statsDescriptionData" :items="statsDescriptionItems" :columns="4" />
    </ArtPageSection>

    <ArtPageSection
      v-if="overview.reminders.length"
      title="结算提醒"
      class="finance-workbench__panel"
    >
      <ElAlert
        v-for="item in overview.reminders"
        :key="item.title"
        :title="item.title"
        :type="item.type"
        show-icon
        :closable="false"
      />
    </ArtPageSection>

    <ReceivablesCollectionAdvisorDrawer ref="collectionAdvisorRef" />
  </ArtPageShell>
</template>

<script setup lang="ts">
  import type { AlertProps, TagProps } from 'element-plus'
  import type { ColumnOption } from '@/types'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric,
    type BusinessWorkspaceTag
  } from '@/components/business/business-workspace-header/index.vue'
  import { fetchAccountingWorkloadSummary, fetchFinanceWorkbench } from '@/api/fms'
  import { financeRouteNames } from '@/router/business-paths'
  import AccountingReadinessPanel from './modules/accounting-readiness-panel.vue'
  import ReceivablesCollectionAdvisorDrawer from './modules/receivables-collection-advisor-drawer.vue'

  defineOptions({ name: 'FinanceWorkbench' })

  type Stats = Api.Fms.FinanceWorkbenchStats
  type Urgency = '普通' | '关注' | '紧急'

  interface WorkbenchTask {
    id: string
    title: string
    count: number
    amount: number | null
    urgency: Urgency
    routeName: string
    query?: Record<string, string>
  }

  interface ProgressItem {
    label: string
    value: string
    percent: number
    color: string
  }

  interface ReminderItem {
    title: string
    type: AlertProps['type']
  }

  interface OverviewGroup {
    loading: boolean
    stats: Stats
    metrics: BusinessWorkspaceMetric[]
    tasks: WorkbenchTask[]
    progressItems: ProgressItem[]
    reminders: ReminderItem[]
    workload: Api.Fms.AccountingWorkloadSummary
  }

  interface CollectionAdvisorExpose {
    handleOpen: () => Promise<void>
  }

  const router = useRouter()
  const loadError = ref<Error | null>(null)
  const collectionAdvisorRef = ref<CollectionAdvisorExpose>()

  const createEmptyStats = (): Stats => ({
    customerReceivableBalance: 0,
    carrierPayableBalance: 0,
    monthReceiptAmount: 0,
    monthPaymentAmount: 0,
    monthRevenueAmount: 0,
    monthCostAmount: 0,
    monthGrossProfit: 0,
    receiptCompletionRate: 0,
    paymentCompletionRate: 0,
    invoiceMatchRate: 0,
    costApprovalRate: 0,
    pendingCustomerStatementCount: 0,
    pendingCustomerStatementAmount: 0,
    pendingCarrierStatementCount: 0,
    pendingCarrierStatementAmount: 0,
    pendingCostCount: 0,
    pendingCostAmount: 0,
    unallocatedReceiptCount: 0,
    unallocatedReceiptAmount: 0,
    unallocatedPaymentCount: 0,
    unallocatedPaymentAmount: 0,
    draftInvoiceCount: 0,
    draftInvoiceAmount: 0,
    pendingInvoiceCount: 0,
    pendingInvoiceAmount: 0,
    pendingPaymentApplicationCount: 0,
    pendingPaymentApplicationAmount: 0,
    approvedUnpaidPaymentCount: 0,
    approvedUnpaidPaymentAmount: 0,
    unapprovedPaymentCount: 0,
    unapprovedPaymentAmount: 0,
    overdueReceivableCount: 0,
    overdueReceivableAmount: 0,
    uninvoicedReceivableCount: 0,
    uninvoicedReceivableAmount: 0
  })

  const createEmptyWorkload = (): Api.Fms.AccountingWorkloadSummary => ({
    failedPostingEventCount: 0,
    pendingConfigurationEventCount: 0,
    pendingPostingEventCount: 0,
    pendingVoucherReviewCount: 0,
    approvedVoucherCount: 0,
    closingPeriodCount: 0
  })

  const overview = reactive<OverviewGroup>({
    loading: false,
    stats: createEmptyStats(),
    metrics: [],
    tasks: [],
    progressItems: [],
    reminders: [],
    workload: createEmptyWorkload()
  })
  const workspaceTags: BusinessWorkspaceTag[] = [
    { label: '经营数据实时汇总', type: 'success', effect: 'plain' },
    { label: '支持 AI 回款风险研判', type: 'info', effect: 'plain' }
  ]

  const taskColumns: ColumnOption<WorkbenchTask>[] = [
    { prop: 'title', label: '待办事项', minWidth: 175 },
    {
      prop: 'count',
      label: '数量',
      width: 90,
      align: 'center',
      formatter: (row) => `${row.count} 项`
    },
    {
      prop: 'amount',
      label: '涉及金额',
      minWidth: 135,
      align: 'right',
      formatter: (row) => (row.amount === null ? '—' : formatMoney(row.amount))
    },
    { prop: 'urgency', label: '优先级', width: 90, useSlot: true },
    { prop: 'operation', label: '操作', width: 90, fixed: 'right', useSlot: true }
  ]

  const statsDescriptionData = computed<Record<string, unknown>>(() => ({ ...overview.stats }))
  const statsDescriptionItems: ArtDescriptionItem[] = [
    { key: 'revenue', label: '运输收入', field: 'monthRevenueAmount', format: 'money' },
    { key: 'cost', label: '运输成本', field: 'monthCostAmount', format: 'money' },
    { key: 'profit', label: '运输毛利', field: 'monthGrossProfit', format: 'money' },
    {
      key: 'margin',
      label: '综合毛利率',
      value: () => `${grossMargin.value}%`
    },
    { key: 'receipt', label: '客户回款', field: 'monthReceiptAmount', format: 'money' },
    { key: 'payment', label: '承运商付款', field: 'monthPaymentAmount', format: 'money' },
    {
      key: 'unallocatedReceipt',
      label: '未核销收款',
      field: 'unallocatedReceiptAmount',
      format: 'money'
    },
    {
      key: 'unallocatedPayment',
      label: '未核销付款',
      field: 'unallocatedPaymentAmount',
      format: 'money'
    }
  ]

  const grossMargin = computed(() => {
    const revenue = Number(overview.stats.monthRevenueAmount || 0)
    return revenue > 0
      ? ((Number(overview.stats.monthGrossProfit || 0) / revenue) * 100).toFixed(2)
      : '0.00'
  })

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function clampRate(value: number): number {
    return Math.min(100, Math.max(0, Number(value || 0)))
  }

  function buildMetrics(stats: Stats): BusinessWorkspaceMetric[] {
    return [
      {
        label: '客户应收余额',
        value: formatMoney(stats.customerReceivableBalance),
        description: `本月已回款 ${formatMoney(stats.monthReceiptAmount)}`,
        icon: 'ri:funds-line',
        tone: 'primary'
      },
      {
        label: '承运商应付余额',
        value: formatMoney(stats.carrierPayableBalance),
        description: `本月已付款 ${formatMoney(stats.monthPaymentAmount)}`,
        icon: 'ri:bank-card-line',
        tone: 'warning'
      },
      {
        label: '本月回款',
        value: formatMoney(stats.monthReceiptAmount),
        description: `回款完成率 ${Number(stats.receiptCompletionRate).toFixed(2)}%`,
        icon: 'ri:money-cny-circle-line',
        tone: 'success'
      },
      {
        label: '本月运输毛利',
        value: formatMoney(stats.monthGrossProfit),
        description: `综合毛利率 ${grossMargin.value}%`,
        icon: 'ri:line-chart-line',
        tone: stats.monthGrossProfit >= 0 ? 'primary' : 'danger'
      }
    ]
  }

  function buildTasks(stats: Stats, workload: Api.Fms.AccountingWorkloadSummary): WorkbenchTask[] {
    const tasks: WorkbenchTask[] = [
      {
        id: 'posting-event-failed',
        title: '自动入账失败事件',
        count: workload.failedPostingEventCount,
        amount: null,
        urgency: '紧急',
        routeName: financeRouteNames.autoPosting,
        query: { tab: 'events', status: 'failed' }
      },
      {
        id: 'posting-event-configuration',
        title: '自动入账待配置事件',
        count: workload.pendingConfigurationEventCount,
        amount: null,
        urgency: '紧急',
        routeName: financeRouteNames.autoPosting,
        query: { tab: 'events', status: 'pending_configuration' }
      },
      {
        id: 'posting-event-pending',
        title: '自动入账待处理事件',
        count: workload.pendingPostingEventCount,
        amount: null,
        urgency: '关注',
        routeName: financeRouteNames.autoPosting,
        query: { tab: 'events', status: 'pending' }
      },
      {
        id: 'voucher-review',
        title: '待审核会计凭证',
        count: workload.pendingVoucherReviewCount,
        amount: null,
        urgency: '紧急',
        routeName: financeRouteNames.voucherCenter,
        query: { status: 'pending_review' }
      },
      {
        id: 'voucher-posting',
        title: '已审核待过账凭证',
        count: workload.approvedVoucherCount,
        amount: null,
        urgency: '关注',
        routeName: financeRouteNames.voucherCenter,
        query: { status: 'approved' }
      },
      {
        id: 'period-closing',
        title: '关账中会计期间',
        count: workload.closingPeriodCount,
        amount: null,
        urgency: '关注',
        routeName: financeRouteNames.periodClose
      },
      {
        id: 'payment-application-review',
        title: '待审批承运商付款申请',
        count: stats.pendingPaymentApplicationCount,
        amount: stats.pendingPaymentApplicationAmount,
        urgency: '紧急',
        routeName: financeRouteNames.paymentApplication,
        query: { status: 'pending_review' }
      },
      {
        id: 'approved-payment-execution',
        title: '已批准待执行付款',
        count: stats.approvedUnpaidPaymentCount,
        amount: stats.approvedUnpaidPaymentAmount,
        urgency: '紧急',
        routeName: financeRouteNames.paymentApplication,
        query: { status: 'approved' }
      },
      {
        id: 'unapproved-payment-review',
        title: '未关联审批付款待复核',
        count: stats.unapprovedPaymentCount,
        amount: stats.unapprovedPaymentAmount,
        urgency: '紧急',
        routeName: financeRouteNames.cashTransaction,
        query: { direction: 'payment' }
      },
      {
        id: 'overdue-receivable',
        title: '账期结束超 30 天未回款',
        count: stats.overdueReceivableCount,
        amount: stats.overdueReceivableAmount,
        urgency: '关注',
        routeName: financeRouteNames.customerSettlement,
        query: { status: 'confirmed' }
      },
      {
        id: 'uninvoiced-receivable',
        title: '已确认对账未完成开票',
        count: stats.uninvoicedReceivableCount,
        amount: stats.uninvoicedReceivableAmount,
        urgency: '关注',
        routeName: financeRouteNames.invoiceManagement,
        query: { direction: 'output' }
      },
      {
        id: 'customer-statement-review',
        title: '待审核客户对账单',
        count: stats.pendingCustomerStatementCount,
        amount: stats.pendingCustomerStatementAmount,
        urgency: '紧急',
        routeName: financeRouteNames.customerSettlement,
        query: { status: 'pending_review' }
      },
      {
        id: 'carrier-statement-review',
        title: '待审核承运商对账单',
        count: stats.pendingCarrierStatementCount,
        amount: stats.pendingCarrierStatementAmount,
        urgency: '紧急',
        routeName: financeRouteNames.carrierSettlement,
        query: { status: 'pending_review' }
      },
      {
        id: 'receipt-allocation',
        title: '待核销客户收款',
        count: stats.unallocatedReceiptCount,
        amount: stats.unallocatedReceiptAmount,
        urgency: '关注',
        routeName: financeRouteNames.cashTransaction,
        query: { direction: 'receipt', status: 'pending_allocation' }
      },
      {
        id: 'payment-allocation',
        title: '待核销承运商付款',
        count: stats.unallocatedPaymentCount,
        amount: stats.unallocatedPaymentAmount,
        urgency: '关注',
        routeName: financeRouteNames.cashTransaction,
        query: { direction: 'payment', status: 'pending_allocation' }
      },
      {
        id: 'invoice-review',
        title: '待复核发票',
        count: stats.pendingInvoiceCount,
        amount: stats.pendingInvoiceAmount,
        urgency: '关注',
        routeName: financeRouteNames.invoiceManagement,
        query: { status: 'pending_review' }
      },
      {
        id: 'invoice-match',
        title: '待匹配草稿发票',
        count: stats.draftInvoiceCount,
        amount: stats.draftInvoiceAmount,
        urgency: '普通',
        routeName: financeRouteNames.invoiceManagement,
        query: { status: 'draft' }
      },
      {
        id: 'cost-review',
        title: '待审核运单费用',
        count: stats.pendingCostCount,
        amount: stats.pendingCostAmount,
        urgency: '关注',
        routeName: financeRouteNames.waybillCost,
        query: { auditStatus: 'pending_review' }
      }
    ]
    return tasks.filter((item) => item.count > 0)
  }

  function buildProgressItems(stats: Stats): ProgressItem[] {
    return [
      {
        label: '客户回款完成率',
        value: `${Number(stats.receiptCompletionRate).toFixed(2)}%`,
        percent: clampRate(stats.receiptCompletionRate),
        color: 'var(--el-color-success)'
      },
      {
        label: '承运商付款完成率',
        value: `${Number(stats.paymentCompletionRate).toFixed(2)}%`,
        percent: clampRate(stats.paymentCompletionRate),
        color: 'var(--el-color-warning)'
      },
      {
        label: '发票匹配完成率',
        value: `${Number(stats.invoiceMatchRate).toFixed(2)}%`,
        percent: clampRate(stats.invoiceMatchRate),
        color: 'var(--el-color-primary)'
      },
      {
        label: '费用审核完成率',
        value: `${Number(stats.costApprovalRate).toFixed(2)}%`,
        percent: clampRate(stats.costApprovalRate),
        color: 'var(--el-color-success)'
      }
    ]
  }

  function buildReminders(stats: Stats): ReminderItem[] {
    const reminders: ReminderItem[] = []
    if (stats.approvedUnpaidPaymentCount > 0) {
      reminders.push({
        title: `有 ${stats.approvedUnpaidPaymentCount} 笔付款申请已审批但尚未付款，金额 ${formatMoney(stats.approvedUnpaidPaymentAmount)}`,
        type: 'warning'
      })
    }
    if (stats.unapprovedPaymentCount > 0) {
      reminders.push({
        title: `发现 ${stats.unapprovedPaymentCount} 笔未关联付款审批的实际付款，金额 ${formatMoney(stats.unapprovedPaymentAmount)}；请复核存量或平台批量入账记录`,
        type: 'error'
      })
    }
    if (stats.unallocatedReceiptCount > 0) {
      reminders.push({
        title: `有 ${stats.unallocatedReceiptCount} 笔客户收款尚未完全核销，金额 ${formatMoney(stats.unallocatedReceiptAmount)}`,
        type: 'warning'
      })
    }
    if (stats.unallocatedPaymentCount > 0) {
      reminders.push({
        title: `有 ${stats.unallocatedPaymentCount} 笔承运商付款尚未完全核销，金额 ${formatMoney(stats.unallocatedPaymentAmount)}`,
        type: 'info'
      })
    }
    if (
      stats.invoiceMatchRate < 100 &&
      (stats.draftInvoiceCount > 0 || stats.pendingInvoiceCount > 0)
    ) {
      reminders.push({
        title: `当前发票匹配完成率 ${Number(stats.invoiceMatchRate).toFixed(2)}%，请及时关联对账单并完成复核`,
        type: 'info'
      })
    }
    return reminders
  }

  function applyStats(stats: Stats, workload = overview.workload): void {
    Object.assign(overview.stats, stats)
    Object.assign(overview.workload, workload)
    overview.metrics = buildMetrics(stats)
    overview.tasks = buildTasks(stats, workload)
    overview.progressItems = buildProgressItems(stats)
    overview.reminders = buildReminders(stats)
  }

  function urgencyType(value: string): TagProps['type'] {
    if (value === '紧急') return 'danger'
    if (value === '关注') return 'warning'
    return 'info'
  }

  function handleTask(task: WorkbenchTask): void {
    const routeName = task.routeName
    if (!routeName) return
    void router.push({ name: routeName, query: task.query })
  }

  function openCollectionAdvisor(): void {
    void collectionAdvisorRef.value?.handleOpen()
  }

  async function loadWorkbench(): Promise<void> {
    overview.loading = true
    loadError.value = null
    try {
      const [workbenchResult, workloadResult] = await Promise.all([
        fetchFinanceWorkbench(),
        fetchAccountingWorkloadSummary()
      ])
      applyStats(
        workbenchResult.data ?? createEmptyStats(),
        workloadResult.data ?? createEmptyWorkload()
      )
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('财务工作台加载失败')
    } finally {
      overview.loading = false
    }
  }

  onMounted(() => void loadWorkbench())
</script>

<style scoped lang="scss">
  .finance-workbench {
    min-width: 0;

    :deep(> .art-async-state) {
      display: grid;
      gap: 20px;
      min-width: 0;
    }

    &__content {
      display: grid;
      grid-template-columns: 1.35fr 1fr;
      gap: 16px;
      min-width: 0;
    }

    &__panel {
      padding: var(--art-section-padding);
    }

    &__progress-list {
      display: grid;
      gap: 24px;
      padding: 2px 0 4px;
    }

    &__progress-item {
      display: grid;
      gap: 8px;

      div {
        display: flex;
        gap: 12px;
        justify-content: space-between;
        color: var(--el-text-color-regular);

        strong {
          font-variant-numeric: tabular-nums;
        }
      }
    }

    .el-alert + .el-alert {
      margin-top: 10px;
    }
  }

  @media (width <= 900px) {
    .finance-workbench {
      &__content {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
