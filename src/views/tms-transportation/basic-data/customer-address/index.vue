<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 82, showExpand: false }"
    />

    <CustomerAddressDialog ref="dialogRef" @success="handleSaveSuccess" />
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
  import {
    deleteCustomerAddress,
    deleteCustomerAddressBatch,
    fetchCustomerAddressList,
    fetchCustomerOptions
  } from '@/api/tms'
  import CustomerAddressDialog from './modules/customer-address-dialog.vue'

  defineOptions({ name: 'TmsCustomerAddress' })

  type CustomerAddress = Api.Tms.BasicData.CustomerAddress
  type CustomerOption = Api.Tms.BasicData.CustomerOption
  type SearchParams = Api.Tms.BasicData.CustomerAddressSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface AddressDialogExpose {
    handleOpen: (
      row?: CustomerAddress,
      context?: { customerId?: string; customerName?: string }
    ) => Promise<void>
  }

  interface TableState {
    searchQuery: SearchParams
  }

  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<AddressDialogExpose>()

  const routeCustomerId = computed(() => String(route.query.customerId ?? ''))
  const customerName = computed(() => String(route.query.customerName ?? ''))
  const addressTypeOptions = computed(() => getDictMap.value.tmsAddressType ?? [])

  const tableState = reactive<TableState>({
    searchQuery: {
      customerId: routeCustomerId.value,
      addressType: undefined,
      createTimeRange: [],
      keyword: ''
    }
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '地址类型',
      key: 'addressType',
      type: 'segment',
      span: 24,
      props: {
        options: [
          { label: '全部', value: undefined },
          ...addressTypeOptions.value.map((item) => ({
            label: item.label,
            value: item.value
          }))
        ]
      }
    },
    {
      label: '客户',
      key: 'customerId',
      type: 'select',
      api: fetchCustomerOptions,
      resultField: 'data',
      labelField: 'customerName',
      valueField: 'id',
      labelFn: (option) => {
        const customer = option as CustomerOption
        return customer.customerCode
          ? `${customer.customerName}（${customer.customerCode}）`
          : customer.customerName
      },
      props: {
        clearable: true,
        filterable: true,
        placeholder: '请选择客户名称或编号'
      }
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
      props: { clearable: true, placeholder: '联系人、电话或详细地址' }
    }
  ])

  const columnsFactory = (): ColumnOption<CustomerAddress>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'addressType',
      label: '地址类型',
      width: 120,
      dict: { code: 'tmsAddressType', display: 'tag' }
    },
    {
      prop: 'customerName',
      label: '客户',
      minWidth: 190,
      formatter: (row) => row.customer?.customerName || customerName.value || '-'
    },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 150 },
    {
      prop: 'fullAddress',
      label: '详细地址',
      minWidth: 300,
      showOverflowTooltip: true,
      formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
    },
    {
      prop: 'isDefault',
      label: '默认',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.isDefault) }
    },
    { prop: 'remark', label: '备注', minWidth: 150, showOverflowTooltip: true },
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
        `确定删除选中的 ${selectedCount} 条地址吗？`,
      onClick: async ({ selectedRows }) => {
        await deleteCustomerAddressBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCustomerAddressList({
      ...params,
      from,
      to
    })
  }

  const openDialog = (row?: CustomerAddress): void => {
    void dialogRef.value?.handleOpen(row, {
      customerId: tableState.searchQuery.customerId,
      customerName: customerName.value
    })
  }

  watch(routeCustomerId, async (value) => {
    tableState.searchQuery.customerId = value
    await nextTick()
    await tableQueryRef.value?.refreshData()
  })

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleDelete = async (row: CustomerAddress): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除“${[row.region, row.addressDetail].filter(Boolean).join(' ')}”吗？`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCustomerAddress(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>
