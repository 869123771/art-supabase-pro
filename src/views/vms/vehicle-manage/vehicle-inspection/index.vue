<template>
  <div class="vehicle-inspection-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="REGULATORY INSPECTION"
      title="车辆年检"
      description="统一维护年检编号、检测机构、费用与有效期，确保车辆持续满足上路合规要求。"
      icon="ri:file-search-line"
      :tags="[
        { label: '年检合规', type: 'primary' },
        { label: '有效期管理', type: 'info' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无车辆年检记录',
        emptyDescription: '可新增年检记录，或调整车辆、年检号和到期日期后重新查询。'
      }"
      :on-success="handleTableSuccess"
      focusable
    />

    <VehicleInspectionDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessage } from 'element-plus'
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
    deleteVehicleInspection,
    deleteVehicleInspectionBatch,
    exportVehicleInspectionList,
    fetchVehicleInspectionList
  } from '@/api/vms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import VehicleInspectionDialog from './modules/vehicle-inspection-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'

  defineOptions({ name: 'VehicleInspection' })

  const { confirmAction } = useArtFeedback()

  type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
  type SearchParams = Api.Vms.VehicleManage.VehicleInspectionSearchParams
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

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const overview = reactive<{ total: number; rows: VehicleInspection[] }>({ total: 0, rows: [] })
  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '年检记录',
      value: overview.total,
      description: '当前筛选条件下的记录总数',
      icon: 'ri:file-list-3-line'
    },
    {
      label: '本页信息完整',
      value: overview.rows.filter((row) => row.inspectionNo && row.expireDate).length,
      description: '年检号与到期日均已维护',
      icon: 'ri:file-check-line',
      tone: 'success'
    },
    {
      label: '本页有效期待补',
      value: overview.rows.filter((row) => !row.expireDate).length,
      description: '缺少年检到期日期',
      icon: 'ri:calendar-close-line',
      tone: 'warning'
    }
  ])

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
      { type: 'selection', width: 48, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 64 },
      { prop: 'companyName', label: '所属公司', minWidth: 160 },
      { prop: 'plateNo', label: '车牌号', width: 108 },
      { prop: 'inspectionDate', label: '年检日期', width: 108 },
      { prop: 'inspectionNo', label: '年检号', minWidth: 150 },
      {
        prop: 'inspectionAmount',
        label: '年检金额',
        width: 110,
        formatter: (row) => formatMoney(row.inspectionAmount)
      },
      { prop: 'vehicleOffice', label: '车管所', minWidth: 140 },
      { prop: 'expireDate', label: '到期日期', width: 108 },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 150,
        formatter: (row) => formatWithDayjs(row.createTime)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehicleInspection:Edit"
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

  const inspectionExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'inspectionDate', title: '年检日期' },
    { key: 'inspectionNo', title: '年检号', required: true },
    { key: 'inspectionAmount', title: '年检金额' },
    { key: 'vehicleOffice', title: '车管所' },
    { key: 'expireDate', title: '到期日期' },
    { key: 'remark', title: '备注' }
  ]

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehicleInspectionList({ ...params, from, to })
  }

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as VehicleInspection[]
    overview.total = response.total ?? rows.length
  }

  const openDialog = (row?: VehicleInspection): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: VehicleInspection): void => {
    if (!row.id) return
    void router.push(`/vms/vehicle-manage/vehicle-inspection-detail/${row.id}`)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'detail',
      label: '详情',
      icon: 'ri:eye-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleInspection:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: VehicleInspection): void => {
    if (item.key === 'detail') {
      viewDetail(row)
      return
    }
    if (item.key === 'delete') void handleDelete(row)
  }

  const handleDelete = async (row: VehicleInspection): Promise<void> => {
    if (!row.id) return

    try {
      await confirmAction(`确定删除车辆“${row.plateNo}”的年检记录吗？`, '删除确认', {
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
    ElMessage.error(getFriendlySupabaseErrorMessage(error, '车辆年检页面异常'))
    return false
  })
</script>

<style scoped lang="scss">
  .vehicle-inspection-page {
    gap: 12px;
    min-width: 0;
  }
</style>
