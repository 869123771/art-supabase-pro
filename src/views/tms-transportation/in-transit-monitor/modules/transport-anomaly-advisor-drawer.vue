<template>
  <ArtDrawer ref="drawerRef" :loading="state.loading" :show-footer="false">
    <div class="transport-advisor">
      <template v-if="state.data">
        <section class="transport-advisor__hero art-card-xs">
          <div class="transport-advisor__hero-main">
            <span class="transport-advisor__icon">
              <ArtSvgIcon icon="ri:shield-flash-line" />
            </span>
            <div>
              <div class="transport-advisor__title-row">
                <strong>{{ state.data.assessment.orderNo }}</strong>
                <ElTag :type="riskTagType" effect="dark">{{ riskLabel }}</ElTag>
              </div>
              <p>{{ state.data.assessment.route }}</p>
            </div>
          </div>
          <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
            重新研判
          </ElButton>
          <div class="transport-advisor__score">
            <div>
              <span>风险评分</span>
              <strong>{{ state.data.assessment.riskScore }}</strong>
            </div>
            <div>
              <span>研判置信度</span>
              <strong>{{ Math.round(state.data.assessment.confidence * 100) }}%</strong>
            </div>
          </div>
          <p class="transport-advisor__summary">{{ state.data.assessment.summary }}</p>
        </section>

        <section class="transport-advisor__section">
          <ArtSectionTitle>异常信号</ArtSectionTitle>
          <div v-if="state.data.assessment.signals.length" class="transport-advisor__signals">
            <article
              v-for="signal in state.data.assessment.signals"
              :key="signal.type"
              class="transport-advisor__signal art-card-xs"
            >
              <header>
                <div>
                  <ArtSvgIcon :icon="signalIcon(signal.severity)" />
                  <strong>{{ signal.title }}</strong>
                </div>
                <ElTag :type="severityTagType(signal.severity)" effect="light">
                  {{ severityLabel(signal.severity) }}
                </ElTag>
              </header>
              <p>{{ signal.detail }}</p>
              <ul>
                <li v-for="item in signal.evidence" :key="item">{{ item }}</li>
              </ul>
            </article>
          </div>
          <ElEmpty v-else description="当前未识别到明确异常" :image-size="76" />
        </section>

        <section class="transport-advisor__section">
          <ArtSectionTitle>建议处置顺序</ArtSectionTitle>
          <ol class="transport-advisor__actions art-card-xs">
            <li v-for="(action, index) in state.data.assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <p>{{ action }}</p>
            </li>
          </ol>
        </section>

        <section class="transport-advisor__section">
          <ArtSectionTitle>数据边界</ArtSectionTitle>
          <ElAlert
            v-for="item in state.data.assessment.limitations"
            :key="item"
            type="info"
            :closable="false"
            show-icon
            :title="item"
          />
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 运输异常研判" />

        <footer class="transport-advisor__meta">
          <span>规则版本：{{ state.data.ruleVersion }}</span>
          <span>生成时间：{{ formatTime(state.data.generatedAt) }}</span>
          <span>本次结果只提供建议，不会自动改变订单或运单状态。</span>
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="异常研判失败"
        :sub-title="state.error"
      >
        <template #extra>
          <ElButton type="primary" @click="loadAssessment">重新研判</ElButton>
        </template>
      </ElResult>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeTransportAnomalyByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsTransportAnomalyAdvisorDrawer' })

  type AdvisorResponse = Api.Tms.InTransit.TransportAnomalyAdvisorResponse
  type RiskLevel = Api.Tms.InTransit.TransportRiskLevel
  type SignalSeverity = Api.Tms.InTransit.TransportAnomalySignal['severity']

  interface DrawerOpenData {
    orderId: string
    orderNo: string
  }

  interface AdvisorState {
    data: AdvisorResponse | null
    error: string
    loading: boolean
    openData: DrawerOpenData | null
  }

  const drawerRef = ref<ArtDrawerExpose<DrawerOpenData>>()
  const state: UnwrapNestedRefs<AdvisorState> = reactive<AdvisorState>({
    data: null,
    error: '',
    loading: false,
    openData: null
  })

  const riskLabelMap: Record<RiskLevel, string> = {
    critical: '严重风险',
    high: '高风险',
    medium: '中风险',
    low: '低风险'
  }

  const tagTypeMap = {
    critical: 'danger',
    high: 'danger',
    medium: 'warning',
    low: 'success'
  } as const

  const riskLabel = computed(() =>
    state.data ? riskLabelMap[state.data.assessment.riskLevel] : '-'
  )
  const riskTagType = computed(() =>
    state.data ? tagTypeMap[state.data.assessment.riskLevel] : 'info'
  )

  async function handleOpen(data: DrawerOpenData): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false, openData: data })
    await drawerRef.value?.handleOpen(data, {
      title: `AI 运输异常研判 · ${data.orderNo}`,
      size: 'lg',
      contentHeight: 'calc(100vh - 132px)',
      showFooter: false,
      onOpen: loadAssessment,
      onReset: () =>
        Object.assign(state, { data: null, error: '', loading: false, openData: null }),
      drawerProps: {
        appendToBody: true,
        closeOnClickModal: false,
        resizable: true
      }
    })
  }

  async function loadAssessment(): Promise<void> {
    const orderId = state.openData?.orderId
    if (!orderId || state.loading) return

    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeTransportAnomalyByAi(orderId)
      if (error) throw error
      if (!data) throw new Error('研判服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getErrorMessage(error)
    } finally {
      state.loading = false
    }
  }

  function severityLabel(severity: SignalSeverity): string {
    return severity === 'critical' ? '严重' : severity === 'high' ? '高风险' : '中风险'
  }

  function severityTagType(severity: SignalSeverity): 'danger' | 'warning' {
    return severity === 'medium' ? 'warning' : 'danger'
  }

  function signalIcon(severity: SignalSeverity): string {
    return severity === 'critical' ? 'ri:alarm-warning-line' : 'ri:error-warning-line'
  }

  function formatTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') || '-'
  }

  function getErrorMessage(error: unknown): string {
    if (error instanceof Error && error.message) return error.message
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message.trim()) return message.trim()
    }
    return 'AI 运输异常研判失败，请稍后重试'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .transport-advisor {
    display: grid;
    gap: 20px;

    &__hero {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 16px;
      padding: 18px;
    }

    &__hero-main {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;

      > div {
        min-width: 0;
      }

      p {
        margin: 5px 0 0;
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 44px;
      height: 44px;
      font-size: 23px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__title-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;

      strong {
        font-size: 17px;
      }
    }

    &__score {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      grid-column: 1 / -1;
      gap: 12px;

      div {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 12px 14px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      span {
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 22px;
        color: var(--el-color-primary);
      }
    }

    &__summary {
      grid-column: 1 / -1;
      margin: 0;
      line-height: 1.7;
      color: var(--el-text-color-regular);
    }

    &__section {
      display: grid;
      gap: 12px;

      :deep(.el-alert + .el-alert) {
        margin-top: 8px;
      }
    }

    &__signals {
      display: grid;
      gap: 10px;
    }

    &__signal {
      display: grid;
      gap: 10px;
      padding: 15px;

      header {
        display: flex;
        gap: 12px;
        align-items: center;
        justify-content: space-between;

        > div {
          display: flex;
          gap: 8px;
          align-items: center;
        }

        .art-svg-icon {
          color: var(--el-color-warning);
        }
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-regular);
      }

      ul {
        display: grid;
        gap: 5px;
        padding-left: 20px;
        margin: 0;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    &__actions {
      display: grid;
      gap: 12px;
      padding: 16px;
      margin: 0;
      list-style: none;

      li {
        display: flex;
        gap: 10px;
        align-items: flex-start;
      }

      span {
        display: grid;
        flex: none;
        place-items: center;
        width: 24px;
        height: 24px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      p {
        margin: 1px 0 0;
        line-height: 1.65;
      }
    }

    &__meta {
      display: flex;
      flex-wrap: wrap;
      gap: 7px 18px;
      padding-top: 4px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  @media (width <= 640px) {
    .transport-advisor {
      &__hero {
        grid-template-columns: 1fr;
      }

      &__score {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
