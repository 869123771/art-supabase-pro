<template>
  <div class="tms-carrier tms-workspace-page art-full-height">
    <TmsWorkspaceHeader
      eyebrow="CARRIER NETWORK"
      title="承运商资料"
      description="集中管理承运主体、合作类型、资质与履约关系，让调度选择和经营评估更高效。"
      icon="ri:truck-line"
      :tags="[
        { label: '运力伙伴', type: 'primary' },
        { label: '资质可追踪', type: 'info' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        emptyText: '暂无承运商资料',
        emptyDescription: '可新增承运商，或调整类型、状态、创建时间和关键字后重新查询。'
      }"
      focusable
    />

    <CarrierDialog ref="dialogRef" @success="handleSaveSuccess" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleDeleteGuardCleared" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElButton, ElMessage } from 'element-plus'
  import { RouterLink } from 'vue-router'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteCarrier,
    deleteCarrierBatch,
    exportCarrierList,
    fetchCarrierList,
    importCarriers
  } from '@/api/tms'
  import CarrierDialog from './modules/carrier-dialog.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'

  defineOptions({ name: 'TmsCarrier' })

  const { confirmAction } = useArtFeedback()

  type Carrier = Api.Tms.BasicData.Carrier
  type SearchParams = Api.Tms.BasicData.CarrierSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface CarrierDialogExpose {
    handleOpen: (row?: Carrier) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  const router = useRouter()
  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<CarrierDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      carrierType: '',
      enabled: undefined,
      createTimeRange: [],
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : '',
      keyword: ''
    }
  })

  const carrierTypeOptions = computed(() => getDictMap.value.tmsCarrierType ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const carrierExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'carrierCode', title: '承运商编码' },
    { key: 'companyName', title: '公司名称', required: true },
    { key: 'carrierType', title: '承运商类型', required: true },
    { key: 'driverCount', title: '司机数量' },
    { key: 'vehicleCount', title: '车辆数量' },
    { key: 'region', title: '区域' },
    { key: 'addressDetail', title: '公司地址' },
    { key: 'enabled', title: '状态' },
    { key: 'contactName', title: '联系人' },
    { key: 'contactPhone', title: '手机号码' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '承运商类型',
      key: 'carrierType',
      type: 'select',
      props: { options: carrierTypeOptions.value, clearable: true }
    },
    {
      label: '承运商状态',
      key: 'enabled',
      type: 'select',
      props: { options: commonBooleanOptions.value, clearable: true }
    },
    {
      label: '创建日期',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至'
      }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '公司名称、编码、联系人或电话' }
    }
  ])

  const columnsFactory = (): ColumnOption<Carrier>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'carrierCode',
      label: '承运商编码',
      width: 165,
      formatter: (row) =>
        row.id ? (
          <RouterLink
            class="tms-carrier__code-link"
            to={`/tms-transportation/basic-data/carrier-detail/${row.id}`}
            title={`查看承运商 ${row.carrierCode || row.companyName} 详情`}
          >
            {row.carrierCode || '-'}
          </RouterLink>
        ) : (
          row.carrierCode || '-'
        )
    },
    { prop: 'companyName', label: '公司名称', minWidth: 210, showOverflowTooltip: true },
    {
      prop: 'carrierType',
      label: '承运商类型',
      width: 150,
      dict: { code: 'tmsCarrierType', display: 'text' }
    },
    {
      prop: 'driverCount',
      label: '司机数量',
      width: 100,
      align: 'right',
      formatter: (row) => (
        <ElButton link type="primary" onClick={() => goDriverManage(row)}>
          {row.driverCount ?? 0}
        </ElButton>
      )
    },
    {
      prop: 'vehicleCount',
      label: '车辆数量',
      width: 100,
      align: 'right',
      formatter: (row) => (
        <ElButton link type="primary" onClick={() => goVehicleManage(row)}>
          {row.vehicleCount ?? 0}
        </ElButton>
      )
    },
    {
      prop: 'address',
      label: '公司地址',
      minWidth: 240,
      showOverflowTooltip: true,
      formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonMore
            list={getMoreActions()}
            onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'import',
      importColumns: carrierExcelColumns,
      importApi: async (rows) => {
        await importCarriers(rows as Carrier[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS承运商资料',
      exportSheetName: '承运商管理',
      exportColumns: carrierExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCarrierList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 个承运商吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const rows = selectedRows as Carrier[]
        if (await inspectDeleteDependencies(rows)) return
        await deleteCarrierBatch(rows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCarrierList({ ...params, from, to })
  }

  const openDialog = (row?: Carrier): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const openDetail = (row: Carrier): void => {
    if (!row.id) return
    void router.push(`/tms-transportation/basic-data/carrier-detail/${row.id}`)
  }

  const goDriverManage = (row: Carrier): void => {
    if (!row.id) return
    void router.push({
      path: '/tms-transportation/basic-data/driver',
      query: { carrierId: row.id }
    })
  }

  const goVehicleManage = (row: Carrier): void => {
    if (!row.id) return
    void router.push({
      path: '/vehicle-manage-system/vehicle-archive-manage',
      query: { carrierId: row.id }
    })
  }

  const getMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'view',
      label: '查看',
      icon: 'ri:eye-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      color: '#f56c6c'
    }
  ]

  const handleMoreAction = (item: ButtonMoreItem, row: Carrier): void => {
    if (item.key === 'view') {
      openDetail(row)
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

  const inspectDeleteDependencies = async (rows: Carrier[]): Promise<boolean> => {
    const resources = rows
      .filter((item) => item.id)
      .map((item) => ({ id: String(item.id), label: item.companyName }))
    if (!resources.length) return false
    return (
      (await deleteGuardRef.value?.inspect({
        resourceType: 'carrier',
        resourceLabel: '承运商',
        resources
      })) ?? false
    )
  }

  const handleDeleteGuardCleared = (): void => {
    void tableQueryRef.value?.getData()
  }

  const syncMasterDeleteReturn = (forceRefresh = false): void => {
    if (route.query.resumeMasterDelete !== '1') return
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed = tableState.searchQuery.recordId !== recordId
    Object.assign(tableState.searchQuery, { recordId, keyword: '' })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteReturn(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteReturn(true))

  const handleDelete = async (row: Carrier): Promise<void> => {
    if (!row.id) return
    try {
      if (await inspectDeleteDependencies([row])) return
      await confirmAction(`确定删除承运商“${row.companyName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteCarrier(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>

<style scoped lang="scss">
  .tms-carrier {
    :deep(.tms-carrier__code-link) {
      display: inline-block;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 600;
      vertical-align: middle;
      color: var(--el-color-primary);
      white-space: nowrap;
      text-decoration: none;

      &:hover {
        color: var(--el-color-primary-dark-2);
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      &:focus-visible {
        outline: 2px solid var(--el-color-primary);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }
  }
</style>
