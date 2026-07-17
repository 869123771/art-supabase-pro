<template>
  <ArtTableMultipleSelect
    ref="selectRef"
    v-model="selector.value"
    v-model:selected-data="selector.selectedRows"
    :api-fn="fetchCargoSelectorData"
    :columns="columns"
    title="批量选择货物"
    subtitle="从货物管理中选择后，会自动带入计量单位、单件体积和单件重量。"
    row-key="id"
    label-key="cargoName"
    description-key="cargoCode"
    search-placeholder="请输入货物名称、编码、单位或备注"
    dialog-width="1040px"
    show-pagination
    :page-size="10"
    @confirm="handleConfirm"
  >
    <template #trigger></template>
  </ArtTableMultipleSelect>
</template>

<script setup lang="ts">
  import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
  import type {
    ArtDataSelectExpose,
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import { fetchCargoList } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'

  defineOptions({ name: 'TmsCargoMultipleSelect' })

  type CargoMaster = Api.Tms.BasicData.Cargo

  interface CargoSelectorState {
    selectedRows: DataSelectRecord[]
    value: Array<string | number>
  }

  const selectRef = ref<ArtDataSelectExpose>()
  const selector = reactive<CargoSelectorState>({
    selectedRows: [],
    value: []
  })
  const columns: DataSelectColumn[] = [
    { prop: 'cargoCode', label: '货物编码', width: 150 },
    { prop: 'cargoName', label: '货物名称', minWidth: 220 },
    { prop: 'unit', label: '单位', width: 100 },
    { prop: 'volumeM3', label: '单件体积（m³）', width: 140 },
    { prop: 'weightKg', label: '单件重量（kg）', width: 140 }
  ]

  const emit = defineEmits<{
    confirm: [rows: CargoMaster[]]
  }>()

  async function open(): Promise<void> {
    await selectRef.value?.open()
  }

  async function fetchCargoSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCargoList({
      keyword: String(params.keyword ?? '').trim(),
      enabled: true,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  function handleConfirm(_value: unknown, rows: DataSelectRecord[]): void {
    emit('confirm', rows as CargoMaster[])
    selector.value = []
    selector.selectedRows = []
  }

  defineExpose({ open })
</script>
