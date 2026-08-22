<template>
  <div class="smis-risk-point-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="RISK CONTROL REGISTER"
      title="风险点管理"
      description="统一维护场所、区域和风险点责任边界，为危险源辨识、LEC 评估与后续巡检闭环提供主台账。"
      icon="ri:map-pin-warning-line"
      :tags="[
        { label: '双重预防机制', type: 'primary' },
        { label: '租户隔离', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <div class="smis-risk-point-page__actions">
          <ElButton v-auth="'SmisRiskPoint:Add'" plain @click="openSpaceDialog('site')">
            <ArtSvgIcon icon="ri:building-2-line" />
            新增场所
          </ElButton>
          <ElButton v-auth="'SmisRiskPoint:Add'" plain @click="openSpaceDialog('area')">
            <ArtSvgIcon icon="ri:layout-grid-line" />
            新增区域
          </ElButton>
          <BusinessTableWorkspaceActions :table="tableQueryRef" />
        </div>
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 84 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无风险点',
        emptyDescription: '请先建立场所和区域，再新增风险点；也可调整筛选条件后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <RiskPointDialog ref="dialogRef" @success="handleSaveSuccess" />
    <SpaceCreateDialog ref="spaceDialogRef" @success="handleSpaceCreated" />
    <RiskAssessmentDrawer ref="assessmentDrawerRef" @changed="handleAssessmentChanged" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElTag } from 'element-plus'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import {
    deleteRiskPoint,
    deleteRiskPointBatch,
    fetchAreaOptions,
    fetchRiskPointList,
    fetchSiteOptions
  } from '@/api/smis'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import RiskPointDialog from './modules/risk-point-dialog.vue'
  import SpaceCreateDialog from './modules/space-create-dialog.vue'
  import RiskAssessmentDrawer from './modules/risk-assessment-drawer.vue'

  defineOptions({ name: 'SmisRiskPoint' })

  type RiskPoint = Api.Smis.RiskControl.RiskPointRecord
  type SearchParams = Api.Smis.RiskControl.RiskPointSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type SpaceMode = 'site' | 'area'

  interface RiskPointDialogExpose {
    handleOpen: (row?: RiskPoint) => Promise<void>
  }

  interface SpaceDialogExpose {
    handleOpen: (mode: SpaceMode) => Promise<void>
  }

  interface AssessmentDrawerExpose {
    handleOpen: (row: RiskPoint) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<RiskPoint>[]
  }

  const { confirmAction } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<RiskPointDialogExpose>()
  const spaceDialogRef = ref<SpaceDialogExpose>()
  const assessmentDrawerRef = ref<AssessmentDrawerExpose>()
  const siteOptions = ref<Array<{ label: string; value: string }>>([])
  const allAreaOptions = ref<Array<{ label: string; value: string; siteId: string }>>([])
  const overview = reactive<{ total: number; rows: RiskPoint[] }>({ total: 0, rows: [] })

  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '风险点总数',
      value: overview.total,
      description: '当前筛选条件下的风险点',
      icon: 'ri:map-pin-2-line'
    },
    {
      label: '本页高等级风险',
      value: overview.rows.filter((row) =>
        ['major', 'critical'].includes(row.currentRiskLevel ?? '')
      ).length,
      description: '较大及重大风险需优先管控',
      icon: 'ri:alarm-warning-line',
      tone: 'danger'
    },
    {
      label: '本页待评估',
      value: overview.rows.filter((row) => !row.currentRiskLevel).length,
      description: '尚无生效评估的风险点',
      icon: 'ri:questionnaire-line',
      tone: 'warning'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    keyword: '',
    siteId: '',
    areaId: '',
    status: '',
    currentRiskLevel: '',
    createTimeRange: []
  })

  const filteredAreaOptions = computed(() =>
    table.searchQuery.siteId
      ? allAreaOptions.value.filter((option) => option.siteId === table.searchQuery.siteId)
      : allAreaOptions.value
  )

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialSearch(),
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { placeholder: '编号、名称、活动或类别' }
      },
      {
        label: '所属场所',
        key: 'siteId',
        type: 'select',
        props: { options: siteOptions.value, filterable: true }
      },
      {
        label: '所属区域',
        key: 'areaId',
        type: 'select',
        props: { options: filteredAreaOptions.value, filterable: true }
      },
      {
        label: '风险等级',
        key: 'currentRiskLevel',
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
        label: '状态',
        key: 'status',
        type: 'select',
        props: {
          options: [
            { label: '启用', value: 'active' },
            { label: '停用', value: 'inactive' },
            { label: '已归档', value: 'archived' }
          ]
        }
      },
      {
        label: '创建时间',
        key: 'createTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          class: '!w-full'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        label: '新增风险点',
        permission: 'SmisRiskPoint:Add',
        onClick: () => openDialog()
      },
      {
        type: 'delete',
        permission: 'SmisRiskPoint:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 个风险点吗？已关联危险源或评估的风险点不能删除。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => String(row.id)).filter(Boolean)
          await deleteRiskPointBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 48, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'riskPointNo', label: '风险点编号', width: 142 },
      { prop: 'riskPointName', label: '风险点名称', minWidth: 180 },
      {
        prop: 'currentRiskLevel',
        label: '当前等级',
        width: 108,
        formatter: (row) =>
          row.currentRiskLevel ? (
            <ArtDictDisplay dictCode="smisRiskLevel" value={row.currentRiskLevel} display="tag" />
          ) : (
            <ElTag type="info">待评估</ElTag>
          )
      },
      { prop: 'site.siteName', label: '场所', minWidth: 150 },
      { prop: 'area.areaName', label: '区域', minWidth: 140 },
      { prop: 'organization.organizationName', label: '责任组织', minWidth: 150 },
      {
        prop: 'responsibleUser',
        label: '责任人',
        width: 110,
        formatter: (row) =>
          row.responsibleUser?.nickName ||
          row.responsibleUser?.userName ||
          row.responsibleUser?.userEmail ||
          '--'
      },
      { prop: 'inspectionFrequency', label: '检查频次', width: 110 },
      {
        prop: 'status',
        label: '状态',
        width: 94,
        dict: { code: 'smisRiskPointStatus', display: 'auto' }
      },
      {
        prop: 'updateTime',
        label: '更新时间',
        minWidth: 168,
        formatter: (row) => formatWithDayjs(row.updateTime)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 150,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="view"
              label="查看风险档案"
              permission="SmisRiskPoint:View"
              onClick={() => openAssessmentDrawer(row)}
            />
            <ArtButtonTable
              type="edit"
              permission="SmisRiskPoint:Edit"
              onClick={() => openDialog(row)}
            />
            <ArtButtonTable
              type="delete"
              permission="SmisRiskPoint:Delete"
              onClick={() => void handleDelete(row)}
            />
          </div>
        )
      }
    ]
  })

  watch(
    () => table.searchQuery.siteId,
    (siteId, previousSiteId) => {
      if (!previousSiteId || siteId === previousSiteId) return
      if (!filteredAreaOptions.value.some((option) => option.value === table.searchQuery.areaId)) {
        table.searchQuery.areaId = ''
      }
    }
  )

  const loadSpaceOptions = async (): Promise<void> => {
    const [sites, areas] = await Promise.all([fetchSiteOptions(), fetchAreaOptions()])
    siteOptions.value = (sites.data ?? []).map((site) => ({
      label: `${site.siteName}（${site.siteCode}）`,
      value: site.id!
    }))
    allAreaOptions.value = (areas.data ?? []).map((area) => ({
      label: `${area.areaName}（${area.areaCode}）`,
      value: area.id!,
      siteId: area.siteId
    }))
  }

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchRiskPointList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as RiskPoint[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: RiskPoint): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openSpaceDialog = (mode: SpaceMode): void => {
    void spaceDialogRef.value?.handleOpen(mode)
  }

  const openAssessmentDrawer = (row: RiskPoint): void => {
    void assessmentDrawerRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleSpaceCreated = async (): Promise<void> => {
    await loadSpaceOptions()
  }

  const handleAssessmentChanged = (): void => {
    void tableQueryRef.value?.refreshUpdate()
  }

  const handleDelete = async (row: RiskPoint): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除风险点“${row.riskPointName}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteRiskPoint(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  onMounted(() => {
    void loadSpaceOptions()
  })
</script>

<style scoped lang="scss">
  .smis-risk-point-page {
    gap: 12px;
    min-width: 0;

    &__actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      justify-content: flex-end;
    }
  }

  @media (width <= 900px) {
    .smis-risk-point-page__actions {
      justify-content: flex-start;
    }
  }
</style>
