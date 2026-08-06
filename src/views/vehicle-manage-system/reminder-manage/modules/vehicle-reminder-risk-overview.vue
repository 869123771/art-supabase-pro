<template>
  <section class="vehicle-reminder-risk art-card-xs" :aria-label="`${title}风险概览`">
    <header class="vehicle-reminder-risk__header">
      <div>
        <span>RISK OVERVIEW</span>
        <h1>{{ title }}风险概览</h1>
        <p>{{ description }}</p>
      </div>
      <div class="vehicle-reminder-risk__stable">
        <span>状态稳定</span>
        <strong>{{ overview.data.stable }}</strong>
        <small>30 天后或暂无临期风险</small>
      </div>
    </header>

    <div v-if="overview.error" class="vehicle-reminder-risk__error">
      <div>
        <ArtSvgIcon icon="ri:error-warning-line" />
        <span>风险数据暂时无法加载，不影响下方提醒列表。</span>
      </div>
      <ElButton link type="primary" @click="loadOverview">重新加载</ElButton>
    </div>

    <div v-else class="vehicle-reminder-risk__metrics" :aria-busy="overview.loading">
      <button
        v-for="item in metricCards"
        :key="item.key"
        type="button"
        :class="[`is-${item.tone}`, { 'is-active': activeRiskBand === item.band }]"
        :aria-pressed="activeRiskBand === item.band"
        @click="emit('select', item.band)"
      >
        <span v-if="activeRiskBand === item.band" class="vehicle-reminder-risk__selected">
          筛选中
        </span>
        <div class="vehicle-reminder-risk__metric-icon">
          <ArtSvgIcon :icon="item.icon" />
        </div>
        <div>
          <span>{{ item.label }}</span>
          <ElSkeleton v-if="overview.loading" animated :rows="0">
            <template #template><ElSkeletonItem variant="text" /></template>
          </ElSkeleton>
          <strong v-else>{{ item.value }}</strong>
          <small>{{ item.hint }}</small>
        </div>
      </button>
    </div>
  </section>
</template>

