<template>
  <ArtDrawer ref="drawerRef" :loading="state.loading" :show-footer="false">
    <template #header="{ data }">
      <div class="cost-auditor__drawer-title">
        <span>
          <ArtSvgIcon icon="ri:sparkling-2-line" />
        </span>
        <div>
          <strong>AI 运单费用审核</strong>
          <small>{{ data.waybillNo }} · 风险审查与财务影响评估</small>
        </div>
      </div>
    </template>

    <div class="cost-auditor">
      <template v-if="state.data">
        <section
          :class="['cost-auditor__hero art-card-xs', `is-${state.data.assessment.riskLevel}`]"
        >
          <header class="cost-auditor__hero-header">
            <div class="cost-auditor__hero-main">
              <span class="cost-auditor__icon">
                <ArtSvgIcon icon="ri:shield-check-line" />
              </span>
              <div>
                <span class="cost-auditor__eyebrow"> <i /> AI COST AUDIT · 实时研判 </span>
                <div class="cost-auditor__title-row">
                  <strong>{{ state.data.assessment.waybillNo }}</strong>
                  <ElTag :type="riskTagType" effect="dark" round>{{ riskLabel }}</ElTag>
                  <ElTag type="info" effect="plain" round>{{ recommendationLabel }}</ElTag>
                </div>
                <p>
                  <ArtSvgIcon icon="ri:route-line" />
                  {{ state.data.assessment.route }}
                </p>
              </div>
            </div>
            <ElButton
              class="cost-auditor__refresh"
              type="primary"
              plain
              :loading="state.loading"
              @click="loadAssessment"
            >
              <ArtSvgIcon icon="ri:refresh-line" />
              重新审核
            </ElButton>
          </header>

          <div class="cost-auditor__score">
            <article class="is-risk">
              <header>
                <span><ArtSvgIcon icon="ri:pulse-line" />风险评分</span>
                <strong>{{ state.data.assessment.riskScore }}</strong>
              </header>
              <ElProgress
                :percentage="state.data.assessment.riskScore"
                :show-text="false"
                :stroke-width="6"
                :color="riskProgressColor"
              />
              <small>综合异常信号与财务影响</small>
            </article>
            <article class="is-confidence">
              <header>
                <span><ArtSvgIcon icon="ri:focus-3-line" />审核置信度</span>
                <strong>{{ confidencePercent }}%</strong>
              </header>
              <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
              <small>基于当前可用业务数据</small>
            </article>
            <article class="is-amount">
              <header>
                <span><ArtSvgIcon icon="ri:money-cny-circle-line" />本笔金额</span>
                <strong>{{ formatMoney(state.data.assessment.metrics.amount) }}</strong>
              </header>
              <div class="cost-auditor__amount-line"><i /></div>
              <small>本次待审费用金额</small>
            </article>
          </div>

          <div class="cost-auditor__conclusion">
            <span><ArtSvgIcon :icon="conclusionIcon" /></span>
            <div>
              <small>AI 审核结论</small>
              <p>{{ state.data.assessment.summary }}</p>
            </div>
          </div>
        </section>

        <section class="cost-auditor__section">
          <ArtSectionTitle>
            <span class="cost-auditor__section-label">
              <ArtSvgIcon icon="ri:funds-box-line" />财务影响
            </span>
          </ArtSectionTitle>
          <div class="cost-auditor__metrics">
            <article class="art-card-xs">
              <span class="cost-auditor__metric-icon is-cost">
                <ArtSvgIcon icon="ri:funds-line" />
              </span>
              <div>
                <span>预计总成本</span>
                <strong>{{ formatMoney(state.data.assessment.metrics.projectedTotalCost) }}</strong>
                <small>计入本笔费用后</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="cost-auditor__metric-icon is-receivable">
                <ArtSvgIcon icon="ri:wallet-3-line" />
              </span>
              <div>
                <span>运单应收</span>
                <strong>{{
                  formatOptionalMoney(state.data.assessment.metrics.receivableAmount)
                }}</strong>
                <small>客户侧应收基线</small>
              </div>
            </article>
            <article :class="['art-card-xs', marginTone]">
              <span class="cost-auditor__metric-icon is-margin">
                <ArtSvgIcon icon="ri:line-chart-line" />
              </span>
              <div>
                <span>预计毛利率</span>
                <strong>{{
                  formatMargin(state.data.assessment.metrics.projectedGrossMargin)
                }}</strong>
                <small>{{ marginDescription }}</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="cost-auditor__metric-icon is-duplicate">
                <ArtSvgIcon icon="ri:file-copy-2-line" />
              </span>
              <div>
                <span>疑似重复</span>
                <strong>{{ state.data.assessment.metrics.duplicateCount }} 条</strong>
                <small>同类型、金额与收款方</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="cost-auditor__metric-icon is-history">
                <ArtSvgIcon icon="ri:bar-chart-grouped-line" />
              </span>
              <div>
                <span>历史中位数</span>
                <strong>{{
                  formatOptionalMoney(state.data.assessment.metrics.benchmarkMedian)
                }}</strong>
                <small>参考样本 {{ state.data.assessment.metrics.benchmarkSampleSize }} 条</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="cost-auditor__metric-icon is-attachment">
                <ArtSvgIcon icon="ri:attachment-2" />
              </span>
              <div>
                <span>附件凭证</span>
                <strong>{{ state.data.assessment.metrics.attachmentCount }} 份</strong>
                <small>票据与证明材料</small>
              </div>
            </article>
          </div>
        </section>

        <section class="cost-auditor__section">
          <ArtSectionTitle>
            <span class="cost-auditor__section-label">
              <ArtSvgIcon icon="ri:alarm-warning-line" />审核风险
            </span>
          </ArtSectionTitle>
          <div v-if="state.data.assessment.signals.length" class="cost-auditor__signals">
            <article
              v-for="signal in state.data.assessment.signals"
              :key="signal.type"
              :class="['cost-auditor__signal art-card-xs', `is-${signal.severity}`]"
            >
              <header>
                <div class="cost-auditor__signal-title">
                  <span><ArtSvgIcon :icon="signalIcon(signal.severity)" /></span>
                  <div>
                    <small>风险信号</small>
                    <strong>{{ signal.title }}</strong>
                  </div>
                </div>
                <ElTag :type="severityTagType(signal.severity)" effect="light" round>
                  {{ severityLabel(signal.severity) }}
                </ElTag>
              </header>
              <p>{{ signal.detail }}</p>
              <div class="cost-auditor__evidence">
                <span v-for="item in signal.evidence" :key="item"><i />{{ item }}</span>
              </div>
            </article>
          </div>
          <ElEmpty v-else description="当前未识别到明确费用异常" :image-size="76" />
        </section>

        <section class="cost-auditor__section">
          <ArtSectionTitle>
            <span class="cost-auditor__section-label">
              <ArtSvgIcon icon="ri:list-check-3" />建议核对顺序
            </span>
          </ArtSectionTitle>
          <ol class="cost-auditor__actions art-card-xs">
            <li v-for="(action, index) in state.data.assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <div>
                <small>核对步骤 {{ index + 1 }}</small>
                <p>{{ action }}</p>
              </div>
            </li>
          </ol>
        </section>

        <section class="cost-auditor__section">
          <ArtSectionTitle>
            <span class="cost-auditor__section-label">
              <ArtSvgIcon icon="ri:information-2-line" />数据边界
            </span>
          </ArtSectionTitle>
          <div class="cost-auditor__limitations art-card-xs">
            <p v-for="item in state.data.assessment.limitations" :key="item">
              <ArtSvgIcon icon="ri:checkbox-circle-line" />
              <span>{{ item }}</span>
            </p>
          </div>
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 运单费用审核" />

        <footer class="cost-auditor__meta">
          <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data.ruleVersion }}</span>
          <span> <ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data.generatedAt) }} </span>
          <span> <ArtSvgIcon icon="ri:shield-check-line" />只读建议，不会自动修改财务数据 </span>
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="费用审核失败"
        :sub-title="state.error"
      >
        <template #extra>
          <ElButton type="primary" @click="loadAssessment">重新审核</ElButton>
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
  import { analyzeWaybillCostByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsWaybillCostAuditDrawer' })

  type AuditResponse = Api.Tms.Finance.WaybillCostAuditResponse
  type RiskLevel = Api.Tms.Finance.WaybillCostAuditRiskLevel
  type Recommendation = Api.Tms.Finance.WaybillCostAuditRecommendation
  type SignalSeverity = Api.Tms.Finance.WaybillCostAuditSeverity

  interface DrawerOpenData {
    costId: string
    waybillNo: string
  }

  interface AuditorState {
    data: AuditResponse | null
    error: string
    loading: boolean
    openData: DrawerOpenData | null
  }

  const drawerRef = ref<ArtDrawerExpose<DrawerOpenData>>()
  const state: UnwrapNestedRefs<AuditorState> = reactive<AuditorState>({
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
  const recommendationLabelMap: Record<Recommendation, string> = {
    block_for_verification: '先核验再决策',
    manual_review: '建议重点人工复核',
    routine_review: '进入常规人工审核'
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

  const riskLabel = computed(() =>
    state.data ? riskLabelMap[state.data.assessment.riskLevel] : '-'
  )
  const riskTagType = computed(() =>
    state.data ? tagTypeMap[state.data.assessment.riskLevel] : 'info'
  )
  const recommendationLabel = computed(() =>
    state.data ? recommendationLabelMap[state.data.assessment.recommendation] : '-'
  )
  const confidencePercent = computed(() =>
    state.data ? Math.round(state.data.assessment.confidence * 100) : 0
  )
  const riskProgressColor = computed(() =>
    state.data ? progressColorMap[state.data.assessment.riskLevel] : progressColorMap.low
  )
  const conclusionIcon = computed(() => {
    const riskLevel = state.data?.assessment.riskLevel
    return riskLevel === 'critical' || riskLevel === 'high'
      ? 'ri:alarm-warning-line'
      : riskLevel === 'medium'
        ? 'ri:error-warning-line'
        : 'ri:checkbox-circle-line'
  })
  const marginTone = computed(() => {
    const margin = state.data?.assessment.metrics.projectedGrossMargin
    if (margin === null || margin === undefined) return 'is-neutral'
    if (margin < 0) return 'is-danger'
    if (margin < 0.1) return 'is-warning'
    return 'is-success'
  })
  const marginDescription = computed(() => {
    const margin = state.data?.assessment.metrics.projectedGrossMargin
    if (margin === null || margin === undefined) return '暂无利润计算基线'
    if (margin < 0) return '成本已超过运单应收'
    if (margin < 0.1) return '低于 10% 风险阈值'
    return '当前利润空间正常'
  })

  async function handleOpen(data: DrawerOpenData): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false, openData: data })
    await drawerRef.value?.handleOpen(data, {
      title: `AI 运单费用审核 · ${data.waybillNo}`,
      size: 'lg',
      contentHeight: 'calc(100vh - 120px)',
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
    const costId = state.openData?.costId
    if (!costId || state.loading) return

    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeWaybillCostByAi(costId)
      if (error) throw error
      if (!data) throw new Error('费用审核服务未返回结果')
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

  function formatMoney(value: number): string {
    return `¥${Number(value).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function formatOptionalMoney(value: number | null): string {
    return value === null ? '数据不足' : formatMoney(value)
  }

  function formatMargin(value: number | null): string {
    return value === null ? '数据不足' : `${Math.round(value * 1_000) / 10}%`
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
    return 'AI 运单费用审核失败，请稍后重试'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .cost-auditor {
    display: grid;
    gap: 24px;

    &__drawer-title {
      display: flex;
      gap: 12px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 38px;
        height: 38px;
        font-size: 20px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      strong {
        overflow: hidden;
        font-size: 16px;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        overflow: hidden;
        color: var(--el-text-color-secondary);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__hero {
      display: grid;
      gap: 18px;
      padding: 20px;
      overflow: hidden;
      border-left: 3px solid var(--el-color-primary);

      &.is-critical,
      &.is-high {
        border-left-color: var(--el-color-danger);

        .cost-auditor__icon,
        .cost-auditor__conclusion > span {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
        }
      }

      &.is-medium {
        border-left-color: var(--el-color-warning);

        .cost-auditor__icon,
        .cost-auditor__conclusion > span {
          color: var(--el-color-warning);
          background: var(--el-color-warning-light-9);
        }
      }

      &.is-low {
        border-left-color: var(--el-color-success);

        .cost-auditor__icon,
        .cost-auditor__conclusion > span {
          color: var(--el-color-success);
          background: var(--el-color-success-light-9);
        }
      }
    }

    &__hero-header {
      display: flex;
      gap: 20px;
      align-items: flex-start;
      justify-content: space-between;
    }

    &__hero-main {
      display: flex;
      gap: 13px;
      align-items: center;
      min-width: 0;

      > div {
        min-width: 0;
      }

      p {
        display: flex;
        gap: 6px;
        align-items: center;
        margin: 6px 0 0;
        overflow: hidden;
        font-size: 13px;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 24px;
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
      color: var(--el-text-color-secondary);
      letter-spacing: 0.08em;

      i {
        width: 5px;
        height: 5px;
        background: var(--el-color-success);
        border-radius: 50%;
        box-shadow: 0 0 0 3px var(--el-color-success-light-9);
      }
    }

    &__title-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;

      strong {
        font-size: 19px;
        color: var(--el-text-color-primary);
      }
    }

    &__refresh {
      flex: none;

      .art-svg-icon {
        margin-right: 5px;
      }
    }

    &__score {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;

      article {
        display: grid;
        gap: 9px;
        min-width: 0;
        padding: 14px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);

        > header {
          display: flex;
          gap: 10px;
          align-items: center;
          justify-content: space-between;

          span {
            display: flex;
            gap: 5px;
            align-items: center;
            min-width: 0;
            color: var(--el-text-color-secondary);
          }

          strong {
            overflow: hidden;
            font-size: 20px;
            text-overflow: ellipsis;
            color: var(--el-color-primary);
            white-space: nowrap;
          }
        }

        small {
          overflow: hidden;
          font-size: 11px;
          text-overflow: ellipsis;
          color: var(--el-text-color-placeholder);
          white-space: nowrap;
        }

        &.is-risk header strong {
          color: var(--el-color-danger);
        }
      }
    }

    &__amount-line {
      height: 6px;
      overflow: hidden;
      background: var(--el-border-color-extra-light);
      border-radius: 999px;

      i {
        display: block;
        width: 100%;
        height: 100%;
        background: linear-gradient(
          90deg,
          var(--el-color-primary-light-5),
          var(--el-color-primary)
        );
        border-radius: inherit;
      }
    }

    &__conclusion {
      display: flex;
      gap: 11px;
      align-items: flex-start;
      padding-top: 16px;
      border-top: 1px dashed var(--el-border-color-lighter);

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 32px;
        height: 32px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      > div {
        display: grid;
        gap: 3px;
      }

      small {
        font-weight: 600;
        color: var(--el-text-color-secondary);
      }

      p {
        margin: 0;
        line-height: 1.7;
        color: var(--el-text-color-primary);
      }
    }

    &__section {
      display: grid;
      gap: 14px;
    }

    &__section-label {
      display: inline-flex;
      gap: 7px;
      align-items: center;

      .art-svg-icon {
        color: var(--el-color-primary);
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;

      article {
        display: flex;
        gap: 12px;
        align-items: center;
        min-width: 0;
        padding: 15px;

        > div {
          display: grid;
          gap: 4px;
          min-width: 0;
        }

        > div > span,
        small {
          overflow: hidden;
          font-size: 12px;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        strong {
          overflow: hidden;
          font-size: 17px;
          text-overflow: ellipsis;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }

        &.is-danger strong {
          color: var(--el-color-danger);
        }

        &.is-warning strong {
          color: var(--el-color-warning-dark-2);
        }

        &.is-success strong {
          color: var(--el-color-success);
        }
      }
    }

    &__metric-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 18px;
      border-radius: var(--el-border-radius-base);

      &.is-cost,
      &.is-duplicate {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }

      &.is-receivable,
      &.is-attachment {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-margin {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-history {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }
    }

    &__signals {
      display: grid;
      gap: 12px;
    }

    &__signal {
      display: grid;
      gap: 12px;
      padding: 16px;
      border-left: 3px solid var(--el-color-warning);

      &.is-critical,
      &.is-high {
        border-left-color: var(--el-color-danger);

        .cost-auditor__signal-title > span {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
        }
      }

      > header {
        display: flex;
        gap: 12px;
        align-items: center;
        justify-content: space-between;
      }

      > p {
        margin: 0;
        line-height: 1.7;
        color: var(--el-text-color-regular);
      }
    }

    &__signal-title {
      display: flex;
      gap: 10px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 36px;
        height: 36px;
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
        border-radius: var(--el-border-radius-base);
      }

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      small {
        font-size: 10px;
        color: var(--el-text-color-placeholder);
        letter-spacing: 0.08em;
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__evidence {
      display: flex;
      flex-wrap: wrap;
      gap: 7px;

      span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        padding: 5px 9px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-small);
      }

      i {
        width: 5px;
        height: 5px;
        background: var(--el-color-warning);
        border-radius: 50%;
      }
    }

    &__actions {
      display: grid;
      padding: 5px 16px;
      margin: 0;
      list-style: none;

      li {
        display: flex;
        gap: 12px;
        align-items: flex-start;
        padding: 13px 0;

        & + li {
          border-top: 1px dashed var(--el-border-color-lighter);
        }

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 26px;
          height: 26px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;
        }

        > div {
          display: grid;
          gap: 3px;
        }

        small {
          font-size: 10px;
          font-weight: 600;
          color: var(--el-color-primary);
          letter-spacing: 0.06em;
        }

        p {
          margin: 0;
          line-height: 1.65;
        }
      }
    }

    &__limitations {
      display: grid;
      gap: 10px;
      padding: 15px 16px;

      p {
        display: flex;
        gap: 8px;
        align-items: flex-start;
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }

      .art-svg-icon {
        flex: none;
        margin-top: 3px;
        color: var(--el-color-primary);
      }
    }

    &__meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 18px;
      padding: 12px 2px 2px;
      font-size: 11px;
      color: var(--el-text-color-placeholder);
      border-top: 1px dashed var(--el-border-color-lighter);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
      }
    }
  }

  @media (width <= 720px) {
    .cost-auditor {
      gap: 20px;

      &__hero-header {
        display: grid;
      }

      &__refresh {
        justify-self: stretch;
      }

      &__score,
      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 480px) {
    .cost-auditor {
      &__drawer-title small,
      &__eyebrow {
        display: none;
      }

      &__hero,
      &__signal {
        padding: 14px;
      }

      &__hero-main {
        align-items: flex-start;
      }

      &__title-row {
        align-items: flex-start;
      }

      &__signal > header {
        align-items: flex-start;
      }
    }
  }
</style>
