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
      :user-context="userContext"
      :date-text="dateText"
      :today-order-count="overview.data.todayOrderCount"
      :pending-dispatch-count="overview.data.pendingDispatchCount"
      :in-transit-count="overview.data.inTransitCount"
      @create-order="navigateTo('/tms-transportation/order-open')"
      @dispatch="navigateTo('/tms-transportation/waybill-management/pending')"
      @refresh="refreshData"
    />

    <DashboardMetricCards :items="metricCards" @select="navigateTo" />

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

    <DashboardRecentOrders
      :orders="overview.data.recentOrders"
      @view-orders="navigateTo('/tms-transportation/order-list')"
      @open-order="openOrder"
    />
  </ArtPageShell>
</template>

<script setup lang="ts">
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
  const { info, language } = storeToRefs(useUserStore())
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
  const locale = computed(() =>
    String(language.value).toLowerCase().startsWith('en') ? 'en-US' : 'zh-CN'
  )
  const greeting = computed(() => {
    const hour = new Date().getHours()
    return hour < 12 ? '早上好' : hour < 18 ? '下午好' : '晚上好'
  })
  const userName = computed(() => {
    const candidates = [
      info.value?.nickName,
      info.value?.organization?.organizationName,
      info.value?.userName
    ]
    return (
      candidates.find((value) => value && !/^\d+$/.test(String(value).trim()))?.trim() || '用户'
    )
  })
  const userContext = computed(() => {
    const organization = info.value?.organization?.organizationName
    const role = info.value?.userRoles?.[0]
    const roleLabels: Record<string, string> = {
      R_SUPER: '平台管理员',
      R_ADMIN: '管理员',
      R_REGISTER: '注册用户'
    }
    return [organization, role ? roleLabels[role] : ''].filter(Boolean).join(' · ')
  })
  const dateText = computed(() =>
    new Intl.DateTimeFormat(locale.value, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      weekday: 'long'
    }).format(new Date())
  )
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
      value: formatNumber(overview.data.todayOrderCount),
      unit: '单',
      hint: '今日新增运输订单',
      icon: 'ri:file-list-3-line',
      tone: 'primary',
      route: '/tms-transportation/order-list'
    },
    {
      key: 'today-freight',
      label: '今日运费',
      value: `¥ ${formatMoney(overview.data.todayFreightAmount)}`,
      hint: '按今日开单金额汇总',
      icon: 'ri:money-cny-circle-line',
      tone: 'info',
      route: '/tms-transportation/order-list'
    },
    {
      key: 'pending-dispatch',
      label: '待调度',
      value: formatNumber(overview.data.pendingDispatchCount),
      unit: '单',
      hint: '待安排车辆与司机',
      icon: 'ri:truck-line',
      tone: 'warning',
      route: '/tms-transportation/waybill-management/pending'
    },
    {
      key: 'in-transit',
      label: '运输中',
      value: formatNumber(overview.data.inTransitCount),
      unit: '单',
      hint: '实时关注运输进度',
      icon: 'ri:route-line',
      tone: 'success',
      route: '/tms-transportation/in-transit-monitor'
    },
    {
      key: 'completed-today',
      label: '今日完成',
      value: formatNumber(overview.data.completedTodayCount),
      unit: '单',
      hint: '今日完成签收结案',
      icon: 'ri:checkbox-circle-line',
      tone: 'success',
      route: '/tms-transportation/order-list'
    },
    {
      key: 'risk',
      label: '风险待处理',
      value: formatNumber(reminderTotal.value),
      unit: '项',
      hint: `${overview.data.pendingAuditVehicleCount} 台车辆待审核`,
      icon: 'ri:alarm-warning-line',
      tone: 'danger',
      route: '/vehicle-manage-system/reminder-manage'
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
      ? new Intl.NumberFormat(locale.value, { maximumFractionDigits: 2 }).format(amount)
      : '0'
  }
  function formatNumber(value: number): string {
    return new Intl.NumberFormat(locale.value, { maximumFractionDigits: 0 }).format(value)
  }
  onMounted(() => {
    void refreshData()
  })
  defineOptions({ name: 'Console' })
</script>

<style scoped lang="scss">
  .operations-dashboard {
    min-height: 100%;
    font-variant-numeric: tabular-nums;

    :deep(> .art-async-state) {
      display: grid;
      gap: var(--art-space-4);
      padding-bottom: var(--art-space-6);
    }

    &__summary {
      display: grid;
      grid-template-columns: minmax(0, 1.62fr) minmax(330px, 0.72fr);
      gap: var(--art-space-4);
    }

    &__operations {
      display: grid;
      grid-template-columns: minmax(0, 1.48fr) minmax(330px, 0.78fr);
      gap: var(--art-space-4);
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
