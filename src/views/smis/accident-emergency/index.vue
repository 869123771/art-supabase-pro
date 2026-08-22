<template>
  <div class="smis-accident-emergency art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="INCIDENT & EMERGENCY"
      title="事故与应急管理"
      description="关联车辆事故与现场事件，完成调查、整改、结案，并维护应急预案和演练改进记录。"
      icon="ri:first-aid-kit-line"
      :tags="[
        { label: 'VMS来源复用', type: 'primary' },
        { label: '普通用户只读', type: 'info' }
      ]"
      :metrics="metrics"
      ><template #actions><BusinessTableWorkspaceActions :table="activeTableRef" /></template
    ></BusinessWorkspaceHeader>

    <section class="smis-accident-emergency__workspace art-card">
      <ElTabs v-model="activeTab">
        <ElTabPane name="accident" label="事故事件">
          <ArtTableQuery
            ref="accidentTableRef"
            v-model="accidentSearch"
            :search-items="accidentSearchItems"
            :api-fn="fetchAccidents"
            :columns-factory="accidentColumns"
            :header-actions="accidentActions"
            header-actions-placement="workspace"
            :search-bar-props="{ span: 6, labelWidth: 84 }"
            :table-props="{
              rowKey: 'id',
              tableLayout: 'fixed',
              emptyText: '暂无事故事件',
              emptyDescription: '可现场上报，也可关联已有 VMS 车辆事故记录。'
            }"
            :on-success="onAccidentSuccess"
            focusable
          />
        </ElTabPane>
        <ElTabPane name="plan" label="应急预案">
          <ArtTableQuery
            ref="planTableRef"
            v-model="emptySearch"
            :search-items="[]"
            :api-fn="fetchPlans"
            :columns-factory="planColumns"
            :header-actions="planActions"
            header-actions-placement="workspace"
            :table-props="{ rowKey: 'id', tableLayout: 'fixed', emptyText: '暂无应急预案' }"
            :on-success="onPlanSuccess"
            focusable
          />
        </ElTabPane>
        <ElTabPane name="drill" label="应急演练">
          <ArtTableQuery
            ref="drillTableRef"
            v-model="emptySearch"
            :search-items="[]"
            :api-fn="fetchDrills"
            :columns-factory="drillColumns"
            :header-actions="drillActions"
            header-actions-placement="workspace"
            :table-props="{ rowKey: 'id', tableLayout: 'fixed', emptyText: '暂无应急演练' }"
            :on-success="onDrillSuccess"
            focusable
          />
        </ElTabPane>
      </ElTabs>
    </section>
    <AccidentCaseDialog ref="accidentDialogRef" @success="refreshAccidents" />
    <AccidentActionDialog ref="accidentActionRef" @success="refreshAccidents" />
    <AccidentCaseDrawer ref="accidentDrawerRef" />
    <EmergencyPlanDialog ref="planDialogRef" @success="refreshPlans" />
    <EmergencyDrillDialog ref="drillDialogRef" @success="refreshDrills" />
  </div>
</template>

