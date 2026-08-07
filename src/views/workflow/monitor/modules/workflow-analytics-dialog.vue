<template>
  <ArtDialog ref="dialogRef" size="xl">
    <div class="workflow-analytics">
      <section class="workflow-analytics__toolbar">
        <div>
          <strong>统计周期</strong>
          <ElSegmented v-model="state.days" :options="periodOptions" @change="loadData" />
        </div>
        <ElButton type="primary" plain :disabled="!state.data" @click="exportCsv">
          <ArtSvgIcon icon="ri:download-2-line" />导出业务汇总
        </ElButton>
      </section>

      <ArtAsyncState
        v-if="state.loading || state.error"
        :loading="state.loading"
        loading-mode="skeleton"
        :skeleton-rows="5"
        :error="state.error"
        error-title="审批运营分析加载失败"
        :min-height="280"
        @retry="loadData"
      />

      <template v-else-if="state.data">
        <section class="workflow-analytics__metrics">
          <article v-for="metric in metrics" :key="metric.label" class="art-card-xs">
            <small>{{ metric.label }}</small>
            <strong>{{ metric.value }}</strong>
            <span>{{ metric.hint }}</span>
          </article>
        </section>

        <section class="workflow-analytics__trend art-card-xs">
          <div class="workflow-analytics__heading">
            <div>
              <ArtSectionTitle :show-line="false">近 14 日发起趋势</ArtSectionTitle>
              <p>柱高按当前区间最大日发起量归一化，仅用于快速识别峰值。</p>
            </div>
            <span>生成于 {{ formatDate(state.data.generatedAt) }}</span>
          </div>
          <div class="workflow-analytics__bars" aria-label="审批每日发起趋势">
            <article v-for="item in recentDaily" :key="item.date">
              <div>
                <span
                  :style="{ height: `${Math.max(6, (item.startedCount / dailyMax) * 100)}%` }"
                  :title="`${item.date}：发起 ${item.startedCount}`"
                />
              </div>
              <strong>{{ item.startedCount }}</strong>
              <small>{{ dayjs(item.date).format('MM-DD') }}</small>
            </article>
          </div>
        </section>

        <section class="workflow-analytics__business art-card-xs">
          <div class="workflow-analytics__heading">
            <div>
              <ArtSectionTitle :show-line="false">按业务类型分析</ArtSectionTitle>
              <p>通过率只计算已有明确通过/驳回结论的实例。</p>
            </div>
            <ElTag effect="plain" round>{{ state.data.businessTypes.length }} 类业务</ElTag>
          </div>

          <ArtEmptyState
            v-if="!state.data.businessTypes.length"
            title="当前周期暂无审批数据"
            description="调整统计周期后可重新查看。"
            icon="ri:bar-chart-box-line"
          />
          <div v-else class="workflow-analytics__business-list">
            <article v-for="item in state.data.businessTypes" :key="item.businessType">
              <div class="workflow-analytics__business-name">
                <ArtDictDisplay
                  dict-code="workflowBusinessType"
                  :value="item.businessType"
                  display="text"
                />
                <small>{{ item.businessType }}</small>
              </div>
              <div
                ><small>实例数</small><strong>{{ item.totalCount }}</strong></div
              >
              <div
                ><small>通过率</small><strong>{{ item.approvalRate }}%</strong></div
              >
              <div
                ><small>平均耗时</small><strong>{{ item.averageDurationHours }}h</strong></div
              >
              <div>
                <small>超时</small>
                <strong :class="{ 'is-danger': item.overdueCount > 0 }">{{
                  item.overdueCount
                }}</strong>
              </div>
            </article>
          </div>
        </section>
      </template>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { ElMessage } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import { fetchWorkflowOperationalAnalytics } from '@/api/workflow'

  defineOptions({ name: 'WorkflowAnalyticsDialog' })

  const dialogRef = ref<ArtDialogExpose>()
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
    data: Api.Workflow.WorkflowOperationalAnalytics | null
  }>({ days: 30, loading: false, error: null, data: null })

  const metrics = computed(() => {
    const summary = state.data?.summary
    return [
      {
        label: '审批实例',
        value: summary?.totalCount ?? 0,
        hint: `${state.days} 天内发起`
      },
      {
        label: '当前运行',
        value: summary?.runningCount ?? 0,
        hint: '尚未形成最终结论'
      },
      {
        label: '已通过',
        value: summary?.approvedCount ?? 0,
        hint: '已完成业务回写'
      },
      {
        label: '超时实例',
        value: summary?.overdueCount ?? 0,
        hint: '存在逾期待办'
      },
      {
        label: '平均耗时',
        value: `${summary?.averageDurationHours ?? 0}h`,
        hint: '仅统计已结束实例'
      }
    ]
  })
  const recentDaily = computed(() => state.data?.daily.slice(-14) ?? [])
  const dailyMax = computed(() =>
    Math.max(1, ...recentDaily.value.map((item) => item.startedCount))
  )

  const formatDate = (value: string) => dayjs(value).format('YYYY-MM-DD HH:mm')

  async function loadData(): Promise<void> {
    state.loading = true
    state.error = null
    try {
      state.data = await fetchWorkflowOperationalAnalytics(state.days)
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('审批运营分析加载失败')
    } finally {
      state.loading = false
    }
  }

  function escapeCsv(value: unknown): string {
    return `"${String(value ?? '').replaceAll('"', '""')}"`
  }

  function exportCsv(): void {
    if (!state.data) return
    const header = [
      '业务类型',
      '实例数',
      '运行中',
      '已通过',
      '已驳回',
      '已中断',
      '超时',
      '通过率(%)',
      '平均耗时(小时)'
    ]
    const rows = state.data.businessTypes.map((item) => [
      item.businessType,
      item.totalCount,
      item.runningCount,
      item.approvedCount,
      item.rejectedCount,
      item.interruptedCount,
      item.overdueCount,
      item.approvalRate,
      item.averageDurationHours
    ])
    const csv = [header, ...rows].map((row) => row.map(escapeCsv).join(',')).join('\r\n')
    const url = URL.createObjectURL(new Blob(['\ufeff', csv], { type: 'text/csv;charset=utf-8' }))
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `审批运营汇总_${state.days}天_${dayjs().format('YYYYMMDD_HHmm')}.csv`
    anchor.click()
    URL.revokeObjectURL(url)
    ElMessage.success('审批运营汇总已导出')
  }

  async function handleOpen(): Promise<void> {
    await dialogRef.value?.handleOpen(undefined, {
      title: '审批运营分析',
      subtitle: '按租户权限统计审批量、通过率、耗时与超时风险。',
      contentMaxHeight: '78vh',
      showFooter: false,
      onOpen: loadData
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-analytics {
    display: grid;
    gap: 14px;
    min-width: 0;

    &__toolbar,
    &__heading {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
    }

    &__toolbar,
    &__metrics,
    &__trend,
    &__business {
      width: 100%;
      min-width: 0;
    }

    &__toolbar {
      padding: 12px 14px;
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-base);

      > div {
        display: flex;
        gap: 10px;
        align-items: center;
      }

      strong {
        font-size: 13px;
        color: var(--art-gray-700);
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 10px;

      article {
        display: grid;
        gap: 4px;
        padding: 13px;
      }

      small,
      span {
        font-size: 11px;
        color: var(--art-gray-500);
      }

      strong {
        font-size: 23px;
        line-height: 1.15;
        color: var(--art-gray-900);
      }
    }

    &__trend,
    &__business {
      padding: 15px;
    }

    &__heading {
      align-items: flex-start;
      margin-bottom: 14px;

      > div {
        display: grid;
        gap: 3px;
      }

      p,
      > span {
        margin: 0;
        font-size: 11px;
        color: var(--art-gray-500);
      }
    }

    &__bars {
      display: grid;
      grid-template-columns: repeat(14, minmax(24px, 1fr));
      gap: 7px;
      min-width: 0;
      overflow-x: auto;

      article {
        display: grid;
        grid-template-rows: 100px auto auto;
        gap: 4px;
        min-width: 24px;
        text-align: center;
      }

      article > div {
        display: flex;
        align-items: flex-end;
        justify-content: center;
        border-bottom: 1px solid var(--art-gray-200);
      }

      article > div span {
        width: min(20px, 70%);
        min-height: 6px;
        background: linear-gradient(
          180deg,
          var(--el-color-primary),
          var(--el-color-primary-light-5)
        );
        border-radius: 5px 5px 0 0;
      }

      strong {
        font-size: 11px;
        color: var(--art-gray-800);
      }

      small {
        font-size: 9px;
        color: var(--art-gray-500);
      }
    }

    &__business-list {
      display: grid;
      gap: 7px;
    }

    &__business-list article {
      display: grid;
      grid-template-columns: minmax(180px, 1.6fr) repeat(4, minmax(76px, 0.7fr));
      gap: 12px;
      align-items: center;
      padding: 11px 12px;
      background: var(--art-gray-50);
      border-radius: var(--el-border-radius-base);

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      small {
        font-size: 10px;
        color: var(--art-gray-500);
      }

      strong {
        font-size: 13px;
        color: var(--art-gray-800);
      }

      strong.is-danger {
        color: var(--el-color-danger);
      }
    }

    &__business-name {
      :deep(.art-dict-display) {
        font-weight: 600;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }
  }

  @media only screen and (width <= 900px) {
    .workflow-analytics {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__business-list article {
        grid-template-columns: minmax(160px, 1.4fr) repeat(4, minmax(70px, 0.7fr));
        overflow-x: auto;
      }
    }
  }

  @media only screen and (width <= 620px) {
    .workflow-analytics {
      &__toolbar {
        align-items: stretch;
      }

      &__toolbar,
      &__toolbar > div {
        flex-direction: column;
        width: 100%;
        min-width: 0;
      }

      &__toolbar :deep(.el-segmented) {
        width: 100%;
      }

      &__metrics {
        grid-template-columns: 1fr;
      }

      &__business-list article {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__business-name {
        grid-column: 1 / -1;
      }
    }
  }
</style>
