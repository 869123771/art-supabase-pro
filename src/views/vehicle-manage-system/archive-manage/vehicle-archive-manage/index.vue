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
      :immediate="table.immediate"
    />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
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
  import {
    deleteVehicleArchive,
    fetchVehicleArchiveDeletePreview,
    fetchVehicleArchiveList
  } from '@/api/vehicle-manage-system'
  import { fetchCarrierDetail, fetchCarrierOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'VehicleArchiveManage' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<VehicleArchive>[]
    immediate: boolean
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
  const route = useRoute()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const initialCarrierId = String(route.query.carrierId || '')

  const withSelectedCarrierOption = async (result: unknown) => {
    const carrierResult = result as Awaited<ReturnType<typeof fetchCarrierOptions>>
    const selectedCarrierId = table.searchQuery.carrierId
    const options = carrierResult.data ?? []

    if (!selectedCarrierId || options.some((option) => option.id === selectedCarrierId)) {
      return carrierResult
    }

    const detailResult = await fetchCarrierDetail(selectedCarrierId)
    const carrier = detailResult.data
    if (!carrier?.id) return carrierResult

    return {
      ...carrierResult,
      data: [carrier as CarrierOption, ...options]
    }
  }

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      carrierId: initialCarrierId,
      companyName: '',
      plateNo: '',
      manufacturer: '',
      chassisNo: '',
      operationStatus: ''
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '所属承运商',
        key: 'carrierId',
        type: 'select',
        api: fetchCarrierOptions,
        afterFetch: withSelectedCarrierOption,
        resultField: 'data',
        labelField: 'companyName',
        valueField: 'id',
        labelFn: (option) => {
          const carrier = option as CarrierOption
          return carrier.carrierCode
            ? `${carrier.companyName}（${carrier.carrierCode}）`
            : carrier.companyName
        },
        props: {
          clearable: true,
          filterable: true,
          placeholder: '请选择承运商'
        }
      },
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
    immediate: !initialCarrierId,
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
              type="edit"
              permission="VehicleArchive:Edit"
              onClick={() => openEditPage(row)}
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
      span: 6,
      labelWidth: 90
    },
    props: {
      rowKey: 'id',
      tableLayout: 'fixed'
    }
  })

  onMounted(async () => {
    if (!initialCarrierId) return
    await nextTick()
    await tableQueryRef.value?.getData()
  })

  watch(
    () => route.query.carrierId,
    async (value) => {
      const carrierId = String(value || '')
      if (table.searchQuery.carrierId === carrierId) return

      table.searchQuery.carrierId = carrierId
      await nextTick()
      await tableQueryRef.value?.getData()
    }
  )

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
      path: `/vehicle-manage-system/archive-manage/vehicle-archive-detail/${row.id}`,
      query: { source: 'manage' }
    })
  }

  const openEditPage = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push({
      path: `/vehicle-manage-system/archive-manage/vehicle-archive-edit/${row.id}`,
      query: { source: 'manage' }
    })
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line',
      auth: 'VehicleArchive:View'
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
    if (item.key === 'view') {
      openDetailPage(row)
      return
    }
    if (item.key === 'delete') {
      void handleDelete(row)
    }
  }

  const handleDelete = async (row: VehicleArchive): Promise<void> => {
    if (!row.id) return

    try {
      const preview = await fetchVehicleArchiveDeletePreview(row.id)
      const deletePreview = preview.data
      if (!deletePreview) return

      if (deletePreview.waybillCount > 0) {
        ElMessage.warning(
          `车辆“${row.plateNo}”已关联 ${deletePreview.waybillCount} 条运单，禁止删除`
        )
        return
      }

      const relatedSummary = deletePreview.relatedCounts
        .filter((item) => item.count > 0)
        .map((item) => `${item.label} ${item.count} 条`)
        .join('，')
      const message =
        deletePreview.relatedTotal > 0
          ? `确定删除车辆档案“${row.plateNo}”吗？该车辆没有关联运单，将一并清理 ${deletePreview.relatedTotal} 条附属记录：${relatedSummary}。删除后无法恢复。`
          : `确定删除车辆档案“${row.plateNo}”吗？该车辆没有关联运单，删除后无法恢复。`

      await ElMessageBox.confirm(message, '删除确认', {
        confirmButtonText: deletePreview.relatedTotal > 0 ? '清理并删除' : '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteVehicleArchive(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch (error) {
      if (error === 'cancel' || error === 'close') return
      ElMessage.error(error instanceof Error ? error.message : '删除失败')
    }
  }
</script>
