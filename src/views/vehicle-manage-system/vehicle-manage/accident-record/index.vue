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

    <AccidentRecordDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessageBox } from 'element-plus'
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
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import {
    deleteVehicleAccident,
    deleteVehicleAccidentBatch,
    exportVehicleAccidentList,
    fetchVehicleAccidentList
  } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import AccidentRecordDialog from './modules/accident-record-dialog.vue'

  defineOptions({ name: 'VehicleAccident' })

  type AccidentRecord = Api.VehicleMgtSys.VehicleManage.VehicleAccidentRecord
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehicleAccidentSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: AccidentRecord) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<AccidentRecord>[]
  }

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const { getDictMap } = storeToRefs(useUserStore())

  const createInitialSearch = (): SearchParams => ({
    companyName: '',
    plateNo: '',
    driverName: '',
    processed: undefined,
    dataSource: '',
    accidentTimeRange: [],
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
      { label: '驾驶员', key: 'driverName', type: 'input' },
      {
        label: '处理状态',
        key: 'processed',
        type: 'select',
        props: { options: getProcessedDictOptions() }
      },
      {
        label: '数据来源',
        key: 'dataSource',
        type: 'select',
        props: { options: getDictMap.value.vehicleAccidentDataSource ?? [] }
      },
      { label: '事故时间', key: 'accidentTimeRange', type: 'date', props: dateRangeProps },
      { label: '创建时间', key: 'createTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        permission: 'VehicleAccident:Add',
        onClick: () => openDialog()
      },
      {
        type: 'export',
        permission: 'VehicleAccident:Export',
        exportFilename: '事故记录',
        exportSheetName: '事故记录',
        exportColumns: accidentExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleAccidentList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        type: 'delete',
        permission: 'VehicleAccident:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条事故记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => row.id).filter(Boolean)
          await deleteVehicleAccidentBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      { prop: 'driverName', label: '驾驶员', width: 120 },
      {
        prop: 'accidentTime',
        label: '事故时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.accidentTime)
      },
      { prop: 'accidentLocation', label: '事故地点', minWidth: 180 },
      { prop: 'accidentSummary', label: '事故概述', minWidth: 220 },
      { prop: 'damageLevel', label: '事故等级', width: 120 },
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
      {
        prop: 'dataSource',
        label: '数据来源',
        width: 110,
        dict: { code: 'vehicleAccidentDataSource', display: 'auto' }
      },
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
              type="view"
              permission="VehicleAccident:View"
              onClick={() => viewDetail(row)}
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

  const accidentExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'driverName', title: '驾驶员' },
    { key: 'accidentTime', title: '事故时间', required: true },
    { key: 'accidentLocation', title: '事故地点' },
    { key: 'accidentSummary', title: '事故概述', required: true },
    { key: 'damageLevel', title: '事故等级' },
    { key: 'responsibilityType', title: '责任类型' },
    { key: 'economicLoss', title: '经济损失' },
    { key: 'processed', title: '处理状态' },
    { key: 'dataSource', title: '数据来源' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchVehicleAccidentList({ ...params, from, to })
  }

  const openDialog = (row?: AccidentRecord): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: AccidentRecord): void => {
    if (!row.id) return
    void router.push(`/vehicle-manage-system/vehicle-manage/accident-record-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    { key: 'edit', label: '编辑', icon: 'ri:edit-2-line', auth: 'VehicleAccident:Edit' },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleAccident:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: AccidentRecord): void => {
    if (item.key === 'edit') {
      openDialog(row)
      return
    }
    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: AccidentRecord): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(`确定删除车辆“${row.plateNo}”的事故记录吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleAccident(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const getProcessedDictOptions = () =>
    (getDictMap.value.vehicleRecordProcessed ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
</script>
