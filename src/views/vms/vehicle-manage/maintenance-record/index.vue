<template>
  <div class="maintenance-record-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="MAINTENANCE CONTROL"
      title="维修保养记录"
      description="统一跟踪车辆维修、保养、工期、费用与承修机构，沉淀完整的车辆健康履历。"
      icon="ri:tools-line"
      :tags="[
        { label: '维保闭环', type: 'primary' },
        { label: '成本可追踪', type: 'info' }
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
        emptyText: '暂无维修保养记录',
        emptyDescription: '可新增维保记录，或调整车辆、维修单号、类型和创建时间后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <MaintenanceRecordDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { isNil } from 'lodash-es'
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
    deleteVehicleMaintenance,
    deleteVehicleMaintenanceBatch,
    exportVehicleMaintenanceList,
    fetchVehicleMaintenanceList
  } from '@/api/vms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import MaintenanceRecordDialog from './modules/maintenance-record-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'

  defineOptions({ name: 'VehicleMaintenance' })

  const { confirmAction } = useArtFeedback()

  type MaintenanceRecord = Api.Vms.VehicleManage.VehicleMaintenanceRecord
  type SearchParams = Api.Vms.VehicleManage.VehicleMaintenanceSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: MaintenanceRecord) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<MaintenanceRecord>[]
  }

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const { getDictMap } = storeToRefs(useUserStore())
  const overview = reactive<{ total: number; rows: MaintenanceRecord[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '维保记录',
      value: overview.total,
      description: '当前筛选条件下的维修保养记录',
      icon: 'ri:file-list-3-line'
    },
    {
      label: '本页已完工',
      value: overview.rows.filter((row) => row.endTime).length,
      description: '已登记结束时间',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    },
    {
      label: '本页费用待核',
      value: overview.rows.filter((row) => isNil(row.costAmount)).length,
      description: '尚未登记维保费用',
      icon: 'ri:money-cny-circle-line',
      tone: 'warning'
    }
  ])

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    maintenanceNo: '',
    maintenanceType: '',
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
      { label: '维修单号', key: 'maintenanceNo', type: 'input' },
      {
        label: '维修类型',
        key: 'maintenanceType',
        type: 'select',
        props: { options: getDictMap.value.vehicleMaintenanceType ?? [] }
      },
      { label: '创建时间', key: 'createTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      { type: 'add', permission: 'VehicleMaintenance:Add', onClick: () => openDialog() },
      {
        type: 'export',
        permission: 'VehicleMaintenance:Export',
        exportFilename: '维修保养记录',
        exportSheetName: '维修保养记录',
        exportColumns: maintenanceExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleMaintenanceList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        type: 'delete',
        permission: 'VehicleMaintenance:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条维修保养记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => row.id).filter(Boolean)
          await deleteVehicleMaintenanceBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      { prop: 'maintenanceNo', label: '维修单号', minWidth: 150 },
      {
        prop: 'maintenanceType',
        label: '维修类型',
        width: 110,
        dict: { code: 'vehicleMaintenanceType', display: 'auto' }
      },
      { prop: 'initiator', label: '发起人', width: 120 },
      {
        prop: 'startTime',
        label: '开始时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.startTime)
      },
      {
        prop: 'endTime',
        label: '结束时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.endTime)
      },
      {
        prop: 'costAmount',
        label: '费用金额',
        width: 120,
        align: 'right',
        formatter: (row) => formatMoney(row.costAmount)
      },
      { prop: 'workshop', label: '维修厂', minWidth: 160 },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.createTime)
      },
      { prop: 'createBy', label: '创建人', width: 130 },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehicleMaintenance:Edit"
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

  const maintenanceExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'maintenanceNo', title: '维修单号', required: true },
    { key: 'maintenanceType', title: '维修类型' },
    { key: 'initiator', title: '发起人' },
    { key: 'startTime', title: '开始时间' },
    { key: 'endTime', title: '结束时间' },
    { key: 'costAmount', title: '费用金额' },
    { key: 'workshop', title: '维修厂' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchVehicleMaintenanceList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as MaintenanceRecord[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: MaintenanceRecord): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: MaintenanceRecord): void => {
    if (!row.id) return
    void router.push(`/vms/vehicle-manage/maintenance-record-detail/${row.id}`)
  }
  const getMoreActions = (): ButtonMoreItem[] => [
    { key: 'view', label: '查看', icon: 'ri:eye-line', auth: 'VehicleMaintenance:View' },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleMaintenance:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: MaintenanceRecord): void => {
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

  const handleDelete = async (row: MaintenanceRecord): Promise<void> => {
    if (!row.id) return
    try {
      await confirmAction(`确定删除维修单“${row.maintenanceNo}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleMaintenance(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const formatMoney = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${Number(value).toFixed(2)} 元`
  }
</script>

<style scoped lang="scss">
  .maintenance-record-page {
    gap: 12px;
    min-width: 0;
  }
</style>
