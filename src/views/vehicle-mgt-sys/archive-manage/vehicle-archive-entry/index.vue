<template>
  <div class="vehicle-archive-list art-full-height">
    <ElTabs
      v-model="auditTab"
      class="vehicle-archive-list__tabs"
      @tab-change="handleAuditTabChange"
    >
      <ElTabPane label="待审核" name="pending" />
      <ElTabPane label="已审核" name="approved" />
    </ElTabs>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      class="vehicle-archive-list__query"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <VehicleArchiveAuditDialog ref="auditDialogRef" @success="handleAuditSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElTabPane, ElTabs, ElTag } from 'element-plus'
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
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    auditVehicleArchive,
    exportVehicleArchiveList,
    fetchVehicleArchiveList
  } from '@/api/vehicle-mgt-sys'
  import { useUserStore } from '@/store/modules/user'
  import VehicleArchiveAuditDialog from '../modules/vehicle-archive-audit-dialog.vue'

  defineOptions({ name: 'VehicleArchiveEntry' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type AuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus
  type AuditTab = Extract<AuditStatus, 'pending' | 'approved'>
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface OptionGroup {
    vehicleType: ComputedRef<Api.DataCenter.DictListItem[]>
    operationStatus: ComputedRef<Api.DataCenter.DictListItem[]>
  }

  interface AuditDialogExpose {
    handleOpen: (row: VehicleArchive) => Promise<void>
  }

  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const auditDialogRef = ref<AuditDialogExpose>()
  const auditTab = ref<AuditTab>('pending')
  const options: UnwrapNestedRefs<OptionGroup> = reactive<OptionGroup>({
    vehicleType: computed(() => getDictMap.value.vehicleType ?? []),
    operationStatus: computed(() => getDictMap.value.vehicleOperationStatus ?? [])
  })

  const searchQuery = ref<SearchParams>({
    companyName: '',
    plateNo: '',
    vehicleType: '',
    manufacturer: '',
    chassisNo: '',
    operationStatus: '',
    auditStatus: auditTab.value
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    { label: '所属公司', key: 'companyName', type: 'input' },
    { label: '车牌号', key: 'plateNo', type: 'input' },
    {
      label: '车型',
      key: 'vehicleType',
      type: 'select',
      props: {
        options: options.vehicleType
      }
    },
    { label: '车辆厂商', key: 'manufacturer', type: 'input' },
    { label: '车架号', key: 'chassisNo', type: 'input' },
    {
      label: '营运状态',
      key: 'operationStatus',
      type: 'select',
      props: {
        options: options.operationStatus
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
    { type: 'globalIndex', label: '序号', width: 70 },
    { prop: 'companyName', label: '所属公司', width: 150 },
    { prop: 'plateNo', label: '车牌号', width: 120 },
    {
      prop: 'vehicleType',
      label: '车型',
      width: 140,
      formatter: (row) => userStore.getDictLabelByValue('vehicleType', row.vehicleType)
    },
    { prop: 'manufacturer', label: '车辆厂商', width: 130 },
    { prop: 'chassisNo', label: '车架号', width: 160 },
    {
      prop: 'operationStatus',
      label: '营运状态',
      width: 100,
      formatter: (row) =>
        userStore.getDictLabelByValue('vehicleOperationStatus', row.operationStatus)
    },
    {
      prop: 'auditStatus',
      label: '审核状态',
      width: 100,
      formatter: (row) => {
        const audit = getAuditMeta(row.auditStatus)
        return <ElTag type={audit.type}>{audit.label}</ElTag>
      }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 120,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD')
    },
    { prop: 'createBy', label: '创建人', width: 100 },
    {
      prop: 'operation',
      label: '操作',
      width: 100,
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
  ]

  const getCurrentAuditStatus = (): AuditTab => {
    return auditTab.value
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
    void router.push({
      path: `/vehicle-mgt-sys/archive-manage/vehicle-archive-detail/${row.id}`,
      query: { source: 'entry' }
    })
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

  const handleAuditSuccess = (): void => {
    void tableQueryRef.value?.refreshData()
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'audit',
      label: '审核',
      icon: 'ri:checkbox-circle-line',
      auth: 'VehicleArchive:Audit',
      color: '#67c23a'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: VehicleArchive): void => {
    if (item.key === 'audit') {
      void auditDialogRef.value?.handleOpen(row)
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
</script>

<style scoped lang="scss">
  .vehicle-archive-list {
    --archive-search-radius: calc(var(--custom-radius) - 4px);

    display: flex;
    flex-direction: column;

    &__tabs {
      padding: 0 16px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-bottom: 0;
      border-radius: var(--el-border-radius-base) var(--el-border-radius-base) 0 0;

      :deep(.el-tabs__header) {
        margin-bottom: 0;
        border-bottom: 0;
      }

      :deep(.el-tabs__nav-wrap::after) {
        height: 0;
      }

      :deep(.el-tabs__item) {
        height: 48px;
        padding: 0 18px;
        font-weight: 500;
        line-height: 48px;
      }
    }

    &__query {
      min-height: 0;

      :deep(.art-search-bar) {
        padding-top: 12px;
        /*border: 1px solid var(--el-border-color-light);*/
        border-top: 0;
        border-radius: 0 0 var(--el-border-radius-base) var(--el-border-radius-base) !important;
        box-shadow: none;
      }

      :deep(.art-table-card) {
        margin-top: 12px !important;
      }
    }
  }
</style>
