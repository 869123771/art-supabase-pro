<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <template #header>
      <div class="transport-advisor__drawer-title">
        <span><ArtSvgIcon icon="ri:shield-flash-line" /></span>
        <div>
          <strong>AI 运输异常研判</strong>
          <small>{{ state.openData?.orderNo || '在途运输风险分析' }} · 只读分析</small>
        </div>
      </div>
    </template>

    <div class="transport-advisor">
      <ArtAsyncState
        :loading="state.loading"
        :loading-mode="state.data ? 'mask' : 'skeleton'"
        :error="state.error"
        min-height="420px"
        @retry="loadAssessment"
      >
        <template v-if="state.data">
          <section
            :class="[
              'transport-advisor__hero art-card-xs',
              `is-${state.data.assessment.riskLevel}`
            ]"
          >
            <header class="transport-advisor__hero-header">
              <div class="transport-advisor__hero-main">
                <span class="transport-advisor__icon">
                  <ArtSvgIcon icon="ri:route-line" />
                </span>
                <div>
                  <span class="transport-advisor__eyebrow"><i />AI TRANSPORT RISK CONTROL</span>
                  <div class="transport-advisor__title-row">
                    <strong>{{ state.data.assessment.orderNo }}</strong>
                    <ElTag :type="riskTagType" effect="dark" round>{{ riskLabel }}</ElTag>
                  </div>
                  <p>{{ state.data.assessment.route }}</p>
                </div>
              </div>
              <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
                <ArtSvgIcon icon="ri:refresh-line" />重新研判
              </ElButton>
            </header>

            <div class="transport-advisor__score">
              <article>
                <header>
                  <span>运输风险评分</span>
                  <strong>{{ state.data.assessment.riskScore }}</strong>
                </header>
                <ElProgress
                  :percentage="state.data.assessment.riskScore"
                  :show-text="false"
                  :stroke-width="6"
                  :color="riskProgressColor"
                />
                <small>结合时效、轨迹与业务更新时间</small>
              </article>
              <article>
                <header>
                  <span>研判置信度</span>
                  <strong>{{ confidencePercent }}%</strong>
                </header>
                <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
                <small>基于当前可获取的运输业务证据</small>
              </article>
              <article>
                <header>
                  <span>异常信号</span>
                  <strong>{{ state.data.assessment.signals.length }}</strong>
                </header>
                <ElProgress
                  :percentage="Math.min(state.data.assessment.signals.length * 25, 100)"
                  :show-text="false"
                  :stroke-width="6"
                  color="var(--el-color-warning)"
                />
                <small>按风险严重程度聚合展示</small>
              </article>
            </div>

            <div class="transport-advisor__summary">
              <span><ArtSvgIcon icon="ri:brain-line" /></span>
              <div>
                <small>AI 研判结论</small>
                <p>{{ state.data.assessment.summary }}</p>
              </div>
            </div>
          </section>

          <section class="transport-advisor__section">
            <ArtSectionTitle>
              <span class="transport-advisor__section-label">
                <ArtSvgIcon icon="ri:alarm-warning-line" />异常信号
              </span>
            </ArtSectionTitle>
            <ArtAsyncState
              :empty="!state.data.assessment.signals.length"
              empty-text="当前未识别到明确异常"
              min-height="160px"
            >
              <div class="transport-advisor__signals">
                <article
                  v-for="signal in state.data.assessment.signals"
                  :key="signal.type"
                  :class="['transport-advisor__signal art-card-xs', `is-${signal.severity}`]"
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
                  <div class="transport-advisor__evidence">
                    <span v-for="item in signal.evidence" :key="item">
                      <i />{{ formatEvidence(item) }}
                    </span>
                  </div>
                </article>
              </div>
            </ArtAsyncState>
          </section>

          <section class="transport-advisor__section">
            <ArtSectionTitle>
              <span class="transport-advisor__section-label">
                <ArtSvgIcon icon="ri:list-check-3" />建议处置顺序
              </span>
            </ArtSectionTitle>
            <ol class="transport-advisor__actions art-card-xs">
              <li v-for="(action, index) in state.data.assessment.recommendedActions" :key="action">
                <span>{{ index + 1 }}</span>
                <div>
                  <small>处置步骤 {{ String(index + 1).padStart(2, '0') }}</small>
                  <p>{{ action }}</p>
                </div>
              </li>
            </ol>
          </section>

          <section class="transport-advisor__section">
            <ArtSectionTitle>
              <span class="transport-advisor__section-label">
                <ArtSvgIcon icon="ri:information-2-line" />判断边界
              </span>
            </ArtSectionTitle>
            <div class="transport-advisor__limitations art-card-xs">
              <p v-for="item in state.data.assessment.limitations" :key="item">
                <ArtSvgIcon icon="ri:checkbox-circle-line" /><span>{{ item }}</span>
              </p>
            </div>
          </section>

          <ArtAiFeedback :run-id="state.data.runId" context-label="AI 运输异常研判" />

          <footer class="transport-advisor__meta">
            <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data.ruleVersion }}</span>
            <span><ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data.generatedAt) }}</span>
            <span>
              <ArtSvgIcon icon="ri:shield-check-line" />本次结果只提供建议，不会自动改变业务状态
            </span>
          </footer>
        </template>
      </ArtAsyncState>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
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
  const confidencePercent = computed(() =>
    state.data ? Math.round(state.data.assessment.confidence * 100) : 0
  )
  const riskProgressColor = computed(() => {
    if (!state.data) return 'var(--el-color-primary)'
    return {
      critical: 'var(--el-color-danger)',
      high: 'var(--el-color-danger)',
      medium: 'var(--el-color-warning)',
      low: 'var(--el-color-success)'
    }[state.data.assessment.riskLevel]
  })

  async function handleOpen(data: DrawerOpenData): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false, openData: data })
    await drawerRef.value?.handleOpen(data, {
      title: `AI 运输异常研判 · ${data.orderNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 116px)',
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
      state.error = getFriendlySupabaseErrorMessage(error, 'AI 运输异常研判失败，请稍后重试')
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

  function formatEvidence(value: string): string {
    const statusLabels: Record<string, string> = {
      transporting: '运输中',
      pending: '待发运',
      completed: '已完成',
      cancelled: '已取消'
    }
    return value
      .replace(
        /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/g,
        (date) => formatWithDayjs(date, 'YYYY-MM-DD HH:mm') || date
      )
      .replace(
        /\b(transporting|pending|completed|cancelled)\b/gi,
        (status) => statusLabels[status.toLowerCase()] || status
      )
      .replace(/：\s+/g, '：')
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .transport-advisor {
    min-width: 0;

    :deep(> .art-async-state) {
      display: grid;
      gap: 22px;
    }

    &__drawer-title {
      display: flex;
      gap: 11px;
      align-items: center;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 38px;
        height: 38px;
        font-size: 19px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      strong,
      small {
        display: block;
      }

      strong {
        font-size: 16px;
        color: var(--el-text-color-primary);
      }

      small {
        margin-top: 3px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__hero {
      position: relative;
      display: grid;
      gap: 18px;
      padding: 20px;
      overflow: hidden;
      border-top: 3px solid var(--el-color-primary);

      &::after {
        position: absolute;
        top: -80px;
        right: -55px;
        width: 210px;
        height: 210px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 70%);
        border-radius: 50%;
        opacity: 0.55;
      }

      &.is-critical,
      &.is-high {
        border-top-color: var(--el-color-danger);
      }

      &.is-medium {
        border-top-color: var(--el-color-warning);
      }

      &.is-low {
        border-top-color: var(--el-color-success);
      }
    }

    &__hero-header {
      z-index: 1;
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
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
        font-size: 13px;
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
      font-size: 22px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__eyebrow {
      display: flex;
      gap: 6px;
      align-items: center;
      margin-bottom: 4px;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.9px;

      i {
        width: 5px;
        height: 5px;
        background: currentcolor;
        border-radius: 50%;
      }
    }

    &__title-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;

      strong {
        font-size: 18px;
      }
    }

    &__score {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;

      article {
        min-width: 0;
        padding: 13px 14px;
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-base);
      }

      header {
        display: flex;
        gap: 10px;
        align-items: baseline;
        justify-content: space-between;
        margin-bottom: 9px;

        span {
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }

        strong {
          font-size: 23px;
          line-height: 1;
          color: var(--el-text-color-primary);
        }
      }

      small {
        display: block;
        margin-top: 8px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--el-text-color-placeholder);
        white-space: nowrap;
      }
    }

    &__summary {
      display: flex;
      gap: 11px;
      align-items: flex-start;
      padding: 13px 15px;
      background: linear-gradient(90deg, var(--el-color-primary-light-9), transparent);
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-base);

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 28px;
        height: 28px;
        color: var(--el-color-primary);
        background: var(--el-bg-color);
        border-radius: 50%;
      }

      small {
        font-size: 11px;
        font-weight: 600;
        color: var(--el-color-primary);
      }

      p {
        margin: 3px 0 0;
        line-height: 1.65;
        color: var(--el-text-color-regular);
      }
    }

    &__section {
      display: grid;
      gap: 12px;
    }

    &__section-label {
      display: inline-flex;
      gap: 7px;
      align-items: center;

      .art-svg-icon {
        color: var(--el-color-primary);
      }
    }

    &__signals {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(310px, 1fr));
      gap: 12px;
    }

    &__signal {
      display: grid;
      gap: 11px;
      padding: 16px;
      border-left: 3px solid var(--el-color-warning);

      &.is-critical,
      &.is-high {
        border-left-color: var(--el-color-danger);
      }

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

      &.is-critical header .art-svg-icon,
      &.is-high header .art-svg-icon {
        color: var(--el-color-danger);
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-regular);
      }
    }

    &__evidence {
      display: grid;
      gap: 7px;

      span {
        display: flex;
        gap: 8px;
        align-items: flex-start;
        padding: 7px 9px;
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-extra-light);
        border-radius: var(--el-border-radius-small);

        i {
          flex: none;
          width: 5px;
          height: 5px;
          margin-top: 6px;
          background: var(--el-color-warning);
          border-radius: 50%;
        }
      }
    }

    &__actions {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      padding: 14px;
      margin: 0;
      list-style: none;

      li {
        display: flex;
        gap: 11px;
        align-items: flex-start;
        min-width: 0;
        padding: 12px;
        background: var(--el-fill-color-extra-light);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-base);
      }

      > li > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 27px;
        height: 27px;
        font-weight: 700;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      li > div {
        min-width: 0;

        small {
          font-size: 10px;
          font-weight: 600;
          color: var(--el-color-primary);
          letter-spacing: 0.3px;
        }

        p {
          margin: 4px 0 0;
          line-height: 1.6;
          color: var(--el-text-color-primary);
        }
      }
    }

    &__limitations {
      display: grid;
      gap: 9px;
      padding: 14px 16px;

      p {
        display: flex;
        gap: 9px;
        align-items: flex-start;
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);

        .art-svg-icon {
          flex: none;
          margin-top: 3px;
          color: var(--el-color-primary);
        }
      }
    }

    &__meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 18px;
      align-items: center;
      padding: 4px 2px 8px;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
      }
    }
  }

  @media (width <= 760px) {
    .transport-advisor {
      &__hero-header {
        flex-direction: column;

        .el-button {
          width: 100%;
        }
      }

      &__score,
      &__signals,
      &__actions {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
