<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="table.searchBarProps"
      :table-props="table.props"
    />
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
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { deleteVehicleArchive, fetchVehicleArchiveList } from '@/api/vehicle-mgt-sys'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'VehicleArchiveManage' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<VehicleArchive>[]
    searchBarProps: {
      span: number
      labelWidth: number
    }
    props: {
      rowKey: string
      tableLayout: 'fixed'
    }
  }

  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      companyName: '',
      plateNo: '',
      manufacturer: '',
      chassisNo: '',
      operationStatus: ''
    },
    searchItems: computed<SearchFormItem[]>(() => [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      { label: '车辆厂商', key: 'manufacturer', type: 'input' },
      { label: '车架号', key: 'chassisNo', type: 'input' },
      {
        label: '营运状态',
        key: 'operationStatus',
        type: 'select',
        props: {
          options: getDictMap.value.vehicleOperationStatus ?? []
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => []),
    columnsFactory: (): ColumnOption<VehicleArchive>[] => [
      { type: 'globalIndex', label: '序号', width: 80 },
      { prop: 'companyName', label: '所属公司', minWidth: 180 },
      { prop: 'plateNo', label: '车牌号', minWidth: 130 },
      {
        prop: 'vehicleType',
        label: '车型',
        minWidth: 150,
        dict: { code: 'vehicleType', display: 'text' }
      },
      { prop: 'manufacturer', label: '车辆厂商', minWidth: 150 },
      { prop: 'chassisNo', label: '车架号', minWidth: 170 },
      {
        prop: 'operationStatus',
        label: '营运状态',
        width: 120,
        dict: { code: 'vehicleOperationStatus', display: 'text' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable
              type="view"
              permission="VehicleArchive:View"
              onClick={() => openDetailPage(row)}
            />
            <ArtButtonMore
              list={getMoreActions()}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ],
    searchBarProps: {
      span: 8,
      labelWidth: 90
    },
    props: {
      rowKey: 'id',
      tableLayout: 'fixed'
    }
  })

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })
    return fetchVehicleArchiveList({
      ...params,
      from,
      to
    })
  }

  const openDetailPage = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push({
      path: `/vehicle-mgt-sys/archive-manage/vehicle-archive-detail/${row.id}`,
      query: { source: 'manage' }
    })
  }

  const openEditPage = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push({
      path: `/vehicle-mgt-sys/archive-manage/vehicle-archive-edit/${row.id}`,
      query: { source: 'manage' }
    })
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'edit',
      label: '编辑',
      icon: 'ri:edit-2-line',
      auth: 'VehicleArchive:Edit'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      auth: 'VehicleArchive:Delete',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: VehicleArchive): void => {
    if (item.key === 'edit') {
      openEditPage(row)
      return
    }
    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleDelete = async (row: VehicleArchive): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(
        `确定删除车辆档案“${row.plateNo}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteVehicleArchive(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无须提示
    }
  }
</script>
