<template>
  <div class="vehicle-violation-page art-full-height">
    <VehicleWorkspaceHeader
      eyebrow="TRAFFIC COMPLIANCE"
      title="车辆违章"
      description="汇总车辆违章行为、扣分、罚款与处理进度，帮助车队及时闭环交通合规风险。"
      icon="ri:traffic-light-line"
      :tags="[
        { label: '交通合规', type: 'primary' },
        { label: '只读业务台账', type: 'info' }
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
      :search-bar-props="{ span: 6, labelWidth: 100 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无车辆违章记录',
        emptyDescription: '可调整车辆、驾驶员、违章行为、处理状态和时间后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { isNil } from 'lodash-es'
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    exportVehicleViolationList,
    fetchVehicleViolationList
  } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import VehicleWorkspaceHeader, {
    type VehicleWorkspaceMetric
  } from '@/views/vehicle-manage-system/modules/vehicle-workspace-header.vue'

  defineOptions({ name: 'VehicleViolation' })

  type ViolationRecord = Api.VehicleMgtSys.VehicleManage.VehicleViolationRecord
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehicleViolationSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<ViolationRecord>[]
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const { getDictMap } = storeToRefs(useUserStore())
  const overview = reactive<{ total: number; rows: ViolationRecord[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<VehicleWorkspaceMetric[]>(() => [
    {
      label: '违章记录',
      value: overview.total,
      description: '当前筛选条件下的违章数量',
      icon: 'ri:file-list-3-line'
    },
    {
      label: '本页已处理',
      value: overview.rows.filter((row) => row.processed).length,
      description: '已完成违章处置',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      label: '本页待处理',
      value: overview.rows.filter((row) => !row.processed).length,
      description: '需要及时处理的违章',
      icon: 'ri:alarm-warning-line',
      tone: 'danger'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    driverName: '',
    violationBehavior: '',
    processed: undefined,
    violationTimeRange: []
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
      { label: '驾驶员', key: 'driverName', type: 'input' },
      { label: '违章行为', key: 'violationBehavior', type: 'input' },
      {
        label: '处理状态',
        key: 'processed',
        type: 'select',
        props: { options: getProcessedDictOptions() }
      },
      { label: '违章时间', key: 'violationTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'export',
        permission: 'VehicleViolation:Export',
        exportFilename: '车辆违章记录',
        exportSheetName: '车辆违章记录',
        exportColumns: violationExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleViolationList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      { prop: 'driverName', label: '驾驶员', width: 120 },
      { prop: 'violationBehavior', label: '违章行为', minWidth: 180 },
      {
        prop: 'violationTime',
        label: '违章时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.violationTime)
      },
      { prop: 'violationLocation', label: '违章地点', minWidth: 180 },
      { prop: 'penaltyPoints', label: '扣分', width: 90, align: 'right' },
      {
        prop: 'fineAmount',
        label: '罚款金额',
        width: 120,
        align: 'right',
        formatter: (row) => formatMoney(row.fineAmount)
      },
      {
        prop: 'processed',
        label: '处理状态',
        width: 110,
        dict: {
          code: 'vehicleRecordProcessed',
          display: 'auto',
          value: (row) => String(row.processed)
        }
      },
      { prop: 'createBy', label: '创建人', width: 130 }
    ]
  })

  const violationExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'driverName', title: '驾驶员' },
    { key: 'violationBehavior', title: '违章行为', required: true },
    { key: 'violationTime', title: '违章时间', required: true },
    { key: 'violationLocation', title: '违章地点' },
    { key: 'penaltyPoints', title: '扣分' },
    { key: 'fineAmount', title: '罚款金额' },
    { key: 'processed', title: '处理状态' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehicleViolationList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as ViolationRecord[]
    overview.total = response.total ?? rows.length
  }

  const getProcessedDictOptions = () =>
    (getDictMap.value.vehicleRecordProcessed ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))

  const formatMoney = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${Number(value).toFixed(2)} 元`
  }
</script>

<style scoped lang="scss">
  .vehicle-violation-page {
    gap: 12px;
    min-width: 0;
  }
</style>