<script setup lang="tsx">
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { canEditField, canViewField, mergeFieldAccessMaps } from '@/utils/field-permission'
  import {
    deleteEmergencyDrill,
    deleteEmergencyPlan,
    fetchAccidentCaseList,
    fetchEmergencyDrillList,
    fetchEmergencyPlanList
  } from '@/api/smis'
  import AccidentCaseDialog from './modules/accident-case-dialog.vue'
  import AccidentActionDialog from './modules/accident-action-dialog.vue'
  import AccidentCaseDrawer from './modules/accident-case-drawer.vue'
  import EmergencyPlanDialog from './modules/emergency-plan-dialog.vue'
  import EmergencyDrillDialog from './modules/emergency-drill-dialog.vue'

  defineOptions({ name: 'SmisAccidentEmergency' })
  type Accident = Api.Smis.AccidentEmergency.AccidentCaseRecord
  type Plan = Api.Smis.AccidentEmergency.EmergencyPlanRecord
  type Drill = Api.Smis.AccidentEmergency.EmergencyDrillRecord
  type Tab = 'accident' | 'plan' | 'drill'
  const { confirmAction } = useArtFeedback()
  const activeTab = ref<Tab>('accident')
  const accidentTableRef = ref<ArtTableQueryExpose>()
  const planTableRef = ref<ArtTableQueryExpose>()
  const drillTableRef = ref<ArtTableQueryExpose>()
  const accidentDialogRef = ref<{ handleOpen: (row?: Accident) => Promise<void> }>()
  const accidentActionRef = ref<{
    handleOpen: (data: {
      row: Accident
      action: Api.Smis.AccidentEmergency.AccidentCaseAction
    }) => Promise<void>
  }>()
  const accidentDrawerRef = ref<{ handleOpen: (row: Accident) => Promise<void> }>()
  const planDialogRef = ref<{ handleOpen: (row?: Plan) => Promise<void> }>()
  const drillDialogRef = ref<{ handleOpen: (row?: Drill) => Promise<void> }>()
  const activeTableRef = computed(
    () =>
      ({ accident: accidentTableRef.value, plan: planTableRef.value, drill: drillTableRef.value })[
        activeTab.value
      ]
  )
  const counts = reactive({ accident: 0, plan: 0, drill: 0, open: 0 })
  const accidentListFieldAccess = ref<
    Api.Smis.AccidentEmergency.AccidentCaseFieldAccessMap
  >({})
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '事故事件',
      value: counts.accident,
      icon: 'ri:alarm-warning-line',
      description: '当前事故与事件台账'
    },
    {
      label: '未结事件',
      value: counts.open,
      icon: 'ri:loader-4-line',
      tone: 'warning',
      description: '当前页未完成调查闭环'
    },
    {
      label: '应急预案',
      value: counts.plan,
      icon: 'ri:file-shield-2-line',
      tone: 'success',
      description: '预案版本台账'
    },
    { label: '应急演练', value: counts.drill, icon: 'ri:team-line', description: '演练与改进记录' }
  ])
  const emptySearch = reactive<Record<string, never>>({})
  const accidentSearch = reactive<Api.Smis.AccidentEmergency.AccidentCaseSearchParams>({
    keyword: '',
    status: '',
    severity: '',
    occurredTimeRange: []
  })
  const accidentSearchItems: SearchFormItem[] = [
    { label: '关键词', key: 'keyword', type: 'input', props: { placeholder: '事件编号或标题' } },
    {
      label: '严重程度',
      key: 'severity',
      type: 'select',
      props: {
        options: [
          { label: '轻微', value: 'slight' },
          { label: '一般', value: 'general' },
          { label: '较大', value: 'major' },
          { label: '重大', value: 'critical' }
        ]
      }
    },
    {
      label: '处理状态',
      key: 'status',
      type: 'select',
      props: {
        options: [
          { label: '已上报', value: 'reported' },
          { label: '调查中', value: 'investigating' },
          { label: '整改中', value: 'rectifying' },
          { label: '已结案', value: 'closed' },
          { label: '已作废', value: 'cancelled' }
        ]
      }
    },
    {
      label: '发生时间',
      key: 'occurredTimeRange',
      type: 'date',
      props: { type: 'daterange', valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    }
  ]
  const accidentActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '上报事故事件',
      permission: 'SmisAccidentEmergency:ManageAccident',
      onClick: () => void accidentDialogRef.value?.handleOpen()
    }
  ])
  const planActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '新增应急预案',
      permission: 'SmisAccidentEmergency:ManagePlan',
      onClick: () => void planDialogRef.value?.handleOpen()
    }
  ])
  const drillActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '新增应急演练',
      permission: 'SmisAccidentEmergency:ManageDrill',
      onClick: () => void drillDialogRef.value?.handleOpen()
    }
  ])
  const userName = (user?: Api.Smis.AccidentEmergency.UserRef | null) =>
    user?.nickName || user?.userName || user?.userEmail || '--'
  const accidentColumns = (): ColumnOption<Accident>[] => [
    { type: 'globalIndex', label: '序号', width: 64 },
    { prop: 'caseNo', label: '事件编号', width: 154 },
    { prop: 'caseTitle', label: '事件标题', minWidth: 200 },
    {
      prop: 'occurredAt',
      label: '发生时间',
      minWidth: 168,
      formatter: (row) => formatWithDayjs(row.occurredAt)
    },
    {
      prop: 'severity',
      label: '严重程度',
      width: 100,
      formatter: (row) =>
        ({ slight: '轻微', general: '一般', major: '较大', critical: '重大' })[row.severity]
    },
    ...(canViewField(accidentListFieldAccess.value, 'caseParticipants')
      ? [
          {
            prop: 'investigatorUser',
            label: '调查负责人',
            width: 112,
            formatter: (row: Accident) => userName(row.investigatorUser)
          } as ColumnOption<Accident>
        ]
      : []),
    {
      prop: 'status',
      label: '状态',
      width: 104,
      dict: { code: 'smisAccidentCaseStatus', display: 'auto' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 270,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="view"
            permission="SmisAccidentEmergency:View"
            onClick={() => void accidentDrawerRef.value?.handleOpen(row)}
          />
          {row.status === 'reported' &&
            canEditField(row.fieldAccess, 'caseParticipants') && (
            <ArtButtonTable
              type="edit"
              permission="SmisAccidentEmergency:ManageAccident"
              onClick={() => void accidentDialogRef.value?.handleOpen(row)}
            />
          )}
          {row.status === 'reported' && (
            <ArtButtonTable
              type="edit"
              label="调查"
              permission="SmisAccidentEmergency:ManageAccident"
              onClick={() => openAccidentAction(row, 'investigate')}
            />
            )}
          {row.status === 'investigating' &&
            canEditField(row.fieldAccess, 'investigationDetails') && (
            <ArtButtonTable
              type="edit"
              label="整改"
              permission="SmisAccidentEmergency:ManageAccident"
              onClick={() => openAccidentAction(row, 'rectify')}
            />
            )}
          {row.status === 'rectifying' &&
            canEditField(row.fieldAccess, 'investigationDetails') && (
            <ArtButtonTable
              type="edit"
              label="结案"
              permission="SmisAccidentEmergency:ManageAccident"
              onClick={() => openAccidentAction(row, 'close')}
            />
            )}
        </div>
      )
    }
  ]
  const planColumns = (): ColumnOption<Plan>[] => [
    { type: 'globalIndex', label: '序号', width: 64 },
    { prop: 'planNo', label: '预案编号', width: 150 },
    { prop: 'planName', label: '预案名称', minWidth: 220 },
    { prop: 'versionNo', label: '版本', width: 76 },
    { prop: 'applicableScope', label: '适用范围', minWidth: 190 },
    { prop: 'ownerUser', label: '责任人', width: 110, formatter: (row) => userName(row.ownerUser) },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'smisEmergencyPlanStatus', display: 'auto' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 130,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="edit"
            permission="SmisAccidentEmergency:ManagePlan"
            onClick={() => void planDialogRef.value?.handleOpen(row)}
          />
          <ArtButtonTable
            type="delete"
            permission="SmisAccidentEmergency:ManagePlan"
            onClick={() => void removePlan(row)}
          />
        </div>
      )
    }
  ]
  const drillColumns = (): ColumnOption<Drill>[] => [
    { type: 'globalIndex', label: '序号', width: 64 },
    { prop: 'drillNo', label: '演练编号', width: 150 },
    { prop: 'drillName', label: '演练名称', minWidth: 210 },
    { prop: 'plan.planName', label: '关联预案', minWidth: 190 },
    {
      prop: 'scheduledAt',
      label: '计划时间',
      minWidth: 168,
      formatter: (row) => formatWithDayjs(row.scheduledAt)
    },
    {
      prop: 'organizerUser',
      label: '组织人',
      width: 104,
      formatter: (row) => userName(row.organizerUser)
    },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'smisEmergencyDrillStatus', display: 'auto' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 130,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="edit"
            permission="SmisAccidentEmergency:ManageDrill"
            onClick={() => void drillDialogRef.value?.handleOpen(row)}
          />
          <ArtButtonTable
            type="delete"
            permission="SmisAccidentEmergency:ManageDrill"
            onClick={() => void removeDrill(row)}
          />
        </div>
      )
    }
  ]
  const fetchAccidents = async (
    params: Api.Smis.AccidentEmergency.AccidentCaseSearchParams & Api.Common.PaginationParams
  ) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchAccidentCaseList({ ...params, from, to })
    const nextAccess = mergeFieldAccessMaps(
      result.fieldAccess,
      ...(result.data ?? []).map((row) => row.fieldAccess)
    )
    const participantVisibilityChanged =
      canViewField(accidentListFieldAccess.value, 'caseParticipants') !==
      canViewField(nextAccess, 'caseParticipants')
    accidentListFieldAccess.value = nextAccess
    if (participantVisibilityChanged) nextTick(() => accidentTableRef.value?.resetColumns())
    return result
  }
  const fetchPlans = () => fetchEmergencyPlanList()
  const fetchDrills = () => fetchEmergencyDrillList()
  const onAccidentSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    counts.accident = response.total ?? rows.length
    counts.open = (rows as Accident[]).filter(
      (row) => !['closed', 'cancelled'].includes(row.status)
    ).length
  }
  const onPlanSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows) => {
    counts.plan = rows.length
  }
  const onDrillSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows) => {
    counts.drill = rows.length
  }
  const openAccidentAction = (
    row: Accident,
    action: Api.Smis.AccidentEmergency.AccidentCaseAction
  ) => void accidentActionRef.value?.handleOpen({ row, action })
  const refreshAccidents = async () => {
    await accidentTableRef.value?.refreshUpdate()
  }
  const refreshPlans = async () => {
    await planTableRef.value?.refreshUpdate()
  }
  const refreshDrills = async () => {
    await drillTableRef.value?.refreshUpdate()
  }
  const removePlan = async (row: Plan) => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除预案“${row.planName}”吗？`, '删除确认', { type: 'warning' })
      await deleteEmergencyPlan(row.id)
      await refreshPlans()
    } catch {
      /* cancelled */
    }
  }
  const removeDrill = async (row: Drill) => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除演练“${row.drillName}”吗？`, '删除确认', { type: 'warning' })
      await deleteEmergencyDrill(row.id)
      await refreshDrills()
    } catch {
      /* cancelled */
    }
  }
</script>

<style scoped lang="scss">
  .smis-accident-emergency {
    gap: 12px;
    min-width: 0;
  }

  .smis-accident-emergency__workspace {
    min-width: 0;
    padding: 0 16px 16px;
    overflow: hidden;
  }

  @media (width <= 900px) {
    .smis-accident-emergency__workspace {
      padding-inline: 10px;
    }
  }
</style>
