<template>
  <div class="vehicle-reminder-risk">
    <BusinessWorkspaceHeader
      eyebrow="VEHICLE RISK CONTROL"
      :title="`${title}风险概览`"
      :description="description"
      icon="ri:alarm-warning-line"
      :tags="overviewTags"
      :metrics="workspaceMetrics"
      @metric-click="handleMetricClick"
    />

    <div v-if="overview.error" class="vehicle-reminder-risk__error art-card-xs" role="alert">
      <div>
        <ArtSvgIcon icon="ri:error-warning-line" />
        <span>风险数据暂时无法加载，不影响下方提醒列表。</span>
      </div>
      <ElButton link type="primary" @click="loadOverview">重新加载</ElButton>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { watchDebounced } from '@vueuse/core'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric,
    type BusinessWorkspaceTag
  } from '@/components/business/business-workspace-header/index.vue'

  defineOptions({ name: 'VehicleReminderRiskOverview' })

  type ReminderSearchParams = Api.Vms.ReminderManage.VehicleReminderSearchParams
  type RiskBand = Api.Vms.ReminderManage.VehicleReminderRiskBand
  type RiskOverview = Api.Vms.ReminderManage.VehicleReminderRiskOverview

  interface RiskOverviewResponse {
    data?: RiskOverview | null
  }

  interface Props {
    title: string
    description: string
    filters: ReminderSearchParams
    fetchFn: (params: ReminderSearchParams) => Promise<RiskOverviewResponse>
  }

  interface MetricCard extends BusinessWorkspaceMetric {
    key: string
    label: string
    value: number
    band: RiskBand
  }

  const props = defineProps<Props>()
  const emit = defineEmits<{ select: [band: RiskBand] }>()
  const activeRiskBand = computed<RiskBand>(() => props.filters.riskBand ?? 'all')
  const overview = reactive<{ loading: boolean; error: Error | null; data: RiskOverview }>({
    loading: true,
    error: null,
    data: { total: 0, overdue: 0, dueWithin7Days: 0, dueWithin30Days: 0, stable: 0 }
  })

  const metricCards = computed<MetricCard[]>(() => [
    {
      key: 'total',
      label: '全部提醒',
      value: overview.data.total,
      description: '当前范围内的全部风险对象',
      icon: 'ri:radar-line',
      tone: 'info',
      band: 'all'
    },
    {
      key: 'overdue',
      label: '已逾期',
      value: overview.data.overdue,
      description: '需要立即确认并处置',
      icon: 'ri:alarm-warning-line',
      tone: 'danger',
      band: 'overdue'
    },
    {
      key: 'seven-days',
      label: '7 天内到期',
      value: overview.data.dueWithin7Days,
      description: '建议本周完成处理安排',
      icon: 'ri:timer-flash-line',
      tone: 'warning',
      band: 'due_7'
    },
    {
      key: 'thirty-days',
      label: '8–30 天到期',
      value: overview.data.dueWithin30Days,
      description: '进入近期准备窗口',
      icon: 'ri:calendar-check-line',
      tone: 'primary',
      band: 'due_30'
    }
  ])

  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() =>
    metricCards.value.map((item) => ({
      ...item,
      interactive: true,
      selected: activeRiskBand.value === item.band,
      loading: overview.loading
    }))
  )
  const overviewTags = computed<BusinessWorkspaceTag[]>(() => [
    {
      label: `状态稳定 ${overview.data.stable}`,
      type: 'success',
      effect: 'plain'
    },
    { label: '支持风险区间筛选', type: 'info', effect: 'plain' }
  ])

  const handleMetricClick = (metric: BusinessWorkspaceMetric): void => {
    const target = metricCards.value.find((item) => item.key === metric.key)
    if (target) emit('select', target.band)
  }

  async function loadOverview(): Promise<void> {
    overview.loading = true
    overview.error = null
    try {
      const result = await props.fetchFn({
        companyName: props.filters.companyName,
        plateNo: props.filters.plateNo
      })
      if (result.data) overview.data = result.data
    } catch (error) {
      overview.error = error instanceof Error ? error : new Error('风险概览加载失败')
    } finally {
      overview.loading = false
    }
  }

  watchDebounced(
    () => [props.filters.companyName, props.filters.plateNo],
    () => void loadOverview(),
    { debounce: 260, immediate: true }
  )

  defineExpose({ loadOverview })
</script>

<style scoped lang="scss">
  .vehicle-reminder-risk {
    display: grid;
    gap: 12px;
    margin-bottom: 12px;

    &__error,
    &__error > div {
      display: flex;
      gap: 8px;
      align-items: center;
    }

    &__error {
      justify-content: space-between;
      min-height: 54px;
      padding: 10px 14px;
      color: var(--el-color-warning);
      background: var(--el-color-warning-light-9);
      border-radius: var(--el-border-radius-base);
    }

    @media (width <= 680px) {
      &__error {
        flex-direction: column;
        align-items: flex-start;
      }
    }
  }
</style>

<style lang="scss">
  .el-table__body tr.vehicle-reminder-row--overdue > td.el-table__cell {
    background: color-mix(in srgb, var(--el-color-danger) 4%, var(--el-bg-color));
  }

  .el-table__body tr.vehicle-reminder-row--overdue > td.el-table__cell:first-child {
    box-shadow: inset 3px 0 0 var(--el-color-danger);
  }

  .el-table__body tr.vehicle-reminder-row--urgent > td.el-table__cell {
    background: color-mix(in srgb, var(--el-color-warning) 4%, var(--el-bg-color));
  }

  .el-table__body tr.vehicle-reminder-row--urgent > td.el-table__cell:first-child {
    box-shadow: inset 3px 0 0 var(--el-color-warning);
  }
</style>
