<template>
  <div class="art-full-height">
    <ArtTableQuery
      v-model="tableState.searchQuery"
      v-model:show-search-bar="tableState.showSearchBar"
      :search-items="tableConfig.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="tableConfig.columnsFactory"
      :search-bar-props="tableConfig.searchBarProps"
      :table-props="tableConfig.tableProps"
    />
  </div>
</template>

<script setup lang="tsx">
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleReminderVehicleServiceLifeList } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import {
    formatDate,
    futureReminderSearchItems,
    renderRemainingDays,
    renderReminderStatus
  } from '../modules/reminder-table'

  defineOptions({ name: 'VehicleServiceLife' })

  type ReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow
  type ReminderSearchParams = Api.VehicleMgtSys.ReminderManage.VehicleReminderSearchParams
  type ReminderTableParams = ReminderSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableState {
    showSearchBar: boolean
    searchQuery: ReminderSearchParams
  }

  interface TableConfig {
    searchItems: SearchFormItem[]
    searchBarProps: { span: number; labelWidth: number; showExpand: boolean }
    tableProps: { rowKey: string; tableLayout: 'fixed' }
    columnsFactory: () => ColumnOption<ReminderRow>[]
  }

  const tableState = reactive<TableState>({
    showSearchBar: false,
    searchQuery: {
      companyName: '',
      plateNo: '',
      reminderDays: undefined
    }
  })

  const tableConfig: TableConfig = {
    searchItems: futureReminderSearchItems,
    searchBarProps: { span: 6, labelWidth: 100, showExpand: false },
    tableProps: { rowKey: 'id', tableLayout: 'fixed' },
    columnsFactory: () => [
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 170 },
      { prop: 'plateNo', label: '车牌号', width: 130 },
      {
        prop: 'startUseDate',
        label: '启用日期',
        width: 130,
        formatter: (row) => formatDate(row.startUseDate)
      },
      { prop: 'serviceYears', label: '使用年限（年）', width: 135 },
      {
        prop: 'expireDate',
        label: '车辆使用到期日期',
        minWidth: 170,
        formatter: (row) => formatDate(row.expireDate)
      },
      {
        prop: 'expired',
        label: '状态',
        width: 100,
        formatter: (row) => renderReminderStatus(row)
      },
      {
        prop: 'remainingDays',
        label: '到期提醒',
        minWidth: 130,
        sortable: true,
        formatter: (row) => renderRemainingDays(row.remainingDays)
      }
    ]
  }

  const fetchTableData = async (params: ReminderTableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchVehicleReminderVehicleServiceLifeList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      reminderDays: params.reminderDays,
      from,
      to
    })
  }
</script>
