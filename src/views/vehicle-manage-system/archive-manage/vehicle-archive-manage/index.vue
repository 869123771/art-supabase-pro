<template>
  <div class="vehicle-archive-manage art-full-height">
    <VehicleWorkspaceHeader
      eyebrow="FLEET ASSET CONTROL"
      title="车辆档案管理"
      description="统一维护车辆身份、资产归属与营运状态，让每一台车都清晰可追溯。"
      icon="ri:truck-line"
      :tags="[
        { label: '一车一档', type: 'primary' },
        { label: '跨承运商管理', type: 'info' }
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
      :search-bar-props="table.searchBarProps"
      :table-props="table.props"
      :immediate="table.immediate"
      :on-success="handleTableSuccess"
      focusable
    />

    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleDeleteGuardCleared" />
  </div>
</template>

<script setup lang="tsx">
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
    ArtTableQueryHeaderAction,
    ArtTableQueryProps
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { deleteVehicleArchive, fetchVehicleArchiveList } from '@/api/vehicle-manage-system'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import { fetchCarrierDetail, fetchCarrierOptions } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import VehicleWorkspaceHeader, {
    type VehicleWorkspaceMetric
  } from '@/views/vehicle-manage-system/modules/vehicle-workspace-header.vue'

  defineOptions({ name: 'VehicleArchiveManage' })

  const { confirmAction } = useArtFeedback()

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

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
      emptyText: string
      emptyDescription: string
    }
  }

  const router = useRouter()
  const route = useRoute()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const initialCarrierId = String(route.query.carrierId || '')
  const initialRecordId = String(route.query.recordId || '')
  const overview = reactive<{ total: number; rows: VehicleArchive[] }>({
    total: 0,
    rows: []
  })
  const operatingCount = computed(
    () => overview.rows.filter((row) => row.operationStatus === 'operating').length
  )
  const incompleteCount = computed(
    () =>
      overview.rows.filter(
        (row) => !row.companyName?.trim() || !row.manufacturer?.trim() || !row.vin?.trim()
      ).length
  )
  const workspaceMetrics = computed<VehicleWorkspaceMetric[]>(() => [
    {
      label: '当前结果',
      value: overview.total,
      description: '随筛选条件实时更新',
      icon: 'ri:database-2-line'
    },
    {
      label: '本页营运中',
      value: operatingCount.value,
      description: '当前页可投入运营车辆',
      icon: 'ri:route-line',
      tone: 'success'
    },
    {
      label: '本页资料待完善',
      value: incompleteCount.value,
      description: '公司、厂商或 VIN 信息缺失',
      icon: 'ri:file-warning-line',
      tone: 'warning'
    }
  ])

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
      recordId: initialRecordId,
      companyName: '',
      plateNo: '',
      manufacturer: '',
      vin: '',
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
      { label: '车牌号', key: 'plateNo', type: 'input', props: { clearable: true } },
      { label: '车辆厂商', key: 'manufacturer', type: 'input', props: { clearable: true } },
      { label: '车架号（VIN）', key: 'vin', type: 'input', props: { clearable: true } },
      {
        label: '营运状态',
        key: 'operationStatus',
        type: 'select',
        props: {
          options: getDictMap.value.vehicleOperationStatus ?? [],
          clearable: true
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => []),
    immediate: !initialCarrierId && !initialRecordId,
    columnsFactory: (): ColumnOption<VehicleArchive>[] => [
      { type: 'globalIndex', label: '序号', width: 64 },
      {
        prop: 'vehicleIdentity',
        label: '车辆档案',
        minWidth: 250,
        formatter: (row) => renderVehicleIdentity(row)
      },
      {
        prop: 'ownership',
        label: '资产归属',
        minWidth: 190,
        formatter: (row) => renderOwnership(row)
      },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 120,
        dict: { code: 'vehicleType', display: 'auto' }
      },
      {
        prop: 'operationStatus',
        label: '营运状态',
        width: 110,
        dict: { code: 'vehicleOperationStatus', display: 'auto' }
      },
      {
        prop: 'auditStatus',
        label: '审核状态',
        width: 110,
        dict: { code: 'vehicleAuditStatus', display: 'auto' }
      },
      {
        prop: 'updateTime',
        label: '最近更新',
        width: 168,
        formatter: (row) => formatWithDayjs(row.updateTime || row.createTime)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 128,
        fixed: 'right',
        formatter: (row) => (
          <div class="vehicle-archive-manage__operation">
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
      tableLayout: 'fixed',
      emptyText: '暂无符合条件的车辆档案',
      emptyDescription: '可调整承运商、车牌号、厂商、VIN 或营运状态后重新查询。'
    }
  })

  onMounted(async () => {
    if (!initialCarrierId && !initialRecordId) return
    await nextTick()
    await tableQueryRef.value?.getData()
  })

  watch(
    () => route.fullPath,
    async () => {
      const carrierId = String(route.query.carrierId || '')
      const recordId = String(route.query.recordId || '')
      if (table.searchQuery.carrierId === carrierId && table.searchQuery.recordId === recordId) {
        return
      }
      Object.assign(table.searchQuery, { carrierId, recordId })
      await nextTick()
      await tableQueryRef.value?.getData()
    },
    { flush: 'post' }
  )

  onActivated(() => void tableQueryRef.value?.getData())

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

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as VehicleArchive[]
    overview.total = response.total ?? rows.length
  }

  const renderVehicleIdentity = (row: VehicleArchive) => (
    <div class="vehicle-archive-manage__vehicle-cell">
      <div>
        <strong>{row.plateNo || '未录入车牌'}</strong>
        <span>{row.manufacturer || '厂商待补充'}</span>
      </div>
      <small title={row.vin}>{row.vin || 'VIN 待补充'}</small>
    </div>
  )

  const renderOwnership = (row: VehicleArchive) => (
    <div class="vehicle-archive-manage__ownership">
      <strong title={row.companyName}>{row.companyName || '所属公司待补充'}</strong>
      <small>
        {row.carrier?.carrierCode
          ? `承运商编码 ${row.carrier.carrierCode}`
          : row.selfNo
            ? `自编号 ${row.selfNo}`
            : '资产编号待补充'}
      </small>
    </div>
  )

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
      if (
        await deleteGuardRef.value?.inspect({
          resourceType: 'vehicle',
          resourceLabel: '车辆档案',
          resources: [{ id: String(row.id), label: row.plateNo }]
        })
      ) {
        return
      }
      await confirmAction(`确定删除车辆档案“${row.plateNo}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
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

  const handleDeleteGuardCleared = (): void => {
    void tableQueryRef.value?.getData()
  }
</script>

<style scoped lang="scss">
  .vehicle-archive-manage {
    gap: 12px;
    min-width: 0;

    :deep(.vehicle-archive-manage__vehicle-cell),
    :deep(.vehicle-archive-manage__ownership) {
      display: grid;
      min-width: 0;
      line-height: 20px;
    }

    :deep(.vehicle-archive-manage__vehicle-cell > div) {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;
    }

    :deep(.vehicle-archive-manage__vehicle-cell strong) {
      flex: none;
      padding: 1px 8px;
      font-weight: 700;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-small);
    }

    :deep(.vehicle-archive-manage__vehicle-cell span),
    :deep(.vehicle-archive-manage__vehicle-cell small),
    :deep(.vehicle-archive-manage__ownership strong),
    :deep(.vehicle-archive-manage__ownership small) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    :deep(.vehicle-archive-manage__vehicle-cell span),
    :deep(.vehicle-archive-manage__vehicle-cell small),
    :deep(.vehicle-archive-manage__ownership small) {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    :deep(.vehicle-archive-manage__ownership strong) {
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    :deep(.vehicle-archive-manage__operation) {
      display: flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }
  }
</style>
