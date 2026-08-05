<template>
  <ArtDrawer ref="drawerRef" :loading="state.loading" :show-footer="false">
    <template #header>
      <div class="collection-advisor__drawer-title">
        <span><ArtSvgIcon icon="ri:hand-coin-line" /></span>
        <div>
          <strong>AI 回款风险助手</strong>
          <small>从对账、开票到回款核销的只读风险研判</small>
        </div>
      </div>
    </template>

    <div class="collection-advisor">
      <template v-if="state.data">
        <section :class="['collection-advisor__hero art-card-xs', `is-${assessment.riskLevel}`]">
          <header class="collection-advisor__hero-header">
            <div class="collection-advisor__hero-main">
              <span class="collection-advisor__hero-icon">
                <ArtSvgIcon icon="ri:funds-line" />
              </span>
              <div>
                <span class="collection-advisor__eyebrow"><i />AI RECEIVABLES CONTROL</span>
                <div class="collection-advisor__title-row">
                  <strong>应收回款风险研判</strong>
                  <ElTag :type="riskTagType" effect="dark" round>{{ riskLabel }}</ElTag>
                  <ElTag type="info" effect="plain" round>{{ recommendationLabel }}</ElTag>
                </div>
                <p>分析当前租户 {{ assessment.metrics.openStatementCount }} 笔未关闭客户对账单</p>
              </div>
            </div>
            <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
              <ArtSvgIcon icon="ri:refresh-line" />重新研判
            </ElButton>
          </header>

          <div class="collection-advisor__scores">
            <article>
              <header
                ><span>回款风险</span><strong>{{ assessment.riskScore }}</strong></header
              >
              <ElProgress
                :percentage="assessment.riskScore"
                :show-text="false"
                :stroke-width="6"
                :color="riskProgressColor"
              />
              <small>综合账龄、对账、开票与金额集中度</small>
            </article>
            <article>
              <header
                ><span>研判置信度</span><strong>{{ confidencePercent }}%</strong></header
              >
              <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
              <small>基于系统内当前财务链路数据</small>
            </article>
            <article>
              <header
                ><span>账面回款率</span
                ><strong>{{ formatPercent(assessment.metrics.collectionRate) }}</strong></header
              >
              <ElProgress
                :percentage="assessment.metrics.collectionRate"
                :show-text="false"
                :stroke-width="6"
                :color="collectionProgressColor"
              />
              <small>已结金额占未关闭对账金额</small>
            </article>
          </div>

          <div class="collection-advisor__conclusion">
            <span><ArtSvgIcon :icon="conclusionIcon" /></span>
            <div>
              <small>AI 财务结论</small>
              <p>{{ assessment.summary }}</p>
            </div>
          </div>
        </section>

        <section class="collection-advisor__section">
          <ArtSectionTitle>
            <span class="collection-advisor__section-label">
              <ArtSvgIcon icon="ri:dashboard-3-line" />应收健康指标
            </span>
          </ArtSectionTitle>
          <div class="collection-advisor__metrics">
            <article class="art-card-xs">
              <span class="collection-advisor__metric-icon is-outstanding">
                <ArtSvgIcon icon="ri:wallet-3-line" />
              </span>
              <div
                ><span>当前未结应收</span
                ><strong>{{ formatMoney(assessment.metrics.outstandingAmount) }}</strong
                ><small>{{ assessment.metrics.openStatementCount }} 笔未关闭对账单</small></div
              >
            </article>
            <article class="art-card-xs is-danger">
              <span class="collection-advisor__metric-icon is-risk">
                <ArtSvgIcon icon="ri:alarm-warning-line" />
              </span>
              <div
                ><span>高关注金额</span
                ><strong>{{ formatMoney(assessment.metrics.atRiskAmount) }}</strong
                ><small>风险分数 60 分及以上</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="collection-advisor__metric-icon is-aging">
                <ArtSvgIcon icon="ri:time-line" />
              </span>
              <div
                ><span>60 天以上账龄</span
                ><strong>{{ formatMoney(assessment.metrics.aging60Amount) }}</strong
                ><small>按账期结束日计算</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="collection-advisor__metric-icon is-review">
                <ArtSvgIcon icon="ri:file-search-line" />
              </span>
              <div
                ><span>对账审核阻塞</span
                ><strong>{{ formatMoney(assessment.metrics.reviewBlockedAmount) }}</strong
                ><small>草稿与待审核对账单</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="collection-advisor__metric-icon is-invoice">
                <ArtSvgIcon icon="ri:bill-line" />
              </span>
              <div
                ><span>待完成开票</span
                ><strong>{{ formatMoney(assessment.metrics.uninvoicedAmount) }}</strong
                ><small>已确认应收的未开票金额</small></div
              >
            </article>
            <article class="art-card-xs">
              <span class="collection-advisor__metric-icon is-settled">
                <ArtSvgIcon icon="ri:checkbox-circle-line" />
              </span>
              <div
                ><span>已结金额</span
                ><strong>{{ formatMoney(assessment.metrics.settledAmount) }}</strong
                ><small>当前分析范围内已核销</small></div
              >
            </article>
          </div>
        </section>

        <section class="collection-advisor__section">
          <ArtSectionTitle>
            <span class="collection-advisor__section-label">
              <ArtSvgIcon icon="ri:radar-line" />优先跟进对账单
            </span>
          </ArtSectionTitle>
          <div v-if="assessment.priorityStatements.length" class="collection-advisor__statements">
            <article
              v-for="statement in assessment.priorityStatements"
              :key="statement.id"
              class="collection-advisor__statement art-card-xs"
            >
              <header>
                <div>
                  <span class="collection-advisor__risk-score">{{ statement.riskScore }}</span>
                  <div>
                    <strong>{{ statement.statementNo }}</strong>
                    <p><ArtSvgIcon icon="ri:building-line" />{{ statement.customerName }}</p>
                  </div>
                </div>
                <ArtDictDisplay
                  code="tmsSettlementStatus"
                  :value="statement.status"
                  display="tag"
                />
              </header>
              <div class="collection-advisor__statement-metrics">
                <span
                  ><small>未结金额</small
                  ><strong>{{ formatMoney(statement.outstandingAmount) }}</strong></span
                >
                <span
                  ><small>账龄参考</small><strong>{{ statement.ageDays }} 天</strong></span
                >
                <span
                  ><small>未开票</small
                  ><strong>{{ formatMoney(statement.uninvoicedAmount) }}</strong></span
                >
              </div>
              <div class="collection-advisor__reasons">
                <span v-for="reason in statement.reasons" :key="reason">{{ reason }}</span>
              </div>
              <footer>
                <span
                  >{{ statement.periodStart || '--' }} 至 {{ statement.periodEnd || '--' }}</span
                >
                <ElButton link type="primary" @click="goToStatement(statement)">
                  查看对账单<ArtSvgIcon icon="ri:arrow-right-line" />
                </ElButton>
              </footer>
            </article>
          </div>
          <ElEmpty v-else description="当前没有需要优先跟进的未结对账单" :image-size="76" />
        </section>

        <div class="collection-advisor__decision-grid">
          <section class="collection-advisor__section">
            <ArtSectionTitle>
              <span class="collection-advisor__section-label">
                <ArtSvgIcon icon="ri:alarm-warning-line" />风险信号
              </span>
            </ArtSectionTitle>
            <div v-if="assessment.signals.length" class="collection-advisor__signals">
              <article
                v-for="signal in assessment.signals"
                :key="signal.type"
                :class="['collection-advisor__signal art-card-xs', `is-${signal.severity}`]"
              >
                <header>
                  <div
                    ><span><ArtSvgIcon :icon="signalIcon(signal.severity)" /></span
                    ><strong>{{ signal.title }}</strong></div
                  >
                  <ElTag :type="severityTagType(signal.severity)" effect="light" round>{{
                    severityLabel(signal.severity)
                  }}</ElTag>
                </header>
                <p>{{ signal.detail }}</p>
                <div class="collection-advisor__evidence">
                  <span v-for="item in signal.evidence" :key="item"><i />{{ item }}</span>
                </div>
              </article>
            </div>
            <ElEmpty v-else description="当前未识别到明确的回款风险信号" :image-size="76" />
          </section>

          <section class="collection-advisor__section">
            <ArtSectionTitle>
              <span class="collection-advisor__section-label">
                <ArtSvgIcon icon="ri:user-star-line" />高关注客户
              </span>
            </ArtSectionTitle>
            <div
              v-if="assessment.riskCustomers.length"
              class="collection-advisor__customers art-card-xs"
            >
              <article
                v-for="customer in assessment.riskCustomers"
                :key="customer.customerId || customer.customerName"
              >
                <span>{{ customer.riskScore }}</span>
                <div>
                  <header
                    ><strong>{{ customer.customerName }}</strong
                    ><small>{{ customer.statementCount }} 笔</small></header
                  >
                  <p
                    >{{ formatMoney(customer.outstandingAmount) }} 未结 · 最长
                    {{ customer.maxAgeDays }} 天</p
                  >
                </div>
              </article>
            </div>
            <ElEmpty v-else description="暂无高关注客户" :image-size="76" />
          </section>
        </div>

        <section class="collection-advisor__section">
          <ArtSectionTitle>
            <span class="collection-advisor__section-label">
              <ArtSvgIcon icon="ri:list-check-3" />建议处理顺序
            </span>
          </ArtSectionTitle>
          <ol class="collection-advisor__actions art-card-xs">
            <li v-for="(action, index) in assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <div
                ><small>财务跟进步骤 {{ index + 1 }}</small
                ><p>{{ action }}</p></div
              >
            </li>
          </ol>
        </section>

        <section class="collection-advisor__section">
          <ArtSectionTitle>
            <span class="collection-advisor__section-label">
              <ArtSvgIcon icon="ri:information-2-line" />判断边界
            </span>
          </ArtSectionTitle>
          <div class="collection-advisor__limitations art-card-xs">
            <p v-for="item in assessment.limitations" :key="item">
              <ArtSvgIcon icon="ri:checkbox-circle-line" /><span>{{ item }}</span>
            </p>
          </div>
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 回款风险助手" />

        <footer class="collection-advisor__meta">
          <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data.ruleVersion }}</span>
          <span><ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data.generatedAt) }}</span>
          <span
            ><ArtSvgIcon
              icon="ri:shield-check-line"
            />只读研判，不会自动改账、催收或修改业务状态</span
          >
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="回款风险分析失败"
        :sub-title="state.error"
      >
        <template #extra
          ><ElButton type="primary" @click="loadAssessment">重新分析</ElButton></template
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
  import { analyzeReceivablesCollectionByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsReceivablesCollectionAdvisorDrawer' })

  type AnalysisResponse = Api.Tms.Finance.ReceivablesCollectionResponse
  type RiskLevel = Api.Tms.Finance.ReceivablesRiskLevel
  type Recommendation = Api.Tms.Finance.ReceivablesRecommendation
  type Severity = Api.Tms.Finance.ReceivablesSignalSeverity
  type PriorityStatement = Api.Tms.Finance.ReceivablesPriorityStatement

  interface AnalysisState {
    data: AnalysisResponse | null
    error: string
    loading: boolean
  }

  const router = useRouter()
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
    unblock_settlement: '先解除对账阻塞',
    complete_invoicing: '先完成开票',
    prioritize_collection: '优先催收长账龄',
    routine_monitoring: '常规回款跟进'
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
  const collectionProgressColor = computed(() => {
    const rate = assessment.value.metrics.collectionRate
    return rate < 30
      ? 'var(--el-color-danger)'
      : rate < 70
        ? 'var(--el-color-warning)'
        : 'var(--el-color-success)'
  })
  const conclusionIcon = computed(() =>
    assessment.value.riskLevel === 'critical' || assessment.value.riskLevel === 'high'
      ? 'ri:alarm-warning-line'
      : 'ri:checkbox-circle-line'
  )

  async function handleOpen(): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false })
    await drawerRef.value?.handleOpen(
      {},
      {
        title: 'AI 回款风险助手',
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
      const { data, error } = await analyzeReceivablesCollectionByAi()
      if (error) throw error
      if (!data) throw new Error('回款风险分析服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getErrorMessage(error)
    } finally {
      state.loading = false
    }
  }

  async function goToStatement(statement: PriorityStatement): Promise<void> {
    await drawerRef.value?.handleClose()
    await router.push({ name: 'TmsCustomerSettlement', query: { keyword: statement.statementNo } })
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
    return '回款风险分析服务暂时不可用，请稍后重试'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .collection-advisor {
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
    &__statement header,
    &__statement header > div,
    &__evidence,
    &__reasons,
    &__meta {
      display: flex;
      align-items: center;
    }

    &__hero-header,
    &__signal header,
    &__statement header {
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

      &.is-risk,
      &.is-aging {
        color: var(--el-color-danger) !important;
        background: var(--el-color-danger-light-9);
      }

      &.is-review,
      &.is-invoice {
        color: var(--el-color-warning) !important;
        background: var(--el-color-warning-light-9);
      }

      &.is-settled {
        color: var(--el-color-success) !important;
        background: var(--el-color-success-light-9);
      }
    }

    &__statements {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    &__statement {
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

      footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding-top: 10px;
        margin-top: 10px;
        font-size: 11px;
        color: var(--art-text-gray-400);
        border-top: 1px dashed var(--el-border-color-lighter);
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

    &__statement-metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 6px;
      padding: 10px;
      margin: 12px 0 10px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);

      span,
      small,
      strong {
        display: block;
        min-width: 0;
      }

      small {
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

    &__reasons,
    &__evidence {
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

    &__decision-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.5fr) minmax(280px, 0.8fr);
      gap: 16px;
      min-width: 0;
    }

    &__signals {
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

    &__customers {
      padding: 4px 16px;

      article {
        display: grid;
        grid-template-columns: 34px minmax(0, 1fr);
        gap: 10px;
        align-items: center;
        padding: 12px 0;

        & + article {
          border-top: 1px dashed var(--el-border-color-lighter);
        }

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          font-size: 12px;
          font-weight: 700;
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
          border-radius: 50%;
        }

        header {
          display: flex;
          gap: 8px;
          align-items: center;
          justify-content: space-between;
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--art-text-gray-900);
          white-space: nowrap;
        }

        small,
        p {
          color: var(--art-text-gray-500);
        }

        p {
          margin: 4px 0 0;
          font-size: 11px;
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

    @media (width <= 760px) {
      &__scores,
      &__metrics,
      &__statements,
      &__decision-grid {
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

      &__statement footer {
        gap: 8px;
        align-items: flex-start;
      }
    }
  }
</style>