<script setup lang="ts">
  import { watchDebounced } from '@vueuse/core'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'VehicleReminderRiskOverview' })

  type ReminderSearchParams = Api.VehicleMgtSys.ReminderManage.VehicleReminderSearchParams
  type RiskBand = Api.VehicleMgtSys.ReminderManage.VehicleReminderRiskBand
  type RiskOverview = Api.VehicleMgtSys.ReminderManage.VehicleReminderRiskOverview

  interface RiskOverviewResponse {
    data?: RiskOverview | null
  }

  interface Props {
    title: string
    description: string
    filters: ReminderSearchParams
    fetchFn: (params: ReminderSearchParams) => Promise<RiskOverviewResponse>
  }

  interface MetricCard {
    key: string
    label: string
    value: number
    hint: string
    icon: string
    tone: 'neutral' | 'danger' | 'warning' | 'primary'
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
      hint: '当前范围内的全部风险对象',
      icon: 'ri:radar-line',
      tone: 'neutral',
      band: 'all'
    },
    {
      key: 'overdue',
      label: '已逾期',
      value: overview.data.overdue,
      hint: '需要立即确认并处置',
      icon: 'ri:alarm-warning-line',
      tone: 'danger',
      band: 'overdue'
    },
    {
      key: 'seven-days',
      label: '7 天内到期',
      value: overview.data.dueWithin7Days,
      hint: '建议本周完成处理安排',
      icon: 'ri:timer-flash-line',
      tone: 'warning',
      band: 'due_7'
    },
    {
      key: 'thirty-days',
      label: '8–30 天到期',
      value: overview.data.dueWithin30Days,
      hint: '进入近期准备窗口',
      icon: 'ri:calendar-check-line',
      tone: 'primary',
      band: 'due_30'
    }
  ])

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
    gap: 16px;
    padding: 20px 22px;
    margin-bottom: 12px;
    overflow: hidden;
    background:
      linear-gradient(
        105deg,
        color-mix(in srgb, var(--theme-color) 5%, transparent),
        transparent 38%
      ),
      var(--art-main-bg-color);

    &__header {
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      min-width: 0;

      > div:first-child {
        min-width: 0;

        > span {
          font-size: 10px;
          font-weight: 700;
          color: var(--theme-color);
          letter-spacing: 0.14em;
        }
      }

      h1 {
        margin: 3px 0 4px;
        font-size: 19px;
        color: var(--el-text-color-primary);
        text-wrap: balance;
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__stable {
      display: grid;
      flex: 0 0 auto;
      grid-template-columns: auto auto;
      gap: 0 10px;
      align-items: baseline;
      padding-left: 22px;
      border-left: 1px solid var(--el-border-color-lighter);

      span,
      small {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 24px;
        color: var(--el-color-success);
        font-variant-numeric: tabular-nums;
      }

      small {
        grid-column: 1 / -1;
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;

      button {
        position: relative;
        display: flex;
        gap: 11px;
        align-items: center;
        min-width: 0;
        min-height: 74px;
        padding: 13px 14px;
        background: color-mix(in srgb, var(--art-main-bg-color) 95%, var(--theme-color));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
        font: inherit;
        text-align: left;
        cursor: pointer;
        transition:
          border-color 160ms ease,
          background-color 160ms ease,
          transform 160ms ease;

        &:hover {
          border-color: color-mix(in srgb, var(--theme-color) 42%, var(--el-border-color));
          transform: translateY(-1px);
        }

        &:focus-visible {
          outline: 2px solid color-mix(in srgb, var(--theme-color) 65%, transparent);
          outline-offset: 2px;
        }

        &.is-active {
          background: color-mix(in srgb, var(--theme-color) 7%, var(--art-main-bg-color));
          border-color: var(--theme-color);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--theme-color) 18%, transparent);
        }

        > div:last-child {
          display: grid;
          gap: 2px;
          min-width: 0;
        }

        span,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        span {
          font-size: 11px;
          color: var(--el-text-color-secondary);
        }

        strong {
          font-size: 21px;
          color: var(--el-text-color-primary);
          font-variant-numeric: tabular-nums;
        }

        small {
          font-size: 10px;
          color: var(--el-text-color-placeholder);
        }

        &.is-danger {
          border-color: var(--el-color-danger-light-7);

          .vehicle-reminder-risk__metric-icon,
          strong {
            color: var(--el-color-danger);
          }

          .vehicle-reminder-risk__metric-icon {
            background: var(--el-color-danger-light-9);
          }
        }

        &.is-warning {
          .vehicle-reminder-risk__metric-icon,
          strong {
            color: var(--el-color-warning);
          }

          .vehicle-reminder-risk__metric-icon {
            background: var(--el-color-warning-light-9);
          }
        }

        &.is-primary {
          .vehicle-reminder-risk__metric-icon {
            color: var(--theme-color);
            background: color-mix(in srgb, var(--theme-color) 10%, transparent);
          }
        }
      }

      :deep(.el-skeleton__item) {
        width: 54px;
        height: 18px;
      }
    }

    &__selected {
      position: absolute;
      top: 7px;
      right: 9px;
      font-size: 9px !important;
      font-weight: 700;
      color: var(--theme-color) !important;
      letter-spacing: 0.04em;
    }

    &__metric-icon {
      display: grid;
      flex: 0 0 36px;
      place-items: center;
      width: 36px;
      height: 36px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }

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

    @media (width <= 1000px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 680px) {
      &__header {
        align-items: flex-start;
      }

      &__header,
      &__error {
        flex-direction: column;
      }

      &__stable {
        padding-left: 0;
        border-left: 0;
      }

      &__metrics {
        grid-template-columns: 1fr;
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
