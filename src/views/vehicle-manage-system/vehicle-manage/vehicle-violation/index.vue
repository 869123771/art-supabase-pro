<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 100 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
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
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    exportVehicleViolationList,
    fetchVehicleViolationList
  } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'

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
