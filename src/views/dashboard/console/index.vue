<template>
  <ArtPageShell
    class="operations-dashboard"
    :loading="overview.loading"
    :loading-mode="loadingMode"
    :error="pageError"
    min-height="520px"
    @retry="refreshData"
  >
    <DashboardHero
      :greeting="greeting"
      :user-name="userName"
      :date-text="dateText"
      :today-order-count="overview.data.todayOrderCount"
      :in-transit-count="overview.data.inTransitCount"
      @create-order="navigateTo('/tms-transportation/order-open')"
      @dispatch="navigateTo('/tms-transportation/waybill-management/pending')"
      @refresh="refreshData"
    />

    <DashboardMetricCards :items="metricCards" />

    <section class="operations-dashboard__summary">
      <DashboardTrend
        :days="overview.days"
        :data="trendData"
        :loading="overview.loading"
        @update:days="handleTrendDaysChange"
      />
      <DashboardOrderFlow
        :days="overview.days"
        :total="statusTotal"
        :in-transit-count="overview.data.inTransitCount"
        :status-items="statusItems"
        @view-orders="navigateTo('/tms-transportation/order-list')"
      />
    </section>

    <section class="operations-dashboard__operations">
      <DashboardTransit
        :orders="overview.data.transitOrders"
        @monitor="navigateTo('/tms-transportation/in-transit-monitor')"
        @open-order="openOrder"
      />
      <DashboardFleetRisk
        :vehicle-count="overview.data.vehicleCount"
        :operating-vehicle-count="overview.data.operatingVehicleCount"
        :pending-audit-vehicle-count="overview.data.pendingAuditVehicleCount"
        :reminder-total="reminderTotal"
        :reminders="overview.data.reminders"
        @view-reminder="navigateTo('/vehicle-manage-system/reminder-manage')"
      />
    </section>

    <DashboardRecentOrders
      :orders="overview.data.recentOrders"
      @view-orders="navigateTo('/tms-transportation/order-list')"
      @open-order="openOrder"
    />
  </ArtPageShell>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { storeToRefs } from 'pinia'
  import { fetchDashboardData, type DashboardData } from '@/api/dashboard'
  import { useUserStore } from '@/store/modules/user'
  import DashboardFleetRisk from './modules/dashboard-fleet-risk.vue'
  import DashboardHero from './modules/dashboard-hero.vue'
  import DashboardMetricCards from './modules/dashboard-metric-cards.vue'
  import DashboardOrderFlow from './modules/dashboard-order-flow.vue'
  import DashboardRecentOrders from './modules/dashboard-recent-orders.vue'
  import DashboardTransit from './modules/dashboard-transit.vue'
  import DashboardTrend from './modules/dashboard-trend.vue'
  import type { DashboardMetric, DashboardStatusItem, DashboardTrendData } from './modules/types'

  interface OverviewState {
    loading: boolean
    loaded: boolean
    error: Error | null
    days: number
    data: DashboardData
  }

  const router = useRouter()
  const { info } = storeToRefs(useUserStore())
  const createEmptyDashboard = (): DashboardData => ({
    todayOrderCount: 0,
    todayFreightAmount: 0,
    pendingDispatchCount: 0,
    inTransitCount: 0,
    vehicleCount: 0,
    operatingVehicleCount: 0,
    pendingAuditVehicleCount: 0,
    completedTodayCount: 0,
    trend: [],
    statusCounts: {},
    transitOrders: [],
    recentOrders: [],
    reminders: []
  })
  const overview = reactive<OverviewState>({
    loading: false,
    loaded: false,
    error: null,
    days: 14,
    data: createEmptyDashboard()
  })
  const statusDefinitions = [
    { key: 'pending_load', label: '待配载', color: 'var(--el-color-primary)' },
    { key: 'pending_order', label: '待发车', color: 'var(--el-color-info)' },
    { key: 'transporting', label: '运输中', color: 'var(--el-color-success)' },
    { key: 'signed', label: '待结案', color: 'var(--el-color-warning)' },
    { key: 'completed', label: '已完成', color: 'var(--el-text-color-secondary)' }
  ]
  const greeting = computed(() =>
    dayjs().hour() < 12 ? '早上好' : dayjs().hour() < 18 ? '下午好' : '晚上好'
  )
  const userName = computed(() => info.value?.userName || '管理员')
  const dateText = computed(() => dayjs().format('YYYY年MM月DD日 dddd'))
  const trendData = computed<DashboardTrendData>(() => ({
    labels: overview.data.trend.map((item) => item.label),
    values: overview.data.trend.map((item) => item.orderCount),
    orderCount: overview.data.trend.reduce((total, item) => total + item.orderCount, 0),
    freightAmount: overview.data.trend.reduce((total, item) => total + item.freightAmount, 0)
  }))
  const statusTotal = computed(() =>
    Object.values(overview.data.statusCounts).reduce((total, value) => total + value, 0)
  )
  const statusItems = computed<DashboardStatusItem[]>(() =>
    statusDefinitions.map((item) => {
      const value = overview.data.statusCounts[item.key] ?? 0
      return {
        ...item,
        value,
        percent: statusTotal.value ? Math.round((value / statusTotal.value) * 100) : 0
      }
    })
  )
  const reminderTotal = computed(() =>
    overview.data.reminders.reduce((total, item) => total + item.count, 0)
  )
  const loadingMode = computed<'mask' | 'skeleton'>(() => (overview.loaded ? 'mask' : 'skeleton'))
  const pageError = computed(() => (overview.loaded ? null : overview.error))
  const metricCards = computed<DashboardMetric[]>(() => [
    {
      key: 'today-order',
      label: '今日开单',
      value: `${overview.data.todayOrderCount} 单`,
      hint: `开单运费 ¥ ${formatMoney(overview.data.todayFreightAmount)}`,
      icon: 'ri:file-list-3-line',
      tone: 'blue'
    },
    {
      key: 'pending-dispatch',
      label: '待配载',
      value: `${overview.data.pendingDispatchCount} 单`,
      hint: '待安排车辆与司机',
      icon: 'ri:truck-line',
      tone: 'orange'
    },
    {
      key: 'in-transit',
      label: '运输中',
      value: `${overview.data.inTransitCount} 单`,
      hint: '实时关注运输进度',
      icon: 'ri:route-line',
      tone: 'green'
    },
    {
      key: 'risk',
      label: '风险待处理',
      value: `${reminderTotal.value} 项`,
      hint: `${overview.data.pendingAuditVehicleCount} 台车辆待审核`,
      icon: 'ri:alarm-warning-line',
      tone: 'red'
    }
  ])

  async function refreshData(): Promise<void> {
    overview.loading = true
    overview.error = null
    try {
      overview.data = await fetchDashboardData(overview.days)
      overview.loaded = true
    } catch (error) {
      overview.error = error instanceof Error ? error : new Error('运营工作台加载失败')
    } finally {
      overview.loading = false
    }
  }
  function handleTrendDaysChange(days: number): void {
    if (overview.days === days) return
    overview.days = days
    void refreshData()
  }
  function navigateTo(path: string): void {
    void router.push(path)
  }
  function openOrder(id?: string): void {
    if (id) void router.push({ name: 'TmsOrderDetail', params: { id } })
  }
  function formatMoney(value?: number | string | null): string {
    const amount = Number(value ?? 0)
    return Number.isFinite(amount)
      ? amount.toLocaleString('zh-CN', { maximumFractionDigits: 2 })
      : '0'
  }
  onMounted(() => {
    void refreshData()
  })
  defineOptions({ name: 'Console' })
</script>

<style scoped lang="scss">
  .operations-dashboard {
    min-height: 100%;

    :deep(> .art-async-state) {
      display: grid;
      gap: 18px;
      padding-bottom: var(--art-space-6);
    }

    &__summary {
      display: grid;
      grid-template-columns: minmax(0, 1.62fr) minmax(330px, 0.72fr);
      gap: 18px;
    }

    &__operations {
      display: grid;
      grid-template-columns: minmax(0, 1.48fr) minmax(330px, 0.78fr);
      gap: 18px;
    }

    @media screen and (width <= 1080px) {
      &__summary,
      &__operations {
        grid-template-columns: 1fr;
      }
    }

    @media screen and (width <= 720px) {
      :deep(> .art-async-state) {
        gap: var(--art-space-3);
      }
    }
  }
</style>
