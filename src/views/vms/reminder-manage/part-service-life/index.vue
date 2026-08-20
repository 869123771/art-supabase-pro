<template>
  <div class="art-full-height">
    <VehicleReminderRiskOverview
      title="配件寿命"
      description="提前识别达到日期或里程阈值的配件，为备件采购与更换排期留出窗口。"
      :filters="tableState.searchQuery"
      :fetch-fn="fetchVehicleReminderPartServiceLifeRiskOverview"
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
    fetchVehicleReminderPartServiceLifeList,
    fetchVehicleReminderPartServiceLifeRiskOverview
  } from '@/api/vms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { isNil } from 'lodash-es'
  import {
    companySearchItem,
    createReminderWorkOrderColumns,
    formatDate,
    formatMileage,
    renderRemainingDays,
    renderReminderStatus
  } from '../modules/reminder-table'
  import VehicleReminderWorkOrderDrawer from '../modules/vehicle-reminder-work-order-drawer.vue'
  import VehicleReminderRiskOverview from '../modules/vehicle-reminder-risk-overview.vue'
  import { getReminderRiskRowClassName } from '../modules/reminder-risk'

  defineOptions({ name: 'VehiclePartServiceLife' })

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
      sourceType: 'part'
      sourceLabel: string
    }) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const workOrderDrawerRef = ref<WorkOrderDrawerExpose>()
  const { getDictMap } = storeToRefs(useUserStore())

  const tableState = reactive<TableState>({
    showSearchBar: false,
    searchQuery: {
      companyName: '',
      plateNo: '',
      expired: undefined
    }
  })

  const tableConfig = computed<TableConfig>(() => {
    const commonBooleanOptions = getDictMap.value.commonBoolean

    return {
      searchItems: [
        companySearchItem,
        { label: '车牌号', key: 'plateNo', type: 'input' },
        {
          label: '是否到期',
          key: 'expired',
          type: 'select',
          props: {
            options: (isNil(commonBooleanOptions) ? [] : commonBooleanOptions).map((item) => ({
              ...item,
              value: item.value === 'true'
            }))
          }
        }
      ],
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
          prop: 'partType',
          label: '零部件类型',
          width: 125,
          dict: { code: 'vehiclePartType', display: 'auto' }
        },
        { prop: 'partName', label: '零部件名称', minWidth: 170 },
        { prop: 'categoryName', label: '类别', minWidth: 130 },
        { prop: 'brand', label: '品牌', width: 110 },
        { prop: 'model', label: '型号', minWidth: 130 },
        { prop: 'rfidTag', label: 'RFID标签', minWidth: 150 },
        {
          prop: 'usedMileage',
          label: '已使用里程（公里）',
          width: 175,
          formatter: (row) => formatMileage(row.usedMileage)
        },
        {
          prop: 'serviceMileage',
          label: '可使用里程（公里）',
          width: 175,
          formatter: (row) => formatMileage(row.serviceMileage)
        },
        {
          prop: 'expireDate',
          label: '零部件使用到期日期',
          width: 190,
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
          view: 'VehiclePartServiceLife:View',
          createWorkOrder: 'VehiclePartServiceLife:CreateWorkOrder',
          transitionWorkOrder: 'VehiclePartServiceLife:TransitionWorkOrder'
        })
      ]
    }
  })

  function openWorkOrder(row: ReminderRow): void {
    void workOrderDrawerRef.value?.handleOpen({
      row,
      sourceType: 'part',
      sourceLabel: '零部件寿命'
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
    return await fetchVehicleReminderPartServiceLifeList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      expired: params.expired,
      riskBand: params.riskBand,
      from,
      to
    })
  }
</script>
