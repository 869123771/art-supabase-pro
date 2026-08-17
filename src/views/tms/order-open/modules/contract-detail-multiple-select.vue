<template>
  <ArtTableMultipleSelect
    ref="selectRef"
    v-model="selector.value"
    v-model:selected-data="selector.selectedRows"
    :api-fn="fetchSelectorData"
    :columns="columns"
    title="批量选择合同明细"
    subtitle="仅展示审核通过、未完成且在有效期内的合同明细；确认后带入货物、计量单位和合同单价。"
    row-key="key"
    label-key="cargoDescription"
    :description-key="getDescription"
    search-placeholder="请输入合同编号、合同名称、货物名称或编码"
    dialog-width="xl"
    show-pagination
    :page-size="10"
    empty-text="暂无可用合同明细"
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
  import { fetchAvailableContractDetailList } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'

  defineOptions({ name: 'TmsContractDetailMultipleSelect' })

  type ContractDetail = Api.Tms.BasicData.ContractDetailSelectorItem

  interface SelectorState {
    selectedRows: DataSelectRecord[]
    value: Array<string | number>
  }

  const selectRef = ref<ArtDataSelectExpose>()
  const selector = reactive<SelectorState>({ selectedRows: [], value: [] })
  const columns: DataSelectColumn[] = [
    { prop: 'contractNo', label: '合同编号', width: 160 },
    { prop: 'contractName', label: '合同名称', minWidth: 190 },
    { prop: 'cargoDescription', label: '货物名称', minWidth: 170 },
    { prop: 'cargoCode', label: '货物编码', width: 130 },
    {
      prop: 'unit',
      label: '计量单位',
      width: 110,
      dict: { code: 'tmsCargoUnit', display: 'auto' }
    },
    { prop: 'contractQuantity', label: '合同数量', width: 120, align: 'right' },
    {
      prop: 'transportUnitPrice',
      label: '合同单价（元）',
      width: 150,
      align: 'right',
      formatter: (row) => Number(row.transportUnitPrice ?? 0).toFixed(2)
    }
  ]

  const emit = defineEmits<{ confirm: [rows: ContractDetail[]] }>()

  const open = async (): Promise<void> => {
    await selectRef.value?.open()
  }

  const fetchSelectorData = async (params: DataSelectFetchParams) => {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    return await fetchAvailableContractDetailList({ keyword: params.keyword, from, to })
  }

  const getDescription = (row: DataSelectRecord): string =>
    [row.contractNo, row.cargoCode].filter(Boolean).join(' / ')

  const handleConfirm = (_value: unknown, rows: DataSelectRecord[]): void => {
    emit('confirm', rows as ContractDetail[])
    selector.value = []
    selector.selectedRows = []
  }

  defineExpose({ open })
</script>
