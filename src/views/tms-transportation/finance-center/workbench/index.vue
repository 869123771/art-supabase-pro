<template>
  <ArtPageShell
    :loading="overview.loading"
    :error="loadError"
    class="finance-workbench"
    @retry="loadWorkbench"
  >
    <ArtPageHeader
      title="财务工作台"
      subtitle="集中查看应收、应付、开票、回款与费用审核进度"
      class="finance-workbench__header"
    >
      <ElButton type="primary" @click="openCollectionAdvisor">
        <ArtSvgIcon icon="ri:sparkling-2-line" />AI 回款风险研判
      </ElButton>
    </ArtPageHeader>

    <FinanceMetricGrid :items="overview.metrics" class="finance-workbench__metrics" />

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
  import { fetchFinanceWorkbench } from '@/api/tms'
  import type { FinanceMetric } from '../modules/finance-types'
  import FinanceMetricGrid from '../modules/finance-metric-grid.vue'
  import ReceivablesCollectionAdvisorDrawer from './modules/receivables-collection-advisor-drawer.vue'

  defineOptions({ name: 'TmsFinanceWorkbench' })

  type Stats = Api.Tms.Finance.FinanceWorkbenchStats
  type Urgency = '普通' | '关注' | '紧急'

  interface WorkbenchTask {
    id: string
    title: string
    count: number
    amount: number
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
    metrics: FinanceMetric[]
    tasks: WorkbenchTask[]
    progressItems: ProgressItem[]
    reminders: ReminderItem[]
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
    pendingInvoiceAmount: 0
  })

  const overview = reactive<OverviewGroup>({
    loading: false,
    stats: createEmptyStats(),
    metrics: [],
    tasks: [],
    progressItems: [],
    reminders: []
  })

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
      formatter: (row) => formatMoney(row.amount)
    },
    { prop: 'urgency', label: '优先级', width: 90, useSlot: true },
    { prop: 'operation', label: '操作', width: 90, fixed: 'right', useSlot: true }
  ]

  const statsDescriptionData = computed<Record<string, unknown>>(
    () => overview.stats as unknown as Record<string, unknown>
  )
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

  function buildMetrics(stats: Stats): FinanceMetric[] {
    return [
      {
        label: '客户应收余额',
        value: formatMoney(stats.customerReceivableBalance),
        trend: `本月已回款 ${formatMoney(stats.monthReceiptAmount)}`,
        icon: 'ri:funds-line',
        tone: 'primary'
      },
      {
        label: '承运商应付余额',
        value: formatMoney(stats.carrierPayableBalance),
        trend: `本月已付款 ${formatMoney(stats.monthPaymentAmount)}`,
        icon: 'ri:bank-card-line',
        tone: 'warning'
      },
      {
        label: '本月回款',
        value: formatMoney(stats.monthReceiptAmount),
        trend: `回款完成率 ${Number(stats.receiptCompletionRate).toFixed(2)}%`,
        icon: 'ri:money-cny-circle-line',
        tone: 'success'
      },
      {
        label: '本月运输毛利',
        value: formatMoney(stats.monthGrossProfit),
        trend: `综合毛利率 ${grossMargin.value}%`,
        icon: 'ri:line-chart-line',
        tone: stats.monthGrossProfit >= 0 ? 'primary' : 'danger'
      }
    ]
  }

  function buildTasks(stats: Stats): WorkbenchTask[] {
    const tasks: WorkbenchTask[] = [
      {
        id: 'customer-statement-review',
        title: '待审核客户对账单',
        count: stats.pendingCustomerStatementCount,
        amount: stats.pendingCustomerStatementAmount,
        urgency: '紧急',
        routeName: 'TmsCustomerSettlement',
        query: { status: 'pending_review' }
      },
      {
        id: 'carrier-statement-review',
        title: '待审核承运商对账单',
        count: stats.pendingCarrierStatementCount,
        amount: stats.pendingCarrierStatementAmount,
        urgency: '紧急',
        routeName: 'TmsCarrierSettlement',
        query: { status: 'pending_review' }
      },
      {
        id: 'receipt-allocation',
        title: '待核销客户收款',
        count: stats.unallocatedReceiptCount,
        amount: stats.unallocatedReceiptAmount,
        urgency: '关注',
        routeName: 'TmsCashTransaction',
        query: { direction: 'receipt', status: 'pending_allocation' }
      },
      {
        id: 'payment-allocation',
        title: '待核销承运商付款',
        count: stats.unallocatedPaymentCount,
        amount: stats.unallocatedPaymentAmount,
        urgency: '关注',
        routeName: 'TmsCashTransaction',
        query: { direction: 'payment', status: 'pending_allocation' }
      },
      {
        id: 'invoice-review',
        title: '待复核发票',
        count: stats.pendingInvoiceCount,
        amount: stats.pendingInvoiceAmount,
        urgency: '关注',
        routeName: 'TmsInvoiceManagement',
        query: { status: 'pending_review' }
      },
      {
        id: 'invoice-match',
        title: '待匹配草稿发票',
        count: stats.draftInvoiceCount,
        amount: stats.draftInvoiceAmount,
        urgency: '普通',
        routeName: 'TmsInvoiceManagement',
        query: { status: 'draft' }
      },
      {
        id: 'cost-review',
        title: '待审核运单费用',
        count: stats.pendingCostCount,
        amount: stats.pendingCostAmount,
        urgency: '关注',
        routeName: 'TmsWaybillCost',
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

  function applyStats(stats: Stats): void {
    Object.assign(overview.stats, stats)
    overview.metrics = buildMetrics(stats)
    overview.tasks = buildTasks(stats)
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
      const { data } = await fetchFinanceWorkbench()
      applyStats(data ?? createEmptyStats())
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

    &__header {
      min-height: 92px;
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
