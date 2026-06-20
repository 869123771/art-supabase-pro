<template>
  <div class="vehicle-part-usage-page art-full-height">
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

    <VehiclePartUsageDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessageBox } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    deleteVehiclePartUsage,
    deleteVehiclePartUsageBatch,
    fetchPartsCategoryTree,
    fetchVehiclePartUsageList
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import TreeUtils from '@/utils/tree'
  import VehiclePartUsageDialog from './modules/vehicle-part-usage-dialog.vue'

  defineOptions({ name: 'VehiclePartsManage' })

  type Usage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
  type SearchParams = Api.VehicleMgtSys.VehicleManage.VehiclePartUsageSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (row?: Usage) => Promise<void>
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<Usage>[]
  }

  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const categoryTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      companyName: '',
      plateNo: '',
      partType: undefined,
      categoryId: undefined,
      partName: '',
      rfidTag: '',
      status: undefined,
      createTimeRange: []
    },
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      {
        label: '零部件类型',
        key: 'partType',
        type: 'select',
        props: { options: getDictMap.value.vehiclePartType ?? [] }
      },
      {
        label: '零部件类别',
        key: 'categoryId',
        type: 'treeSelect',
        api: fetchPartsCategoryTree,
        afterFetch: (result: unknown) => {
          const records =
            (result as { data?: Api.VehicleMgtSys.BasicInfo.PartsCategory[] }).data ?? []
          return categoryTreeUtils.listToTree(records)
        },
        labelField: 'categoryName',
        valueField: 'id',
        childrenField: 'children',
        props: { checkStrictly: true }
      },
      { label: '零部件名称', key: 'partName', type: 'input' },
      { label: 'RFID标签', key: 'rfidTag', type: 'input' },
      {
        label: '状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.vehiclePartUsageStatus ?? [] }
      },
      {
        label: '创建时间',
        key: 'createTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          class: '!w-full'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        type: 'add',
        permission: 'VehiclePartUsage:Add',
        onClick: () => openDialog()
      },
      {
        type: 'delete',
        permission: 'VehiclePartUsage:Delete',
        content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
          `确定删除选中的 ${selectedCount} 条零部件使用记录吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          const ids = selectedRows
            .map((row) => row.id)
            .filter((id): id is string => typeof id === 'string')
          await deleteVehiclePartUsageBatch(ids)
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: (): ColumnOption<Usage>[] => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      {
        prop: 'partType',
        label: '零部件类型',
        width: 120,
        dict: { code: 'vehiclePartType', display: 'auto' }
      },
      { prop: 'partName', label: '零部件名称', minWidth: 170 },
      { prop: 'categoryName', label: '类别', minWidth: 130 },
      { prop: 'brand', label: '品牌', width: 110 },
      { prop: 'model', label: '型号', minWidth: 130 },
      { prop: 'rfidTag', label: 'RFID标签', minWidth: 150 },
      { prop: 'enableDate', label: '启用日期', width: 120 },
      {
        prop: 'warrantySummary',
        label: '质保期',
        minWidth: 160,
        formatter: formatWarranty
      },
      { prop: 'serviceYears', label: '使用年限（年）', width: 130 },
      {
        prop: 'usedYears',
        label: '已使用时长（年）',
        width: 140,
        formatter: (row) => formatUsedYears(row.enableDate)
      },
      { prop: 'serviceMileage', label: '可使用里程（公里）', width: 155 },
      { prop: 'usedMileage', label: '已使用里程（公里）', width: 155 },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'vehiclePartUsageStatus', display: 'badge' }
      },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 180,
        formatter: (row) => formatWithDayjs(row.createTime)
      },
      { prop: 'createBy', label: '创建人', width: 140 },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="edit"
              permission="VehiclePartUsage:Edit"
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

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehiclePartUsageList({ ...params, from, to })
  }

  const formatWarranty = (row: Usage): string => {
    if (row.warrantyMode === 'vehicle') return '随整车质保'
    const values = [
      row.warrantyMileage ? `${row.warrantyMileage}公里` : '',
      row.warrantyDuration ? `${row.warrantyDuration}个月` : ''
    ].filter(Boolean)
    return values.join(' / ') || '--'
  }

  const formatUsedYears = (enableDate?: string | null): string => {
    if (!enableDate) return '--'
    const start = new Date(enableDate)
    if (Number.isNaN(start.getTime())) return '--'
    const years = Math.max(0, (Date.now() - start.getTime()) / (365.25 * 24 * 60 * 60 * 1000))
    return years.toFixed(1)
  }

  const openDialog = (row?: Usage): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const viewDetail = (row: Usage): void => {
    if (!row.id) return
    void router.push(`/vehicle-manage-system/vehicle-manage/part-manage-detail/${row.id}`)
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line',
      auth: 'VehiclePartUsage:View'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehiclePartUsage:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: Usage): void => {
    if (item.key === 'view') {
      viewDetail(row)
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

  const handleDelete = async (row: Usage): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除“${row.plateNo} / ${row.partName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteVehiclePartUsage(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // User cancelled.
    }
  }
</script>
