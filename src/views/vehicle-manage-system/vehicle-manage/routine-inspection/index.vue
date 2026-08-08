<template>
  <div class="routine-inspection-page art-full-height">
    <VehicleWorkspaceHeader
      eyebrow="DAILY SAFETY CHECK"
      title="车辆例行检查"
      description="记录出车前后与周期性检查结果、责任人员和处置方式，把安全隐患前置发现。"
      icon="ri:clipboard-line"
      :tags="[
        { label: '安全检查', type: 'primary' },
        { label: '责任可追溯', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无车辆例检记录',
        emptyDescription: '可新增检查记录，或调整车辆、检查类型、结果和时间后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <RoutineInspectionDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { storeToRefs } from 'pinia'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import {
    deleteVehicleRoutineInspection,
    deleteVehicleRoutineInspectionBatch,
    exportVehicleRoutineInspectionList,
    fetchVehicleRoutineInspectionList
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import RoutineInspectionDialog from './modules/routine-inspection-dialog.vue'
  import VehicleWorkspaceHeader, {
    type VehicleWorkspaceMetric
  } from '@/views/vehicle-manage-system/modules/vehicle-workspace-header.vue'

  defineOptions({ name: 'VehicleRoutineInspection' })

  const { confirmAction } = useArtFeedback()

  type RoutineInspection = Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionRecord
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: RoutineInspection) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<RoutineInspection>[]
  }

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const { getDictMap } = storeToRefs(useUserStore())
  const overview = reactive<{ total: number; rows: RoutineInspection[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<VehicleWorkspaceMetric[]>(() => [
    {
      label: '例检记录',
      value: overview.total,
      description: '当前筛选条件下的检查记录',
      icon: 'ri:clipboard-line'
    },
    {
      label: '本页责任信息完整',
      value: overview.rows.filter((row) => row.inspector && row.driverName).length,
      description: '检查人与驾驶员均已登记',
      icon: 'ri:team-line',
      tone: 'success'
    },
    {
      label: '本页责任信息待补',
      value: overview.rows.filter((row) => !row.inspector || !row.driverName).length,
      description: '至少缺少一位责任人员',
      icon: 'ri:user-warning-line',
      tone: 'warning'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    inspectionType: '',
    checkResult: '',
    inspectionTimeRange: [],
    createTimeRange: []
  })

  const dateRangeProps = {
    type: 'daterange',
    valueFormat: 'YYYY-MM-DD',
    startPlaceholder: '开始日期',
    endPlaceholder: '结束日期',
    class: '!w-full'
  }

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialSearch(),
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      {
        label: '例检类型',
        key: 'inspectionType',
        type: 'select',
        props: { options: getDictMap.value.vehicleRoutineInspectionType ?? [] }
      },
      {
        label: '检查结果',
        key: 'checkResult',
        type: 'select',
        props: { options: getDictMap.value.vehicleRoutineInspectionResult ?? [] }
      },
      { label: '例检时间', key: 'inspectionTimeRange', type: 'date', props: dateRangeProps },
      { label: '创建时间', key: 'createTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      { type: 'add', permission: 'VehicleRoutineInspection:Add', onClick: () => openDialog() },
      {
        type: 'export',
        permission: 'VehicleRoutineInspection:Export',
        exportFilename: '例检记录',
        exportSheetName: '例检记录',
        exportColumns: routineInspectionExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleRoutineInspectionList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        type: 'delete',
        permission: 'VehicleRoutineInspection:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条例检记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => row.id).filter(Boolean)
          await deleteVehicleRoutineInspectionBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 48, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'companyName', label: '所属公司', minWidth: 170 },
      { prop: 'plateNo', label: '车牌号', width: 108 },
      { prop: 'routineInspectionNo', label: '例检编号', minWidth: 160 },
      {
        prop: 'inspectionType',
        label: '例检类型',
        width: 112,
        dict: { code: 'vehicleRoutineInspectionType', display: 'auto' }
      },
      {
        prop: 'inspectionTime',
        label: '例检时间',
        minWidth: 170,
        formatter: (row) => formatWithDayjs(row.inspectionTime)
      },
      { prop: 'inspector', label: '检查人', width: 100 },
      { prop: 'driverName', label: '驾驶员', width: 100 },
      {
        prop: 'checkResult',
        label: '检查结果',
        width: 108,
        dict: { code: 'vehicleRoutineInspectionResult', display: 'auto' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehicleRoutineInspection:Edit"
              onClick={() => openDialog(row)}
            />
            <ArtButtonMore
              list={getMoreActions()}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ]
  })

  const routineInspectionExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'routineInspectionNo', title: '例检编号', required: true },
    { key: 'inspectionType', title: '例检类型' },
    { key: 'inspectionTime', title: '例检时间', required: true },
    { key: 'inspector', title: '检查人' },
    { key: 'driverName', title: '驾驶员' },
    { key: 'checkCondition', title: '检查情况' },
    { key: 'checkResult', title: '检查结果' },
    { key: 'handlingMethod', title: '处理方式' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchVehicleRoutineInspectionList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as RoutineInspection[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: RoutineInspection): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: RoutineInspection): void => {
    if (!row.id) return
    void router.push(`/vehicle-manage-system/vehicle-manage/routine-inspection-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line',
      auth: 'VehicleRoutineInspection:View'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleRoutineInspection:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: RoutineInspection): void => {
    if (item.key === 'view') {
      viewDetail(row)
      return
    }
    if (item.key === 'delete') void handleDelete(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: RoutineInspection): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除例检记录“${row.routineInspectionNo}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleRoutineInspection(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>

<style scoped lang="scss">
  .routine-inspection-page {
    gap: 12px;
    min-width: 0;
  }
</style>
