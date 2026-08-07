<template>
  <ArtDrawer ref="drawerRef" size="lg" :show-footer="false">
    <template #header>
      <div class="workflow-instance__title">
        <span><ArtSvgIcon icon="ri:file-history-line" /></span>
        <div><strong>审批实例详情</strong><small>流程状态、任务与操作轨迹</small></div>
      </div>
    </template>

    <ArtAsyncState
      :loading="state.loading"
      loading-mode="skeleton"
      :error="state.error"
      :empty="!state.detail"
      empty-text="未找到审批实例"
      :min-height="420"
      @retry="loadDetail"
    >
      <div v-if="state.detail" class="workflow-instance">
        <section class="workflow-instance__hero art-card-xs">
          <div class="workflow-instance__hero-main">
            <span><ArtSvgIcon icon="ri:git-merge-line" /></span>
            <div>
              <small
                >{{ state.detail.definition?.name || '审批流程' }} · V{{
                  state.detail.version?.versionNo || '-'
                }}</small
              >
              <h2>{{ state.detail.businessTitle }}</h2>
              <p>{{ state.detail.businessType }} · {{ state.detail.businessId }}</p>
            </div>
          </div>
          <ArtDictDisplay
            dict-code="workflowInstanceStatus"
            :value="state.detail.status"
            display="tag"
          />
        </section>

        <section class="workflow-instance__section art-card-xs">
          <ArtSectionTitle>实例概览</ArtSectionTitle>
          <ArtDescriptions :data="state.detail" :items="descriptionItems" :columns="2" />
        </section>

        <section class="workflow-instance__section art-card-xs">
          <div class="workflow-instance__section-heading">
            <ArtSectionTitle>审批任务</ArtSectionTitle>
            <span>{{ sortedTasks.length }} 条任务</span>
          </div>
          <ArtTable
            :data="sortedTasks"
            :columns="taskColumns"
            :pagination="false"
            table-layout="fixed"
            stripe
          />
        </section>

        <section class="workflow-instance__section art-card-xs">
          <ArtProcessTimeline
            :items="actionTimelineItems"
            title="流转记录"
            summary="不可篡改审计轨迹"
            action-dict-code="workflowActionType"
            empty-title="暂无流转记录"
            empty-description="流程动作发生后会自动记录在这里。"
          />
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtProcessTimeline from '@/components/core/layouts/art-process-timeline/index.vue'
  import type {
    ArtProcessTimelineItem,
    ArtProcessTimelineTone
  } from '@/components/core/layouts/art-process-timeline/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatWithDayjs } from '@/utils/time'
  import { fetchWorkflowInstanceDetail } from '@/api/workflow'

  defineOptions({ name: 'WorkflowInstanceDrawer' })

  const drawerRef = ref<ArtDrawerExpose<string>>()
  const state = reactive<{
    instanceId: string
    loading: boolean
    error: Error | null
    detail: Api.Workflow.WorkflowInstanceRecord | null
  }>({ instanceId: '', loading: false, error: null, detail: null })

  const sortedTasks = computed(() =>
    [...(state.detail?.tasks || [])].sort(
      (a, b) => a.nodeOrder - b.nodeOrder || a.createTime.localeCompare(b.createTime)
    )
  )
  const sortedActions = computed(() =>
    [...(state.detail?.actions || [])].sort((a, b) => b.createTime.localeCompare(a.createTime))
  )
  const getActionAuditDescription = (action: Api.Workflow.WorkflowActionRecord) => {
    const isPlatformOverride = action.metadata?.operatorType === 'platform_super_override'
    if (!isPlatformOverride) return action.comment
    const originalAssignee = String(action.metadata.originalAssigneeName || '原审批人')
    return [`平台超管代审批 · 原审批人：${originalAssignee}`, action.comment]
      .filter(Boolean)
      .join('；')
  }
  const actionTimelineItems = computed<ArtProcessTimelineItem[]>(() =>
    sortedActions.value.map((action) => ({
      id: action.id,
      actorName:
        action.actor?.nickName ||
        action.actor?.userName ||
        action.actor?.userEmail ||
        action.actorNameSnapshot,
      actorAvatar: action.actor?.avatar,
      actionValue: action.action,
      title:
        action.metadata?.operatorType === 'platform_super_override'
          ? `${action.nodeName || '流程'} · 平台超管代审批`
          : action.nodeName || '流程',
      description: getActionAuditDescription(action),
      time: action.createTime,
      tone: getActionTone(action.action),
      system: !action.actorUserId
    }))
  )

  const formatDate = (value?: string | null): string =>
    value ? String(formatWithDayjs(value) ?? '--') : '--'
  const createDecisionRuleCell = (row: Api.Workflow.WorkflowTaskRecord) => {
    const label =
      row.approvalMode === 'all'
        ? '全员会签'
        : row.approvalMode === 'percentage'
          ? '比例会签'
          : '或签'
    const threshold =
      row.approvalMode === 'percentage'
        ? `${row.approvalThresholdPercent ?? 100}% 通过 · `
        : row.approvalMode === 'any'
          ? '一人通过 · '
          : '全员通过 · '

    return (
      <div class="workflow-instance__decision-rule">
        <strong>{label}</strong>
        <small>
          {threshold}
          {row.rejectVetoEnabled === false ? '容错计算' : '一票否决'}
        </small>
      </div>
    )
  }
  const descriptionItems = computed<ArtDescriptionItem<Api.Workflow.WorkflowInstanceRecord>[]>(
    () => [
      { key: 'initiator', label: '发起人', field: 'initiatorNameSnapshot' },
      {
        key: 'startedAt',
        label: '发起时间',
        value: (detail: Api.Workflow.WorkflowInstanceRecord) => formatDate(detail.startedAt)
      },
      {
        key: 'currentNode',
        label: '当前节点',
        value: (detail: Api.Workflow.WorkflowInstanceRecord) =>
          detail.currentNodeName || '流程已结束'
      },
      {
        key: 'finishedAt',
        label: '结束时间',
        value: (detail: Api.Workflow.WorkflowInstanceRecord) => formatDate(detail.finishedAt)
      },
      {
        key: 'finishComment',
        label: '结束说明',
        value: (detail: Api.Workflow.WorkflowInstanceRecord) => detail.finishComment || '--',
        span: 2
      }
    ]
  )
  const taskColumns: ColumnOption<Api.Workflow.WorkflowTaskRecord>[] = [
    { prop: 'nodeName', label: '审批节点', minWidth: 135 },
    { prop: 'assigneeNameSnapshot', label: '审批人', minWidth: 115 },
    {
      prop: 'approvalMode',
      label: '决策规则',
      minWidth: 150,
      formatter: createDecisionRuleCell
    },
    {
      prop: 'status',
      label: '状态',
      width: 105,
      dict: { code: 'workflowTaskStatus', display: 'tag' }
    },
    {
      prop: 'handledAt',
      label: '处理时间',
      width: 160,
      formatter: (row) => formatDate(row.handledAt)
    },
    {
      prop: 'comment',
      label: '审批意见',
      minWidth: 150,
      showOverflowTooltip: true,
      formatter: (row) => row.comment || '--'
    }
  ]
  const getActionTone = (action: Api.Workflow.ActionType): ArtProcessTimelineTone => {
    if (action === 'approve') return 'success'
    if (action === 'reject' || action === 'cancel') return 'danger'
    if (action === 'withdraw') return 'warning'
    return 'primary'
  }

  async function loadDetail(): Promise<void> {
    if (!state.instanceId) return
    state.loading = true
    state.error = null
    try {
      const response = await fetchWorkflowInstanceDetail(state.instanceId)
      state.detail = response.data
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('审批实例加载失败')
    } finally {
      state.loading = false
    }
  }

  async function handleOpen(instanceId: string): Promise<void> {
    state.instanceId = instanceId
    state.detail = null
    state.error = null
    await drawerRef.value?.handleOpen(instanceId, {
      title: '审批实例详情',
      contentHeight: 'calc(100vh - 86px)'
    })
    await loadDetail()
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .workflow-instance__title {
    display: flex;
    gap: 11px;
    align-items: center;

    > span {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 20px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: calc(var(--el-border-radius-base) + 3px);
    }

    div {
      display: grid;
      gap: 2px;
    }

    strong {
      color: var(--art-gray-900);
    }

    small {
      font-size: 11px;
      color: var(--art-gray-500);
    }
  }

  .workflow-instance {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 13px;
    width: 100%;
    min-width: 0;
    padding: 2px;

    &__hero {
      display: flex;
      gap: 20px;
      align-items: center;
      justify-content: space-between;
      padding: 20px;
      background: linear-gradient(
        135deg,
        var(--el-color-primary-light-9),
        var(--default-box-color) 70%
      );
    }

    &__hero-main {
      display: flex;
      gap: 13px;
      align-items: center;
      min-width: 0;

      > span {
        display: grid;
        flex: 0 0 auto;
        place-items: center;
        width: 46px;
        height: 46px;
        font-size: 22px;
        color: #fff;
        background: linear-gradient(145deg, var(--el-color-primary), #7467f6);
        border-radius: calc(var(--el-border-radius-base) + 6px);
      }

      div {
        min-width: 0;
      }

      small {
        font-weight: 600;
        color: var(--el-color-primary);
      }

      h2 {
        margin: 4px 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 19px;
        color: var(--art-gray-900);
        white-space: nowrap;
      }

      p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--art-gray-500);
        white-space: nowrap;
      }
    }

    &__section {
      width: 100%;
      min-width: 0;
      padding: 18px;
    }

    &__section-heading {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 14px;
    }

    &__section-heading > span {
      font-size: 11px;
      color: var(--art-gray-500);
    }

    &__decision-rule {
      display: grid;
      gap: 3px;
      min-width: 0;

      strong {
        font-size: 13px;
        font-weight: 600;
        color: var(--art-gray-800);
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--art-gray-500);
        white-space: nowrap;
      }
    }
  }
</style>
