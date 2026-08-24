<template>
  <div v-auth="'WorkflowAnalytics:View'" class="workflow-analytics-page business-workspace-page">
    <BusinessWorkspaceHeader
      eyebrow="APPROVAL PERFORMANCE"
      title="审批效能"
      description="从业务结果、节点 SLA 与审批负载三个维度识别流程瓶颈，辅助优化规则和人员安排。"
      icon="ri:bar-chart-grouped-line"
      :tags="[
        { label: `${state.days} 天统计周期`, type: 'primary' },
        { label: '样本约束', type: 'info' },
        { label: '租户安全', type: 'success' }
      ]"
      :metrics="metrics"
      refreshable
      refresh-label="刷新审批效能"
      :refresh-loading="state.loading"
      @refresh="loadData"
    >
      <template #actions>
        <ElSegmented v-model="state.days" :options="periodOptions" @change="loadData" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtAsyncState
      v-if="state.loading || state.error"
      :loading="state.loading"
      loading-mode="skeleton"
      :skeleton-rows="7"
      :error="state.error"
      error-title="审批效能加载失败"
      :min-height="420"
      @retry="loadData"
    />

    <template v-else-if="state.operational && state.bottleneck">
      <section class="workflow-analytics-page__decision-strip art-card-xs">
        <div>
          <span :class="decisionTone.className"><ArtSvgIcon :icon="decisionTone.icon" /></span>
          <div>
            <strong>{{ decisionTone.title }}</strong>
            <p>{{ decisionTone.description }}</p>
          </div>
        </div>
        <ElTag :type="decisionTone.tagType" effect="plain" round>
          {{ attentionNodeCount }} 个节点需关注
        </ElTag>
      </section>

      <div class="workflow-analytics-page__grid">
        <section class="workflow-analytics-page__trend art-card-xs">
          <header>
            <div>
              <ArtSectionTitle :show-line="false">近 14 日发起趋势</ArtSectionTitle>
              <p>用于识别审批流量峰值和周期性容量压力。</p>
            </div>
            <span>共 {{ recentTotal }} 个实例</span>
          </header>
          <ArtEmptyState
            v-if="!recentDaily.length"
            title="当前周期暂无发起数据"
            description="有流程发起后会形成每日趋势。"
            icon="ri:bar-chart-line"
          />
          <ElScrollbar v-else class="workflow-analytics-page__bars-scroll">
            <div class="workflow-analytics-page__bars" aria-label="近 14 日审批发起趋势">
              <article v-for="item in recentDaily" :key="item.date">
                <div>
                  <i
                    :style="{ height: `${Math.max(6, (item.startedCount / dailyMax) * 100)}%` }"
                    :title="`${item.date} 发起 ${item.startedCount} 个流程`"
                  />
                </div>
                <strong>{{ item.startedCount }}</strong>
                <small>{{ dayjs(item.date).format('MM-DD') }}</small>
              </article>
            </div>
          </ElScrollbar>
        </section>

        <section class="workflow-analytics-page__business art-card-xs">
          <header>
            <div>
              <ArtSectionTitle :show-line="false">业务审批表现</ArtSectionTitle>
              <p>通过率仅统计已形成通过或驳回结论的实例。</p>
            </div>
            <ElTag effect="plain" round>{{ state.operational.businessTypes.length }} 类业务</ElTag>
          </header>
          <ArtEmptyState
            v-if="!state.operational.businessTypes.length"
            title="暂无业务审批数据"
            description="调整统计周期后可重新查看。"
            icon="ri:pie-chart-line"
          />
          <ElScrollbar v-else max-height="302px">
            <div class="workflow-analytics-page__business-list">
              <article v-for="item in state.operational.businessTypes" :key="item.businessType">
                <div>
                  <ArtDictDisplay
                    dict-code="workflowBusinessType"
                    :value="item.businessType"
                    display="text"
                  />
                  <small>{{ item.totalCount }} 个实例</small>
                </div>
                <p
                  ><span>通过率</span><strong>{{ item.approvalRate }}%</strong></p
                >
                <p
                  ><span>平均耗时</span><strong>{{ item.averageDurationHours }}h</strong></p
                >
                <p :class="{ 'is-danger': item.overdueCount > 0 }">
                  <span>超时</span><strong>{{ item.overdueCount }}</strong>
                </p>
              </article>
            </div>
          </ElScrollbar>
        </section>
      </div>

      <section class="workflow-analytics-page__bottleneck art-card-xs">
        <header>
          <div>
            <ArtSectionTitle :show-line="false">节点瓶颈</ArtSectionTitle>
            <p>
              按风险等级、逾期待办和 P90 处理耗时排序；样本少于
              {{ state.bottleneck.minimumSampleSize }} 条仅展示，不直接形成绩效结论。
            </p>
          </div>
          <ElTag effect="plain" round>SLA {{ bottleneckSummary.slaComplianceRate }}%</ElTag>
        </header>
        <ArtEmptyState
          v-if="!state.bottleneck.nodes.length"
          title="暂无节点运行样本"
          description="流程运行后会形成节点级治理依据。"
          icon="ri:flow-chart"
        />
        <ElScrollbar v-else class="workflow-analytics-page__node-scroll">
          <div class="workflow-analytics-page__node-list">
            <article
              v-for="item in state.bottleneck.nodes"
              :key="`${item.definitionId}:${item.nodeKey}`"
            >
              <div class="workflow-analytics-page__node-main">
                <div>
                  <ElTag :type="riskMeta[item.riskLevel].type" effect="light" size="small">
                    {{ riskMeta[item.riskLevel].label }}
                  </ElTag>
                  <strong>{{ item.nodeName }}</strong>
                </div>
                <span>{{ item.definitionName }}</span>
                <small v-if="item.slaMeasuredCount < state.bottleneck.minimumSampleSize">
                  样本 {{ item.slaMeasuredCount }} 条，暂不评级
                </small>
              </div>
              <p
                ><span>待办</span><strong>{{ item.pendingCount }}</strong></p
              >
              <p :class="{ 'is-danger': item.overduePendingCount > 0 }">
                <span>逾期</span><strong>{{ item.overduePendingCount }}</strong>
              </p>
              <p
                ><span>SLA</span><strong>{{ item.slaComplianceRate }}%</strong></p
              >
              <p
                ><span>P90</span><strong>{{ item.p90HandleHours }}h</strong></p
              >
            </article>
          </div>
        </ElScrollbar>
      </section>

      <section class="workflow-analytics-page__workload art-card-xs">
        <header>
          <div>
            <ArtSectionTitle :show-line="false">审批负载</ArtSectionTitle>
            <p>结合当前待办、已处理量、委托和转交情况识别人员承载压力。</p>
          </div>
          <ElTag effect="plain" round>{{ state.bottleneck.approvers.length }} 位审批人</ElTag>
        </header>
        <ArtEmptyState
          v-if="!state.bottleneck.approvers.length"
          title="暂无审批人负载数据"
          description="产生审批任务后会展示租户范围内的负载分布。"
          icon="ri:team-line"
        />
        <div v-else class="workflow-analytics-page__approvers">
          <article
            v-for="item in state.bottleneck.approvers.slice(0, 8)"
            :key="item.assigneeUserId"
          >
            <span>{{ getInitial(item.assigneeName) }}</span>
            <div>
              <strong>{{ item.assigneeName || '未命名审批人' }}</strong>
              <small>待办 {{ item.pendingCount }} · 已处理 {{ item.handledCount }}</small>
            </div>
            <ElTag :type="riskMeta[item.riskLevel].type" effect="plain" size="small">
              SLA {{ item.slaComplianceRate }}%
            </ElTag>
          </article>
        </div>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { TagProps } from 'element-plus'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { createFriendlySupabaseError } from '@/utils/supabase'
  import {
    fetchWorkflowBottleneckAnalytics,
    fetchWorkflowOperationalAnalytics
  } from '@/api/workflow'

  defineOptions({ name: 'WorkflowAnalytics' })

  const periodOptions = [
    { label: '7 天', value: 7 },
    { label: '30 天', value: 30 },
    { label: '90 天', value: 90 },
    { label: '180 天', value: 180 }
  ]
  const state = reactive<{
    days: number
    loading: boolean
    error: Error | null
    operational: Api.Workflow.WorkflowOperationalAnalytics | null
    bottleneck: Api.Workflow.WorkflowBottleneckAnalytics | null
  }>({
    days: 30,
    loading: false,
    error: null,
    operational: null,
    bottleneck: null
  })

  const riskMeta: Record<
    Api.Workflow.WorkflowAnalyticsRiskLevel,
    { label: string; type: TagProps['type'] }
  > = {
    normal: { label: '运行平稳', type: 'success' },
    warning: { label: '建议关注', type: 'warning' },
    critical: { label: '优先治理', type: 'danger' }
  }

  const bottleneckSummary = computed(() =>
    state.bottleneck
      ? state.bottleneck.summary
      : {
          slaComplianceRate: 100,
          slaMeasuredCount: 0,
          p90HandleHours: 0,
          pendingCount: 0,
          overduePendingCount: 0,
          delegatedCount: 0,
          transferredCount: 0
        }
  )
  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const summary = state.operational?.summary
    return [
      {
        label: '审批实例',
        value: summary?.totalCount ?? 0,
        description: `${state.days} 天内发起`,
        icon: 'ri:file-list-3-line',
        tone: 'primary',
        loading: state.loading
      },
      {
        label: 'SLA 达标率',
        value: `${bottleneckSummary.value.slaComplianceRate}%`,
        description: `${bottleneckSummary.value.slaMeasuredCount} 条纳入 SLA`,
        icon: 'ri:timer-flash-line',
        tone: bottleneckSummary.value.slaComplianceRate < 90 ? 'warning' : 'success',
        loading: state.loading
      },
      {
        label: '逾期待办',
        value: bottleneckSummary.value.overduePendingCount,
        description: `${bottleneckSummary.value.pendingCount} 条当前待办`,
        icon: 'ri:alarm-warning-line',
        tone: bottleneckSummary.value.overduePendingCount ? 'danger' : 'success',
        loading: state.loading
      },
      {
        label: 'P90 处理耗时',
        value: `${bottleneckSummary.value.p90HandleHours}h`,
        description: '90% 已处理任务不超过该值',
        icon: 'ri:speed-up-line',
        tone: 'info',
        loading: state.loading
      }
    ]
  })
  const attentionNodeCount = computed(
    () => state.bottleneck?.nodes.filter((item) => item.riskLevel !== 'normal').length ?? 0
  )
  const recentDaily = computed(() => state.operational?.daily.slice(-14) ?? [])
  const recentTotal = computed(() =>
    recentDaily.value.reduce((sum, item) => sum + item.startedCount, 0)
  )
  const dailyMax = computed(() =>
    Math.max(1, ...recentDaily.value.map((item) => item.startedCount))
  )
  const decisionTone = computed<{
    className: string
    icon: string
    title: string
    description: string
    tagType: TagProps['type']
  }>(() => {
    if (bottleneckSummary.value.overduePendingCount > 0 || attentionNodeCount.value > 0) {
      return {
        className: 'is-warning',
        icon: 'ri:alert-line',
        title: '审批容量存在可治理项',
        description: '优先处理逾期待办和高风险节点，再结合审批负载调整 SLA 或人员安排。',
        tagType: 'warning'
      }
    }
    return {
      className: 'is-success',
      icon: 'ri:shield-check-line',
      title: '审批运行整体平稳',
      description: '当前未识别到明显瓶颈，可继续观察业务峰值和流程样本变化。',
      tagType: 'success'
    }
  })

  const getInitial = (name?: string | null): string =>
    name?.trim().slice(0, 1).toUpperCase() || '审'

  async function loadData(): Promise<void> {
    state.loading = true
    state.error = null
    try {
      const [operational, bottleneck] = await Promise.all([
        fetchWorkflowOperationalAnalytics(state.days),
        fetchWorkflowBottleneckAnalytics(state.days)
      ])
      state.operational = operational
      state.bottleneck = bottleneck
    } catch (error) {
      state.error = createFriendlySupabaseError(error, '审批效能加载失败，请稍后重试')
    } finally {
      state.loading = false
    }
  }

  onMounted(() => void loadData())
