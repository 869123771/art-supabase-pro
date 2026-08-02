<template>
  <div class="ai-operations">
    <section class="ai-operations__hero art-card-xs">
      <div class="ai-operations__hero-main">
        <div class="ai-operations__brand">
          <ArtSvgIcon icon="ri:brain-2-line" />
        </div>
        <div>
          <span>AI OPERATIONS</span>
          <h1>AI 运行中心</h1>
          <p
            >持续跟踪调用质量、响应速度、Token 消耗与失败原因，让每一次 AI 执行都可观测、可追溯。</p
          >
        </div>
      </div>
      <div class="ai-operations__hero-actions">
        <ElRadioGroup v-model="overview.days" size="small" @change="loadOverview">
          <ElRadioButton :value="7">7 天</ElRadioButton>
          <ElRadioButton :value="30">30 天</ElRadioButton>
          <ElRadioButton :value="90">90 天</ElRadioButton>
        </ElRadioGroup>
        <ElTooltip content="刷新运行数据" placement="bottom">
          <ArtIconButton
            icon="ri:refresh-line"
            circle
            :class="{ 'ai-operations__refreshing': overview.loading }"
            @click="refreshAll"
          />
        </ElTooltip>
      </div>
    </section>

    <section class="ai-operations__metrics" v-loading="overview.loading">
      <article
        v-for="metric in metricCards"
        :key="metric.key"
        class="ai-operations__metric art-card-xs"
      >
        <div :class="['ai-operations__metric-icon', `is-${metric.tone}`]">
          <ArtSvgIcon :icon="metric.icon" />
        </div>
        <div>
          <span>{{ metric.label }}</span>
          <strong>{{ metric.value }}</strong>
          <small>{{ metric.hint }}</small>
        </div>
      </article>
    </section>

    <section class="ai-operations__insights">
      <article class="ai-operations__trend art-card-xs">
        <header class="ai-operations__card-header">
          <div>
            <span>运行趋势</span>
            <h2>每日执行质量</h2>
          </div>
          <div class="ai-operations__legend">
            <span class="is-success">成功</span>
            <span class="is-danger">失败</span>
          </div>
        </header>
        <ArtLineChart
          height="260px"
          :data="trendSeries"
          :x-axis-data="trendLabels"
          :colors="['#36c98f', '#f56c6c']"
          :show-area-color="true"
          :show-axis-line="false"
          :show-legend="false"
          :loading="overview.loading"
        />
      </article>

      <article class="ai-operations__features art-card-xs">
        <header class="ai-operations__card-header">
          <div>
            <span>能力分布</span>
            <h2>功能调用占比</h2>
          </div>
          <strong>{{ formatNumber(overview.data.totalRuns) }} 次</strong>
        </header>
        <div class="ai-operations__feature-content">
          <ArtRingChart
            height="210px"
            :data="featureChartData"
            :colors="['#5b8ff9', '#5ad8a6', '#f6bd16', '#7262fd', '#78d3f8']"
            :center-text="`${overview.data.featureBreakdown.length} 个场景`"
            :loading="overview.loading"
          />
          <div class="ai-operations__feature-list">
            <div v-for="item in overview.data.featureBreakdown" :key="item.feature">
              <span
                ><i /><ArtDictDisplay dict-code="aiRunFeature" :value="item.feature" display="text"
              /></span>
              <strong>{{ item.total }}</strong>
              <small>{{ formatDuration(item.averageLatencyMs) }}</small>
            </div>
            <ElEmpty
              v-if="!overview.data.featureBreakdown.length"
              description="暂无运行数据"
              :image-size="54"
            />
          </div>
        </div>
      </article>
    </section>

    <section class="ai-operations__health art-card-xs">
      <div class="ai-operations__health-title">
        <div class="ai-operations__health-icon"><ArtSvgIcon icon="ri:heart-pulse-line" /></div>
        <div>
          <span>质量信号</span>
          <h2>反馈与异常概览</h2>
        </div>
      </div>
      <div class="ai-operations__feedback">
        <div
          ><ArtSvgIcon icon="ri:thumb-up-line" /><span>有帮助</span
          ><strong>{{ overview.data.positiveFeedback }}</strong></div
        >
        <div
          ><ArtSvgIcon icon="ri:thumb-down-line" /><span>需改进</span
          ><strong>{{ overview.data.negativeFeedback }}</strong></div
        >
      </div>
      <div class="ai-operations__errors">
        <template v-if="overview.data.topErrors.length">
          <div v-for="item in overview.data.topErrors" :key="item.code">
            <code>{{ item.code }}</code
            ><span>{{ item.count }} 次</span>
          </div>
        </template>
        <div v-else class="ai-operations__healthy">
          <ArtSvgIcon icon="ri:checkbox-circle-line" /> 当前周期内暂无失败异常
        </div>
      </div>
    </section>

    <section class="ai-operations__table">
      <ArtTableQuery
        ref="tableQueryRef"
        v-model="searchQuery"
        :search-items="searchItems"
        :api-fn="fetchAiRunList"
        :columns-factory="columnsFactory"
        :search-bar-props="{ span: 6, labelWidth: 84 }"
        :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
      />
    </section>

    <AiRunDetailDrawer ref="detailDrawerRef" @diagnosed="refreshAfterDiagnosis" />
  </div>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type { ColumnOption } from '@/types'
  import type { LineDataItem, PieDataItem } from '@/types/component/chart'
  import { useUserStore } from '@/store/modules/user'
  import {
    createEmptyAiOperationsOverview,
    fetchAiOperationsOverview,
    fetchAiRunList,
    type AiOperationsOverview,
    type AiRunListItem,
    type AiRunSearchParams
  } from '@/api/ai-operations'
  import AiRunDetailDrawer from './modules/ai-run-detail-drawer.vue'

  defineOptions({ name: 'AiOperations' })

  interface DetailDrawerExpose {
    handleOpen: (data: { id: string }) => Promise<void>
  }

  type MetricTone = 'primary' | 'success' | 'warning' | 'purple'

  interface MetricCard {
    key: string
    label: string
    value: string
    hint: string
    icon: string
    tone: MetricTone
  }

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const detailDrawerRef = ref<DetailDrawerExpose>()
  const searchQuery = ref<Partial<AiRunSearchParams>>({
    feature: '',
    status: '',
    model: '',
    timeRange: undefined
  })
  const overview = reactive<{ days: number; loading: boolean; data: AiOperationsOverview }>({
    days: 30,
    loading: false,
    data: createEmptyAiOperationsOverview(30)
  })

  const metricCards = computed<MetricCard[]>(() => [
    {
      key: 'runs',
      label: '总运行次数',
      value: formatNumber(overview.data.totalRuns),
      hint: `${overview.data.runningRuns} 个任务正在运行`,
      icon: 'ri:flashlight-line',
      tone: 'primary'
    },
    {
      key: 'success',
      label: '成功率',
      value: `${overview.data.successRate.toFixed(1)}%`,
      hint: `${overview.data.failedRuns} 次失败需要关注`,
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      key: 'latency',
      label: '平均响应',
      value: formatDuration(overview.data.averageLatencyMs),
      hint: `P95 ${formatDuration(overview.data.p95LatencyMs)}`,
      icon: 'ri:speed-up-line',
      tone: 'warning'
    },
    {
      key: 'tokens',
      label: 'Token 消耗',
      value: formatCompactNumber(overview.data.inputTokens + overview.data.outputTokens),
      hint: `输入 ${formatCompactNumber(overview.data.inputTokens)} · 输出 ${formatCompactNumber(overview.data.outputTokens)}`,
      icon: 'ri:coins-line',
      tone: 'purple'
    }
  ])

  const trendLabels = computed(() =>
    overview.data.dailyTrend.map((item) => dayjs(item.date).format('MM-DD'))
  )
  const trendSeries = computed<LineDataItem[]>(() => [
    {
      name: '成功',
      data: overview.data.dailyTrend.map((item) => item.succeeded),
      showAreaColor: true
    },
    {
      name: '失败',
      data: overview.data.dailyTrend.map((item) => item.failed),
      showAreaColor: true
    }
  ])
  const featureChartData = computed<PieDataItem[]>(() =>
    overview.data.featureBreakdown.map((item) => ({ name: item.feature, value: item.total }))
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '功能场景',
      key: 'feature',
      type: 'select',
      props: {
        placeholder: '请选择功能场景',
        options: getDictMap.value?.aiRunFeature ?? [],
        clearable: true
      }
    },
    {
      label: '运行状态',
      key: 'status',
      type: 'select',
      props: {
        placeholder: '请选择运行状态',
        options: getDictMap.value?.aiRunStatus ?? [],
        clearable: true
      }
    },
    {
      label: '模型',
      key: 'model',
      type: 'input',
      props: { placeholder: '请输入模型名称', clearable: true }
    },
    {
      label: '运行日期',
      key: 'timeRange',
      type: 'date',
      props: {
        type: 'daterange',
        rangeSeparator: '至',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        valueFormat: 'YYYY-MM-DD'
      }
    }
  ])

  const columnsFactory = (): ColumnOption<AiRunListItem>[] => [
    { type: 'globalIndex', label: '序号', width: 76 },
    {
      prop: 'feature',
      label: '功能场景',
      minWidth: 120,
      dict: { code: 'aiRunFeature', display: 'text' }
    },
    {
      prop: 'status',
      label: '状态',
      width: 92,
      dict: { code: 'aiRunStatus', display: 'auto' }
    },
    { prop: 'model', label: '模型', minWidth: 160, showOverflowTooltip: true },
    {
      prop: 'latencyMs',
      label: '耗时',
      width: 100,
      formatter: (row) => (
        <span class={getLatencyClass(row.latencyMs)}>{formatDuration(row.latencyMs)}</span>
      )
    },
    {
      prop: 'tokens',
      label: 'Token',
      width: 112,
      formatter: (row) => <span>{formatNumber(row.inputTokens + row.outputTokens)}</span>
    },
    {
      prop: 'toolCalls',
      label: '工具',
      width: 78,
      formatter: (row) => <span>{row.toolCalls?.length ?? 0}</span>
    },
    {
      prop: 'feedback',
      label: '反馈',
      width: 88,
      formatter: (row) => renderFeedback(row)
    },
    {
      prop: 'startedAt',
      label: '开始时间',
      width: 170,
      formatter: (row) => <span>{formatDateTime(row.startedAt)}</span>
    },
    {
      prop: 'operation',
      label: '操作',
      width: 76,
      fixed: 'right',
      formatter: (row) => <ArtButtonTable type="view" onClick={() => openDetail(row)} />
    }
  ]

  async function loadOverview(): Promise<void> {
    overview.loading = true
    try {
      overview.data = await fetchAiOperationsOverview(overview.days)
    } finally {
      overview.loading = false
    }
  }

  async function refreshAll(): Promise<void> {
    if (overview.loading) return
    try {
      await Promise.all([loadOverview(), tableQueryRef.value?.refreshData()])
      ElMessage.success('AI 运行数据已刷新')
    } catch {
      // 接口层已统一展示错误信息。
    }
  }

  function openDetail(row: AiRunListItem): void {
    void detailDrawerRef.value?.handleOpen({ id: row.id })
  }

  function refreshAfterDiagnosis(): void {
    void Promise.all([loadOverview(), tableQueryRef.value?.refreshData()])
  }

  function renderFeedback(row: AiRunListItem) {
    const rating = row.feedback?.[0]?.rating
    if (rating === 1) return <ArtSvgIcon icon="ri:thumb-up-fill" class="text-success" />
    if (rating === -1) return <ArtSvgIcon icon="ri:thumb-down-fill" class="text-error" />
    return <span class="text-g-500">--</span>
  }

  function getLatencyClass(value?: number | null): string {
    if (value == null) return 'text-g-500'
    if (value > 15_000) return 'text-error'
    if (value > 5_000) return 'text-warning'
    return ''
  }

  function formatDuration(value?: number | null): string {
    if (value == null) return '--'
    if (value >= 1000) return `${(value / 1000).toFixed(value >= 10_000 ? 1 : 2)} s`
    return `${value} ms`
  }

  function formatNumber(value: number): string {
    return Number(value || 0).toLocaleString('zh-CN')
  }

  function formatCompactNumber(value: number): string {
    return Intl.NumberFormat('zh-CN', { notation: 'compact', maximumFractionDigits: 1 }).format(
      value || 0
    )
  }

  function formatDateTime(value?: string | null): string {
    return value ? dayjs(value).format('YYYY-MM-DD HH:mm:ss') : '--'
  }

  onMounted(async () => {
    await Promise.all([userStore.fetchDictList(), loadOverview()])
  })
