<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="state.loading"
      loading-mode="skeleton"
      :skeleton-rows="9"
      :error="state.error"
      error-title="车辆健康研判失败"
      min-height="520px"
      @retry="loadAssessment"
    >
      <div v-if="state.data" class="vehicle-health-advisor">
        <section class="vehicle-health-advisor__hero art-card-xs">
          <div class="vehicle-health-advisor__identity">
            <span class="vehicle-health-advisor__icon"
              ><ArtSvgIcon icon="ri:car-washing-line"
            /></span>
            <div>
              <span class="vehicle-health-advisor__eyebrow"><i />AI FLEET HEALTH</span>
              <div class="vehicle-health-advisor__title-row">
                <strong>{{ assessment.plateNo }}</strong>
                <ElTag :type="riskTagType" effect="dark">{{ riskLabel }}</ElTag>
              </div>
              <p
                >{{ assessment.vehicleType }} ·
                {{ assessment.operationStatus || '运营状态未记录' }}</p
              >
            </div>
          </div>
          <ElButton type="primary" plain :loading="state.loading" @click="loadAssessment">
            <ArtSvgIcon icon="ri:refresh-line" />重新研判
          </ElButton>
          <div class="vehicle-health-advisor__scores">
            <article>
              <span>车辆健康分</span><strong :class="scoreTone">{{ assessment.healthScore }}</strong
              ><small>满分 100</small>
            </article>
            <article>
              <span>风险评分</span><strong>{{ assessment.riskScore }}</strong
              ><small>{{ assessment.signals.length }} 项信号</small>
            </article>
            <article>
              <span>研判置信度</span><strong>{{ Math.round(assessment.confidence * 100) }}%</strong
              ><small>基于台账完整度</small>
            </article>
          </div>
          <p class="vehicle-health-advisor__summary">{{ assessment.summary }}</p>
        </section>

        <section class="vehicle-health-advisor__section">
          <ArtSectionTitle>关键健康指标</ArtSectionTitle>
          <div class="vehicle-health-advisor__metrics">
            <article v-for="metric in metricItems" :key="metric.label" class="art-card-xs">
              <span>{{ metric.label }}</span
              ><strong>{{ metric.value }}</strong
              ><small>{{ metric.hint }}</small>
            </article>
          </div>
        </section>

        <section class="vehicle-health-advisor__section">
          <ArtSectionTitle>风险证据</ArtSectionTitle>
          <div v-if="assessment.signals.length" class="vehicle-health-advisor__signals">
            <article
              v-for="signal in assessment.signals"
              :key="signal.type"
              class="vehicle-health-advisor__signal art-card-xs"
            >
              <header>
                <div>
                  <span class="vehicle-health-advisor__signal-icon"
                    ><ArtSvgIcon :icon="signalIcon(signal.severity)"
                  /></span>
                  <div
                    ><strong>{{ signal.title }}</strong
                    ><small>{{ signal.detail }}</small></div
                  >
                </div>
                <ElTag :type="severityTagType(signal.severity)" effect="light">{{
                  severityLabel(signal.severity)
                }}</ElTag>
              </header>
              <ul
                ><li v-for="item in signal.evidence" :key="item">{{ item }}</li></ul
              >
            </article>
          </div>
          <ArtEmptyState
            v-else
            title="当前未发现明确的车辆健康风险"
            :visual-size="72"
            size="compact"
          />
        </section>

        <section class="vehicle-health-advisor__section">
          <ArtSectionTitle>建议处理顺序</ArtSectionTitle>
          <ol class="vehicle-health-advisor__actions art-card-xs">
            <li v-for="(action, index) in assessment.recommendedActions" :key="action">
              <span>{{ index + 1 }}</span
              ><p>{{ action }}</p>
            </li>
          </ol>
        </section>

        <section class="vehicle-health-advisor__section">
          <ArtSectionTitle>数据边界</ArtSectionTitle>
          <div class="vehicle-health-advisor__limitations">
            <ElAlert
              v-for="item in assessment.limitations"
              :key="item"
              :title="item"
              type="info"
              show-icon
              :closable="false"
            />
          </div>
        </section>

        <ArtAiFeedback :run-id="state.data.runId" context-label="AI 车辆健康研判" />
        <footer class="vehicle-health-advisor__meta">
          <span>规则版本：{{ state.data.ruleVersion }}</span>
          <span>生成时间：{{ formatTime(state.data.generatedAt) }}</span>
          <span>只提供建议，不会自动改变车辆或维保状态。</span>
        </footer>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import type { UnwrapNestedRefs } from 'vue'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import { analyzeVehicleHealthByAi } from '@/api/vms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'VehicleHealthAdvisorDrawer' })

  type AdvisorResponse = Api.Vms.VehicleManage.VehicleHealthAdvisorResponse
  type Assessment = Api.Vms.VehicleManage.VehicleHealthAssessment
  type RiskLevel = Api.Vms.VehicleManage.VehicleHealthRiskLevel
  type Severity = Api.Vms.VehicleManage.VehicleHealthSeverity

  interface DrawerOpenData {
    vehicleId: string
    plateNo: string
  }
  interface AdvisorState {
    data: AdvisorResponse | null
    error: string
    loading: boolean
    openData: DrawerOpenData | null
  }
  interface MetricItem {
    label: string
    value: string
    hint: string
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
  const riskTagTypeMap = {
    critical: 'danger',
    high: 'danger',
    medium: 'warning',
    low: 'success'
  } as const

  const assessment = computed<Assessment>(() => state.data!.assessment)
  const riskLabel = computed(() => riskLabelMap[assessment.value.riskLevel])
  const riskTagType = computed(() => riskTagTypeMap[assessment.value.riskLevel])
  const scoreTone = computed(() => ({
    'is-danger': assessment.value.healthScore < 40,
    'is-warning': assessment.value.healthScore >= 40 && assessment.value.healthScore < 70,
    'is-success': assessment.value.healthScore >= 70
  }))
  const metricItems = computed<MetricItem[]>(() => {
    const metrics = assessment.value.metrics
    return [
      {
        label: '当前里程',
        value:
          metrics.currentMileage === null ? '--' : `${metrics.currentMileage.toLocaleString()} km`,
        hint: metrics.currentMileage === null ? '需要补录里程' : '最近一条里程台账'
      },
      {
        label: '保险剩余',
        value: formatRemainingDays(metrics.insuranceDaysRemaining),
        hint: '取较早到期项'
      },
      {
        label: '年检剩余',
        value: formatRemainingDays(metrics.inspectionDaysRemaining),
        hint: '按最近到期日计算'
      },
      {
        label: '距上次维保',
        value: metrics.daysSinceMaintenance === null ? '--' : `${metrics.daysSinceMaintenance} 天`,
        hint: metrics.daysSinceMaintenance === null ? '暂无维保基线' : '周期基线 180 天'
      },
      { label: '近 90 天维修', value: `${metrics.repairCount90Days} 次`, hint: '用于识别重复故障' },
      {
        label: '安全待闭环',
        value: `${metrics.unresolvedAccidentCount + metrics.failedRoutineInspectionCount} 项`,
        hint: '事故与不合格例检'
      },
      { label: '部件到期', value: `${metrics.duePartCount} 个`, hint: '达到里程或年限基线' }
    ]
  })

  async function handleOpen(data: DrawerOpenData): Promise<void> {
    Object.assign(state, { data: null, error: '', loading: false, openData: data })
    await drawerRef.value?.handleOpen(data, {
      title: `AI 车辆健康研判 · ${data.plateNo}`,
      size: 'lg',
      contentHeight: 'calc(100vh - 132px)',
      showFooter: false,
      onOpen: loadAssessment,
      onReset: () =>
        Object.assign(state, { data: null, error: '', loading: false, openData: null }),
      drawerProps: { appendToBody: true, closeOnClickModal: false, resizable: true }
    })
  }

  async function loadAssessment(): Promise<void> {
    const vehicleId = state.openData?.vehicleId
    if (!vehicleId || state.loading) return
    state.loading = true
    state.error = ''
    try {
      const { data, error } = await analyzeVehicleHealthByAi(vehicleId)
      if (error) throw error
      if (!data) throw new Error('车辆健康研判服务未返回结果')
      state.data = data
    } catch (error) {
      state.data = null
      state.error = getFriendlySupabaseErrorMessage(error, 'AI 车辆健康研判失败，请稍后重试')
    } finally {
      state.loading = false
    }
  }

  function formatRemainingDays(value: number | null): string {
    if (value === null) return '--'
    return value < 0 ? `逾期 ${Math.abs(value)} 天` : `${value} 天`
  }
  function severityLabel(severity: Severity): string {
    return severity === 'critical' ? '严重' : severity === 'high' ? '高风险' : '中风险'
  }
  function severityTagType(severity: Severity): 'danger' | 'warning' {
    return severity === 'medium' ? 'warning' : 'danger'
  }
  function signalIcon(severity: Severity): string {
    return severity === 'critical' ? 'ri:alarm-warning-line' : 'ri:error-warning-line'
  }
  function formatTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') || '-'
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .vehicle-health-advisor {
    display: grid;
    gap: var(--art-space-5);
    min-width: 0;

    &__hero {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 16px;
      padding: 20px;
      overflow: hidden;
      background:
        radial-gradient(circle at 94% 4%, var(--el-color-primary-light-9), transparent 38%),
        var(--el-bg-color);
    }

    &__identity {
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
      flex: 0 0 46px;
      place-items: center;
      width: 46px;
      height: 46px;
      font-size: 24px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-8);
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
      letter-spacing: 0.12em;

      i {
        width: 16px;
        height: 2px;
        background: var(--el-color-primary);
        border-radius: 999px;
      }
    }

    &__title-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;

      strong {
        font-size: 19px;
      }
    }

    &__scores {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      grid-column: 1 / -1;
      gap: 12px;

      article {
        display: grid;
        gap: 5px;
        min-width: 0;
        padding: 14px 16px;
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      span,
      small {
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 24px;
        color: var(--el-color-primary);

        &.is-danger {
          color: var(--el-color-danger);
        }

        &.is-warning {
          color: var(--el-color-warning);
        }

        &.is-success {
          color: var(--el-color-success);
        }
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        white-space: nowrap;
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
      min-width: 0;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;

      article {
        display: grid;
        gap: 7px;
        min-width: 0;
        padding: 14px;
      }

      span,
      small,
      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      span,
      small {
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 18px;
        color: var(--el-text-color-primary);
      }

      small {
        font-size: 11px;
      }
    }

    &__signals,
    &__limitations {
      display: grid;
      gap: 10px;
    }

    &__signal {
      display: grid;
      gap: 12px;
      padding: 16px;

      header,
      header > div {
        display: flex;
        gap: 10px;
        align-items: flex-start;
        min-width: 0;
      }

      header {
        justify-content: space-between;

        > div > div {
          display: grid;
          gap: 5px;
          min-width: 0;
        }

        small {
          line-height: 1.55;
          color: var(--el-text-color-secondary);
          overflow-wrap: anywhere;
        }
      }

      ul {
        display: grid;
        gap: 6px;
        padding: 10px 12px 10px 32px;
        margin: 0;
        font-size: 12px;
        line-height: 1.55;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-small);
      }
    }

    &__signal-icon {
      display: grid;
      flex: 0 0 32px;
      place-items: center;
      width: 32px;
      height: 32px;
      color: var(--el-color-warning);
      background: var(--el-color-warning-light-9);
      border-radius: var(--el-border-radius-base);
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
        flex: 0 0 24px;
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
      padding-bottom: 4px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  @media (width <= 900px) {
    .vehicle-health-advisor__metrics {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (width <= 640px) {
    .vehicle-health-advisor {
      &__hero {
        grid-template-columns: 1fr;
      }

      &__scores,
      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
