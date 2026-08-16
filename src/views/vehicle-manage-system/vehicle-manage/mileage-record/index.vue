<template>
  <div class="mileage-record-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="MILEAGE LEDGER"
      title="车辆里程"
      description="按行程沉淀车辆起止时间与里程数据，为维保周期、成本分析和车辆利用率提供依据。"
      icon="ri:speed-up-line"
      :tags="[
        { label: '行程自动沉淀', type: 'primary' },
        { label: '只读运营数据', type: 'info' }
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
        emptyText: '暂无车辆里程记录',
        emptyDescription: '可调整所属公司、车牌号或行驶时间范围后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { exportVehicleMileageList, fetchVehicleMileageList } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'

  defineOptions({ name: 'VehicleMileage' })

  type MileageRecord = Api.VehicleMgtSys.VehicleManage.VehicleMileageRecord
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehicleMileageSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<MileageRecord>[]
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const overview = reactive<{ total: number; rows: MileageRecord[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '里程记录',
      value: overview.total,
      description: '当前筛选条件下的行程数量',
      icon: 'ri:road-map-line'
    },
    {
      label: '本页累计行驶',
      value: `${overview.rows.reduce((sum, row) => sum + Number(row.runningMileage || 0), 0).toFixed(0)} km`,
      description: '当前页行驶里程合计',
      icon: 'ri:speed-up-line',
      tone: 'success'
    },
    {
      label: '本页未结束行程',
      value: overview.rows.filter((row) => !row.endTime).length,
      description: '尚未登记结束时间',
      icon: 'ri:timer-flash-line',
      tone: 'warning'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    drivingTimeRange: []
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
      { label: '行驶时间', key: 'drivingTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'export',
        permission: 'VehicleMileage:Export',
        exportFilename: '里程记录',
        exportSheetName: '里程记录',
        exportColumns: mileageExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleMileageList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 48, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'companyName', label: '所属公司', minWidth: 220 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      {
        prop: 'startTime',
        label: '开始时间',
        minWidth: 180,
        formatter: (row) => formatWithDayjs(row.startTime)
      },
      {
        prop: 'startMileage',
        label: '开始里程',
        width: 120,
        align: 'right',
        formatter: (row) => formatMileage(row.startMileage)
      },
      {
        prop: 'endMileage',
        label: '结束里程',
        width: 120,
        align: 'right',
        formatter: (row) => formatMileage(row.endMileage)
      },
      {
        prop: 'runningMileage',
        label: '行驶里程',
        width: 120,
        align: 'right',
        formatter: (row) => formatMileage(row.runningMileage)
      },
      {
        prop: 'endTime',
        label: '结束时间',
        minWidth: 180,
        formatter: (row) => formatWithDayjs(row.endTime)
      }
    ]
  })

  const mileageExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'startTime', title: '开始时间' },
    { key: 'startMileage', title: '开始里程' },
    { key: 'endTime', title: '结束时间' },
    { key: 'endMileage', title: '结束里程' },
    { key: 'runningMileage', title: '行驶里程' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchVehicleMileageList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as MileageRecord[]
    overview.total = response.total ?? rows.length
  }

  const formatMileage = (value?: number | null): string => {
    if (value === undefined || value === null) return '--'
    return `${Number(value).toFixed(2)} km`
  }
</script>

<style scoped lang="scss">
  .mileage-record-page {
    gap: 12px;
    min-width: 0;
  }
</style>
