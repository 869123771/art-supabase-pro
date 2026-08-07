<template>
  <div class="art-full-height workflow-workbench">
    <section class="workflow-workbench__hero art-card-xs">
      <div class="workflow-workbench__welcome">
        <span><ArtSvgIcon icon="ri:verified-badge-line" /></span>
        <div>
          <span>APPROVAL WORKSPACE</span>
          <h1>审批工作台</h1>
          <p>统一处理跨业务审批任务，跟踪我发起的流程，并通过完整轨迹快速还原每次决策。</p>
        </div>
      </div>
      <ElButton :loading="summary.loading" @click="refreshCurrent">
        <ArtSvgIcon icon="ri:refresh-line" />刷新数据
      </ElButton>
    </section>

    <section v-loading="summary.loading" class="workflow-workbench__metrics">
      <article v-for="metric in metricCards" :key="metric.key" class="art-card-xs">
        <span :class="`is-${metric.tone}`"><ArtSvgIcon :icon="metric.icon" /></span>
        <div
          ><small>{{ metric.label }}</small
          ><strong>{{ metric.value }}</strong
          ><p>{{ metric.hint }}</p></div
        >
      </article>
    </section>

    <section class="workflow-workbench__workspace art-card-xs">
      <header class="workflow-workbench__workspace-header">
        <div>
          <ArtSectionTitle :show-line="false">{{ workspaceTitle }}</ArtSectionTitle>
          <p>{{ activeTabDescription }}</p>
        </div>
        <ElTag :type="activeTab === 'global' ? 'warning' : 'primary'" effect="plain" round>
          {{ activeTab === 'global' ? '平台超管全局视角' : '数据按当前租户隔离' }}
        </ElTag>
      </header>

      <ElTabs v-model="activeTab" class="workflow-workbench__tabs" @tab-change="handleTabChange">
        <ElTabPane name="pending">
          <template #label
            ><span class="workflow-workbench__tab-label"
              ><ArtSvgIcon icon="ri:inbox-archive-line" />待我审批<ElBadge
                :value="summary.data.pendingCount"
                :max="99" /></span
          ></template>
          <ArtTableQuery
            ref="pendingTableRef"
            v-model="pendingTable.searchQuery"
            :search-items="pendingTable.searchItems"
            :api-fn="fetchPendingData"
            :columns-factory="pendingTable.columnsFactory"
            :search-bar-props="searchBarProps"
            :table-props="tableProps"
          />
        </ElTabPane>
        <ElTabPane v-if="isPlatformSuper" name="global">
          <template #label>
            <span class="workflow-workbench__tab-label">
              <ArtSvgIcon icon="ri:global-line" />全局待办
              <ElBadge :value="globalPendingCount" :max="99" />
            </span>
          </template>
          <div class="workflow-workbench__override-guidance">
            <ArtSvgIcon icon="ri:shield-user-line" />
            <span>
              仅用于跨租户应急代办。每次通过或驳回都必须填写干预原因，并记录实际操作人与原审批人。
            </span>
          </div>
          <ArtTableQuery
            ref="globalTableRef"
            v-model="globalTable.searchQuery"
            :search-items="globalTable.searchItems"
            :api-fn="fetchGlobalPendingData"
            :columns-factory="globalTable.columnsFactory"
            :search-bar-props="searchBarProps"
            :table-props="tableProps"
          />
        </ElTabPane>
        <ElTabPane name="handled">
          <template #label
            ><span class="workflow-workbench__tab-label"
              ><ArtSvgIcon icon="ri:checkbox-circle-line" />我已处理</span
            ></template
          >
          <ArtTableQuery
            ref="handledTableRef"
            v-model="handledTable.searchQuery"
            :search-items="handledTable.searchItems"
            :api-fn="fetchHandledData"
            :columns-factory="handledTable.columnsFactory"
            :search-bar-props="searchBarProps"
            :table-props="tableProps"
          />
        </ElTabPane>
        <ElTabPane name="initiated">
          <template #label
            ><span class="workflow-workbench__tab-label"
              ><ArtSvgIcon icon="ri:send-plane-line" />我发起的</span
            ></template
          >
          <ArtTableQuery
            ref="initiatedTableRef"
            v-model="initiatedTable.searchQuery"
            :search-items="initiatedTable.searchItems"
            :api-fn="fetchInitiatedData"
            :columns-factory="initiatedTable.columnsFactory"
            :search-bar-props="searchBarProps"
            :table-props="tableProps"
          />
        </ElTabPane>
      </ElTabs>
    </section>

    <WorkflowActionDialog ref="actionDialogRef" @success="handleActionSuccess" />
    <WorkflowInstanceDrawer ref="instanceDrawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { ElMessage, ElTag } from 'element-plus'
  import { useRoute } from 'vue-router'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchHandledWorkflowTasks,
    fetchInitiatedWorkflowInstances,
    fetchPendingWorkflowTasks,
    fetchPlatformGlobalPendingWorkflowTasks,
    fetchWorkflowWorkbenchSummary,
    withdrawWorkflow
  } from '@/api/workflow'
  import WorkflowActionDialog from './modules/workflow-action-dialog.vue'
  import WorkflowInstanceDrawer from './modules/workflow-instance-drawer.vue'

  defineOptions({ name: 'WorkflowWorkbench' })

  type ActiveTab = 'pending' | 'global' | 'handled' | 'initiated'
  type Task = Api.Workflow.WorkflowTaskRecord
  type Instance = Api.Workflow.WorkflowInstanceRecord
  interface TaskSearch {
    keyword: string
    businessType: string
    status?: Api.Workflow.TaskStatus | ''
  }
  interface InstanceSearch {
    keyword: string
    businessType: string
    status: Api.Workflow.InstanceStatus | ''
  }
  type TaskTableParams = TaskSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type InstanceTableParams = InstanceSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  interface ActionDialogExpose {
    handleOpen: (
      task: Task,
      action: 'approve' | 'reject',
      options?: { platformOverride?: boolean }
    ) => Promise<void>
  }
  interface InstanceDrawerExpose {
    handleOpen: (instanceId: string) => Promise<void>
  }
  interface TableGroup<TSearch, TRow> {
    searchQuery: TSearch
    searchItems: ComputedRef<SearchFormItem[]>
    columnsFactory: () => ColumnOption<TRow>[]
  }

  const { getUserInfo, getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const { confirmAction, promptReason } = useArtFeedback()
  const route = useRoute()
  const activeTab = ref<ActiveTab>('pending')
  const pendingTableRef = ref<ArtTableQueryExpose>()
  const globalTableRef = ref<ArtTableQueryExpose>()
  const handledTableRef = ref<ArtTableQueryExpose>()
  const initiatedTableRef = ref<ArtTableQueryExpose>()
  const actionDialogRef = ref<ActionDialogExpose>()
  const instanceDrawerRef = ref<InstanceDrawerExpose>()
  const searchBarProps = { span: 8, labelWidth: 88 }
  const tableProps = { rowKey: 'id', tableLayout: 'fixed' as const }

  const summary = reactive({
    loading: false,
    data: { pendingCount: 0, handledCount: 0, initiatedRunningCount: 0, initiatedCompletedCount: 0 }
  })
  const currentUserId = computed(() => String(getUserInfo.value.userId || ''))
  const globalPendingCount = ref(0)
  let openedRouteInstanceId = ''

  const businessTypeSearchItem = (): SearchFormItem => ({
    label: '业务类型',
    key: 'businessType',
    type: 'select',
    props: {
      options: getDictMap.value.workflowBusinessType ?? [],
      placeholder: '全部业务类型',
      clearable: true
    }
  })
  const keywordSearchItem: SearchFormItem = {
    label: '业务标题',
    key: 'keyword',
    type: 'input',
    props: { placeholder: '搜索业务单据', clearable: true }
  }

  const formatDate = (value?: string | null) => (value ? formatWithDayjs(value) : '--')
  const openInstance = (instanceId?: string) =>
    instanceId && instanceDrawerRef.value?.handleOpen(instanceId)

  const createBusinessCell = (instance?: Instance) => (
    <div class="workflow-workbench__business-cell">
      <strong>{instance?.businessTitle || '--'}</strong>
      <small>{instance?.definition?.name || instance?.businessId || '--'}</small>
    </div>
  )

  const pendingTable: UnwrapNestedRefs<TableGroup<TaskSearch, Task>> = reactive<
    TableGroup<TaskSearch, Task>
  >({
    searchQuery: { keyword: '', businessType: '' },
    searchItems: computed(() => [keywordSearchItem, businessTypeSearchItem()]),
    columnsFactory: () => [
      {
        prop: 'businessTitle',
        label: '业务单据',
        minWidth: 220,
        fixed: 'left',
        formatter: (row) => createBusinessCell(row.instance)
      },
      {
        prop: 'businessType',
        label: '业务类型',
        minWidth: 145,
        formatter: (row) => (
          <ArtDictDisplay
            dictCode="workflowBusinessType"
            value={row.instance?.businessType}
            display="text"
          />
        )
      },
      { prop: 'nodeName', label: '当前节点', minWidth: 140 },
      {
        prop: 'initiator',
        label: '发起人',
        width: 115,
        formatter: (row) => row.instance?.initiatorNameSnapshot || '--'
      },
      {
        prop: 'createTime',
        label: '收到时间',
        width: 165,
        formatter: (row) => formatDate(row.createTime)
      },
      {
        prop: 'dueAt',
        label: '审批时限',
        width: 150,
        formatter: (row) =>
          row.dueAt ? (
            <span
              class={{
                'workflow-workbench__due': true,
                'is-overdue': dayjs(row.dueAt).isBefore(dayjs())
              }}
            >
              {dayjs(row.dueAt).isBefore(dayjs()) ? '已超时 · ' : ''}
              {dayjs(row.dueAt).format('MM-DD HH:mm')}
            </span>
          ) : (
            <span>--</span>
          )
      },
      {
        prop: 'operation',
        label: '操作',
        width: 160,
        fixed: 'right',
        formatter: (row) => (
          <div class="workflow-workbench__actions">
            <ArtButtonTable
              type="sign"
              label="通过审批"
              onClick={() => actionDialogRef.value?.handleOpen(row, 'approve')}
            />
            <ArtButtonTable
              type="delete"
              icon="ri:close-line"
              label="驳回申请"
              onClick={() => actionDialogRef.value?.handleOpen(row, 'reject')}
            />
            <ArtButtonTable
              type="view"
              label="查看详情"
              onClick={() => openInstance(row.instanceId)}
            />
          </div>
        )
      }
    ]
  })

  const globalTable: UnwrapNestedRefs<TableGroup<TaskSearch, Task>> = reactive<
    TableGroup<TaskSearch, Task>
  >({
    searchQuery: { keyword: '', businessType: '' },
    searchItems: computed(() => [keywordSearchItem, businessTypeSearchItem()]),
    columnsFactory: () => {
      const personalColumns = pendingTable.columnsFactory()
      return [
        personalColumns[0],
        {
          prop: 'tenant',
          label: '所属租户',
          minWidth: 150,
          formatter: (row) => (
            <div class="workflow-workbench__tenant-cell">
              <strong>{row.tenant?.tenantName || '--'}</strong>
              <small>{row.tenant?.tenantCode || '--'}</small>
            </div>
          )
        },
        personalColumns[1],
        { prop: 'assigneeNameSnapshot', label: '原审批人', minWidth: 120 },
        ...personalColumns.slice(2, -1),
        {
          prop: 'operation',
          label: '代审批操作',
          width: 185,
          fixed: 'right',
          formatter: (row) => (
            <div class="workflow-workbench__actions">
              <ArtButtonTable
                type="sign"
                label="代为通过"
                onClick={() =>
                  actionDialogRef.value?.handleOpen(row, 'approve', { platformOverride: true })
                }
              />
              <ArtButtonTable
                type="delete"
                icon="ri:close-line"
                label="代为驳回"
                onClick={() =>
                  actionDialogRef.value?.handleOpen(row, 'reject', { platformOverride: true })
                }
              />
              <ArtButtonTable
                type="view"
                label="查看详情"
                onClick={() => openInstance(row.instanceId)}
              />
            </div>
          )
        }
      ] as ColumnOption<Task>[]
    }
  })

  const handledTable: UnwrapNestedRefs<TableGroup<TaskSearch, Task>> = reactive<
    TableGroup<TaskSearch, Task>
  >({
    searchQuery: { keyword: '', businessType: '', status: '' },
    searchItems: computed(() => [
      keywordSearchItem,
      businessTypeSearchItem(),
      {
        label: '处理结果',
        key: 'status',
        type: 'select',
        props: {
          options: getDictMap.value.workflowTaskStatus ?? [],
          clearable: true,
          placeholder: '全部结果'
        }
      }
    ]),
    columnsFactory: () => [
      {
        prop: 'businessTitle',
        label: '业务单据',
        minWidth: 220,
        fixed: 'left',
        formatter: (row) => createBusinessCell(row.instance)
      },
      { prop: 'nodeName', label: '审批节点', minWidth: 140 },
      {
        prop: 'status',
        label: '处理结果',
        width: 110,
        dict: { code: 'workflowTaskStatus', display: 'tag' }
      },
      {
        prop: 'comment',
        label: '审批意见',
        minWidth: 190,
        showOverflowTooltip: true,
        formatter: (row) => row.comment || '--'
      },
      {
        prop: 'handledAt',
        label: '处理时间',
        width: 165,
        formatter: (row) => formatDate(row.handledAt)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 80,
        fixed: 'right',
        formatter: (row) => (
          <ArtButtonTable
            type="view"
            label="查看详情"
            onClick={() => openInstance(row.instanceId)}
          />
        )
      }
    ]
  })

  const initiatedTable: UnwrapNestedRefs<TableGroup<InstanceSearch, Instance>> = reactive<
    TableGroup<InstanceSearch, Instance>
  >({
    searchQuery: { keyword: '', businessType: '', status: '' },
    searchItems: computed(() => [
      keywordSearchItem,
      businessTypeSearchItem(),
      {
        label: '流程状态',
        key: 'status',
        type: 'select',
        props: {
          options: getDictMap.value.workflowInstanceStatus ?? [],
          clearable: true,
          placeholder: '全部状态'
        }
      }
    ]),
    columnsFactory: () => [
      {
        prop: 'businessTitle',
        label: '业务单据',
        minWidth: 220,
        fixed: 'left',
        formatter: (row) => createBusinessCell(row)
      },
      {
        prop: 'businessType',
        label: '业务类型',
        minWidth: 145,
        formatter: (row) => (
          <ArtDictDisplay dictCode="workflowBusinessType" value={row.businessType} display="text" />
        )
      },
      {
        prop: 'status',
        label: '流程状态',
        width: 110,
        dict: { code: 'workflowInstanceStatus', display: 'tag' }
      },
      {
        prop: 'currentNodeName',
        label: '当前节点',
        minWidth: 145,
        formatter: (row) => row.currentNodeName || '流程已结束'
      },
      {
        prop: 'startedAt',
        label: '发起时间',
        width: 165,
        formatter: (row) => formatDate(row.startedAt)
      },
      {
        prop: 'finishedAt',
        label: '结束时间',
        width: 165,
        formatter: (row) => formatDate(row.finishedAt)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 115,
        fixed: 'right',
        formatter: (row) => (
          <div class="workflow-workbench__actions">
            <ArtButtonTable type="view" label="查看详情" onClick={() => openInstance(row.id)} />
            <ArtButtonTable
              type="delete"
              icon="ri:arrow-go-back-line"
              label="撤回申请"
              disabled={row.status !== 'running'}
              onClick={() => handleWithdraw(row)}
            />
          </div>
        )
      }
    ]
  })

  const metricCards = computed(() => [
    {
      key: 'pending',
      label: '待我审批',
      value: summary.data.pendingCount,
      hint: '需要及时做出决策',
      icon: 'ri:inbox-archive-line',
      tone: 'primary'
    },
    {
      key: 'handled',
      label: '我已处理',
      value: summary.data.handledCount,
      hint: '历史审批任务累计',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      key: 'running',
      label: '进行中的申请',
      value: summary.data.initiatedRunningCount,
      hint: '我发起且尚未结束',
      icon: 'ri:loader-2-line',
      tone: 'warning'
    },
    {
      key: 'finished',
      label: '已结束的申请',
      value: summary.data.initiatedCompletedCount,
      hint: '审批、驳回或撤回',
      icon: 'ri:archive-drawer-line',
      tone: 'info'
    }
  ])
  const activeTabDescription = computed(
    () =>
      ({
        pending: '优先处理临近时限和已超时的任务。',
        global: '跨租户查看全部有效待办，并在必要时执行有原因、有审计的代审批。',
        handled: '回顾我做出的审批决定与意见。',
        initiated: '跟踪我发起的所有审批流程。'
      })[activeTab.value]
  )
  const workspaceTitle = computed(() =>
    activeTab.value === 'global' ? '平台全局审批' : '我的审批'
  )

  function requireUserId(): string {
    if (!currentUserId.value) throw new Error('当前用户信息尚未就绪')
    return currentUserId.value
  }
  function fetchPendingData(params: TaskTableParams) {
    const { from, to } = pageInfoHandler(params)
    return fetchPendingWorkflowTasks({ ...params, assigneeUserId: requireUserId(), from, to })
  }
  async function fetchGlobalPendingData(params: TaskTableParams) {
    const { from, to } = pageInfoHandler(params)
    const response = await fetchPlatformGlobalPendingWorkflowTasks({ ...params, from, to })
    globalPendingCount.value = response.data?.total ?? 0
    return response
  }
  function fetchHandledData(params: TaskTableParams) {
    const { from, to } = pageInfoHandler(params)
    return fetchHandledWorkflowTasks({ ...params, assigneeUserId: requireUserId(), from, to })
  }
  function fetchInitiatedData(params: InstanceTableParams) {
    const { from, to } = pageInfoHandler(params)
    return fetchInitiatedWorkflowInstances({
      ...params,
      initiatorUserId: requireUserId(),
      from,
      to
    })
  }

  async function loadSummary(): Promise<void> {
    if (!currentUserId.value) return
    summary.loading = true
    try {
      const [personalSummary, globalPending] = await Promise.all([
        fetchWorkflowWorkbenchSummary(currentUserId.value),
        isPlatformSuper.value
          ? fetchPlatformGlobalPendingWorkflowTasks({ from: 0, to: 0 })
          : Promise.resolve(null)
      ])
      Object.assign(summary.data, personalSummary)
      globalPendingCount.value = globalPending?.data?.total ?? 0
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '审批统计加载失败')
    } finally {
      summary.loading = false
    }
  }

  function getActiveTableRef() {
    if (activeTab.value === 'global') return globalTableRef
    if (activeTab.value === 'handled') return handledTableRef
    if (activeTab.value === 'initiated') return initiatedTableRef
    return pendingTableRef
  }

  async function refreshCurrent(): Promise<void> {
    await Promise.all([loadSummary(), getActiveTableRef().value?.getData()])
  }
  async function handleTabChange(): Promise<void> {
    await getActiveTableRef().value?.getData()
  }
  async function handleActionSuccess(): Promise<void> {
    await Promise.all([
      pendingTableRef.value?.getData(),
      isPlatformSuper.value ? globalTableRef.value?.getData() : Promise.resolve(),
      handledTableRef.value?.getData(),
      loadSummary()
    ])
  }
  async function handleWithdraw(row: Instance): Promise<void> {
    await confirmAction(`撤回“${row.businessTitle}”后，当前待办将取消且本次流程不可恢复。`, {
      title: '撤回审批申请',
      confirmButtonText: '继续填写原因',
      type: 'warning'
    })
    const reason = await promptReason('请说明撤回原因，原因将写入审计轨迹。', '撤回原因', {
      maxLength: 200
    })
    await withdrawWorkflow(row.id, reason)
    await Promise.all([initiatedTableRef.value?.getData(), loadSummary()])
  }

  async function syncRouteContext(): Promise<void> {
    const routeTab = String(route.query.tab || '')
    if (
      routeTab === 'pending' ||
      routeTab === 'handled' ||
      routeTab === 'initiated' ||
      (routeTab === 'global' && isPlatformSuper.value)
    ) {
      activeTab.value = routeTab
    }

    const instanceId = String(route.query.instanceId || '')
    if (!instanceId || instanceId === openedRouteInstanceId) return
    openedRouteInstanceId = instanceId
    await nextTick()
    await instanceDrawerRef.value?.handleOpen(instanceId)
  }

  watch(
    () => route.fullPath,
    () => void syncRouteContext(),
    { flush: 'post' }
  )
  onActivated(() => {
    void loadSummary()
    void syncRouteContext()
  })
  onMounted(() => {
    void loadSummary()
    void syncRouteContext()
  })
