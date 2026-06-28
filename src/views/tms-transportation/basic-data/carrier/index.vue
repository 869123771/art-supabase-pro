<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
    />

    <CarrierDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElMessage, ElMessageBox } from 'element-plus'
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

  defineOptions({ name: 'TmsCarrier' })

  type Carrier = Api.Tms.BasicData.Carrier
  type SearchParams = Api.Tms.BasicData.CarrierSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface CarrierDialogExpose {
    handleOpen: (row?: Carrier) => Promise<void>
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<CarrierDialogExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      carrierType: '',
      enabled: undefined,
      createTimeRange: [],
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
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    { prop: 'companyName', label: '公司名称', minWidth: 190, showOverflowTooltip: true },
    { prop: 'carrierCode', label: '承运商编码', width: 140 },
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
        await deleteCarrierBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
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
      path: '/vehicle-manage-system/archive-manage/vehicle-archive-manage',
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

  const handleDelete = async (row: Carrier): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除承运商“${row.companyName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCarrier(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>
