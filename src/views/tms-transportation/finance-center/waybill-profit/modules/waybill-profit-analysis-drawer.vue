<template>
  <ArtDrawer ref="drawerRef" :loading="state.loading" :show-footer="false">
    <template #header>
      <div class="profit-analyst__drawer-title">
        <span><ArtSvgIcon icon="ri:line-chart-line" /></span>
        <div>
          <strong>AI 运单利润诊断</strong>
          <small>跨运单成本完整性与经营风险分析</small>
        </div>
      </div>
    </template>

    <div class="profit-analyst">
      <template v-if="state.data">
        <section :class="['profit-analyst__hero art-card-xs', `is-${assessment.riskLevel}`]">
          <header class="profit-analyst__hero-header">
            <div class="profit-analyst__hero-main">
              <span class="profit-analyst__hero-icon">
                <ArtSvgIcon icon="ri:funds-box-line" />
              </span>
              <div>
                <span class="profit-analyst__eyebrow"><i />AI PROFIT HEALTH CHECK</span>
                <div class="profit-analyst__title-row">
                  <strong>运单利润经营体检</strong>
                  <ElTag :type="riskTagType" effect="dark" round>{{ riskLabel }}</ElTag>
                  <ElTag type="info" effect="plain" round>{{ recommendationLabel }}</ElTag>
                </div>
                <p>分析当前租户最近 {{ assessment.metrics.totalWaybills }} 票非作废运单</p>
              </div>
            </div>
            <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
              <ArtSvgIcon icon="ri:refresh-line" />重新诊断
            </ElButton>
          </header>

          <div class="profit-analyst__scores">
            <article>
              <header
                ><span>经营风险</span><strong>{{ assessment.riskScore }}</strong></header
              >
              <ElProgress
                :percentage="assessment.riskScore"
                :show-text="false"
                :stroke-width="6"
                :color="riskProgressColor"
              />
              <small>综合亏损、成本覆盖与承运应付</small>
            </article>
            <article>
              <header
                ><span>诊断置信度</span><strong>{{ confidencePercent }}%</strong></header
              >
              <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
              <small>基于当前系统业务数据</small>
            </article>
            <article>
              <header
                ><span>成本覆盖率</span
                ><strong>{{ formatPercent(assessment.metrics.costCoverage) }}</strong></header
              >
              <ElProgress
                :percentage="assessment.metrics.costCoverage"
                :show-text="false"
                :stroke-width="6"
                :color="coverageProgressColor"
              />
              <small>{{ assessment.metrics.missingCostCount }} 票尚未形成成本</small>
            </article>
          </div>

          <div class="profit-analyst__conclusion">
            <span><ArtSvgIcon :icon="conclusionIcon" /></span>
            <div>
              <small>AI 经营结论</small>
              <p>{{ assessment.summary }}</p>
            </div>
          </div>
        </section>

        <section class="profit-analyst__section">
          <ArtSectionTitle>
            <span class="profit-analyst__section-label">
              <ArtSvgIcon icon="ri:dashboard-3-line" />利润健康指标
            </span>
          </ArtSectionTitle>
          <div class="profit-analyst__metrics">
            <article class="art-card-xs">
              <span class="profit-analyst__metric-icon is-receivable">
                <ArtSvgIcon icon="ri:wallet-3-line" />
              </span>
              <div
                ><span>账面应收</span
                ><strong>{{ formatMoney(assessment.metrics.receivableAmount) }}</strong
                ><small>当前分析范围</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="profit-analyst__metric-icon is-cost">
                <ArtSvgIcon icon="ri:funds-line" />
              </span>
              <div
                ><span>已形成成本</span
                ><strong>{{ formatMoney(assessment.metrics.totalCostAmount) }}</strong
                ><small>审核成本与承运应付</small></div
              >
            </article>
            <article :class="['art-card-xs', profitTone]">
              <span class="profit-analyst__metric-icon is-profit">
                <ArtSvgIcon icon="ri:line-chart-line" />
              </span>
              <div
                ><span>账面毛利</span
                ><strong>{{ formatMoney(assessment.metrics.bookGrossProfit) }}</strong
                ><small>受成本覆盖率影响</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="profit-analyst__metric-icon is-coverage">
                <ArtSvgIcon icon="ri:pie-chart-2-line" />
              </span>
              <div
                ><span>完成单成本覆盖</span
                ><strong>{{ formatPercent(assessment.metrics.finalizedCostCoverage) }}</strong
                ><small>{{ assessment.metrics.finalizedWaybills }} 票完成/签收</small></div
              >
            </article>
            <article class="art-card-xs is-danger">
              <span class="profit-analyst__metric-icon is-loss">
                <ArtSvgIcon icon="ri:arrow-down-circle-line" />
              </span>
              <div
                ><span>亏损运单</span
                ><strong>{{ assessment.metrics.negativeMarginCount }} 票</strong
                ><small>毛利额或毛利率为负</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="profit-analyst__metric-icon is-carrier">
                <ArtSvgIcon icon="ri:truck-line" />
              </span>
              <div
                ><span>承运应付缺失</span
                ><strong>{{ assessment.metrics.carrierPayableMissingCount }} 票</strong
                ><small>已关联承运商但应付为零</small></div
              >
            </article>
          </div>
        </section>

        <section class="profit-analyst__section">
          <ArtSectionTitle>
            <span class="profit-analyst__section-label">
              <ArtSvgIcon icon="ri:alarm-warning-line" />经营风险信号
            </span>
          </ArtSectionTitle>
          <div v-if="assessment.signals.length" class="profit-analyst__signals">
            <article
              v-for="signal in assessment.signals"
              :key="signal.type"
              :class="['profit-analyst__signal art-card-xs', `is-${signal.severity}`]"
            >
              <header>
                <div>
                  <span><ArtSvgIcon :icon="signalIcon(signal.severity)" /></span>
                  <strong>{{ signal.title }}</strong>
                </div>
                <ElTag :type="severityTagType(signal.severity)" effect="light" round>
                  {{ severityLabel(signal.severity) }}
                </ElTag>
              </header>
              <p>{{ signal.detail }}</p>
              <div class="profit-analyst__evidence">
                <span v-for="item in signal.evidence" :key="item"><i />{{ item }}</span>
              </div>
            </article>
          </div>
          <ElEmpty v-else description="当前未识别到明确经营风险" :image-size="76" />
        </section>

        <section class="profit-analyst__section">
          <ArtSectionTitle>
            <span class="profit-analyst__section-label">
              <ArtSvgIcon icon="ri:radar-line" />优先核对运单
            </span>
          </ArtSectionTitle>
          <div v-if="assessment.riskWaybills.length" class="profit-analyst__waybills">
            <article
              v-for="waybill in assessment.riskWaybills"
              :key="waybill.id || waybill.waybillId"
              class="profit-analyst__waybill art-card-xs"
            >
              <header>
                <div>
                  <span class="profit-analyst__risk-score">{{ waybill.riskScore }}</span>
                  <div>
                    <strong>{{ waybill.waybillNo }}</strong>
                    <p><ArtSvgIcon icon="ri:route-line" />{{ waybill.route }}</p>
                  </div>
                </div>
                <ArtDictDisplay
                  dict-code="tmsWaybillStatus"
                  :value="waybill.waybillStatus"
                  display="tag"
                />
              </header>
              <div class="profit-analyst__waybill-party">
                <span><ArtSvgIcon icon="ri:building-2-line" />{{ waybill.customerName }}</span>
                <span><ArtSvgIcon icon="ri:truck-line" />{{ waybill.carrierName }}</span>
              </div>
              <div class="profit-analyst__waybill-metrics">
                <span
                  >应收<strong>{{ formatMoney(waybill.receivableAmount) }}</strong></span
                >
                <span
                  >成本<strong>{{ formatMoney(waybill.totalCostAmount) }}</strong></span
                >
                <span
                  >毛利<strong :class="{ 'is-negative': waybill.grossProfit < 0 }">{{
                    formatMoney(waybill.grossProfit)
                  }}</strong></span
                >
              </div>
              <div class="profit-analyst__reasons">
                <span v-for="reason in waybill.reasons" :key="reason">{{ reason }}</span>
              </div>
            </article>
          </div>
          <ElEmpty v-else description="暂无需要优先核对的运单" :image-size="76" />
        </section>

        <section class="profit-analyst__section">
          <ArtSectionTitle>
            <span class="profit-analyst__section-label">
              <ArtSvgIcon icon="ri:list-check-3" />建议处理顺序
            </span>
          </ArtSectionTitle>
          <ol class="profit-analyst__actions art-card-xs">
            <li v-for="(action, index) in assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <div
                ><small>经营核对步骤 {{ index + 1 }}</small
                ><p>{{ action }}</p></div
              >
            </li>
          </ol>
        </section>

        <section class="profit-analyst__section">
          <ArtSectionTitle>
            <span class="profit-analyst__section-label">
              <ArtSvgIcon icon="ri:information-2-line" />数据边界
            </span>
          </ArtSectionTitle>
          <div class="profit-analyst__limitations art-card-xs">
            <p v-for="item in assessment.limitations" :key="item">
              <ArtSvgIcon icon="ri:checkbox-circle-line" /><span>{{ item }}</span>
            </p>
          </div>
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 运单利润诊断" />

        <footer class="profit-analyst__meta">
          <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data.ruleVersion }}</span>
          <span><ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data.generatedAt) }}</span>
          <span><ArtSvgIcon icon="ri:shield-check-line" />只读诊断，不会自动修改财务数据</span>
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="利润诊断失败"
        :sub-title="state.error"
      >
        <template #extra
          ><ElButton type="primary" @click="loadAssessment">重新诊断</ElButton></template
        >
      </ElResult>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeWaybillProfitByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsWaybillProfitAnalysisDrawer' })

  type AnalysisResponse = Api.Tms.Finance.WaybillProfitAnalysisResponse
  type RiskLevel = Api.Tms.Finance.WaybillProfitAnalysisRiskLevel
  type Recommendation = Api.Tms.Finance.WaybillProfitAnalysisRecommendation
  type Severity = Api.Tms.Finance.WaybillProfitAnalysisSeverity

  interface AnalysisState {
    data: AnalysisResponse | null
    error: string
    loading: boolean
  }

  const drawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const state: UnwrapNestedRefs<AnalysisState> = reactive<AnalysisState>({
    data: null,
    error: '',
    loading: false
  })

  const riskLabelMap: Record<RiskLevel, string> = {
    critical: '严重风险',
    high: '高风险',
    medium: '中风险',
    low: '健康'
  }
  const recommendationLabelMap: Record<Recommendation, string> = {
    repair_cost_baseline: '先补齐成本基线',
    manual_profit_review: '优先人工复核亏损',
    routine_monitoring: '进入常规经营监控'
  }
  const tagTypeMap = {
    critical: 'danger',
    high: 'danger',
    medium: 'warning',
    low: 'success'
  } as const
  const progressColorMap: Record<RiskLevel, string> = {
    critical: 'var(--el-color-danger)',
    high: 'var(--el-color-danger)',
    medium: 'var(--el-color-warning)',
    low: 'var(--el-color-success)'
  }

  const assessment = computed(() => state.data!.assessment)
  const riskLabel = computed(() => riskLabelMap[assessment.value.riskLevel])
  const riskTagType = computed(() => tagTypeMap[assessment.value.riskLevel])
  const recommendationLabel = computed(
    () => recommendationLabelMap[assessment.value.recommendation]
  )
  const confidencePercent = computed(() => Math.round(assessment.value.confidence * 100))
  const riskProgressColor = computed(() => progressColorMap[assessment.value.riskLevel])
  const coverageProgressColor = computed(() => {
    const coverage = assessment.value.metrics.costCoverage
    return coverage < 30
      ? 'var(--el-color-danger)'
      : coverage < 70
        ? 'var(--el-color-warning)'
        : 'var(--el-color-success)'
  })
  const conclusionIcon = computed(() =>
    assessment.value.riskLevel === 'critical' || assessment.value.riskLevel === 'high'
      ? 'ri:alarm-warning-line'
      : 'ri:checkbox-circle-line'
  )
  const profitTone = computed(() =>
    assessment.value.metrics.bookGrossProfit < 0 ? 'is-danger' : 'is-neutral'
  )

  async function handleOpen(): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false })
    await drawerRef.value?.handleOpen(
      {},
      {
        title: 'AI 运单利润诊断',
        size: 'xl',
        contentHeight: 'calc(100vh - 120px)',
        showFooter: false,
        onOpen: loadAssessment,
        onReset: () => Object.assign(state, { data: null, error: '', loading: false }),
        drawerProps: {
          appendToBody: true,
          closeOnClickModal: false,
          resizable: true
        }
      }
    )
  }

  async function loadAssessment(): Promise<void> {
    if (state.loading) return
    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeWaybillProfitByAi()
      if (error) throw error
      if (!data) throw new Error('利润诊断服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getErrorMessage(error)
    } finally {
      state.loading = false
    }
  }

  function severityLabel(severity: Severity): string {
    return severity === 'critical' ? '严重' : severity === 'high' ? '高风险' : '中风险'
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

  function formatTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '--'
  }

  function getErrorMessage(error: unknown): string {
    if (error instanceof Error) return error.message
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message) return message
    }
    return '利润诊断服务暂时不可用，请稍后重试'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .profit-analyst {
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

    &__hero {
      position: relative;
      padding: 20px;
      overflow: hidden;
      background:
        radial-gradient(circle at 84% 12%, rgb(99 102 241 / 12%), transparent 28%),
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
    &__waybill header,
    &__waybill header > div,
    &__waybill-party,
    &__evidence,
    &__reasons,
    &__meta {
      display: flex;
      align-items: center;
    }

    &__hero-header,
    &__signal header,
    &__waybill header {
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
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--custom-radius);
      box-shadow: 0 10px 24px rgb(99 102 241 / 18%);

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
          font-size: 11px;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    }

    &__conclusion {
      display: flex;
      gap: 12px;
      align-items: center;
      padding-top: 16px;
      margin-top: 16px;
      border-top: 1px dashed var(--el-border-color-lighter);

      > span {
        display: grid;
        flex: 0 0 34px;
        place-items: center;
        width: 34px;
        height: 34px;
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
        border-radius: var(--el-border-radius-base);
      }

      small {
        color: var(--art-text-gray-500);
      }

      p {
        margin: 3px 0 0;
        line-height: 1.65;
        color: var(--art-text-gray-800);
      }
    }

    &__section {
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
          font-size: 16px;
          color: var(--art-text-gray-900);
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        small {
          overflow: hidden;
          font-size: 11px;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        &.is-danger strong {
          color: var(--el-color-danger);
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

      &.is-cost,
      &.is-loss {
        color: var(--el-color-danger) !important;
        background: var(--el-color-danger-light-9);
      }

      &.is-profit,
      &.is-coverage {
        color: var(--el-color-success) !important;
        background: var(--el-color-success-light-9);
      }

      &.is-carrier {
        color: var(--el-color-warning) !important;
        background: var(--el-color-warning-light-9);
      }
    }

    &__signals,
    &__waybills {
      display: grid;
      gap: 10px;
    }

    &__signal {
      position: relative;
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

      i {
        width: 5px;
        height: 5px;
        background: var(--el-color-warning);
        border-radius: 50%;
      }
    }

    &__waybills {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    &__waybill {
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
          font-size: 11px;
          color: var(--art-text-gray-500);
          text-overflow: ellipsis;
          white-space: nowrap;
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

    &__waybill-party {
      gap: 12px;
      margin: 12px 0;

      span {
        display: flex;
        gap: 5px;
        align-items: center;
        min-width: 0;
        overflow: hidden;
        font-size: 11px;
        color: var(--art-text-gray-500);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__waybill-metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 6px;
      padding: 10px;
      margin-bottom: 10px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);

      span,
      strong {
        display: block;
      }

      span {
        font-size: 10px;
        color: var(--art-text-gray-500);
      }

      strong {
        margin-top: 3px;
        overflow: hidden;
        font-size: 12px;
        color: var(--art-text-gray-800);
        text-overflow: ellipsis;
        white-space: nowrap;

        &.is-negative {
          color: var(--el-color-danger);
        }
      }
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

        small {
          color: var(--el-color-primary);
        }

        p {
          margin: 3px 0 0;
          line-height: 1.55;
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

    @media (width <= 720px) {
      &__hero-header {
        align-items: flex-start;
      }

      &__scores,
      &__metrics,
      &__waybills {
        grid-template-columns: 1fr;
      }

      &__waybill-metrics {
        grid-template-columns: repeat(3, minmax(0, 1fr));
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

      &__waybill-party {
        flex-direction: column;
        gap: 5px;
        align-items: flex-start;
      }
    }
  }
</style>