</script>

<style scoped lang="scss">
  .workflow-workbench {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;

    &__hero {
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      padding: 22px 24px;
      background:
        radial-gradient(circle at 88% 10%, rgb(103 88 246 / 14%), transparent 30%),
        var(--default-box-color);
    }
    &__welcome {
      display: flex;
      gap: 15px;
      align-items: center;
      min-width: 0;
    }
    &__welcome > span {
      display: grid;
      flex: 0 0 auto;
      width: 52px;
      height: 52px;
      color: #fff;
      background: linear-gradient(145deg, var(--el-color-primary), #7868f8);
      border-radius: calc(var(--el-border-radius-base) + 8px);
      box-shadow: 0 12px 25px rgb(76 91 220 / 23%);
      place-items: center;
      font-size: 26px;
    }
    &__welcome > div > span {
      color: var(--el-color-primary);
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
    }
    &__welcome h1 {
      margin: 4px 0 5px;
      color: var(--art-gray-900);
      font-size: 24px;
    }
    &__welcome p {
      margin: 0;
      color: var(--art-gray-500);
      font-size: 13px;
      line-height: 1.55;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      min-height: 102px;
    }
    &__metrics article {
      display: flex;
      gap: 13px;
      align-items: center;
      padding: 17px;
      min-width: 0;
    }
    &__metrics article > span {
      display: grid;
      flex: 0 0 auto;
      width: 43px;
      height: 43px;
      border-radius: calc(var(--el-border-radius-base) + 5px);
      place-items: center;
      font-size: 21px;
    }
    &__metrics article > span.is-primary {
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
    }
    &__metrics article > span.is-success {
      color: var(--el-color-success);
      background: var(--el-color-success-light-9);
    }
    &__metrics article > span.is-warning {
      color: var(--el-color-warning);
      background: var(--el-color-warning-light-9);
    }
    &__metrics article > span.is-info {
      color: var(--el-color-info);
      background: var(--el-color-info-light-9);
    }
    &__metrics article div {
      display: grid;
      min-width: 0;
      grid-template-columns: 1fr auto;
      align-items: baseline;
      column-gap: 8px;
    }
    &__metrics small {
      color: var(--art-gray-500);
      font-size: 12px;
    }
    &__metrics strong {
      color: var(--art-gray-900);
      font-size: 25px;
    }
    &__metrics p {
      grid-column: 1 / -1;
      margin: 4px 0 0;
      overflow: hidden;
      color: var(--art-gray-400);
      font-size: 10px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__workspace {
      flex: 1;
      min-height: 0;
      padding: 18px;
    }
    &__workspace-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 2px;
    }
    &__workspace-header p {
      margin: 5px 0 0;
      color: var(--art-gray-500);
      font-size: 12px;
    }
    &__tabs {
      min-height: 0;
    }
    &__tab-label {
      display: inline-flex;
      gap: 7px;
      align-items: center;
    }
    &__tab-label :deep(.el-badge__content) {
      transform: translateY(-1px) scale(0.82);
    }
    &__override-guidance {
      display: flex;
      gap: 8px;
      align-items: flex-start;
      margin: 2px 0 12px;
      padding: 10px 12px;
      color: var(--el-color-warning-dark-2);
      font-size: 12px;
      line-height: 1.55;
      background: var(--el-color-warning-light-9);
      border: 1px solid var(--el-color-warning-light-7);
      border-radius: var(--el-border-radius-base);
    }
    &__override-guidance svg {
      flex: 0 0 auto;
      margin-top: 2px;
      font-size: 16px;
    }

    :deep(.workflow-workbench__business-cell),
    :deep(.workflow-workbench__tenant-cell) {
      display: grid;
      min-width: 0;
      gap: 3px;
    }
    :deep(.workflow-workbench__business-cell strong),
    :deep(.workflow-workbench__business-cell small),
    :deep(.workflow-workbench__tenant-cell strong),
    :deep(.workflow-workbench__tenant-cell small) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    :deep(.workflow-workbench__business-cell small),
    :deep(.workflow-workbench__tenant-cell small) {
      color: var(--art-gray-500);
      font-size: 11px;
    }
    :deep(.workflow-workbench__actions) {
      display: flex;
      align-items: center;
    }
    :deep(.workflow-workbench__due.is-overdue) {
      color: var(--el-color-danger);
      font-weight: 600;
    }
    :deep(.art-table-query) {
      min-width: 0;
    }
    :deep(.art-table-card) {
      border: 1px solid var(--art-gray-200);
    }
  }

  @media (width <= 1100px) {
    .workflow-workbench__metrics {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (width <= 720px) {
    .workflow-workbench__hero {
      align-items: flex-start;
      padding: 18px;
    }
    .workflow-workbench__hero > button {
      flex: 0 0 auto;
      padding: 8px;
    }
    .workflow-workbench__hero > button :deep(span) {
      display: none;
    }
    .workflow-workbench__welcome {
      align-items: flex-start;
    }
    .workflow-workbench__welcome h1 {
      font-size: 20px;
    }
    .workflow-workbench__metrics {
      grid-template-columns: 1fr;
    }
    .workflow-workbench__metrics article {
      padding: 14px;
    }
    .workflow-workbench__workspace {
      padding: 14px;
    }
    .workflow-workbench__workspace-header > .el-tag {
      display: none;
    }
  }
</style>
