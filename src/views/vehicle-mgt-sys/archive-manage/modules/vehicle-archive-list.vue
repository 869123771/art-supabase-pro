<template>
  <div class="vehicle-archive-list art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    >
      <template #header-left>
        <ElSegmented v-model="auditTab" :options="auditTabOptions" @change="handleAuditTabChange" />
      </template>
    </ArtTableQuery>
  </div>
</template>

<script setup lang="tsx">
  import { ElMessageBox, ElSegmented, ElTag } from 'element-plus'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction,
    ArtTableQueryHeaderActionContext
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    auditVehicleArchive,
    deleteVehicleArchive,
    deleteVehicleArchiveBatch,
    exportVehicleArchiveList,
    fetchVehicleArchiveList
  } from '@/api/vehicle-mgt-sys'

  defineOptions({ name: 'VehicleArchiveList' })

  interface Props {
    mode?: 'entry' | 'manage'
  }

  const props = withDefaults(defineProps<Props>(), {
    mode: 'entry'
  })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type AuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  const router = useRouter()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const auditTab = ref<AuditStatus | 'all'>(props.mode === 'entry' ? 'pending' : 'all')

  const auditTabOptions = [
    { label: '全部', value: 'all' },
    { label: '待审核', value: 'pending' },
    { label: '已通过', value: 'approved' },
    { label: '未通过', value: 'rejected' }
  ]

  const searchQuery = ref<SearchParams>({
    companyName: '',
    plateNo: '',
    vehicleType: '',
    manufacturer: '',
    chassisNo: '',
    operationStatus: '',
    auditStatus: auditTab.value === 'all' ? undefined : auditTab.value
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    { label: '所属公司', key: 'companyName', type: 'input' },
    { label: '车牌号', key: 'plateNo', type: 'input' },
    {
      label: '车型',
      key: 'vehicleType',
      type: 'select',
      props: {
        options: vehicleTypeOptions
      }
    },
    { label: '车辆厂商', key: 'manufacturer', type: 'input' },
    { label: '车架号', key: 'chassisNo', type: 'input' },
    {
      label: '营运状态',
      key: 'operationStatus',
      type: 'select',
      props: {
        options: operationStatusOptions
      }
    },
    {
      label: '创建时间',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期'
      }
    }
  ])

  const archiveExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'vehicleType', title: '车型', required: true },
    { key: 'manufacturer', title: '车辆厂商' },
    { key: 'chassisNo', title: '车架号' },
    { key: 'vin', title: '车架号（VIN）', required: true },
    { key: 'operationStatus', title: '营运状态' },
    { key: 'auditStatus', title: '审核状态' },
    { key: 'createTime', title: '创建时间' },
    { key: 'createBy', title: '创建人' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      permission: 'VehicleArchive:Add',
      onClick: () => openEditPage()
    },
    {
      key: 'batch-audit',
      label: '批量审核',
      icon: 'ri:checkbox-circle-line',
      permission: 'VehicleArchive:Audit',
      selectionRequired: true,
      confirm: true,
      confirmTitle: '批量审核',
      content: (ctx: ArtTableQueryHeaderActionContext) =>
        `确定将选中的 ${ctx.selectedCount} 条车辆档案审核通过吗？`,
      buttonProps: { type: 'primary', plain: true },
      hidden: () => props.mode === 'manage',
      onClick: handleBatchAudit
    },
    {
      type: 'export',
      exportFilename: '车辆档案',
      exportSheetName: '车辆档案',
      exportColumns: archiveExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportVehicleArchiveList({
          ...(searchParams as SearchParams),
          auditStatus: getCurrentAuditStatus(),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    },
    {
      type: 'delete',
      permission: 'VehicleArchive:Delete',
      content: ({ selectedCount }: ArtTableQueryHeaderActionContext) =>
        `确定删除选中的 ${selectedCount} 条车辆档案吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const ids = selectedRows
          .map((row) => row.id)
          .filter((id): id is string => typeof id === 'string')
        await deleteVehicleArchiveBatch(ids)
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchVehicleArchiveList({
      ...params,
      auditStatus: getCurrentAuditStatus(),
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<VehicleArchive>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'companyName', label: '所属公司', minWidth: 160 },
    { prop: 'plateNo', label: '车牌号', minWidth: 130 },
    { prop: 'vehicleType', label: '车型', minWidth: 150 },
    { prop: 'manufacturer', label: '车辆厂商', minWidth: 140 },
    { prop: 'chassisNo', label: '车架号', minWidth: 160 },
    {
      prop: 'operationStatus',
      label: '营运状态',
      width: 120,
      formatter: (row) => getOptionLabel(operationStatusOptions, row.operationStatus)
    },
    {
      prop: 'auditStatus',
      label: '审核状态',
      width: 120,
      formatter: (row) => {
        const audit = getAuditMeta(row.auditStatus)
        return <ElTag type={audit.type}>{audit.label}</ElTag>
      }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 160,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD')
    },
    { prop: 'createBy', label: '创建人', minWidth: 150 },
    {
      prop: 'operation',
      label: '操作',
      width: 170,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable
            type="view"
            permission="VehicleArchive:View"
            onClick={() => openDetailPage(row)}
          />
          <ArtButtonTable
            type="edit"
            permission="VehicleArchive:Edit"
            onClick={() => openEditPage(row)}
          />
          <ArtButtonTable
            type="delete"
            permission="VehicleArchive:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  const getCurrentAuditStatus = (): AuditStatus | undefined => {
    return auditTab.value === 'all' ? undefined : auditTab.value
  }

  const handleAuditTabChange = (): void => {
    searchQuery.value.auditStatus = getCurrentAuditStatus()
    void tableQueryRef.value?.refreshData()
  }

  const openEditPage = (row?: VehicleArchive): void => {
    const path = row?.id
      ? `/vehicle-mgt-sys/archive-manage/vehicle-archive-edit/${row.id}`
      : '/vehicle-mgt-sys/archive-manage/vehicle-archive-edit'
    void router.push(path)
  }

  const openDetailPage = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push(`/vehicle-mgt-sys/archive-manage/vehicle-archive-detail/${row.id}`)
  }

  const handleBatchAudit = async ({
    selectedRows
  }: ArtTableQueryHeaderActionContext): Promise<void> => {
    const ids = selectedRows
      .map((row) => row.id)
      .filter((id): id is string => typeof id === 'string')
    await Promise.all(ids.map((id) => auditVehicleArchive({ id, auditStatus: 'approved' })))
    await tableQueryRef.value?.refreshUpdate()
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

  const getAuditMeta = (value?: string) => {
    const map = {
      pending: { label: '待审核', type: 'warning' },
      approved: { label: '已通过', type: 'success' },
      rejected: { label: '未通过', type: 'danger' }
    } as const
    return map[(value || 'pending') as keyof typeof map] ?? map.pending
  }

  const getOptionLabel = (options: Array<{ label: string; value: string }>, value?: string) => {
    return options.find((item) => item.value === value)?.label || value || ''
  }

  const vehicleTypeOptions = [
    { label: '大型城市客车', value: 'large-city-bus' },
    { label: '中型客车', value: 'medium-bus' },
    { label: '小型客车', value: 'small-bus' },
    { label: '货车', value: 'truck' },
    { label: '专用车', value: 'special-vehicle' }
  ]

  const operationStatusOptions = [
    { label: '营运', value: 'operating' },
    { label: '停运', value: 'stopped' },
    { label: '维修', value: 'maintenance' },
    { label: '报废', value: 'scrapped' }
  ]
</script>

<style scoped lang="scss">
  .vehicle-archive-list {
    :deep(.el-segmented) {
      --el-segmented-item-selected-color: var(--el-color-primary);

      margin-right: 8px;
    }
  }
</style>
