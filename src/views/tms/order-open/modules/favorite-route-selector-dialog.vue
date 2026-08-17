<template>
  <ArtTableSingleSelect
    ref="selectRef"
    v-model="selector.value"
    v-model:selected-data="selector.selectedRows"
    :api-fn="fetchSelectorData"
    :columns="selector.columns"
    title="选择常用线路"
    subtitle="选择后将同时覆盖当前发货与收货信息"
    row-key="id"
    :label-key="getRouteLabel"
    :description-key="getRouteDescription"
    :disabled-key="isRouteUnavailable"
    search-placeholder="请输入线路名称或备注"
    empty-text="暂无可用常用线路，请先在基础资料中维护"
    dialog-width="xl"
    show-pagination
    :page-size="10"
    @confirm="handleConfirm"
  >
    <template #trigger></template>
  </ArtTableSingleSelect>
</template>

<script setup lang="ts">
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    ArtDataSelectExpose,
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import { fetchFavoriteRouteList } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatOrderAddress } from './order-open-model'

  defineOptions({ name: 'TmsOrderFavoriteRouteSelectorDialog' })

  type FavoriteRoute = Api.Tms.BasicData.FavoriteRoute
  type CustomerAddress = Api.Tms.BasicData.CustomerAddress

  interface SelectorGroup {
    value?: string | number
    selectedRows: DataSelectRecord[]
    columns: DataSelectColumn[]
  }

  const emit = defineEmits<{
    (event: 'select', route: FavoriteRoute): void
  }>()

  const selectRef = ref<ArtDataSelectExpose>()

  const getEndpointCustomerName = (
    route: FavoriteRoute,
    address?: CustomerAddress | null
  ): string => address?.customer?.customerName || route.customer?.customerName || '公共地址'

  const getEndpointContact = (address?: CustomerAddress | null): string =>
    [address?.contactName, address?.contactPhone].filter(Boolean).join(' / ') || '未维护联系人'

  const getEndpointAddress = (address?: CustomerAddress | null): string =>
    formatOrderAddress(address?.region, address?.addressDetail) || '地址记录不可用'

  const selector = reactive<SelectorGroup>({
    value: undefined,
    selectedRows: [],
    columns: [
      { prop: 'routeName', label: '线路名称', minWidth: 180 },
      {
        prop: 'originCustomer',
        label: '发货客户',
        minWidth: 160,
        formatter: (row) => {
          const route = row as FavoriteRoute
          return getEndpointCustomerName(route, route.originAddress)
        }
      },
      {
        prop: 'originContact',
        label: '发货联系人',
        minWidth: 170,
        formatter: (row) => getEndpointContact((row as FavoriteRoute).originAddress)
      },
      {
        prop: 'originAddress',
        label: '发货地址',
        minWidth: 260,
        formatter: (row) => getEndpointAddress((row as FavoriteRoute).originAddress)
      },
      {
        prop: 'destinationCustomer',
        label: '收货客户',
        minWidth: 160,
        formatter: (row) => {
          const route = row as FavoriteRoute
          return getEndpointCustomerName(route, route.destinationAddress)
        }
      },
      {
        prop: 'destinationContact',
        label: '收货联系人',
        minWidth: 170,
        formatter: (row) => getEndpointContact((row as FavoriteRoute).destinationAddress)
      },
      {
        prop: 'destinationAddress',
        label: '收货地址',
        minWidth: 260,
        formatter: (row) => getEndpointAddress((row as FavoriteRoute).destinationAddress)
      }
    ]
  })

  const fetchSelectorData = async (params: DataSelectFetchParams) => {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchFavoriteRouteList({
      keyword: params.keyword,
      enabled: true,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  const getRouteLabel = (row: DataSelectRecord): string => (row as FavoriteRoute).routeName

  const getRouteDescription = (row: DataSelectRecord): string => {
    const route = row as FavoriteRoute
    return `${getEndpointAddress(route.originAddress)} → ${getEndpointAddress(route.destinationAddress)}`
  }

  const isRouteUnavailable = (row: DataSelectRecord): boolean => {
    const route = row as FavoriteRoute
    return !route.originAddress || !route.destinationAddress
  }

  const handleConfirm = (_value: unknown, rows: DataSelectRecord[]): void => {
    const route = rows[0] as FavoriteRoute | undefined
    if (!route?.originAddress || !route.destinationAddress) return
    emit('select', route)
  }

  async function handleOpen(): Promise<void> {
    Object.assign(selector, { value: undefined, selectedRows: [] })
    await nextTick()
    await selectRef.value?.open()
  }

  defineExpose({ handleOpen })
</script>
