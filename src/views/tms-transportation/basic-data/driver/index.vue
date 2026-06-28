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

    <DriverDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessageBox } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { deleteDriver, deleteDriverBatch, fetchCarrierOptions, fetchDriverList } from '@/api/tms'
  import DriverDialog from './modules/driver-dialog.vue'

  defineOptions({ name: 'TmsDriver' })

  type Driver = Api.Tms.BasicData.Driver
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type SearchParams = Api.Tms.BasicData.DriverSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DriverDialogExpose {
    handleOpen: (row?: Driver) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const route = useRoute()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DriverDialogExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      carrierId: '',
      gender: '',
      enabled: undefined,
      createTimeRange: [],
      keyword: ''
    }
  })

  onMounted(() => {
    const carrierId = String(route.query.carrierId || '')
    if (carrierId) {
      tableState.searchQuery.carrierId = carrierId
    }
  })

  const genderOptions = computed(() => getDictMap.value.sex ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属承运商',
      key: 'carrierId',
      type: 'select',
      api: fetchCarrierOptions,
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
    {
      label: '性别',
      key: 'gender',
      type: 'select',
      props: { options: genderOptions.value, clearable: true }
    },
    {
      label: '状态',
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
      props: {
        clearable: true,
        placeholder: '姓名、手机号、身份证号或家庭住址'
      }
    }
  ])

  const columnsFactory = (): ColumnOption<Driver>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'driverName',
      label: '姓名',
      minWidth: 120,
      showOverflowTooltip: true
    },
    {
      prop: 'carrierName',
      label: '所属承运商',
      minWidth: 210,
      showOverflowTooltip: true,
      formatter: (row) => row.carrier?.companyName || '-'
    },
    { prop: 'phone', label: '手机号码', width: 150 },
    {
      prop: 'gender',
      label: '性别',
      width: 90,
      dict: { code: 'sex', display: 'text' }
    },
    { prop: 'licenseType', label: '驾照类型', width: 100 },
    {
      prop: 'licenseExpireDate',
      label: '驾照日期',
      width: 130,
      formatter: (row) => row.licenseExpireDate || '-'
    },
    {
      prop: 'homeAddress',
      label: '家庭住址',
      minWidth: 260,
      showOverflowTooltip: true,
      formatter: (row) => row.homeAddress || '-'
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
        <div>
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 个司机吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        await deleteDriverBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchDriverList({ ...params, from, to })
  }

  const openDialog = (row?: Driver): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: Driver): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除司机“${row.driverName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteDriver(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示
    }
  }
</script>
