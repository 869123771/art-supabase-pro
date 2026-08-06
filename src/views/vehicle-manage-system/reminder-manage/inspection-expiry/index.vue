<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
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
  import { fetchVehicleReminderInspectionExpiryList } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import {
    createReminderWorkOrderColumns,
    formatDate,
    futureReminderSearchItems,
    renderRemainingDays,
    renderReminderStatus
  } from '../modules/reminder-table'
  import VehicleReminderWorkOrderDrawer from '../modules/vehicle-reminder-work-order-drawer.vue'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'VehicleInspectionExpiry' })

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

  interface WorkOrderDrawerExpose {
    handleOpen: (data: {
      row: ReminderRow
      sourceType: 'inspection'
      sourceLabel: string
    }) => Promise<void>
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const workOrderDrawerRef = ref<WorkOrderDrawerExpose>()
  const { getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
  const canManageWorkOrder = computed(
    () =>
      isPlatformSuper.value ||
      (getUserInfo.value.userRoles ?? []).some((role) =>
        ['R_ADMIN', 'YQ_ADMIN', 'R_REGISTER'].includes(role)
      )
  )

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
        prop: 'expireDate',
        label: '年检到期日期',
        minWidth: 160,
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
      ...createReminderWorkOrderColumns(openWorkOrder, () => canManageWorkOrder.value)
    ]
  }

  function openWorkOrder(row: ReminderRow): void {
    void workOrderDrawerRef.value?.handleOpen({
      row,
      sourceType: 'inspection',
      sourceLabel: '年检到期'
    })
  }

  function handleWorkOrderSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  const fetchTableData = async (params: ReminderTableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchVehicleReminderInspectionExpiryList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      reminderDays: params.reminderDays,
      from,
      to
    })
  }
</script>
