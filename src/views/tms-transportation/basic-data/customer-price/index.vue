<template>
  <div class="art-full-height customer-price">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{ tableLayout: 'fixed', fit: false, showOverflowTooltip: false }"
    />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessageBox } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption } from '@/types'
  import { fetchRegionOptions } from '@/api/common'
  import {
    deleteCustomerPrice,
    deleteCustomerPriceBatch,
    exportCustomerPriceList,
    fetchCustomerPriceList
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsCustomerPrice' })

  type CustomerPrice = Api.Tms.BasicData.CustomerPrice
  type CustomerPriceCargoItem = Api.Tms.BasicData.CustomerPriceCargoItem
  type SearchParams = Api.Tms.BasicData.CustomerPriceSearchParams
  type SearchModel = SearchParams & {
    originRegionPath?: string[]
    destinationRegionPath?: string[]
  }
  type TableParams = SearchModel & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchModel
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()

  const table = reactive<TableGroup>({
    searchQuery: {
      originRegionPath: [],
      destinationRegionPath: [],
      createTimeRange: [],
      keyword: ''
    }
  })

  const cargoUnitOptions = computed(() => getDictMap.value.tmsCargoUnit ?? [])
  const transportTypeOptions = computed(() => getDictMap.value.tmsCustomerPriceTransportType ?? [])
  const cargoTypeOptions = computed(() => getDictMap.value.tmsCustomerPriceCargoType ?? [])
  const billingMethodOptions = computed(() => getDictMap.value.tmsCustomerPriceBillingMethod ?? [])

  const customerPriceExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'originRegion', title: '始发地' },
    { key: 'destinationRegion', title: '目的地' },
    {
      key: 'customerName',
      title: '客户名称',
      formatter: (_value, row) => (row as CustomerPrice).customer?.customerName || ''
    },
    { key: 'shippingInfo', title: '发货信息', formatter: (_value, row) => formatShippingInfo(row) },
    {
      key: 'receivingInfo',
      title: '收货信息',
      formatter: (_value, row) => formatReceivingInfo(row)
    },
    { key: 'transportType', title: '类型', formatter: (value) => formatDict('transport', value) },
    { key: 'cargoType', title: '货物类型', formatter: (value) => formatDict('cargo', value) },
    {
      key: 'cargoQuantityTotal',
      title: '货物数量',
      formatter: (_value, row) => formatCargoQuantity(row as CustomerPrice)
    },
    {
      key: 'cargoVolumeTotal',
      title: '总体积',
      formatter: (value) => `${formatNumber(value as number | string | null, 2)}m3`
    },
    {
      key: 'cargoWeightTotal',
      title: '总重量',
      formatter: (value) => `${formatNumber(value as number | string | null, 2)}kg`
    },
    {
      key: 'totalFee',
      title: '运费合计',
      formatter: (value) => formatMoney(value as number | string | null)
    },
    { key: 'createBy', title: '创建人' },
    {
      key: 'createTime',
      title: '创建时间',
      formatter: (value) => formatDateTime(value as string | null)
    }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '始发地',
      key: 'originRegionPath',
      type: 'cascader',
      api: fetchRegionOptions,
      labelField: 'name',
      valueField: 'name',
      childrenField: 'children',
      props: {
        class: 'w-full',
        clearable: true,
        filterable: true,
        placeholder: '请选择',
        props: {
          label: 'name',
          value: 'name',
          children: 'children',
          emitPath: true,
          checkStrictly: true
        }
      }
    },
    {
      label: '目的地',
      key: 'destinationRegionPath',
      type: 'cascader',
      api: fetchRegionOptions,
      labelField: 'name',
      valueField: 'name',
      childrenField: 'children',
      props: {
        class: 'w-full',
        clearable: true,
        filterable: true,
        placeholder: '请选择',
        props: {
          label: 'name',
          value: 'name',
          children: 'children',
          emitPath: true,
          checkStrictly: true
        }
      }
    },
    {
      label: '创建日期',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '请选择日期',
        endPlaceholder: '请选择日期',
        rangeSeparator: '~'
      }
    },
    {
      label: '',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '请输入关键词搜索' }
    }
  ])

  const columnsFactory = (): ColumnOption<CustomerPrice>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { prop: 'originRegion', label: '始发地', width: 170 },
    { prop: 'destinationRegion', label: '目的地', width: 170 },
    {
      prop: 'customerName',
      label: '客户名称',
      width: 190,
      formatter: (row) => row.customer?.customerName || '-'
    },
    {
      prop: 'shippingInfo',
      label: '发货信息',
      minWidth: 240,
      formatter: (row) => renderShippingInfo(row)
    },
    {
      prop: 'receivingInfo',
      label: '收货信息',
      minWidth: 240,
      formatter: (row) => renderReceivingInfo(row)
    },
    {
      prop: 'transportType',
      label: '类型',
      width: 100,
      dict: { code: 'tmsCustomerPriceTransportType', display: 'text' }
    },
    {
      prop: 'cargoType',
      label: '货物类型',
      width: 110,
      dict: { code: 'tmsCustomerPriceCargoType', display: 'text' }
    },
    {
      prop: 'cargoQuantityTotal',
      label: '货物数量',
      width: 110,
      align: 'right',
      formatter: (row) => formatCargoQuantity(row)
    },
    {
      prop: 'cargoVolumeTotal',
      label: '总体积',
      width: 110,
      align: 'right',
      formatter: (row) => `${formatNumber(row.cargoVolumeTotal, 2)}m³`
    },
    {
      prop: 'cargoWeightTotal',
      label: '总重量',
      width: 110,
      align: 'right',
      formatter: (row) => `${formatNumber(row.cargoWeightTotal, 2)}kg`
    },
    {
      prop: 'totalFee',
      label: '运费合计',
      width: 120,
      align: 'right',
      formatter: (row) => formatMoney(row.totalFee)
    },
    { prop: 'createBy', label: '创建人', width: 120 },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatDateTime(row.createTime)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="edit" onClick={() => openEditPage(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', label: '新增', onClick: () => openEditPage() },
    {
      type: 'delete',
      label: '批量删除',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条客户价格吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        await deleteCustomerPriceBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS客户价格维护',
      exportSheetName: '客户价格维护',
      exportColumns: customerPriceExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCustomerPriceList({
          ...normalizeSearchParams(searchParams as SearchModel),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCustomerPriceList({
      ...normalizeSearchParams(params),
      from,
      to
    })
  }

  const normalizeSearchParams = (params: SearchModel): SearchParams => {
    const { originRegionPath, destinationRegionPath, ...rest } = params
    return {
      ...rest,
      originRegion: joinRegionPath(originRegionPath),
      destinationRegion: joinRegionPath(destinationRegionPath)
    }
  }

  const joinRegionPath = (regionPath?: string[]): string | undefined => {
    const text = regionPath?.filter(Boolean).join('/')
    return text || undefined
  }

  const openEditPage = (row?: CustomerPrice): void => {
    if (row?.id) {
      void router.push({ name: 'TmsCustomerPriceEdit', params: { id: row.id } })
      return
    }
    void router.push({ name: 'TmsCustomerPriceEdit' })
  }

  const handleDelete = async (row: CustomerPrice): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除「${row.customer?.customerName || '客户价格'}」这条价格吗？`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCustomerPrice(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  const renderShippingInfo = (row: CustomerPrice) => (
    <div class="customer-price__info">
      <span>联系人姓名：{row.shippingContactName || '-'}</span>
      <span>联系电话：{row.shippingContactPhone || '-'}</span>
      <span>发货地址：{formatFullAddress(row.originRegion, row.shippingAddressDetail)}</span>
    </div>
  )

  const renderReceivingInfo = (row: CustomerPrice) => (
    <div class="customer-price__info">
      <span>联系人姓名：{row.receivingContactName || '-'}</span>
      <span>联系电话：{row.receivingContactPhone || '-'}</span>
      <span>收货地址：{formatFullAddress(row.destinationRegion, row.receivingAddressDetail)}</span>
    </div>
  )

  const formatShippingInfo = (row: unknown): string => {
    const data = row as CustomerPrice
    return [
      `联系人姓名：${data.shippingContactName || ''}`,
      `联系电话：${data.shippingContactPhone || ''}`,
      `发货地址：${formatFullAddress(data.originRegion, data.shippingAddressDetail)}`
    ].join('\n')
  }

  const formatReceivingInfo = (row: unknown): string => {
    const data = row as CustomerPrice
    return [
      `联系人姓名：${data.receivingContactName || ''}`,
      `联系电话：${data.receivingContactPhone || ''}`,
      `收货地址：${formatFullAddress(data.destinationRegion, data.receivingAddressDetail)}`
    ].join('\n')
  }

  const formatFullAddress = (region?: string | null, address?: string | null): string =>
    [region, address].filter(Boolean).join(' ') || '-'

  const formatCargoQuantity = (row: CustomerPrice): string => {
    const quantity = formatNumber(row.cargoQuantityTotal, 0)
    const unit = getCargoUnitLabel(row.cargoItems?.[0])
    return `${quantity}${unit}`
  }

  const getCargoUnitLabel = (item?: CustomerPriceCargoItem): string => {
    if (!item?.unit) return ''
    return getLabel(cargoUnitOptions.value, item.unit)
  }

  const formatDict = (type: 'transport' | 'cargo' | 'billing', value: unknown): string => {
    if (!value) return ''
    const options =
      type === 'transport'
        ? transportTypeOptions.value
        : type === 'cargo'
          ? cargoTypeOptions.value
          : billingMethodOptions.value
    return getLabel(options, String(value))
  }

  const getLabel = (options: Api.DataCenter.DictListItem[], value?: string | null): string => {
    if (!value) return ''
    const item = options.find((option) => option.value === value || option.label === value)
    return item?.label || item?.name || value
  }

  const formatNumber = (value?: number | string | null, precision = 2): string => {
    const numberValue = Number(value ?? 0)
    if (Number.isNaN(numberValue)) return '0'
    return numberValue
      .toFixed(precision)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?)0+$/, '$1')
  }

  const formatMoney = (value?: number | string | null): string => formatNumber(value, 2)

  const formatDateTime = (value?: string | null): string =>
    value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '-') : '-'
</script>

<style scoped lang="scss">
  .customer-price {
    :deep(.customer-price__info) {
      display: flex;
      flex-direction: column;
      gap: 2px;
      align-items: flex-start;
      line-height: 20px;
      white-space: normal;
    }
  }
</style>
