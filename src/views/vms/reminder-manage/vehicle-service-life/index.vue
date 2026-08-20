<template>
  <div class="art-full-height">
    <VehicleReminderRiskOverview
      title="车辆寿命"
      description="汇总车辆使用年限风险，帮助提前规划检修、替换与运力调整。"
      :filters="tableState.searchQuery"
      :fetch-fn="fetchVehicleReminderVehicleServiceLifeRiskOverview"
      @select="handleRiskBandChange"
    />
    <ArtTableQuery
      ref="tableQueryRef"
      focusable
      v-model="tableState.searchQuery"
      v-model:show-search-bar="tableState.showSearchBar"
      :search-items="tableConfig.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="tableConfig.columnsFactory"
      :search-bar-props="tableConfig.searchBarProps"
      :table-props="tableConfig.tableProps"
    />
    <VehicleReminderWorkOrderDrawer ref="workOrderDrawerRef" @success="handleWorkOrderSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    fetchVehicleReminderVehicleServiceLifeList,
    fetchVehicleReminderVehicleServiceLifeRiskOverview
  } from '@/api/vms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import {
    createReminderWorkOrderColumns,
    formatDate,
    futureReminderSearchItems,
    renderRemainingDays,
    renderReminderStatus
  } from '../modules/reminder-table'
  import VehicleReminderWorkOrderDrawer from '../modules/vehicle-reminder-work-order-drawer.vue'
  import VehicleReminderRiskOverview from '../modules/vehicle-reminder-risk-overview.vue'
  import { getReminderRiskRowClassName } from '../modules/reminder-risk'

  defineOptions({ name: 'VehicleServiceLife' })

  type ReminderRow = Api.Vms.ReminderManage.VehicleReminderRow
  type ReminderSearchParams = Api.Vms.ReminderManage.VehicleReminderSearchParams
  type RiskBand = Api.Vms.ReminderManage.VehicleReminderRiskBand
  type ReminderTableParams = ReminderSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableState {
    showSearchBar: boolean
    searchQuery: ReminderSearchParams
  }

  interface TableConfig {
    searchItems: SearchFormItem[]
    searchBarProps: { span: number; labelWidth: number; showExpand: boolean }
    tableProps: {
      rowKey: string
      tableLayout: 'fixed'
      rowClassName: typeof getReminderRiskRowClassName
    }
    columnsFactory: () => ColumnOption<ReminderRow>[]
  }

  interface WorkOrderDrawerExpose {
    handleOpen: (data: {
      row: ReminderRow
      sourceType: 'vehicle'
      sourceLabel: string
    }) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const workOrderDrawerRef = ref<WorkOrderDrawerExpose>()

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
    tableProps: {
      rowKey: 'id',
      tableLayout: 'fixed',
      rowClassName: getReminderRiskRowClassName
    },
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
      },
      ...createReminderWorkOrderColumns(openWorkOrder, {
        view: 'VehicleServiceLife:View',
        createWorkOrder: 'VehicleServiceLife:CreateWorkOrder',
        transitionWorkOrder: 'VehicleServiceLife:TransitionWorkOrder'
      })
    ]
  }

  function openWorkOrder(row: ReminderRow): void {
    void workOrderDrawerRef.value?.handleOpen({
      row,
      sourceType: 'vehicle',
      sourceLabel: '车辆使用年限'
    })
  }

  function handleWorkOrderSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  function handleRiskBandChange(riskBand: RiskBand): void {
    tableState.searchQuery.riskBand = riskBand === 'all' ? undefined : riskBand
    void nextTick(() => tableQueryRef.value?.getData())
  }

  const fetchTableData = async (params: ReminderTableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchVehicleReminderVehicleServiceLifeList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      reminderDays: params.reminderDays,
      riskBand: params.riskBand,
      from,
      to
    })
  }
</script>