</script>

<style scoped lang="scss">
  .ai-operations {
    display: grid;
    gap: 16px;
    padding-bottom: 20px;

    &__hero {
      position: relative;
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      min-height: 128px;
      padding: 24px 28px;
      overflow: hidden;

      &::after {
        position: absolute;
        top: -95px;
        right: 8%;
        width: 260px;
        height: 260px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, rgb(91 143 249 / 14%), transparent 68%);
      }
    }

    &__hero-main,
    &__hero-actions,
    &__health-title,
    &__feedback,
    &__feedback > div {
      display: flex;
      align-items: center;
    }

    &__hero-main {
      gap: 18px;
      min-width: 0;

      span {
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.16em;
      }

      h1 {
        margin: 3px 0 5px;
        font-size: 23px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.7;
        color: var(--el-text-color-secondary);
      }
    }

    &__brand {
      display: grid;
      flex: 0 0 58px;
      place-items: center;
      width: 58px;
      height: 58px;
      font-size: 27px;
      color: #fff;
      background: linear-gradient(145deg, var(--el-color-primary), #7259e7);
      border-radius: 17px;
      box-shadow: 0 14px 30px rgb(64 116 255 / 25%);
    }

    &__hero-actions {
      z-index: 1;
      flex-shrink: 0;
      gap: 10px;
    }

    &__refreshing :deep(svg) {
      animation: ai-operations-spin 0.8s linear infinite;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;
    }

    &__metric {
      display: flex;
      gap: 14px;
      align-items: center;
      min-width: 0;
      padding: 20px;

      > div:last-child {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      strong {
        font-size: 23px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 11px;
        color: var(--el-text-color-placeholder);
      }
    }

    &__metric-icon,
    &__health-icon {
      display: grid;
      flex-shrink: 0;
      place-items: center;
      width: 44px;
      height: 44px;
      font-size: 21px;
      border-radius: 13px;
    }

    &__metric-icon {
      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-purple {
        color: #7259e7;
        background: color-mix(in srgb, #7259e7 10%, var(--el-bg-color));
      }
    }

    &__insights {
      display: grid;
      grid-template-columns: minmax(0, 1.65fr) minmax(340px, 1fr);
      gap: 16px;
    }

    &__trend,
    &__features {
      min-width: 0;
      padding: 21px 24px 14px;
    }

    &__card-header {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 10px;

      span {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      h2 {
        margin: 3px 0 0;
        font-size: 17px;
        color: var(--el-text-color-primary);
      }

      > strong {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__legend {
      display: flex;
      gap: 14px;

      span::before {
        display: inline-block;
        width: 7px;
        height: 7px;
        margin-right: 6px;
        content: '';
        border-radius: 50%;
      }

      .is-success::before {
        background: #36c98f;
      }

      .is-danger::before {
        background: #f56c6c;
      }
    }

    &__feature-content {
      display: grid;
      grid-template-columns: 46% 54%;
      align-items: center;
      min-height: 250px;
    }

    &__feature-list {
      display: grid;
      gap: 12px;
      min-width: 0;

      > div:not(.el-empty) {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto auto;
        gap: 10px;
        align-items: center;
      }

      span {
        display: flex;
        gap: 7px;
        align-items: center;
        min-width: 0;
        font-size: 12px;
      }

      i {
        width: 7px;
        height: 7px;
        background: var(--el-color-primary);
        border-radius: 50%;
      }

      strong {
        font-size: 13px;
        color: var(--el-text-color-primary);
      }

      small {
        min-width: 57px;
        font-size: 10px;
        color: var(--el-text-color-placeholder);
        text-align: right;
      }
    }

    &__health {
      display: grid;
      grid-template-columns: minmax(210px, 0.7fr) minmax(240px, 0.8fr) minmax(320px, 1.5fr);
      gap: 20px;
      align-items: center;
      padding: 19px 24px;
    }

    &__health-title {
      gap: 12px;

      span {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      h2 {
        margin: 3px 0 0;
        font-size: 16px;
        color: var(--el-text-color-primary);
      }
    }

    &__health-icon {
      color: #7259e7;
      background: color-mix(in srgb, #7259e7 10%, var(--el-bg-color));
    }

    &__feedback {
      gap: 10px;

      > div {
        flex: 1;
        gap: 6px;
        padding: 10px 12px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      span {
        flex: 1;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 15px;
        color: var(--el-text-color-primary);
      }
    }

    &__errors {
      display: flex;
      gap: 8px;
      justify-content: flex-end;
      min-width: 0;
      overflow: hidden;

      > div {
        display: flex;
        gap: 7px;
        align-items: center;
        min-width: 0;
        padding: 8px 10px;
        background: var(--el-color-danger-light-9);
        border-radius: var(--el-border-radius-small);
      }

      code {
        max-width: 130px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 10px;
        color: var(--el-color-danger);
        white-space: nowrap;
      }

      span {
        flex-shrink: 0;
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }
    }

    &__errors &__healthy {
      color: var(--el-color-success);
      background: var(--el-color-success-light-9);
    }

    &__table {
      min-width: 0;
    }

    @media (width <= 1200px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__insights {
        grid-template-columns: 1fr;
      }

      &__health {
        grid-template-columns: 1fr 1fr;
      }

      &__errors {
        grid-column: 1 / -1;
        justify-content: flex-start;
      }
    }

    @media (width <= 720px) {
      &__hero {
        align-items: flex-start;
        padding: 20px;
      }

      &__hero,
      &__hero-actions {
        flex-direction: column;
      }

      &__hero-main {
        align-items: flex-start;
      }

      &__metrics {
        grid-template-columns: 1fr;
      }

      &__feature-content {
        grid-template-columns: 1fr;
      }

      &__health {
        grid-template-columns: 1fr;
      }

      &__errors {
        flex-wrap: wrap;
        grid-column: auto;
      }
    }
  }

  @keyframes ai-operations-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
