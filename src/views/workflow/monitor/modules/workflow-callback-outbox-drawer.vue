<template>
  <ArtDrawer ref="drawerRef" size="xl" :show-footer="false">
    <div class="workflow-callback-outbox">
      <section class="workflow-callback-outbox__intro art-card-xs">
        <span><ArtSvgIcon icon="ri:inbox-archive-line" /></span>
        <div>
          <strong>业务状态回写保障</strong>
          <p>审批结果先可靠入队，回写失败自动重试；死信需核对业务单据后人工补偿。</p>
        </div>
        <ElTag v-if="!isPlatformSuper" type="info" effect="plain" round>本租户只读</ElTag>
      </section>

      <ElAlert
        v-if="state.error"
        type="error"
        :closable="false"
        show-icon
        title="业务回调队列加载失败"
      >
        <template #default>
          <span>{{ state.error.message }}</span>
          <ElButton link type="primary" @click="loadData">重新加载</ElButton>
        </template>
      </ElAlert>

      <section v-loading="state.loading" class="workflow-callback-outbox__metrics">
        <article v-for="metric in metricCards" :key="metric.key" class="art-card-xs">
          <span :class="`is-${metric.tone}`"><ArtSvgIcon :icon="metric.icon" /></span>
          <div>
            <small>{{ metric.label }}</small>
            <strong>{{ metric.value }}</strong>
          </div>
        </article>
      </section>

      <section class="workflow-callback-outbox__table art-card-xs">
        <header>
          <div>
            <ArtSectionTitle :show-line="false">投递事件</ArtSectionTitle>
            <p>同一审批实例严格按事件顺序回写，失败事件会阻塞后续状态，避免业务状态倒退。</p>
          </div>
          <div class="workflow-callback-outbox__tools">
            <ElSelect
              v-model="state.status"
              placeholder="全部状态"
              clearable
              class="workflow-callback-outbox__status-filter"
              @change="loadData"
            >
              <ElOption
                v-for="option in statusOptions"
                :key="option.value"
                :label="option.label"
                :value="option.value"
              />
            </ElSelect>
            <ElButton :loading="state.loading" @click="loadData">
              <ArtSvgIcon icon="ri:refresh-line" />刷新
            </ElButton>
          </div>
        </header>

        <ArtTable
          :data="state.items"
          :columns="columns"
          :loading="state.loading"
          :pagination="false"
          row-key="id"
          table-layout="fixed"
          height="100%"
          empty-text="当前筛选条件下没有回调事件"
        />
      </section>
    </div>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElMessageBox } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { ColumnOption } from '@/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { formatWithDayjs } from '@/utils/time'
  import { fetchWorkflowCallbackOutbox, retryWorkflowBusinessCallback } from '@/api/workflow'

  defineOptions({ name: 'WorkflowCallbackOutboxDrawer' })

  type CallbackRow = Api.Workflow.WorkflowCallbackRecord
  interface DrawerOpenData {
    focusFailures?: boolean
  }
  interface CallbackState {
    loading: boolean
    error: Error | null
    status: Api.Workflow.WorkflowCallbackStatus | ''
    items: CallbackRow[]
    summary: Api.Workflow.WorkflowCallbackSummary
    retryingId: string
  }

  const emit = defineEmits<{ (event: 'change'): void }>()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const drawerRef = ref<ArtDrawerExpose<DrawerOpenData>>()
  const state = reactive<CallbackState>({
    loading: false,
    error: null,
    status: '',
    items: [],
    summary: { pending: 0, processing: 0, retryWait: 0, succeeded: 0, deadLetter: 0 },
    retryingId: ''
  })

  const statusOptions = computed(() => getDictMap.value.workflowCallbackStatus ?? [])
  const unresolvedCount = computed(
    () => state.summary.pending + state.summary.processing + state.summary.retryWait
  )
  const metricCards = computed(() => [
    {
      key: 'unresolved',
      label: '处理中',
      value: unresolvedCount.value,
      icon: 'ri:loader-4-line',
      tone: unresolvedCount.value ? 'warning' : 'success'
    },
    {
      key: 'retry',
      label: '等待重试',
      value: state.summary.retryWait,
      icon: 'ri:restart-line',
      tone: state.summary.retryWait ? 'warning' : 'info'
    },
    {
      key: 'dead',
      label: '死信事件',
      value: state.summary.deadLetter,
      icon: 'ri:error-warning-line',
      tone: state.summary.deadLetter ? 'danger' : 'success'
    },
    {
      key: 'success',
      label: '已成功',
      value: state.summary.succeeded,
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    }
  ])

  const formatDate = (value?: string | null) => (value ? formatWithDayjs(value) : '--')
  const canRetry = (row: CallbackRow) =>
    isPlatformSuper.value && (row.status === 'retry_wait' || row.status === 'dead_letter')

  const createBusinessCell = (row: CallbackRow) => (
    <div class="workflow-callback-outbox__business-cell">
      <strong>{row.businessTitle}</strong>
      <small>{row.businessId}</small>
    </div>
  )
  const createDeliveryCell = (row: CallbackRow) => (
    <div class="workflow-callback-outbox__delivery-cell">
      <span>
        本轮 {row.attemptCount}/{row.maxAttempts}
      </span>
      <small>
        累计 {row.totalAttempts} 次 · 人工 {row.manualRetryCount} 次
      </small>
    </div>
  )
  const createErrorCell = (row: CallbackRow) => (
    <div class={{ 'workflow-callback-outbox__error-cell': true, 'is-empty': !row.lastError }}>
      <strong>{row.lastErrorCode || (row.status === 'succeeded' ? '投递成功' : '--')}</strong>
      <small title={row.lastError || ''}>{row.lastError || '暂无异常信息'}</small>
    </div>
  )

  const columns: ColumnOption<CallbackRow>[] = [
    {
      prop: 'businessTitle',
      label: '业务单据',
      minWidth: 230,
      fixed: 'left',
      formatter: createBusinessCell
    },
    {
      prop: 'tenantName',
      label: '所属租户',
      minWidth: 135,
      formatter: (row) => row.tenantName || '--'
    },
    {
      prop: 'targetStatus',
      label: '目标状态',
      width: 105,
      formatter: (row) => (
        <ArtDictDisplay dictCode="workflowInstanceStatus" value={row.targetStatus} display="tag" />
      )
    },
    {
      prop: 'status',
      label: '投递状态',
      width: 110,
      formatter: (row) => (
        <ArtDictDisplay dictCode="workflowCallbackStatus" value={row.status} display="tag" />
      )
    },
    { prop: 'attemptCount', label: '投递次数', minWidth: 155, formatter: createDeliveryCell },
    { prop: 'lastError', label: '最近结果', minWidth: 220, formatter: createErrorCell },
    {
      prop: 'nextAttemptAt',
      label: '下次执行',
      width: 165,
      formatter: (row) =>
        row.status === 'succeeded' ? formatDate(row.processedAt) : formatDate(row.nextAttemptAt)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 94,
      fixed: 'right',
      formatter: (row) =>
        !isPlatformSuper.value ? (
          <span class="workflow-callback-outbox__operation-placeholder">只读</span>
        ) : canRetry(row) ? (
          <ArtButtonTable
            type="edit"
            icon="ri:restart-line"
            label="人工补偿"
            loading={state.retryingId === row.id}
            onClick={() => handleRetry(row)}
          />
        ) : (
          <span class="workflow-callback-outbox__operation-placeholder">无需处理</span>
        )
    }
  ]

  async function loadData(): Promise<void> {
    state.loading = true
    state.error = null
    try {
      const result = await fetchWorkflowCallbackOutbox(state.status || null, 100)
      state.items = result.items
      Object.assign(state.summary, result.summary)
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('业务回调队列加载失败')
    } finally {
      state.loading = false
    }
  }

  async function handleRetry(row: CallbackRow): Promise<void> {
    if (!isPlatformSuper.value) return

    try {
      await ElMessageBox.confirm(
        `将立即重新回写“${row.businessTitle}”的审批状态。请先确认业务单据仍允许变更。`,
        '确认人工补偿',
        {
          type: 'warning',
          confirmButtonText: '确认重试',
          cancelButtonText: '暂不处理'
        }
      )
    } catch {
      return
    }
    state.retryingId = row.id
    try {
      await retryWorkflowBusinessCallback(row.id)
      await loadData()
      emit('change')
    } finally {
      state.retryingId = ''
    }
  }

  async function handleOpen(data: DrawerOpenData = {}): Promise<void> {
    state.status = data.focusFailures ? 'dead_letter' : ''
    await drawerRef.value?.handleOpen(data, {
      title: '业务回调队列',
      contentHeight: 'calc(100vh - 150px)',
      scrollbarAlways: true,
      showFooter: false,
      onOpen: () => void loadData()
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-callback-outbox {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 100%;

    &__intro {
      display: flex;
      gap: 14px;
      align-items: center;
      padding: 16px 18px;

      > span {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 44px;
        height: 44px;
        font-size: 22px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: var(--el-border-radius-base);
      }

      > div {
        flex: 1;
        min-width: 0;
      }

      strong {
        font-size: 15px;
        color: var(--art-gray-900);
      }

      p {
        margin: 4px 0 0;
        font-size: 12px;
        line-height: 1.6;
        color: var(--art-gray-500);
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;

      article {
        display: flex;
        gap: 10px;
        align-items: center;
        min-width: 0;
        padding: 13px 14px;

        > span {
          display: grid;
          place-items: center;
          width: 36px;
          height: 36px;
          font-size: 18px;
          border-radius: var(--el-border-radius-base);

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          &.is-warning {
            color: var(--el-color-warning);
            background: var(--el-color-warning-light-9);
          }

          &.is-danger {
            color: var(--el-color-danger);
            background: var(--el-color-danger-light-9);
          }

          &.is-info {
            color: var(--el-color-info);
            background: var(--el-color-info-light-9);
          }
        }

        > div {
          display: grid;
          min-width: 0;
        }

        small {
          font-size: 11px;
          color: var(--art-gray-500);
        }

        strong {
          font-size: 20px;
          line-height: 1.3;
          color: var(--art-gray-900);
        }
      }
    }

    &__table {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-height: 420px;
      padding: 16px;

      > header {
        display: flex;
        gap: 16px;
        align-items: center;
        justify-content: space-between;
        padding: 0 2px 14px;

        > div:first-child {
          min-width: 0;
        }

        p {
          margin: 4px 0 0;
          font-size: 12px;
          color: var(--art-gray-500);
        }
      }

      :deep(.art-table) {
        flex: 1;
        min-height: 0;
      }
    }

    &__tools {
      display: flex;
      flex: 0 0 auto;
      gap: 8px;
      align-items: center;
    }

    &__status-filter {
      width: 150px;
    }

    &__business-cell,
    &__delivery-cell,
    &__error-cell {
      display: grid;
      gap: 3px;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        font-weight: 600;
        color: var(--art-gray-900);
      }

      small {
        font-size: 11px;
        color: var(--art-gray-500);
      }
    }

    &__error-cell {
      strong {
        font-size: 11px;
        color: var(--el-color-danger);
      }

      &.is-empty strong {
        color: var(--el-color-success);
      }
    }

    &__operation-placeholder {
      font-size: 12px;
      color: var(--art-gray-400);
    }

    @media screen and (width <= 900px) {
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__table > header {
        flex-direction: column;
        align-items: flex-start;
      }

      &__tools {
        width: 100%;
      }

      &__status-filter {
        flex: 1;
        min-width: 0;
      }
    }

    @media screen and (width <= 560px) {
      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
