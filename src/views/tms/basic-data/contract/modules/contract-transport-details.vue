<template>
  <section class="contract-transport-details art-card-xs" aria-label="运输合同明细">
    <div class="contract-transport-details__header">
      <div>
        <ArtSectionTitle :show-line="false">运输合同明细</ArtSectionTitle>
        <p>
          {{
            editable
              ? '按货物维护合同数量、计量单位和运输价格，运费自动按数量与单价计算。'
              : '当前字段权限仅允许查看运输明细，修改需获得明细价格可编辑权限。'
          }}
        </p>
      </div>
      <div v-if="editable" class="contract-transport-details__actions">
        <ElButton plain @click="openCargoSelector">
          <template #icon><ArtSvgIcon icon="ri:archive-stack-line" /></template>
          批量选货物
        </ElButton>
        <ElButton type="primary" plain @click="addDetail">
          <template #icon><ArtSvgIcon icon="ri:add-line" /></template>
          新增明细
        </ElButton>
      </div>
    </div>

    <ArtTable
      :data="modelValue"
      :columns="columns"
      :pagination="undefined"
      empty-text="暂无运输合同明细"
      empty-description="点击“新增明细”维护合同约定的货物、数量和价格。"
      empty-height="180px"
    />

    <CargoMultipleSelect ref="cargoSelectorRef" @confirm="handleCargoSelectorConfirm" />
  </section>
</template>

