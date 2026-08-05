<template>
  <ArtTableSingleSelect
    ref="selectRef"
    v-model="selector.value"
    v-model:selected-data="selector.selectedRows"
    :api-fn="fetchSelectorData"
    :columns="selector.columns"
    :title="selector.title"
    row-key="id"
    :label-key="getCustomerLabel"
    :description-key="getCustomerDescription"
    search-placeholder="请输入客户名称/电话/地址搜索"
    dialog-width="lg"
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
  import { fetchCustomerSelectorList } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'

  defineOptions({ name: 'TmsOrderCustomerSelectorDialog' })

  type SelectorMode = 'shipping' | 'receiving'
  type CustomerItem = Api.Tms.Order.CustomerSelectorItem

  interface SelectorGroup {
    mode: SelectorMode
    title: string
    value?: string | number
    selectedRows: DataSelectRecord[]
    columns: DataSelectColumn[]
  }

  const emit = defineEmits<{
    (event: 'select', mode: SelectorMode, row: CustomerItem): void
  }>()

  const selectRef = ref<ArtDataSelectExpose>()

  const selector = reactive<SelectorGroup>({
    mode: 'shipping',
    title: '选择发货人客户',
    value: undefined,
    selectedRows: [],
    columns: [
      { prop: 'customerName', label: '客户名称', minWidth: 160 },
      { prop: 'contactName', label: '联系人', width: 120 },
      { prop: 'contactPhone', label: '联系电话', width: 150 },
      { prop: 'region', label: '区域', minWidth: 150 },
      { prop: 'addressDetail', label: '详细地址', minWidth: 260 }
    ]
  })

  const fetchSelectorData = async (params: DataSelectFetchParams) => {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerSelectorList({
      keyword: params.keyword,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  const getCustomerLabel = (row: DataSelectRecord): string => {
    const customer = row as CustomerItem
    return customer.contactName || customer.customerName
  }

  const getCustomerDescription = (row: DataSelectRecord): string => {
    const customer = row as CustomerItem
    return [customer.contactPhone, customer.region, customer.addressDetail]
      .filter(Boolean)
      .join(' / ')
  }

  const handleConfirm = (_value: unknown, rows: DataSelectRecord[]): void => {
    const customer = rows[0] as CustomerItem | undefined
    if (!customer) return
    emit('select', selector.mode, customer)
  }

  async function handleOpen(mode: SelectorMode): Promise<void> {
    Object.assign(selector, {
      mode,
      title: mode === 'shipping' ? '选择发货人客户' : '选择收货人客户',
      value: undefined,
      selectedRows: []
    })
    await nextTick()
    await selectRef.value?.open()
  }

  defineExpose({ handleOpen })
</script>
