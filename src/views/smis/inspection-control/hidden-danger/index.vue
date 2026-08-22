<template>
  <div class="smis-hidden-danger-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="INSPECTION & RECTIFICATION"
      title="隐患排查治理"
      description="把检查任务、隐患上报、责任整改、复查退回与销号留痕串成一条可追溯业务闭环。"
      icon="ri:shield-check-line"
      :tags="[
        { label: '检查—整改—销号', type: 'primary' },
        { label: '普通用户只读', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions
          :table="activeTab === 'danger' ? dangerTableRef : taskTableRef"
        />
      </template>
    </BusinessWorkspaceHeader>

    <section class="smis-hidden-danger-page__workspace art-card">
      <ElTabs v-model="activeTab">
        <ElTabPane name="danger" label="隐患治理台账">
          <ArtTableQuery
            ref="dangerTableRef"
            v-model="dangerTable.searchQuery"
            :search-items="dangerTable.searchItems"
            :api-fn="fetchDangerData"
            :columns-factory="dangerTable.columnsFactory"
            :header-actions="dangerTable.headerActions"
            header-actions-placement="workspace"
            :search-bar-props="{ span: 6, labelWidth: 84 }"
            :table-props="{
              rowKey: 'id',
              tableLayout: 'fixed',
              emptyText: '暂无隐患记录',
              emptyDescription: '可直接上报现场隐患，或从检查任务中登记发现的问题。'
            }"
            :on-success="handleDangerSuccess"
            focusable
          />
        </ElTabPane>

        <ElTabPane name="task" label="检查任务">
          <ArtTableQuery
            ref="taskTableRef"
            v-model="taskTable.searchQuery"
            :search-items="taskTable.searchItems"
            :api-fn="fetchTaskData"
            :columns-factory="taskTable.columnsFactory"
            :header-actions="taskTable.headerActions"
            header-actions-placement="workspace"
            :search-bar-props="{ span: 6, labelWidth: 84 }"
            :table-props="{
              rowKey: 'id',
              tableLayout: 'fixed',
              emptyText: '暂无检查任务',
              emptyDescription: '新增任务后可开始执行、登记隐患并提交检查结果。'
            }"
            :on-success="handleTaskSuccess"
            focusable
          />
        </ElTabPane>
      </ElTabs>
    </section>

    <InspectionTaskDialog ref="taskDialogRef" @success="refreshTasks" />
    <InspectionTaskActionDialog ref="taskActionDialogRef" @success="refreshAll" />
    <HiddenDangerDialog ref="dangerDialogRef" @success="refreshAll" />
    <HiddenDangerActionDialog ref="dangerActionDialogRef" @success="refreshDangers" />
    <HiddenDangerDrawer ref="dangerDrawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import {
    deleteInspectionTask,
    fetchHiddenDangerList,
    fetchInspectionTaskList,
    fetchSmisRiskPointOptions,
    startHiddenDangerWorkflow,
    transitionInspectionTask
  } from '@/api/smis'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import InspectionTaskDialog from './modules/inspection-task-dialog.vue'
  import InspectionTaskActionDialog from './modules/inspection-task-action-dialog.vue'
  import HiddenDangerDialog from './modules/hidden-danger-dialog.vue'
  import HiddenDangerActionDialog from './modules/hidden-danger-action-dialog.vue'
  import HiddenDangerDrawer from './modules/hidden-danger-drawer.vue'

  defineOptions({ name: 'SmisHiddenDanger' })

  type Task = Api.Smis.InspectionControl.InspectionTaskRecord
  type TaskSearch = Api.Smis.InspectionControl.InspectionTaskSearchParams
  type Danger = Api.Smis.InspectionControl.HiddenDangerRecord
  type DangerSearch = Api.Smis.InspectionControl.HiddenDangerSearchParams
  type TaskParams = TaskSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type DangerParams = DangerSearch & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  interface TaskDialogExpose {
    handleOpen: (row?: Task) => Promise<void>
  }
  interface TaskActionDialogExpose {
    handleOpen: (data: { row: Task; action: 'complete' | 'cancel' }) => Promise<void>
  }
  interface DangerDialogExpose {
    handleOpen: (data?: { task?: Task; riskPointId?: string }) => Promise<void>
  }
  interface DangerActionDialogExpose {
    handleOpen: (data: {
      row: Danger
      action: Api.Smis.InspectionControl.HiddenDangerAction
    }) => Promise<void>
  }
  interface DangerDrawerExpose {
    handleOpen: (row: Danger) => Promise<void>
  }
  interface TableGroup<TSearch, TRow> {
    searchQuery: TSearch
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<TRow>[]
  }

  const { confirmAction } = useArtFeedback()
  const activeTab = ref<'danger' | 'task'>('danger')
  const dangerTableRef = ref<ArtTableQueryExpose>()
  const taskTableRef = ref<ArtTableQueryExpose>()
  const taskDialogRef = ref<TaskDialogExpose>()
  const taskActionDialogRef = ref<TaskActionDialogExpose>()
  const dangerDialogRef = ref<DangerDialogExpose>()
  const dangerActionDialogRef = ref<DangerActionDialogExpose>()
  const dangerDrawerRef = ref<DangerDrawerExpose>()
  const riskPointOptions = ref<Array<{ label: string; value: string }>>([])
  const overview = reactive<{
    dangerTotal: number
    dangers: Danger[]
    taskTotal: number
    tasks: Task[]
  }>({
    dangerTotal: 0,
    dangers: [],
    taskTotal: 0,
    tasks: []
  })

  const isOverdue = (row: Danger): boolean =>
    Boolean(
      row.rectificationDeadline &&
      !['closed', 'cancelled'].includes(row.status) &&
      dayjs(row.rectificationDeadline).isBefore(dayjs())
    )
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '隐患总数',
      value: overview.dangerTotal,
      description: '当前筛选条件下的隐患记录',
      icon: 'ri:alert-line'
    },
    {
      label: '本页待治理',
      value: overview.dangers.filter((row) => !['closed', 'cancelled'].includes(row.status)).length,
      description: '已上报、整改中或待复查',
      icon: 'ri:loader-4-line',
      tone: 'warning'
    },
    {
      label: '本页已逾期',
      value: overview.dangers.filter(isOverdue).length,
      description: '超过整改期限且尚未销号',
      icon: 'ri:alarm-warning-line',
      tone: 'danger'
    },
    {
      label: '检查任务',
      value: overview.taskTotal,
      description: '当前筛选条件下的检查任务',
      icon: 'ri:task-line',
      tone: 'success'
    }
  ])

  const dateRangeProps = {
    type: 'daterange',
    valueFormat: 'YYYY-MM-DD',
    startPlaceholder: '开始日期',
    endPlaceholder: '结束日期',
    class: '!w-full'
  }
  const riskFilterItem = (): SearchFormItem => ({
    label: '风险点',
    key: 'riskPointId',
    type: 'select',
    props: { options: riskPointOptions.value, filterable: true }
  })

  const dangerTable = reactive<TableGroup<DangerSearch, Danger>>({
    searchQuery: {
      keyword: '',
      status: '',
      dangerLevel: '',
      riskPointId: '',
      overdueOnly: false,
      reportedTimeRange: []
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { placeholder: '编号、标题或描述' }
      },
      riskFilterItem(),
      {
        label: '隐患等级',
        key: 'dangerLevel',
        type: 'select',
        props: {
          options: [
            { label: '低风险', value: 'low' },
            { label: '一般风险', value: 'general' },
            { label: '较大风险', value: 'major' },
            { label: '重大风险', value: 'critical' }
          ]
        }
      },
      {
        label: '治理状态',
        key: 'status',
        type: 'select',
        props: {
          options: [
            { label: '已上报', value: 'reported' },
            { label: '整改中', value: 'rectifying' },
            { label: '待复查', value: 'pending_review' },
            { label: '已销号', value: 'closed' },
            { label: '已作废', value: 'cancelled' }
          ]
        }
      },
      { label: '上报时间', key: 'reportedTimeRange', type: 'date', props: dateRangeProps },
      { label: '仅看逾期', key: 'overdueOnly', type: 'switch' }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        label: '上报隐患',
        permission: 'SmisHiddenDanger:Report',
        onClick: () => void dangerDialogRef.value?.handleOpen()
      }
    ]),
    columnsFactory: () => [
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'dangerNo', label: '隐患编号', width: 156 },
      { prop: 'dangerTitle', label: '隐患标题', minWidth: 200 },
      {
        prop: 'dangerLevel',
        label: '等级',
        width: 100,
        formatter: (row) => (
          <ArtDictDisplay dictCode="smisRiskLevel" value={row.dangerLevel} display="tag" />
        )
      },
      { prop: 'riskPoint.riskPointName', label: '风险点', minWidth: 170 },
      {
        prop: 'responsibleUser',
        label: '整改责任人',
        width: 116,
        formatter: (row) => userName(row.responsibleUser)
      },
      {
        prop: 'rectificationDeadline',
        label: '整改期限',
        minWidth: 168,
        formatter: (row) => (
          <span class={isOverdue(row) ? 'smis-overdue' : ''}>
            {formatWithDayjs(row.rectificationDeadline)}
          </span>
        )
      },
      {
        prop: 'status',
        label: '状态',
        width: 104,
        dict: { code: 'smisHiddenDangerStatus', display: 'auto' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 320,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="view"
              permission="SmisHiddenDanger:View"
              onClick={() => openDanger(row)}
            />
            {['reported', 'rectifying'].includes(row.status) && (
              <ArtButtonTable
                type="edit"
                label="指派"
                permission="SmisHiddenDanger:Assign"
                onClick={() => openDangerAction(row, 'assign')}
              />
            )}
            {row.status === 'rectifying' && (
              <ArtButtonTable
                type="edit"
                label="提交复查"
                permission="SmisHiddenDanger:Rectify"
                onClick={() => openDangerAction(row, 'submit_review')}
              />
            )}
            {row.status === 'pending_review' && (
              <>
                <ArtButtonTable
                  type="edit"
                  label="流程审批"
                  permission="SmisHiddenDanger:Review"
                  onClick={() => void startDangerWorkflow(row)}
                />
                <ArtButtonTable
                  type="edit"
                  label="退回"
                  permission="SmisHiddenDanger:Review"
                  onClick={() => openDangerAction(row, 'reject')}
                />
                <ArtButtonTable
                  type="edit"
                  label="销号"
                  permission="SmisHiddenDanger:Review"
                  onClick={() => openDangerAction(row, 'close')}
                />
              </>
            )}
          </div>
        )
      }
    ]
  })

  const taskTable = reactive<TableGroup<TaskSearch, Task>>({
    searchQuery: { keyword: '', status: '', riskPointId: '', scheduledTimeRange: [] },
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '关键词', key: 'keyword', type: 'input', props: { placeholder: '任务编号或名称' } },
      riskFilterItem(),
      {
        label: '任务状态',
        key: 'status',
        type: 'select',
        props: {
          options: [
            { label: '待执行', value: 'pending' },
            { label: '执行中', value: 'in_progress' },
            { label: '已完成', value: 'completed' },
            { label: '已取消', value: 'cancelled' }
          ]
        }
      },
      { label: '计划时间', key: 'scheduledTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        label: '新增检查任务',
        permission: 'SmisHiddenDanger:ExecuteInspection',
        onClick: () => void taskDialogRef.value?.handleOpen()
      }
    ]),
    columnsFactory: () => [
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'taskNo', label: '任务编号', width: 156 },
      { prop: 'taskName', label: '任务名称', minWidth: 190 },
      { prop: 'riskPoint.riskPointName', label: '风险点', minWidth: 170 },
      {
        prop: 'inspectorUser',
        label: '检查人',
        width: 108,
        formatter: (row) => userName(row.inspectorUser)
      },
      {
        prop: 'scheduledStartAt',
        label: '计划开始',
        minWidth: 168,
        formatter: (row) => formatWithDayjs(row.scheduledStartAt)
      },
      {
        prop: 'result.checkResult',
        label: '检查结果',
        width: 108,
        formatter: (row) =>
          row.result?.checkResult ? (
            <ArtDictDisplay
              dictCode="smisInspectionResult"
              value={row.result.checkResult}
              display="tag"
            />
          ) : (
            '--'
          )
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'smisInspectionTaskStatus', display: 'auto' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 300,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            {row.status === 'pending' && (
              <ArtButtonTable
                type="edit"
                permission="SmisHiddenDanger:ExecuteInspection"
                onClick={() => void taskDialogRef.value?.handleOpen(row)}
              />
            )}
            {row.status === 'pending' && (
              <ArtButtonTable
                type="edit"
                label="开始"
                permission="SmisHiddenDanger:ExecuteInspection"
                onClick={() => void startTask(row)}
              />
            )}
            {['pending', 'in_progress'].includes(row.status) && (
              <ArtButtonTable
                type="add"
                label="登记隐患"
                permission="SmisHiddenDanger:Report"
                onClick={() => void dangerDialogRef.value?.handleOpen({ task: row })}
              />
            )}
            {['pending', 'in_progress'].includes(row.status) && (
              <ArtButtonTable
                type="edit"
                label="完成"
                permission="SmisHiddenDanger:ExecuteInspection"
                onClick={() => openTaskAction(row, 'complete')}
              />
            )}
            {row.status === 'pending' && (
              <ArtButtonTable
                type="delete"
                permission="SmisHiddenDanger:ExecuteInspection"
                onClick={() => void removeTask(row)}
              />
            )}
          </div>
        )
      }
    ]
  })

  const userName = (
    user?: { nickName?: string | null; userName?: string | null; userEmail: string } | null
  ) => user?.nickName || user?.userName || user?.userEmail || '--'
  const fetchDangerData = (params: DangerParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchHiddenDangerList({ ...params, from, to })
  }
  const fetchTaskData = (params: TaskParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchInspectionTaskList({ ...params, from, to })
  }
  const handleDangerSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.dangers = rows as Danger[]
    overview.dangerTotal = response.total ?? rows.length
  }
  const handleTaskSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.tasks = rows as Task[]
    overview.taskTotal = response.total ?? rows.length
  }
  const openDanger = (row: Danger): void => {
    void dangerDrawerRef.value?.handleOpen(row)
  }
  const openDangerAction = (
    row: Danger,
    action: Api.Smis.InspectionControl.HiddenDangerAction
  ): void => {
    void dangerActionDialogRef.value?.handleOpen({ row, action })
  }
  const openTaskAction = (row: Task, action: 'complete' | 'cancel'): void => {
    void taskActionDialogRef.value?.handleOpen({ row, action })
  }
  const startTask = async (row: Task): Promise<void> => {
    if (!row.id) return
    await transitionInspectionTask({ id: row.id, action: 'start' })
    await refreshTasks()
  }
  const startDangerWorkflow = async (row: Danger): Promise<void> => {
    if (!row.id) return
    await confirmAction(
      `确定将“${row.dangerTitle}”提交到现有审批工作台吗？审批通过后自动销号，驳回后自动退回整改。`,
      '发起流程审批',
      {
        confirmButtonText: '发起审批',
        cancelButtonText: '取消',
        type: 'warning'
      }
    )
    await startHiddenDangerWorkflow(row.id)
    await refreshDangers()
  }
  const removeTask = async (row: Task): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除待执行任务“${row.taskName}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteInspectionTask(row.id)
      await refreshTasks()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
  const refreshDangers = async (): Promise<void> => {
    await dangerTableRef.value?.refreshUpdate()
  }
  const refreshTasks = async (): Promise<void> => {
    await taskTableRef.value?.refreshUpdate()
  }
  const refreshAll = async (): Promise<void> => {
    await Promise.all([refreshDangers(), refreshTasks()])
  }

  onMounted(async () => {
    const response = await fetchSmisRiskPointOptions()
    riskPointOptions.value = (response.data ?? []).map((item) => ({
      label: `${item.riskPointNo} · ${item.riskPointName}`,
      value: item.id!
    }))
  })
</script>

<style scoped lang="scss">
  .smis-hidden-danger-page {
    gap: 12px;
    min-width: 0;

    &__workspace {
      min-width: 0;
      padding: 0 16px 16px;
      overflow: hidden;
    }
  }

  :deep(.smis-overdue) {
    font-weight: 600;
    color: var(--el-color-danger);
  }

  @media (width <= 900px) {
    .smis-hidden-danger-page__workspace {
      padding-inline: 10px;
    }
  }
</style>