</script>

<style scoped lang="scss">
  .workflow-analytics-page {
    gap: 12px;
    min-width: 0;

    &__decision-strip,
    &__trend,
    &__business,
    &__bottleneck,
    &__workload {
      min-width: 0;
      padding: 16px;
    }

    &__decision-strip {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;

      > div {
        display: flex;
        gap: 12px;
        align-items: center;
        min-width: 0;

        > span {
          display: grid;
          flex: 0 0 38px;
          place-items: center;
          width: 38px;
          height: 38px;
          border-radius: var(--el-border-radius-base);

          &.is-warning {
            color: var(--el-color-warning-dark-2);
            background: var(--el-color-warning-light-9);
          }

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }
        }
      }

      strong {
        color: var(--art-gray-900);
      }

      p {
        margin: 3px 0 0;
        font-size: 12px;
        color: var(--art-gray-600);
      }
    }

    &__grid {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(380px, 0.9fr);
      gap: 12px;
      min-width: 0;
    }

    header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 14px;

      p,
      > span {
        margin: 3px 0 0;
        font-size: 11px;
        color: var(--art-gray-500);
      }
    }

    &__bars {
      display: grid;
      grid-template-columns: repeat(14, minmax(26px, 1fr));
      gap: 7px;
      min-width: 0;
      overflow: hidden;

      article {
        display: grid;
        grid-template-rows: 116px auto auto;
        gap: 3px;
        min-width: 0;
        text-align: center;

        > div {
          display: flex;
          align-items: flex-end;
          justify-content: center;
          border-bottom: 1px solid var(--art-gray-200);
        }

        i {
          width: min(20px, 72%);
          min-height: 4px;
          background: var(--theme-color);
          border-radius: var(--el-border-radius-small) var(--el-border-radius-small) 0 0;
        }

        strong {
          font-size: 12px;
          color: var(--art-gray-800);
        }

        small {
          font-size: 10px;
          color: var(--art-gray-500);
        }
      }
    }

    &__bars-scroll {
      width: 100%;
    }

    &__business-list,
    &__node-list {
      display: grid;
      gap: 8px;
      padding-right: 8px;

      article {
        display: grid;
        gap: 10px;
        align-items: center;
        padding: 10px 12px;
        background: var(--art-gray-50);
        border-radius: var(--el-border-radius-base);

        p {
          display: grid;
          gap: 2px;
          margin: 0;

          span,
          small {
            font-size: 10px;
            color: var(--art-gray-500);
          }

          strong {
            font-size: 12px;
            color: var(--art-gray-800);
          }

          &.is-danger strong {
            color: var(--el-color-danger);
          }
        }
      }
    }

    &__business-list article {
      grid-template-columns: minmax(150px, 1.4fr) repeat(3, minmax(62px, 0.7fr));

      > div:first-child {
        display: grid;
        gap: 3px;

        small {
          color: var(--art-gray-500);
        }
      }
    }

    &__node-scroll {
      height: min(290px, 32vh);
    }

    &__node-list article {
      grid-template-columns: minmax(230px, 1.6fr) repeat(4, minmax(70px, 0.6fr));
    }

    &__node-main {
      display: grid;
      gap: 3px;
      min-width: 0;

      > div {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;
      }

      strong,
      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      span,
      small {
        font-size: 11px;
        color: var(--art-gray-500);
      }
    }

    &__approvers {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;

      article {
        display: grid;
        grid-template-columns: 34px minmax(0, 1fr) auto;
        gap: 9px;
        align-items: center;
        min-width: 0;
        padding: 10px;
        background: var(--art-gray-50);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          place-items: center;
          width: 34px;
          height: 34px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;
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

        small {
          color: var(--art-gray-500);
        }
      }
    }

    @media (width <= 1180px) {
      &__grid {
        grid-template-columns: 1fr;
      }

      &__approvers {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 760px) {
      &__decision-strip,
      header {
        flex-direction: column;
        align-items: flex-start;
      }

      &__bars {
        min-width: 520px;
      }

      &__business-list article,
      &__node-list article {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__business-list article > div:first-child,
      &__node-main {
        grid-column: 1 / -1;
      }

      &__approvers {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
