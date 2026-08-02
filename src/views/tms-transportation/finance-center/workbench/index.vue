<template>
  <div v-loading="overview.loading" class="finance-workbench">
    <FinanceMetricGrid :items="overview.metrics" />

    <div class="finance-workbench__content">
      <section class="art-card-xs finance-workbench__panel">
        <ArtSectionTitle>财务待办</ArtSectionTitle>
        <ElTable :data="overview.tasks" table-layout="fixed" empty-text="当前没有待办事项">
          <ElTableColumn prop="title" label="待办事项" min-width="175" />
          <ElTableColumn prop="count" label="数量" width="90" align="center">
            <template #default="{ row }">{{ row.count }} 项</template>
          </ElTableColumn>
          <ElTableColumn prop="amount" label="涉及金额" min-width="135" align="right">
            <template #default="{ row }">{{ formatMoney(row.amount) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="urgency" label="优先级" width="90">
            <template #default="{ row }">
              <ElTag :type="urgencyType(row.urgency)">{{ row.urgency }}</ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="操作" width="90" fixed="right">
            <template #default="{ row }">
              <ElButton link type="primary" @click="handleTask(row)">去处理</ElButton>
            </template>
          </ElTableColumn>
        </ElTable>
      </section>

      <section class="art-card-xs finance-workbench__panel">
        <ArtSectionTitle>业务完成率</ArtSectionTitle>
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
      </section>
    </div>

    <section class="art-card-xs finance-workbench__panel">
      <ArtSectionTitle>本月经营概览</ArtSectionTitle>
      <ElDescriptions :column="4" border>
        <ElDescriptionsItem label="运输收入">{{
          formatMoney(overview.stats.monthRevenueAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="运输成本">{{
          formatMoney(overview.stats.monthCostAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="运输毛利">{{
          formatMoney(overview.stats.monthGrossProfit)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="综合毛利率">{{ grossMargin }}%</ElDescriptionsItem>
        <ElDescriptionsItem label="客户回款">{{
          formatMoney(overview.stats.monthReceiptAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="承运商付款">{{
          formatMoney(overview.stats.monthPaymentAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="未核销收款">{{
          formatMoney(overview.stats.unallocatedReceiptAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="未核销付款">{{
          formatMoney(overview.stats.unallocatedPaymentAmount)
        }}</ElDescriptionsItem>
      </ElDescriptions>
    </section>

    <section v-if="overview.reminders.length" class="art-card-xs finance-workbench__panel">
      <ArtSectionTitle>结算提醒</ArtSectionTitle>
      <ElAlert
        v-for="item in overview.reminders"
        :key="item.title"
        :title="item.title"
        :type="item.type"
        show-icon
        :closable="false"
      />
    </section>
  </div>
</template>

<script setup lang="ts">
  import type { AlertProps, TagProps } from 'element-plus'
  import { fetchFinanceWorkbench } from '@/api/tms'
  import type { FinanceMetric } from '../modules/finance-types'
  import FinanceMetricGrid from '../modules/finance-metric-grid.vue'

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

  const router = useRouter()

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

  function handleTask(task: Record<string, unknown>): void {
    const routeName = typeof task.routeName === 'string' ? task.routeName : ''
    if (!routeName) return
    const query = task.query as Record<string, string> | undefined
    void router.push({ name: routeName, query })
  }

  async function loadWorkbench(): Promise<void> {
    overview.loading = true
    try {
      const { data } = await fetchFinanceWorkbench()
      applyStats(data ?? createEmptyStats())
    } finally {
      overview.loading = false
    }
  }

  onMounted(() => void loadWorkbench())
</script>

<style scoped lang="scss">
  .finance-workbench {
    display: grid;
    gap: 12px;

    &__content {
      display: grid;
      grid-template-columns: 1.35fr 1fr;
      gap: 12px;
    }

    &__panel {
      padding: 18px;
    }

    &__progress-list {
      display: grid;
      gap: 22px;
      margin-top: 18px;
    }

    &__progress-item {
      display: grid;
      gap: 8px;

      div {
        display: flex;
        justify-content: space-between;
        color: var(--el-text-color-regular);
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
