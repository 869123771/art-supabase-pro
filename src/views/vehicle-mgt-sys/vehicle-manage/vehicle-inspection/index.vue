<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <VehicleInspectionDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import {
    deleteVehicleInspection,
    deleteVehicleInspectionBatch,
    exportVehicleInspectionList,
    fetchVehicleInspectionList
  } from '@/api/vehicle-mgt-sys'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import VehicleInspectionDialog from './modules/vehicle-inspection-dialog.vue'

  defineOptions({ name: 'VehicleInspection' })

  type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehicleInspectionSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: VehicleInspection) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<VehicleInspection>[]
  }

  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()

  const dateRangeProps = {
    type: 'daterange',
    valueFormat: 'YYYY-MM-DD',
    startPlaceholder: '开始日期',
    endPlaceholder: '结束日期',
    class: '!w-full'
  }

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      companyName: '',
      plateNo: '',
      inspectionNo: '',
      expireDateRange: [],
      createTimeRange: []
    },
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      { label: '年检号', key: 'inspectionNo', type: 'input' },
      { label: '到期日期', key: 'expireDateRange', type: 'date', props: dateRangeProps },
      { label: '创建时间', key: 'createTimeRange', type: 'date', props: dateRangeProps }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        permission: 'VehicleInspection:Add',
        onClick: () => openDialog()
      },
      {
        type: 'export',
        permission: 'VehicleInspection:Export',
        exportFilename: '车辆年检',
        exportSheetName: '车辆年检',
        exportColumns: inspectionExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportVehicleInspectionList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        type: 'delete',
        permission: 'VehicleInspection:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条车辆年检记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows.map((row) => row.id).filter(Boolean)
          await deleteVehicleInspectionBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: () => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      { prop: 'inspectionDate', label: '年检日期', width: 120 },
      { prop: 'inspectionNo', label: '年检号', minWidth: 150 },
      {
        prop: 'inspectionAmount',
        label: '年检金额',
        width: 120,
        formatter: (row) => formatMoney(row.inspectionAmount)
      },
      { prop: 'vehicleOffice', label: '车管所', minWidth: 140 },
      { prop: 'expireDate', label: '到期日期', width: 120 },
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
        width: 104,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehicleInspection:Edit"
              onClick={() => openDialog(row)}
            />
            <ArtButtonTable
              type="delete"
              permission="VehicleInspection:Delete"
              onClick={() => handleDelete(row)}
            />
          </div>
        )
      }
    ]
  })

  const inspectionExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'inspectionDate', title: '年检日期' },
    { key: 'inspectionNo', title: '年检号', required: true },
    { key: 'inspectionAmount', title: '年检金额' },
    { key: 'vehicleOffice', title: '车管所' },
    { key: 'expireDate', title: '到期日期' },
    { key: 'compulsoryPolicyNo', title: '交强险保单号' },
    { key: 'compulsoryCompanyName', title: '交强险保险公司' },
    { key: 'compulsoryInsureDate', title: '交强险投保日期' },
    { key: 'compulsoryPremium', title: '交强险投保金额' },
    { key: 'compulsoryExpireDate', title: '交强险到期日期' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehicleInspectionList({ ...params, from, to })
  }

  const openDialog = (row?: VehicleInspection): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: VehicleInspection): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(`确定删除车辆“${row.plateNo}”的年检记录吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleInspection(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const formatMoney = (value?: number | null): string => {
    if (value === undefined || value === null) return '--'
    return `${Number(value).toFixed(2)} 元`
  }

  onErrorCaptured((error) => {
    ElMessage.error(error instanceof Error ? error.message : '车辆年检页面异常')
    return false
  })
</script>
