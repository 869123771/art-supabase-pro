<template>
  <ArtDrawer ref="drawerRef" :loading="state.loading" :show-footer="false">
    <template #header="{ data }">
      <div class="invoice-auditor__drawer-title">
        <span><ArtSvgIcon icon="ri:file-shield-2-line" /></span>
        <div>
          <strong>AI 发票合规审核</strong>
          <small>{{ data.invoiceRecordNo }} · 票面数据与对账关系复核</small>
        </div>
      </div>
    </template>

    <div class="invoice-auditor">
      <template v-if="state.data">
        <section :class="['invoice-auditor__hero art-card-xs', `is-${assessment.riskLevel}`]">
          <header class="invoice-auditor__hero-header">
            <div class="invoice-auditor__identity">
              <span class="invoice-auditor__identity-icon">
                <ArtSvgIcon icon="ri:bill-line" />
              </span>
              <div>
                <span class="invoice-auditor__eyebrow"><i /> AI INVOICE AUDIT · 实时研判</span>
                <div class="invoice-auditor__title-row">
                  <strong>{{ assessment.invoiceNo || assessment.invoiceRecordNo }}</strong>
                  <ElTag :type="riskTagType" effect="dark" round>{{ riskLabel }}</ElTag>
                  <ElTag type="info" effect="plain" round>{{ recommendationLabel }}</ElTag>
                </div>
                <p>
                  <ArtSvgIcon icon="ri:building-2-line" />
                  {{ assessment.counterpartyName }}
                </p>
              </div>
            </div>
            <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
              <ArtSvgIcon icon="ri:refresh-line" />
              重新审核
            </ElButton>
          </header>

          <div class="invoice-auditor__score-grid">
            <article>
              <span>风险评分</span>
              <strong class="is-risk">{{ assessment.riskScore }}</strong>
              <ElProgress
                :percentage="assessment.riskScore"
                :show-text="false"
                :stroke-width="6"
                :color="riskProgressColor"
              />
              <small>综合数据异常与财务影响</small>
            </article>
            <article>
              <span>审核置信度</span>
              <strong>{{ confidencePercent }}%</strong>
              <ElProgress :percentage="confidencePercent" :show-text="false" :stroke-width="6" />
              <small>取决于当前资料完整程度</small>
            </article>
            <article>
              <span>价税合计</span>
              <strong>{{ formatMoney(assessment.metrics.totalAmount) }}</strong>
              <div class="invoice-auditor__amount-line"><i /></div>
              <small>当前待复核发票金额</small>
            </article>
          </div>

          <div class="invoice-auditor__conclusion">
            <span><ArtSvgIcon :icon="conclusionIcon" /></span>
            <div>
              <small>AI 审核结论</small>
              <p>{{ assessment.summary }}</p>
            </div>
          </div>
        </section>

        <section class="invoice-auditor__section">
          <ArtSectionTitle>
            <span class="invoice-auditor__section-label">
              <ArtSvgIcon icon="ri:pie-chart-2-line" />审核概览
            </span>
          </ArtSectionTitle>
          <div class="invoice-auditor__metrics">
            <article class="art-card-xs">
              <span class="invoice-auditor__metric-icon is-total">
                <ArtSvgIcon icon="ri:money-cny-circle-line" />
              </span>
              <div>
                <span>公式计算合计</span>
                <strong>{{ formatMoney(assessment.metrics.calculatedTotalAmount) }}</strong>
                <small>不含税金额 + 税额</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="invoice-auditor__metric-icon is-linked">
                <ArtSvgIcon icon="ri:links-line" />
              </span>
              <div>
                <span>对账覆盖率</span>
                <strong>{{ coveragePercent }}%</strong>
                <small>已关联 {{ formatMoney(assessment.metrics.linkedAmount) }}</small>
              </div>
            </article>
            <article
              :class="['art-card-xs', { 'is-warning': assessment.metrics.unlinkedAmount > 0 }]"
            >
              <span class="invoice-auditor__metric-icon is-unlinked">
                <ArtSvgIcon icon="ri:link-unlink-m" />
              </span>
              <div>
                <span>未关联金额</span>
                <strong>{{ formatMoney(assessment.metrics.unlinkedAmount) }}</strong>
                <small>需确认业务归属</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="invoice-auditor__metric-icon is-statement">
                <ArtSvgIcon icon="ri:file-list-3-line" />
              </span>
              <div>
                <span>关联对账单</span>
                <strong>{{ assessment.metrics.statementCount }} 张</strong>
                <small>当前发票关联依据</small>
              </div>
            </article>
            <article
              :class="['art-card-xs', { 'is-danger': assessment.metrics.duplicateCount > 0 }]"
            >
              <span class="invoice-auditor__metric-icon is-duplicate">
                <ArtSvgIcon icon="ri:file-copy-2-line" />
              </span>
              <div>
                <span>疑似重复票号</span>
                <strong>{{ assessment.metrics.duplicateCount }} 张</strong>
                <small>同租户未作废记录</small>
              </div>
            </article>
            <article class="art-card-xs">
              <span class="invoice-auditor__metric-icon is-attachment">
                <ArtSvgIcon icon="ri:attachment-2" />
              </span>
              <div>
                <span>原始附件</span>
                <strong>{{ assessment.metrics.attachmentCount }} 份</strong>
                <small>票面与电子发票凭证</small>
              </div>
            </article>
          </div>
        </section>

        <section class="invoice-auditor__section">
          <ArtSectionTitle>
            <span class="invoice-auditor__section-label">
              <ArtSvgIcon icon="ri:alarm-warning-line" />合规风险
            </span>
          </ArtSectionTitle>
          <div v-if="assessment.signals.length" class="invoice-auditor__signals">
            <article
              v-for="signal in assessment.signals"
              :key="signal.type"
              :class="['invoice-auditor__signal art-card-xs', `is-${signal.severity}`]"
            >
              <header>
                <div class="invoice-auditor__signal-title">
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
              <div class="invoice-auditor__evidence">
                <span v-for="item in signal.evidence" :key="item"><i />{{ item }}</span>
              </div>
            </article>
          </div>
          <div v-else class="invoice-auditor__empty art-card-xs">
            <span><ArtSvgIcon icon="ri:shield-check-line" /></span>
            <div>
              <strong>当前数据检查通过</strong>
              <p>未发现明确异常，仍需按财务制度核对原始票面后完成最终复核。</p>
            </div>
          </div>
        </section>

        <section class="invoice-auditor__section">
          <ArtSectionTitle>
            <span class="invoice-auditor__section-label">
              <ArtSvgIcon icon="ri:list-check-3" />建议核对顺序
            </span>
          </ArtSectionTitle>
          <ol class="invoice-auditor__actions art-card-xs">
            <li v-for="(action, index) in assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span>
              <div>
                <small>核对步骤 {{ index + 1 }}</small>
                <p>{{ action }}</p>
              </div>
            </li>
          </ol>
        </section>

        <section class="invoice-auditor__section">
          <ArtSectionTitle>
            <span class="invoice-auditor__section-label">
              <ArtSvgIcon icon="ri:information-2-line" />数据边界
            </span>
          </ArtSectionTitle>
          <div class="invoice-auditor__limitations art-card-xs">
            <p v-for="item in assessment.limitations" :key="item">
              <ArtSvgIcon icon="ri:checkbox-circle-line" /><span>{{ item }}</span>
            </p>
          </div>
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 发票合规审核" />

        <footer class="invoice-auditor__meta">
          <span><ArtSvgIcon icon="ri:git-commit-line" />{{ state.data.ruleVersion }}</span>
          <span><ArtSvgIcon icon="ri:time-line" />{{ formatTime(state.data.generatedAt) }}</span>
          <span><ArtSvgIcon icon="ri:shield-check-line" />只读建议，不会自动审批发票</span>
        </footer>
      </template>

      <ElResult
        v-else-if="state.error"
        icon="warning"
        title="发票审核失败"
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
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import type { UnwrapNestedRefs } from 'vue'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { analyzeInvoiceComplianceByAi } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'TmsInvoiceComplianceAuditDrawer' })

  type AuditResponse = Api.Tms.Finance.InvoiceComplianceAuditResponse
  type Assessment = Api.Tms.Finance.InvoiceComplianceAssessment
  type RiskLevel = Api.Tms.Finance.InvoiceComplianceRiskLevel
  type Recommendation = Api.Tms.Finance.InvoiceComplianceRecommendation
  type SignalSeverity = Api.Tms.Finance.InvoiceComplianceSeverity

  interface DrawerOpenData {
    invoiceId: string
    invoiceRecordNo: string
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
    routine_review: '进入常规人工复核'
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

  const assessment = computed<Assessment>(() => state.data!.assessment)
  const riskLabel = computed(() => riskLabelMap[assessment.value.riskLevel])
  const riskTagType = computed(() => tagTypeMap[assessment.value.riskLevel])
  const recommendationLabel = computed(
    () => recommendationLabelMap[assessment.value.recommendation]
  )
  const confidencePercent = computed(() => Math.round(assessment.value.confidence * 100))
  const coveragePercent = computed(
    () => Math.round(assessment.value.metrics.coverageRate * 1000) / 10
  )
  const riskProgressColor = computed(() => progressColorMap[assessment.value.riskLevel])
  const conclusionIcon = computed(() => {
    const riskLevel = assessment.value.riskLevel
    return riskLevel === 'critical' || riskLevel === 'high'
      ? 'ri:alarm-warning-line'
      : riskLevel === 'medium'
        ? 'ri:error-warning-line'
        : 'ri:shield-check-line'
  })

  async function handleOpen(data: DrawerOpenData): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false, openData: data })
    await drawerRef.value?.handleOpen(data, {
      title: `AI 发票合规审核 · ${data.invoiceRecordNo}`,
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
    const invoiceId = state.openData?.invoiceId
    if (!invoiceId || state.loading) return

    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeInvoiceComplianceByAi(invoiceId)
      if (error) throw error
      if (!data) throw new Error('发票审核服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getFriendlySupabaseErrorMessage(error, 'AI 发票合规审核失败，请稍后重试')
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
    return formatCurrencyValue(value)
  }

  function formatTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') || '-'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .invoice-auditor {
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

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-size: 16px;
      }

      small {
        color: var(--el-text-color-secondary);
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

        .invoice-auditor__identity-icon,
        .invoice-auditor__conclusion > span {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
        }
      }

      &.is-medium {
        border-left-color: var(--el-color-warning);

        .invoice-auditor__identity-icon,
        .invoice-auditor__conclusion > span {
          color: var(--el-color-warning);
          background: var(--el-color-warning-light-9);
        }
      }

      &.is-low {
        border-left-color: var(--el-color-success);

        .invoice-auditor__identity-icon,
        .invoice-auditor__conclusion > span {
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

      .art-svg-icon {
        margin-right: 5px;
      }
    }

    &__identity {
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
        text-overflow: ellipsis;
        font-size: 13px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__identity-icon {
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

    &__score-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;

      article {
        display: grid;
        gap: 8px;
        min-width: 0;
        padding: 14px;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);

        > span,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 20px;
          color: var(--el-color-primary);
          white-space: nowrap;

          &.is-risk {
            color: var(--el-color-danger);
          }
        }

        small {
          font-size: 11px;
          color: var(--el-text-color-placeholder);
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
        small,
        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        > div > span,
        small {
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }

        strong {
          font-size: 17px;
        }

        &.is-warning strong {
          color: var(--el-color-warning-dark-2);
        }

        &.is-danger strong {
          color: var(--el-color-danger);
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

      &.is-total,
      &.is-statement {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-linked,
      &.is-attachment {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-unlinked {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-duplicate {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
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

        .invoice-auditor__signal-title > span {
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

    &__empty {
      display: flex;
      gap: 13px;
      align-items: center;
      padding: 18px;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 42px;
        height: 42px;
        font-size: 22px;
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
        border-radius: var(--el-border-radius-base);
      }

      > div {
        display: grid;
        gap: 4px;
      }

      p {
        margin: 0;
        color: var(--el-text-color-secondary);
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
    .invoice-auditor {
      gap: 20px;

      &__hero-header {
        display: grid;
      }

      &__score-grid,
      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 480px) {
    .invoice-auditor {
      &__drawer-title small,
      &__eyebrow {
        display: none;
      }

      &__hero,
      &__signal {
        padding: 14px;
      }

      &__identity,
      &__signal > header {
        align-items: flex-start;
      }
    }
  }
</style>
