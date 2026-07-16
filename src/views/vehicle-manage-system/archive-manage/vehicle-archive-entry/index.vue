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
      :key="auditTab"
      ref="tableQueryRef"
      v-model="searchQuery"
      class="vehicle-archive-list__query"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />

    <VehicleArchiveAuditDialog ref="auditDialogRef" @success="handleAuditSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElTabPane, ElTabs } from 'element-plus'
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
  import { exportVehicleArchiveList, fetchVehicleArchiveList } from '@/api/vehicle-manage-system'
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
    handleBatchOpen: (rows: VehicleArchive[]) => Promise<void>
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
    vin: '',
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
    { label: '车架号（VIN）', key: 'vin', type: 'input' },
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
        endPlaceholder: '结束日期',
        class: '!w-full'
      }
    }
  ])

  const archiveExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'companyName', title: '所属公司' },
    { key: 'plateNo', title: '车牌号', required: true },
    { key: 'vehicleType', title: '车型', required: true },
    { key: 'manufacturer', title: '车辆厂商' },
    { key: 'chassisNo', title: '底盘号' },
    { key: 'vin', title: '车架号（VIN）', required: true },
    { key: 'operationStatus', title: '营运状态' },
    { key: 'auditStatus', title: '审核状态' },
    { key: 'createTime', title: '创建时间' },
    { key: 'createBy', title: '创建人' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => {
    const actions: ArtTableQueryHeaderAction[] = []

    if (auditTab.value === 'pending') {
      actions.push(
        {
          type: 'add',
          permission: 'VehicleArchive:Add',
          onClick: () => handleAdd()
        },
        {
          key: 'batch-audit',
          label: '批量审核',
          icon: 'ri:checkbox-circle-line',
          permission: 'VehicleArchive:Audit',
          selectionRequired: true,
          buttonProps: { type: 'primary', plain: true },
          onClick: handleBatchAudit
        }
      )
    }

    actions.push({
      type: 'export',
      exportFilename: '车辆档案',
      exportSheetName: '车辆档案',
      exportColumns: archiveExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) => {
        return exportVehicleArchiveList({
          ...(searchParams as SearchParams),
          ...getAuditSearchParams(),
          ids: selectedIds.map(String),
          maxRows
        })
      }
    })

    return actions
  })

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({
      current: params.current,
      size: params.size
    })

    return fetchVehicleArchiveList({
      ...params,
      ...getAuditSearchParams(),
      from,
      to
    })
  }

  const columnsFactory = (): ColumnOption<VehicleArchive>[] => {
    const columns: ColumnOption<VehicleArchive>[] = []

    if (auditTab.value === 'pending') {
      columns.push({ type: 'selection', width: 50, fixed: 'left', reserveSelection: true })
    }

    columns.push(
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'companyName', label: '所属公司', minWidth: '140px' },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 140,
        dict: { code: 'vehicleType', display: 'text' }
      },
      { prop: 'manufacturer', label: '车辆厂商', width: 130 },
      { prop: 'vin', label: '车架号（VIN）', width: 200 },
      {
        prop: 'operationStatus',
        label: '营运状态',
        width: 100,
        dict: { code: 'vehicleOperationStatus', display: 'text' }
      },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 180,
        formatter: (row) => formatWithDayjs(row.createTime)
      },
      { prop: 'createBy', label: '创建人', width: 160 }
    )

    if (auditTab.value === 'approved') {
      columns.push(
        {
          prop: 'auditStatus',
          label: '审核状态',
          width: 100,
          dict: {
            code: 'vehicleAuditStatus',
            display: 'badge'
          }
        },
        {
          prop: 'auditTime',
          label: '审核时间',
          width: 180,
          formatter: (row) => formatWithDayjs(row.auditTime || row.updateTime)
        },
        {
          prop: 'auditBy',
          label: '审核人',
          width: 160,
          formatter: (row) => row.auditBy || row.updateBy || '--'
        }
      )
    }

    columns.push({
      prop: 'operation',
      label: '操作',
      width: auditTab.value === 'approved' ? 80 : 100,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable
            type="view"
            permission="VehicleArchive:View"
            onClick={() => handleDetail(row)}
          />
          {auditTab.value === 'pending' && (
            <ArtButtonMore
              list={getMoreActions()}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          )}
        </div>
      )
    })

    return columns
  }

  const getAuditSearchParams = (): Pick<SearchParams, 'auditStatus' | 'auditStatuses'> => {
    if (auditTab.value === 'pending') {
      return {
        auditStatus: 'pending',
        auditStatuses: undefined
      }
    }

    return {
      auditStatus: undefined,
      auditStatuses: ['approved', 'rejected']
    }
  }

  const handleAuditTabChange = (): void => {
    Object.assign(searchQuery.value, getAuditSearchParams())
  }

  const handleAdd = (): void => {
    const path = '/vehicle-manage-system/archive-manage/vehicle-archive-edit'
    void router.push(path)
  }

  const handleDetail = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push({
      path: `/vehicle-manage-system/archive-manage/vehicle-archive-detail/${row.id}`,
      query: { source: 'entry' }
    })
  }

  const handleBatchAudit = ({ selectedRows }: ArtTableQueryHeaderActionContext): void => {
    void auditDialogRef.value?.handleBatchOpen(selectedRows as VehicleArchive[])
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

        /* border: 1px solid var(--el-border-color-light); */
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
