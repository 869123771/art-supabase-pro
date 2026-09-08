<template>
  <div ref="screenRef" class="enterprise-screen asset-maintenance-screen">
    <ArtAsyncState
      class="enterprise-screen__state"
      :loading="state.loading"
      :loading-mode="state.loaded ? 'mask' : 'skeleton'"
      :error="state.loaded ? null : state.error"
      :min-height="0"
      full-height
      @retry="loadData"
    >
      <ElScrollbar class="enterprise-screen__scrollbar">
        <div class="enterprise-screen__stage asset-maintenance-stage">
          <header class="command-header">
            <div class="command-header__identity">
              <button
                type="button"
                class="screen-icon-button"
                aria-label="返回工作台"
                title="返回工作台"
                @click="exitScreen"
              >
                <ArtSvgIcon icon="ri:arrow-left-line" />
              </button>
              <div>
                <span>ASSET RELIABILITY COMMAND</span>
                <h1>设备资产运维大屏</h1>
              </div>
            </div>

            <nav class="screen-nav" aria-label="大屏场景">
              <RouterLink to="/dashboard/business-cockpit">
                <ArtSvgIcon icon="ri:bar-chart-box-line" />
                经营驾驶舱
              </RouterLink>
              <RouterLink to="/dashboard/operations-command">
                <ArtSvgIcon icon="ri:radar-line" />
                运营态势
              </RouterLink>
              <RouterLink
                to="/dashboard/asset-maintenance-command"
                class="is-active"
                aria-current="page"
              >
                <ArtSvgIcon icon="ri:settings-3-line" />
                设备运维
              </RouterLink>
            </nav>

            <div class="command-header__status">
              <div>
                <time :datetime="currentTime">{{ timeText }}</time>
                <span>{{ dateText }}</span>
              </div>
              <span class="live-status"><i /> PMIS · MDM 已联通</span>
              <button
                type="button"
                class="screen-icon-button"
                :aria-label="fullscreenButtonLabel"
                :aria-pressed="isFullscreen"
                :title="fullscreenButtonLabel"
                @click="toggleScreenFullscreen"
              >
                <ArtSvgIcon
                  :icon="isFullscreen ? 'ri:fullscreen-exit-line' : 'ri:fullscreen-line'"
                />
              </button>
              <button
                type="button"
                class="screen-icon-button"
                :disabled="state.loading"
                aria-label="刷新设备运维数据"
                title="刷新设备运维数据"
                @click="loadData()"
              >
                <ArtSvgIcon icon="ri:refresh-line" :class="{ 'is-spinning': state.loading }" />
              </button>
            </div>
          </header>

          <main class="asset-screen-content">
            <section class="metric-rail" aria-label="设备运维核心指标">
              <article v-for="metric in primaryMetrics" :key="metric.label" class="hero-metric">
                <div class="hero-metric__icon" :class="`is-${metric.tone}`">
                  <ArtSvgIcon :icon="metric.icon" />
                </div>
                <div class="hero-metric__content">
                  <span>{{ metric.label }}</span>
                  <strong
                    >{{ metric.value }}<em>{{ metric.unit }}</em></strong
                  >
                  <small>{{ metric.hint }}</small>
                </div>
                <i class="hero-metric__signal" :class="`is-${metric.tone}`" />
              </article>
            </section>

            <section class="asset-command-layout">
              <div class="asset-column asset-column--left">
                <article class="screen-panel asset-health-panel">
                  <ScreenPanelHeading
                    eyebrow="ASSET VITALS"
                    title="设备生命体征"
                    icon="ri:pulse-line"
                  >
                    <template #aside>
                      <span class="panel-caption is-live">{{ healthLabel }}</span>
                    </template>
                  </ScreenPanelHeading>
                  <AssetVitalsChart
                    class="asset-vitals"
                    :health="equipmentHealth"
                    :connected-rate="connectedRate"
                    :inspection-rate="inspectionCompletionRate"
                  />
                  <div class="asset-status-composition__heading">
                    <span>设备状态构成</span>
                    <strong>{{ data.equipment.enabled }} 台在册</strong>
                  </div>
                  <div
                    class="asset-status-distribution"
                    role="img"
                    :aria-label="equipmentStatusSummary"
                  >
                    <i
                      v-for="item in equipmentStatuses"
                      :key="item.label"
                      :class="`is-${item.tone}`"
                      :style="{ width: `${item.percent}%` }"
                    />
                  </div>
                  <div class="asset-status-grid">
                    <div v-for="item in equipmentStatuses" :key="item.label">
                      <strong>{{ item.value }}<em> 台</em></strong>
                      <span><i :class="`is-${item.tone}`" />{{ item.label }}</span>
                    </div>
                  </div>
                </article>

                <article class="screen-panel department-load-panel">
                  <ScreenPanelHeading
                    eyebrow="WORKSHOP LOAD"
                    title="车间设备负荷"
                    icon="ri:building-4-line"
                  >
                    <template #aside>
                      <span class="panel-caption">{{ data.departmentLoad.length }} 个车间</span>
                    </template>
                  </ScreenPanelHeading>
                  <ScreenHorizontalBarChart
                    v-if="data.departmentLoad.length"
                    class="department-load-chart"
                    :items="departmentLoadChartItems"
                    summary-label="车间设备负荷"
                    value-label="设备"
                    risk-label="故障"
                  />
                  <div v-else class="asset-compact-empty">
                    <ArtSvgIcon icon="ri:building-4-line" />
                    <span>暂无已归属车间的设备</span>
                  </div>
                </article>
              </div>

              <div class="asset-column asset-column--center">
                <article class="screen-panel asset-reactor-panel">
                  <ScreenPanelHeading
                    eyebrow="3D RELIABILITY REACTOR"
                    title="设备可靠性反应堆"
                    icon="ri:cpu-line"
                  >
                    <template #aside>
                      <span class="panel-caption is-live">数据融合 {{ refreshText }}</span>
                    </template>
                  </ScreenPanelHeading>
                  <AssetReliabilityCore
                    :health="equipmentHealth"
                    :total="data.equipment.total"
                    :connected-rate="connectedRate"
                    :fault-count="data.equipment.fault"
                    :open-repair-count="data.repair.open"
                    :overdue-count="totalOverdue"
                    :risk-count="riskCount"
                  />
                </article>

                <article class="screen-panel maintenance-pipeline-panel">
                  <ScreenPanelHeading
                    eyebrow="MAINTENANCE LOOP"
                    title="维修闭环推进"
                    icon="ri:git-merge-line"
                  >
                    <template #aside>
                      <span class="pipeline-rate"
                        >本月闭环 {{ data.repair.completedMonth }} 单</span
                      >
                    </template>
                  </ScreenPanelHeading>
                  <ScreenStageChart
                    class="maintenance-pipeline-chart"
                    :items="repairPipeline"
                    accent-var="--asset-green"
                  />
                  <div class="inspection-progress">
                    <div>
                      <span>今日点巡检完成率</span>
                      <strong>{{ inspectionCompletionRate }}%</strong>
                    </div>
                    <i><b :style="{ width: `${inspectionCompletionRate}%` }" /></i>
                    <small>
                      {{ data.inspection.todayCompleted }}/{{ data.inspection.todayTotal }} 项已完成
                      · 近 30 天发现 {{ data.inspection.abnormal30d }} 项异常
                    </small>
                  </div>
                </article>
              </div>

              <div class="asset-column asset-column--right">
                <article class="screen-panel work-order-panel">
                  <ScreenPanelHeading
                    eyebrow="FAULT COMMAND"
                    title="故障抢修队列"
                    icon="ri:alarm-warning-line"
                  >
                    <template #aside>
                      <span class="risk-count">{{ data.repair.open }}</span>
                    </template>
                  </ScreenPanelHeading>
                  <div v-if="visibleActiveWorkOrders.length" class="asset-work-list">
                    <div
                      v-for="item in visibleActiveWorkOrders"
                      :key="item.id"
                      class="asset-work-item"
                    >
                      <i :class="`is-${urgencyTone(item.urgency)}`" />
                      <div>
                        <header>
                          <strong>{{ item.equipmentName }}</strong>
                          <span :class="`is-${urgencyTone(item.urgency)}`">{{
                            urgencyLabel(item.urgency)
                          }}</span>
                        </header>
                        <p>{{ item.faultSymptom }}</p>
                        <small>
                          {{ item.workOrderNo }} · {{ item.repairerName || '待指派维修人' }} ·
                          {{ dueTimeText(item.requiredCompleteAt) }}
                        </small>
                      </div>
                    </div>
                  </div>
                  <div v-else class="asset-compact-empty is-success">
                    <ArtSvgIcon icon="ri:shield-check-line" />
                    <span>当前没有未闭环故障工单</span>
                  </div>
                </article>

                <article class="screen-panel upcoming-task-panel">
                  <ScreenPanelHeading
                    eyebrow="SERVICE WINDOW"
                    title="近期保养窗口"
                    icon="ri:calendar-check-line"
                  >
                    <template #aside>
                      <span class="panel-caption"
                        >未来 30 天 {{ data.maintenance.scheduled30Days }} 项</span
                      >
                    </template>
                  </ScreenPanelHeading>
                  <template v-if="visibleUpcomingTasks.length">
                    <AssetMaintenanceWindowChart
                      class="maintenance-window-chart"
                      :items="maintenanceWindowChartItems"
                    />
                    <div class="upcoming-task-list is-compact">
                      <div v-for="item in visibleUpcomingTasks" :key="item.id">
                        <time :datetime="item.dueDate">
                          <strong>{{ dayText(item.dueDate) }}</strong>
                          <span>{{ monthText(item.dueDate) }}</span>
                        </time>
                        <div>
                          <header>
                            <strong>{{ item.equipmentName }}</strong>
                            <span :class="{ 'is-overdue': isTaskOverdue(item.dueDate) }">
                              {{
                                isTaskOverdue(item.dueDate)
                                  ? '已逾期'
                                  : planKindLabel(item.planKind)
                              }}
                            </span>
                          </header>
                          <p>{{ item.planName }}</p>
                          <small
                            >{{ item.responsibleName || '待安排负责人' }} · {{ item.taskNo }}</small
                          >
                        </div>
                      </div>
                    </div>
                  </template>
                  <div v-else class="asset-compact-empty">
                    <ArtSvgIcon icon="ri:calendar-check-line" />
                    <span>暂无待执行保养任务</span>
                  </div>
                </article>
              </div>
            </section>
          </main>

          <footer class="screen-footer">
            <div class="screen-footer__bus" aria-label="设备业务域接入状态">
              <span
                v-for="system in businessSystems"
                :key="system.code"
                :class="`is-${system.state}`"
              >
                <i /><b>{{ system.code }}</b>
              </span>
            </div>
            <span class="screen-footer__view">设备资产 · 点巡检 · 保养 · 维修闭环</span>
            <span class="screen-footer__scope">当前租户业务数据 · ASSET RELIABILITY BUS</span>
          </footer>
        </div>
      </ElScrollbar>
    </ArtAsyncState>
  </div>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import AssetMaintenanceWindowChart from './asset-maintenance-window-chart.vue'
  import AssetReliabilityCore from './asset-reliability-core.vue'
  import AssetVitalsChart from './asset-vitals-chart.vue'
  import ScreenHorizontalBarChart from './screen-horizontal-bar-chart.vue'
  import ScreenPanelHeading from './screen-panel-heading.vue'
  import ScreenStageChart from './screen-stage-chart.vue'
  import {
    fetchAssetMaintenanceDashboardData,
    type AssetMaintenanceDashboardData
  } from '@/api/enterprise-dashboard'

  type MetricTone = 'primary' | 'success' | 'warning' | 'danger' | 'info'
  type Urgency = 'normal' | 'urgent' | 'expedite' | 'emergency'

  interface ScreenState {
    loading: boolean
    loaded: boolean
    error: Error | null
    requestId: number
  }

  interface BusinessSystem {
    code: string
    state: 'live' | 'linked' | 'ready'
  }

  const router = useRouter()
  const screenRef = ref<HTMLElement | null>(null)
  const currentTime = ref(new Date().toISOString())
  const state = reactive<ScreenState>({ loading: false, loaded: false, error: null, requestId: 0 })
  const {
    isFullscreen,
    isSupported: isFullscreenSupported,
    toggle: toggleFullscreen
  } = useFullscreen(screenRef, { autoExit: true })

  const createEmptyData = (): AssetMaintenanceDashboardData => ({
    generatedAt: new Date().toISOString(),
    equipment: {
      total: 0,
      enabled: 0,
      normal: 0,
      maintenance: 0,
      fault: 0,
      idle: 0,
      critical: 0,
      connected: 0,
      unassigned: 0
    },
    inspection: { todayTotal: 0, todayCompleted: 0, pending: 0, overdue: 0, abnormal30d: 0 },
    maintenance: {
      enabledPlans: 0,
      pending: 0,
      overdue: 0,
      pendingConfirm: 0,
      completedMonth: 0,
      scheduled30Days: 0
    },
    repair: {
      open: 0,
      reported: 0,
      inProgress: 0,
      pendingConfirm: 0,
      overdue: 0,
      emergency: 0,
      completedMonth: 0
    },
    departmentLoad: [],
    categoryDistribution: [],
    activeWorkOrders: [],
    upcomingTasks: []
  })
  const data = reactive<AssetMaintenanceDashboardData>(createEmptyData())

  const timeText = computed(() => dayjs(currentTime.value).format('HH:mm:ss'))
  const dateText = computed(() => dayjs(currentTime.value).format('YYYY年MM月DD日 · dddd'))
  const refreshText = computed(() => dayjs(data.generatedAt).format('HH:mm:ss'))
  const fullscreenButtonLabel = computed(() => {
    if (!isFullscreenSupported.value) return '当前浏览器不支持全屏'
    return isFullscreen.value ? '退出全屏' : '进入全屏'
  })
  const equipmentHealth = computed(() =>
    data.equipment.enabled
      ? Math.max(
          0,
          Math.min(100, Math.round((data.equipment.normal / data.equipment.enabled) * 100))
        )
      : 0
  )
  const connectedRate = computed(() =>
    data.equipment.enabled
      ? Math.round((data.equipment.connected / data.equipment.enabled) * 100)
      : 0
  )
  const inspectionCompletionRate = computed(() =>
    data.inspection.todayTotal
      ? Math.round((data.inspection.todayCompleted / data.inspection.todayTotal) * 100)
      : 0
  )
  const totalOverdue = computed(
    () => data.inspection.overdue + data.maintenance.overdue + data.repair.overdue
  )
  const riskCount = computed(
    () => data.equipment.fault + totalOverdue.value + data.repair.emergency
  )
  const healthLabel = computed(() => {
    if (!data.equipment.enabled) return '暂无在册设备'
    if (equipmentHealth.value >= 90) return '运行稳定'
    if (equipmentHealth.value >= 75) return '重点观察'
    if (equipmentHealth.value >= 60) return '需安排检修'
    return '高风险运行'
  })
  const primaryMetrics = computed(() => [
    {
      label: '设备总量',
      value: data.equipment.total,
      unit: '台',
      hint: `${data.equipment.critical} 台关键设备`,
      icon: 'ri:database-2-line',
      tone: 'primary' as MetricTone
    },
    {
      label: '设备健康度',
      value: equipmentHealth.value,
      unit: '%',
      hint: `${data.equipment.normal}/${data.equipment.enabled} 台运行正常`,
      icon: 'ri:pulse-line',
      tone: scoreTone(equipmentHealth.value)
    },
    {
      label: '信号接入率',
      value: connectedRate.value,
      unit: '%',
      hint: `${data.equipment.connected} 台已接入安灯或状态卡`,
      icon: 'ri:wireless-charging-line',
      tone: connectedRate.value >= 80 ? ('success' as MetricTone) : ('info' as MetricTone)
    },
    {
      label: '今日点巡检',
      value: inspectionCompletionRate.value,
      unit: '%',
      hint: `${data.inspection.todayCompleted}/${data.inspection.todayTotal} 项已完成`,
      icon: 'ri:checkbox-circle-line',
      tone: scoreTone(inspectionCompletionRate.value)
    },
    {
      label: '未闭环维修',
      value: data.repair.open,
      unit: '单',
      hint: `${data.repair.inProgress} 单抢修中`,
      icon: 'ri:tools-line',
      tone: data.repair.open ? ('warning' as MetricTone) : ('success' as MetricTone)
    },
    {
      label: '逾期任务',
      value: totalOverdue.value,
      unit: '项',
      hint: '巡检、保养与维修聚合',
      icon: 'ri:alarm-warning-line',
      tone: totalOverdue.value ? ('danger' as MetricTone) : ('success' as MetricTone)
    }
  ])

  const equipmentStatuses = computed(() => {
    const total = Math.max(data.equipment.enabled, 1)
    return [
      { label: '正常运行', value: data.equipment.normal, tone: 'success' },
      { label: '保养维护', value: data.equipment.maintenance, tone: 'primary' },
      { label: '设备故障', value: data.equipment.fault, tone: 'danger' },
      { label: '空闲待机', value: data.equipment.idle, tone: 'info' }
    ].map((item) => ({ ...item, percent: Math.max(0, (item.value / total) * 100) }))
  })
  const equipmentStatusSummary = computed(
    () =>
      `设备状态构成：${equipmentStatuses.value
        .map((item) => `${item.label} ${item.value}台`)
        .join('，')}`
  )
  const repairPipeline = computed(() => [
    { label: '故障上报', value: data.repair.reported, caption: '等待受理' },
    { label: '抢修执行', value: data.repair.inProgress, caption: '维修处理中' },
    { label: '待确认', value: data.repair.pendingConfirm, caption: '等待验收' },
    { label: '本月闭环', value: data.repair.completedMonth, caption: '已完成工单' }
  ])
  const departmentLoadChartItems = computed(() =>
    data.departmentLoad.map((item) => ({
      label: item.departmentName,
      value: item.equipmentTotal,
      riskValue: item.faultCount,
      caption: `未闭环 ${item.openRepairCount} 单`
    }))
  )
  const visibleActiveWorkOrders = computed(() => data.activeWorkOrders.slice(0, 4))
  const visibleUpcomingTasks = computed(() => data.upcomingTasks.slice(0, 2))
  const maintenanceWindowChartItems = computed(() =>
    data.upcomingTasks.map((item) => ({
      name: item.equipmentName,
      dueDate: item.dueDate,
      planName: item.planName
    }))
  )
  const businessSystems: BusinessSystem[] = [
    { code: 'MDM', state: 'live' },
    { code: 'PMIS', state: 'live' },
    { code: 'SMIS', state: 'linked' },
    { code: 'IoT', state: 'linked' },
    { code: 'EAM', state: 'ready' },
    { code: 'AI', state: 'ready' }
  ]

  useIntervalFn(() => {
    currentTime.value = new Date().toISOString()
  }, 1000)
  useIntervalFn(() => {
    void loadData(false)
  }, 60000)

  onMounted(() => {
    void loadData()
  })

  async function loadData(showLoading = true): Promise<void> {
    const requestId = ++state.requestId
    if (showLoading) state.loading = true
    state.error = null
    try {
      const result = await fetchAssetMaintenanceDashboardData()
      if (requestId !== state.requestId) return
      Object.assign(data, result)
      state.loaded = true
    } catch (error) {
      if (requestId !== state.requestId) return
      state.error = error instanceof Error ? error : new Error('设备运维大屏加载失败')
    } finally {
      if (requestId === state.requestId) state.loading = false
    }
  }

  function scoreTone(score: number): MetricTone {
    if (score >= 90) return 'success'
    if (score >= 75) return 'primary'
    if (score >= 60) return 'warning'
    return 'danger'
  }

  function urgencyTone(urgency: Urgency): MetricTone {
    if (urgency === 'emergency') return 'danger'
    if (urgency === 'expedite' || urgency === 'urgent') return 'warning'
    return 'primary'
  }

  function urgencyLabel(urgency: Urgency): string {
    return { normal: '普通', urgent: '紧急', expedite: '加急', emergency: '特急' }[urgency]
  }

  function dueTimeText(value: string | null): string {
    if (!value) return '未设置完成时限'
    const target = dayjs(value)
    if (!target.isValid()) return '完成时限待确认'
    const minutes = target.diff(dayjs(), 'minute')
    if (minutes < 0) return `已逾期 ${formatDuration(Math.abs(minutes))}`
    return `${formatDuration(minutes)}后到期`
  }

  function formatDuration(minutes: number): string {
    if (minutes < 60) return `${minutes} 分钟`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours} 小时`
    return `${Math.floor(hours / 24)} 天`
  }

  function dayText(value: string): string {
    return dayjs(value).format('DD')
  }

  function monthText(value: string): string {
    return dayjs(value).format('MM月')
  }

  function isTaskOverdue(value: string): boolean {
    return dayjs(value).isBefore(dayjs(), 'day')
  }

  function planKindLabel(kind: 'maintenance' | 'preventive'): string {
    return kind === 'maintenance' ? '保养' : '预防维护'
  }

  async function toggleScreenFullscreen(): Promise<void> {
    if (!isFullscreenSupported.value) {
      ElMessage.warning('当前浏览器不支持全屏显示')
      return
    }
    try {
      await toggleFullscreen()
    } catch {
      ElMessage.error('全屏切换失败，请检查浏览器权限后重试')
    }
  }

  function exitScreen(): void {
    if (window.history.length > 1) {
      router.back()
      return
    }
    void router.push('/dashboard/console')
  }
</script>

<style scoped lang="scss" src="./enterprise-big-screen.scss"></style>
<style scoped lang="scss" src="./asset-maintenance-big-screen.scss"></style>
