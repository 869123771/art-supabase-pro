<template>
  <ArtDrawer ref="drawerRef">
    <template #header>
      <div class="carrier-advisor__drawer-title">
        <span><ArtSvgIcon icon="ri:bar-chart-grouped-line" /></span>
        <div>
          <strong>AI 承运商经营评估</strong>
          <small>履约、成本、结算与准入证据的只读经营研判</small>
        </div>
      </div>
    </template>

    <div class="carrier-advisor">
      <template v-if="state.loading && !assessment">
        <div class="carrier-advisor__skeleton art-card-xs">
          <ElSkeleton :rows="8" animated />
        </div>
      </template>

      <template v-else-if="assessment">
        <section class="carrier-advisor__hero art-card-xs" :class="`is-${assessment.riskLevel}`">
          <header class="carrier-advisor__hero-header">
            <div class="carrier-advisor__hero-main">
              <span class="carrier-advisor__hero-icon">
                <ArtSvgIcon :icon="riskIcon" />
              </span>
              <div>
                <span class="carrier-advisor__eyebrow"><i />AI PERFORMANCE REVIEW</span>
                <div class="carrier-advisor__title-row">
                  <strong>{{ assessment.companyName }}</strong>
                  <ElTag :type="riskTagType" effect="light">{{ riskLabel }}</ElTag>
                  <ElTag type="info" effect="plain">{{ strategyLabel }}</ElTag>
                </div>
                <p>{{ assessment.carrierCode }} · {{ assessment.summary }}</p>
              </div>
            </div>
            <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
              <ArtSvgIcon icon="ri:refresh-line" />重新评估
            </ElButton>
          </header>

          <div class="carrier-advisor__scores">
            <article>
              <header
                ><span>经营表现</span><strong>{{ assessment.performanceScore }}</strong></header
              >
              <ElProgress
                :percentage="assessment.performanceScore"
                :show-text="false"
                :stroke-width="6"
                :color="performanceColor"
              />
              <small>综合履约、资质与治理质量</small>
            </article>
            <article>
              <header
                ><span>风险评分</span><strong>{{ assessment.riskScore }}</strong></header
              >
              <ElProgress
                :percentage="assessment.riskScore"
                :show-text="false"
                :stroke-width="6"
                :color="riskColor"
              />
              <small>{{ assessment.signals.length }} 项需要关注的经营信号</small>
            </article>
            <article>
              <header
                ><span>判断置信度</span><strong>{{ confidencePercent }}%</strong></header
              >
              <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
              <small>基于 {{ assessment.metrics.waybillCount }} 票履约样本</small>
            </article>
          </div>
        </section>

        <section class="carrier-advisor__section">
          <ArtSectionTitle>
            <span class="carrier-advisor__section-label">
              <ArtSvgIcon icon="ri:dashboard-3-line" />经营快照
            </span>
          </ArtSectionTitle>
          <div class="carrier-advisor__metrics">
            <article v-for="metric in metricCards" :key="metric.label" class="art-card-xs">
              <span class="carrier-advisor__metric-icon" :class="metric.tone">
                <ArtSvgIcon :icon="metric.icon" />
              </span>
              <div>
                <span>{{ metric.label }}</span>
                <strong>{{ metric.value }}</strong>
                <small>{{ metric.hint }}</small>
              </div>
            </article>
          </div>
        </section>

        <section class="carrier-advisor__section">
          <ArtSectionTitle>
            <span class="carrier-advisor__section-label">
              <ArtSvgIcon icon="ri:radar-line" />风险与改进信号
            </span>
          </ArtSectionTitle>
          <div v-if="assessment.signals.length" class="carrier-advisor__signals">
            <article
              v-for="signal in assessment.signals"
              :key="signal.type"
              class="carrier-advisor__signal art-card-xs"
              :class="`is-${signal.severity}`"
            >
              <header>
                <div>
                  <span><ArtSvgIcon :icon="signalIcon(signal.severity)" /></span>
                  <strong>{{ signal.title }}</strong>
                </div>
                <ElTag :type="severityTagType(signal.severity)" size="small" effect="light">
                  {{ severityLabel(signal.severity) }}
                </ElTag>
              </header>
              <p>{{ signal.detail }}</p>
              <div class="carrier-advisor__evidence">
                <span v-for="item in signal.evidence" :key="item"><i />{{ item }}</span>
              </div>
            </article>
          </div>
          <div v-else class="carrier-advisor__healthy art-card-xs">
            <span><ArtSvgIcon icon="ri:shield-check-line" /></span>
            <div>
              <strong>当前未识别到显著经营风险</strong>
              <p>资质、履约、费用与结算证据处于可接受范围，建议保持月度复核。</p>
            </div>
          </div>
        </section>

        <section v-if="assessment.riskWaybills.length" class="carrier-advisor__section">
          <ArtSectionTitle>
            <span class="carrier-advisor__section-label">
              <ArtSvgIcon icon="ri:file-warning-line" />重点履约证据
            </span>
          </ArtSectionTitle>
          <div class="carrier-advisor__waybills">
            <article
              v-for="waybill in assessment.riskWaybills"
              :key="waybill.id || waybill.waybillNo"
              class="art-card-xs"
            >
              <header>
                <div>
                  <span class="carrier-advisor__risk-score">{{ waybill.riskScore }}</span>
                  <div>
                    <strong>{{ waybill.waybillNo }}</strong>
                    <p><ArtSvgIcon icon="ri:route-line" />{{ waybill.route }}</p>
                  </div>
                </div>
                <ArtDictDisplay
                  dict-code="tmsWaybillStatus"
                  :value="waybill.status"
                  display="tag"
                />
              </header>
              <div class="carrier-advisor__waybill-meta">
                <span
                  >运费<strong>{{ formatMoney(waybill.freightAmount) }}</strong></span
                >
                <span
                  >计划到达<strong>{{ formatTime(waybill.plannedUnloadTime) }}</strong></span
                >
                <span
                  >实际到达<strong>{{ formatTime(waybill.arrivedAt) }}</strong></span
                >
              </div>
              <div class="carrier-advisor__reasons">
                <span v-for="reason in waybill.reasons" :key="reason">
                  <ArtSvgIcon icon="ri:error-warning-line" />{{ reason }}
                </span>
              </div>
            </article>
          </div>
        </section>

        <section class="carrier-advisor__section">
          <ArtSectionTitle>
            <span class="carrier-advisor__section-label">
              <ArtSvgIcon icon="ri:task-line" />建议动作
            </span>
          </ArtSectionTitle>
          <ol class="carrier-advisor__actions art-card-xs">
            <li v-for="(action, index) in assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <p>{{ action }}</p>
            </li>
          </ol>
        </section>

        <section class="carrier-advisor__section">
          <ArtSectionTitle>
            <span class="carrier-advisor__section-label">
              <ArtSvgIcon icon="ri:shield-check-line" />判断边界
            </span>
          </ArtSectionTitle>
          <div class="carrier-advisor__limitations art-card-xs">
            <p v-for="item in assessment.limitations" :key="item">
              <ArtSvgIcon icon="ri:checkbox-circle-line" /><span>{{ item }}</span>
            </p>
          </div>
        </section>

        <div class="carrier-advisor__feedback">
          <ArtAiFeedback :run-id="state.data!.runId" context-label="AI 承运商经营评估" />
        </div>

        <footer class="carrier-advisor__meta">
          <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data!.ruleVersion }}</span>
          <span><ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data!.generatedAt) }}</span>
          <span> <ArtSvgIcon icon="ri:lock-2-line" />只读评估，不会自动修改承运商或业务状态 </span>
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="承运商经营评估失败"
        :sub-title="state.error"
      >
        <template #extra>
          <ElButton type="primary" @click="loadAssessment">重新评估</ElButton>
        </template>
      </ElResult>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import type { UnwrapNestedRefs } from 'vue'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeCarrierPerformanceByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsCarrierPerformanceAdvisorDrawer' })

  type AnalysisResponse = Api.Tms.BasicData.CarrierPerformanceAdvisorResponse
  type Assessment = Api.Tms.BasicData.CarrierPerformanceAssessment
  type RiskLevel = Api.Tms.BasicData.CarrierPerformanceRiskLevel
  type Severity = Api.Tms.BasicData.CarrierPerformanceSeverity
  type Strategy = Api.Tms.BasicData.CarrierCooperationStrategy

  interface AnalysisState {
    carrierId: string
    data: AnalysisResponse | null
    error: string
    loading: boolean
  }

  interface MetricCard {
    label: string
    value: string
    hint: string
    icon: string
    tone: string
  }

  const drawerRef = ref<ArtDrawerExpose<{ carrierId: string }>>()
  const state: UnwrapNestedRefs<AnalysisState> = reactive<AnalysisState>({
    carrierId: '',
    data: null,
    error: '',
    loading: false
  })

  const riskLabelMap: Record<RiskLevel, string> = {
    critical: '严重风险',
    high: '高风险',
    medium: '需改进',
    low: '表现稳定'
  }
  const strategyLabelMap: Record<Strategy, string> = {
    manual_qualification_review: '先完成人工准入复核',
    conditional_cooperation: '附条件合作',
    improve_and_monitor: '整改并观察',
    preferred_partner: '可作为优选承运商',
    insufficient_evidence: '先小批量积累样本'
  }
  const tagTypeMap: Record<RiskLevel, 'danger' | 'warning' | 'success'> = {
    critical: 'danger',
    high: 'danger',
    medium: 'warning',
    low: 'success'
  }
  const colorMap: Record<RiskLevel, string> = {
    critical: 'var(--el-color-danger)',
    high: 'var(--el-color-danger)',
    medium: 'var(--el-color-warning)',
    low: 'var(--el-color-success)'
  }

  const assessment = computed<Assessment | null>(() => state.data?.assessment ?? null)
  const riskLabel = computed(() =>
    assessment.value ? riskLabelMap[assessment.value.riskLevel] : ''
  )
  const strategyLabel = computed(() =>
    assessment.value ? strategyLabelMap[assessment.value.cooperationStrategy] : ''
  )
  const riskTagType = computed(() =>
    assessment.value ? tagTypeMap[assessment.value.riskLevel] : 'warning'
  )
  const riskColor = computed(() =>
    assessment.value ? colorMap[assessment.value.riskLevel] : 'var(--el-color-warning)'
  )
  const performanceColor = computed(() => {
    const score = assessment.value?.performanceScore ?? 0
    return score >= 75
      ? 'var(--el-color-success)'
      : score >= 50
        ? 'var(--el-color-warning)'
        : 'var(--el-color-danger)'
  })
  const confidencePercent = computed(() => Math.round((assessment.value?.confidence ?? 0) * 100))
  const riskIcon = computed(() =>
    assessment.value?.riskLevel === 'low' ? 'ri:shield-check-line' : 'ri:alarm-warning-line'
  )
  const metricCards = computed<MetricCard[]>(() => {
    const metrics = assessment.value?.metrics
    if (!metrics) return []
    return [
      {
        label: '履约完成率',
        value: formatPercent(metrics.completionRate),
        hint: `${metrics.completedCount}/${metrics.waybillCount} 票完成或签收`,
        icon: 'ri:checkbox-circle-line',
        tone: metrics.completionRate >= 80 ? 'is-success' : 'is-warning'
      },
      {
        label: '可计量准点率',
        value: metrics.onTimeRate === null ? '样本不足' : formatPercent(metrics.onTimeRate),
        hint: `${metrics.onTimeSampleCount} 票具备计划和实际到达`,
        icon: 'ri:timer-line',
        tone: metrics.onTimeRate !== null && metrics.onTimeRate < 85 ? 'is-warning' : 'is-success'
      },
      {
        label: '取消率',
        value: formatPercent(metrics.cancellationRate),
        hint: `${metrics.cancelledCount} 票取消 · ${metrics.activeCount} 票在途`,
        icon: 'ri:close-circle-line',
        tone: metrics.cancellationRate >= 15 ? 'is-danger' : 'is-info'
      },
      {
        label: '运力档案',
        value: `${metrics.vehicleCount} 车 / ${metrics.driverCount} 人`,
        hint: '当前系统内可关联资源',
        icon: 'ri:truck-line',
        tone: metrics.vehicleCount && metrics.driverCount ? 'is-info' : 'is-warning'
      },
      {
        label: '费用与运费比',
        value:
          metrics.costToFreightRate === null
            ? '数据不足'
            : formatPercent(metrics.costToFreightRate),
        hint: `${formatMoney(metrics.totalCostAmount)} / ${formatMoney(metrics.totalFreightAmount)}`,
        icon: 'ri:funds-box-line',
        tone: metrics.pendingCostCount || metrics.rejectedCostCount ? 'is-warning' : 'is-info'
      },
      {
        label: '治理待办',
        value: `${metrics.pendingCostCount + metrics.rejectedCostCount + metrics.openStatementCount} 项`,
        hint: `费用 ${metrics.pendingCostCount + metrics.rejectedCostCount} · 对账 ${metrics.openStatementCount}`,
        icon: 'ri:todo-line',
        tone:
          metrics.pendingCostCount + metrics.rejectedCostCount + metrics.openStatementCount
            ? 'is-danger'
            : 'is-success'
      }
    ]
  })

  async function handleOpen(carrierId: string): Promise<void> {
    Object.assign(state, { carrierId, data: null, error: '', loading: false })
    await drawerRef.value?.handleOpen(
      { carrierId },
      {
        title: 'AI 承运商经营评估',
        size: 'xl',
        contentHeight: 'calc(100vh - 120px)',
        showFooter: false,
        onOpen: loadAssessment,
        onReset: () =>
          Object.assign(state, { carrierId: '', data: null, error: '', loading: false }),
        drawerProps: {
          appendToBody: true,
          closeOnClickModal: false,
          resizable: true
        }
      }
    )
  }

  async function loadAssessment(): Promise<void> {
    if (!state.carrierId || state.loading) return
    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeCarrierPerformanceByAi(state.carrierId)
      if (error) throw error
      if (!data) throw new Error('承运商经营评估服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getFriendlySupabaseErrorMessage(
        error,
        '承运商经营评估服务暂时不可用，请稍后重试'
      )
    } finally {
      state.loading = false
    }
  }

  function severityLabel(severity: Severity): string {
    return severity === 'critical' ? '严重' : severity === 'high' ? '高风险' : '需关注'
  }

  function severityTagType(severity: Severity): 'danger' | 'warning' {
    return severity === 'medium' ? 'warning' : 'danger'
  }

  function signalIcon(severity: Severity): string {
    return severity === 'critical'
      ? 'ri:alarm-warning-line'
      : severity === 'high'
        ? 'ri:error-warning-line'
        : 'ri:information-line'
  }

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function formatPercent(value?: number | null): string {
    return value === null || value === undefined ? '--' : `${Number(value).toFixed(1)}%`
  }

  function formatTime(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '--'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .carrier-advisor {
    min-width: 0;

    &__drawer-title {
      display: flex;
      gap: 12px;
      align-items: center;

      > span {
        display: grid;
        place-items: center;
        width: 40px;
        height: 40px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      strong,
      small {
        display: block;
      }

      strong {
        color: var(--art-text-gray-900);
      }

      small {
        margin-top: 3px;
        color: var(--art-text-gray-500);
      }
    }

    &__skeleton {
      padding: 24px;
    }

    &__hero {
      position: relative;
      padding: 20px;
      overflow: hidden;
      background:
        radial-gradient(circle at 86% 10%, rgb(59 130 246 / 12%), transparent 28%),
        var(--art-main-bg-color);

      &::before {
        position: absolute;
        top: 0;
        left: 0;
        width: 4px;
        height: 100%;
        content: '';
        background: var(--el-color-primary);
      }

      &.is-critical::before,
      &.is-high::before {
        background: var(--el-color-danger);
      }

      &.is-medium::before {
        background: var(--el-color-warning);
      }

      &.is-low::before {
        background: var(--el-color-success);
      }
    }

    &__hero-header,
    &__hero-main,
    &__title-row,
    &__signal header,
    &__signal header > div,
    &__waybills article header,
    &__waybills article header > div,
    &__evidence,
    &__reasons,
    &__meta {
      display: flex;
      align-items: center;
    }

    &__hero-header,
    &__signal header,
    &__waybills article header {
      justify-content: space-between;
    }

    &__hero-main {
      gap: 14px;
      min-width: 0;

      > div {
        min-width: 0;
      }

      p {
        margin: 6px 0 0;
        color: var(--art-text-gray-500);
      }
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 52px;
      place-items: center;
      width: 52px;
      height: 52px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #4f46e5);
      border-radius: var(--custom-radius);
      box-shadow: 0 10px 24px rgb(59 130 246 / 18%);

      :deep(svg) {
        width: 25px;
        height: 25px;
      }
    }

    &__eyebrow {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.13em;

      i {
        width: 6px;
        height: 6px;
        background: var(--el-color-success);
        border-radius: 50%;
      }
    }

    &__title-row {
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 4px;

      > strong {
        margin-right: 3px;
        font-size: 19px;
        color: var(--art-text-gray-900);
      }
    }

    &__scores {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin-top: 18px;

      article {
        min-width: 0;
        padding: 13px 14px;
        background: color-mix(in srgb, var(--art-main-bg-color) 95%, var(--el-color-primary));
        border-radius: var(--el-border-radius-base);

        header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 9px;
        }

        span,
        small {
          color: var(--art-text-gray-500);
        }

        strong {
          font-size: 20px;
          color: var(--art-text-gray-900);
        }

        small {
          display: block;
          margin-top: 7px;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 11px;
          white-space: nowrap;
        }
      }
    }

    &__section {
      min-width: 0;
      margin-top: 22px;
    }

    &__section-label {
      display: inline-flex;
      gap: 7px;
      align-items: center;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 10px;

      article {
        display: flex;
        gap: 12px;
        align-items: center;
        min-width: 0;
        padding: 14px;

        > div {
          min-width: 0;
        }

        span,
        strong,
        small {
          display: block;
        }

        span,
        small {
          color: var(--art-text-gray-500);
        }

        strong {
          margin: 3px 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 16px;
          color: var(--art-text-gray-900);
          white-space: nowrap;
        }

        small {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 11px;
          white-space: nowrap;
        }
      }
    }

    &__metric-icon {
      display: grid !important;
      flex: 0 0 38px;
      place-items: center;
      width: 38px;
      height: 38px;
      color: var(--el-color-primary) !important;
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      &.is-success {
        color: var(--el-color-success) !important;
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning) !important;
        background: var(--el-color-warning-light-9);
      }

      &.is-danger {
        color: var(--el-color-danger) !important;
        background: var(--el-color-danger-light-9);
      }
    }

    &__signals {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    &__signal {
      position: relative;
      min-width: 0;
      padding: 15px 16px;
      overflow: hidden;

      &::before {
        position: absolute;
        top: 0;
        left: 0;
        width: 3px;
        height: 100%;
        content: '';
        background: var(--el-color-warning);
      }

      &.is-critical::before,
      &.is-high::before {
        background: var(--el-color-danger);
      }

      header > div {
        gap: 9px;

        > span {
          display: grid;
          place-items: center;
          width: 30px;
          height: 30px;
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
          border-radius: var(--el-border-radius-base);
        }
      }

      p {
        margin: 10px 0;
        line-height: 1.65;
        color: var(--art-text-gray-600);
      }
    }

    &__evidence,
    &__reasons {
      flex-wrap: wrap;
      gap: 7px;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 4px 8px;
        font-size: 11px;
        color: var(--art-text-gray-600);
        background: var(--el-fill-color-lighter);
        border-radius: 999px;
      }
    }

    &__evidence i {
      width: 5px;
      height: 5px;
      background: var(--el-color-warning);
      border-radius: 50%;
    }

    &__healthy {
      display: flex;
      gap: 14px;
      align-items: center;
      padding: 18px;

      > span {
        display: grid;
        flex: 0 0 42px;
        place-items: center;
        width: 42px;
        height: 42px;
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
        border-radius: var(--el-border-radius-base);
      }

      strong {
        color: var(--art-text-gray-900);
      }

      p {
        margin: 4px 0 0;
        color: var(--art-text-gray-500);
      }
    }

    &__waybills {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;

      article {
        min-width: 0;
        padding: 15px;

        header > div {
          gap: 10px;
          min-width: 0;

          > div {
            min-width: 0;
          }

          strong {
            color: var(--art-text-gray-900);
          }

          p {
            display: flex;
            gap: 5px;
            align-items: center;
            margin: 4px 0 0;
            overflow: hidden;
            text-overflow: ellipsis;
            font-size: 11px;
            color: var(--art-text-gray-500);
            white-space: nowrap;
          }
        }
      }
    }

    &__risk-score {
      display: grid;
      flex: 0 0 36px;
      place-items: center;
      width: 36px;
      height: 36px;
      font-weight: 700;
      color: var(--el-color-danger);
      background: var(--el-color-danger-light-9);
      border-radius: 50%;
    }

    &__waybill-meta {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 6px;
      padding: 10px;
      margin: 12px 0 10px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);

      span,
      strong {
        display: block;
        min-width: 0;
      }

      span {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }

      strong {
        margin-top: 3px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-800);
        white-space: nowrap;
      }
    }

    &__reasons span {
      color: var(--el-color-danger);
      background: var(--el-color-danger-light-9);
    }

    &__actions {
      padding: 4px 18px;
      margin: 0;
      list-style: none;

      li {
        display: grid;
        grid-template-columns: 30px minmax(0, 1fr);
        gap: 12px;
        align-items: center;
        padding: 13px 0;

        & + li {
          border-top: 1px dashed var(--el-border-color-lighter);
        }

        > span {
          display: grid;
          place-items: center;
          width: 28px;
          height: 28px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;
        }

        p {
          margin: 0;
          line-height: 1.6;
          color: var(--art-text-gray-700);
        }
      }
    }

    &__limitations {
      padding: 12px 16px;

      p {
        display: flex;
        gap: 8px;
        align-items: flex-start;
        margin: 0;
        line-height: 1.6;
        color: var(--art-text-gray-500);

        & + p {
          margin-top: 8px;
        }

        :deep(svg) {
          flex: 0 0 auto;
          margin-top: 3px;
          color: var(--el-color-primary);
        }
      }
    }

    &__feedback {
      margin-top: 20px;
    }

    &__meta {
      flex-wrap: wrap;
      gap: 14px;
      padding: 14px 2px 2px;
      margin-top: 20px;
      font-size: 11px;
      color: var(--art-text-gray-400);
      border-top: 1px dashed var(--el-border-color-lighter);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
      }
    }

    @media (width <= 760px) {
      &__scores,
      &__metrics,
      &__signals,
      &__waybills {
        grid-template-columns: 1fr;
      }
    }

    @media (width <= 480px) {
      &__hero-header,
      &__hero-main {
        flex-direction: column;
        align-items: flex-start;
      }

      &__hero-header :deep(.el-button) {
        width: 100%;
      }

      &__waybill-meta {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