<script setup lang="tsx">
  import { round } from 'lodash-es'
  import {
    ElAutocomplete,
    ElButton,
    ElInput,
    ElInputNumber,
    ElOption,
    ElSelect,
    type AutocompleteFetchSuggestionsCallback
  } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCargoList } from '@/api/tms'
  import CargoMultipleSelect from '@/views/tms/modules/cargo-multiple-select.vue'
  import { mergeContractCargoSelections } from './contract-cargo-selection'
  import { formatSensitiveNumber } from '@/utils/field-permission'

  defineOptions({ name: 'ContractTransportDetails' })

  type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail
  type Cargo = Api.Tms.BasicData.Cargo

  interface CargoSuggestion extends Cargo {
    value: string
  }

  interface CargoSelectorExpose {
    open: () => Promise<void>
  }

  interface Props {
    modelValue: ContractTransportDetail[]
    unitOptions: Api.DataCenter.DictListItem[]
    pricingAccess: Api.Tms.BasicData.FieldAccessLevel
    editable: boolean
  }

  const props = defineProps<Props>()
  const cargoSelectorRef = ref<CargoSelectorExpose>()
  const emit = defineEmits<{
    'update:modelValue': [value: ContractTransportDetail[]]
  }>()

  const createInitialDetail = (): ContractTransportDetail => ({
    cargoId: null,
    cargoDescription: '',
    cargoCode: '',
    contractQuantity: 1,
    unit: '',
    transportUnitPrice: 0,
    freight: 0
  })

  const updateDetail = (
    current: ContractTransportDetail,
    patch: Partial<ContractTransportDetail>
  ): void => {
    if (!props.editable) return
    emit(
      'update:modelValue',
      props.modelValue.map((item) => {
        if (item !== current) return item
        const next = { ...item, ...patch }
        if (
          props.pricingAccess === 'edit' &&
          ('contractQuantity' in patch || 'transportUnitPrice' in patch)
        ) {
          next.freight = round(
            Number(next.contractQuantity || 0) * Number(next.transportUnitPrice || 0),
            2
          )
        }
        return next
      })
    )
  }

  const canViewPricing = computed(() => props.pricingAccess !== 'hidden')
  const canEditPricing = computed(() => props.editable && props.pricingAccess === 'edit')
  const numericModelValue = (
    value: Api.Tms.BasicData.SensitiveNumber | undefined
  ): number | null => (typeof value === 'number' ? value : null)

  const columns = computed<ColumnOption<ContractTransportDetail>[]>(() => [
    { type: 'globalIndex', label: '行号', width: 68, fixed: 'left' },
    {
      prop: 'cargoDescription',
      label: '货物描述',
      minWidth: 190,
      formatter: (row) => (
        <ElAutocomplete
          modelValue={row.cargoDescription}
          fetchSuggestions={(keyword, callback) => void fetchCargoSuggestions(keyword, callback)}
          valueKey="value"
          triggerOnFocus={true}
          clearable
          disabled={!props.editable}
          maxlength={120}
          placeholder="选择或输入货物"
          onUpdate:modelValue={(value: string | number) =>
            updateDetail(row, { cargoDescription: String(value), cargoId: null })
          }
          onSelect={(item: Record<string, unknown>) => handleCargoSelect(row, item)}
        />
      )
    },
    {
      prop: 'cargoCode',
      label: '货物编码',
      minWidth: 142,
      formatter: (row) => (
        <ElInput
          modelValue={row.cargoCode}
          maxlength={60}
          disabled={!props.editable}
          placeholder="请输入编码"
          onUpdate:modelValue={(value: string | number) =>
            updateDetail(row, { cargoCode: String(value) })
          }
        />
      )
    },
    {
      prop: 'contractQuantity',
      label: '合同数量',
      minWidth: 140,
      formatter: (row) => (
        <ElInputNumber
          modelValue={row.contractQuantity}
          min={0}
          precision={4}
          controls={false}
          disabled={!props.editable}
          class="w-full!"
          onUpdate:modelValue={(value?: number) =>
            updateDetail(row, { contractQuantity: Number(value ?? 0) })
          }
        />
      )
    },
    {
      prop: 'unit',
      label: '计量单位',
      minWidth: 130,
      formatter: (row) => (
        <ElSelect
          modelValue={row.unit}
          filterable
          disabled={!props.editable}
          placeholder="请选择"
          class="w-full!"
          onUpdate:modelValue={(value: string | number) =>
            updateDetail(row, { unit: String(value) })
          }
        >
          {props.unitOptions.map((item) => (
            <ElOption
              key={item.value}
              label={item.label || item.name || item.value}
              value={item.value}
            />
          ))}
        </ElSelect>
      )
    },
    ...(canViewPricing.value
      ? [
          {
            prop: 'transportUnitPrice',
            label: '运输单价(元)',
            minWidth: 154,
            formatter: (row: ContractTransportDetail) =>
              canEditPricing.value ? (
                <ElInputNumber
                  modelValue={numericModelValue(row.transportUnitPrice)}
                  min={0}
                  precision={4}
                  controls={false}
                  class="w-full!"
                  onUpdate:modelValue={(value?: number) =>
                    updateDetail(row, { transportUnitPrice: Number(value ?? 0) })
                  }
                />
              ) : (
                <span>
                  {formatSensitiveNumber(row.transportUnitPrice, {
                    maximumFractionDigits: 4
                  })}
                </span>
              )
          },
          {
            prop: 'freight',
            label: '运费(元)',
            minWidth: 130,
            align: 'right' as const,
            formatter: (row: ContractTransportDetail) => formatSensitiveNumber(row.freight)
          }
        ]
      : []),
    ...(props.editable
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 76,
            fixed: 'right' as const,
            formatter: (row: ContractTransportDetail) => (
              <ArtButtonTable type="delete" onClick={() => removeDetail(row)} />
            )
          }
        ]
      : [])
  ])

  const addDetail = (): void => {
    if (!props.editable) return
    emit('update:modelValue', [...props.modelValue, createInitialDetail()])
  }

  const openCargoSelector = async (): Promise<void> => {
    if (!props.editable) return
    await cargoSelectorRef.value?.open()
  }

  const handleCargoSelectorConfirm = (selectedCargoes: Cargo[]): void => {
    if (!props.editable) return
    const result = mergeContractCargoSelections(props.modelValue, selectedCargoes)
    if (result.addedCount) emit('update:modelValue', result.items)
  }

  const removeDetail = (row: ContractTransportDetail): void => {
    if (!props.editable) return
    emit(
      'update:modelValue',
      props.modelValue.filter((item) => item !== row)
    )
  }

  const fetchCargoSuggestions = async (
    keyword: string,
    callback: AutocompleteFetchSuggestionsCallback
  ): Promise<void> => {
    try {
      const { data } = await fetchCargoList({
        keyword: keyword.trim(),
        enabled: true,
        from: 0,
        to: 19
      })
      const suggestions: CargoSuggestion[] = (data ?? []).map((item) => ({
        ...item,
        value: item.cargoName
      }))
      callback(suggestions)
    } catch {
      callback([])
    }
  }

  const handleCargoSelect = (row: ContractTransportDetail, item: Record<string, unknown>): void => {
    updateDetail(row, {
      cargoId: item.id ? String(item.id) : null,
      cargoDescription: String(item.cargoName ?? item.value ?? ''),
      cargoCode: String(item.cargoCode ?? ''),
      unit: String(item.unit ?? row.unit ?? '')
    })
  }
</script>

<style scoped lang="scss">
  .contract-transport-details {
    min-width: 0;
    padding: 16px;

    &__header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 12px;

      p {
        margin: 5px 0 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    &__actions {
      display: flex;
      flex: none;
      flex-wrap: wrap;
      gap: 10px;
      justify-content: flex-end;

      :deep(.el-button) {
        flex: none;
        margin-left: 0;
        white-space: nowrap;
      }
    }

    :deep(.el-input-number),
    :deep(.el-autocomplete) {
      width: 100%;
    }

    @media (width <= 680px) {
      &__header {
        flex-direction: column;

        .contract-transport-details__actions {
          width: 100%;

          :deep(.el-button) {
            flex: 1 1 160px;
          }
        }
      }
    }
  }
</style>
