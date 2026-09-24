<template>
  <component
    :is="selectorComponent"
    :model-value="multiple ? modelValues : modelValue"
    :selected-data="selectedData"
    :api-fn="apiFn"
    :columns="columns"
    :navigation="navigation"
    row-key="id"
    :label-key="labelKey || getMaterialLabel"
    :description-key="getMaterialDescription"
    :title="title"
    :subtitle="subtitle"
    :placeholder="placeholder"
    :search-placeholder="searchPlaceholder"
    :empty-text="emptyText"
    :empty-description="emptyDescription"
    :disabled-key="disabledKey"
    :disabled="disabled"
    :clearable="clearable"
    :show-selected-panel="showSelectedPanel"
    :reset-draft-on-open="resetDraftOnOpen"
    :show-pagination="true"
    :page-size="10"
    :page-sizes="[10, 20, 30, 50]"
    @update:model-value="updateValue"
    @update:selected-data="handleSelectedDataChange"
    @change="handleChange"
    @confirm="handleConfirm"
    @clear="emit('clear')"
  >
    <template v-if="$slots.trigger" #trigger="slotProps">
      <slot name="trigger" v-bind="slotProps" />
    </template>
  </component>
</template>

<script setup lang="ts">
  import type { Component } from 'vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
  import type {
    DataSelectApiFn,
    DataSelectColumn,
    DataSelectKey,
    DataSelectNavigation,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import { normalizeStringList } from '@/utils/form/normalize'

  defineOptions({ name: 'ArtMaterialSelect' })

  export interface MaterialSelectCategory {
    id: string
    parentId?: string | null
    categoryCode: string
    categoryName: string
  }

  export interface MaterialSelectRecord {
    id: string
    materialCode?: string | null
    materialName?: string | null
    description?: string | null
    specificationModel?: string | null
    drawingNo?: string | null
    materialComposition?: string | null
    brand?: string | null
    materialType?: string | null
    inboundWarehouseId?: string | null
    materialSource?: string | null
    specialPurchaseType?: string | null
    category?: { categoryName?: string | null } | null
    materialTypeRef?: { typeName?: string | null } | null
  }

  interface Props {
    modelValue?: string
    multiple?: boolean
    modelValues?: string[]
    selectedData?: MaterialSelectRecord[]
    apiFn: DataSelectApiFn
    categories?: MaterialSelectCategory[]
    title?: string
    subtitle?: string
    placeholder?: string
    searchPlaceholder?: string
    emptyText?: string
    emptyDescription?: string
    disabledKey?: string | ((row: DataSelectRecord) => boolean)
    disabled?: boolean
    clearable?: boolean
    showSelectedPanel?: boolean
    labelKey?: string | ((row: DataSelectRecord) => string)
    resetDraftOnOpen?: boolean
  }

  const props = withDefaults(defineProps<Props>(), {
    modelValue: undefined,
    multiple: false,
    modelValues: () => [],
    selectedData: () => [],
    categories: () => [],
    title: '数据来源物料编码',
    subtitle: '按物料分类筛选并选择业务所需的物料编码',
    placeholder: '请选择物料',
    searchPlaceholder: '搜索物料编码、名称、规格型号或图号',
    emptyText: '暂无可选物料',
    emptyDescription: '请先维护物料编码后再继续当前业务。',
    disabledKey: undefined,
    disabled: false,
    clearable: true,
    showSelectedPanel: true,
    resetDraftOnOpen: false
  })

  const emit = defineEmits<{
    'update:modelValue': [value: string | undefined]
    'update:modelValues': [value: string[]]
    'update:selectedData': [rows: MaterialSelectRecord[]]
    change: [value: string | string[] | undefined, rows: MaterialSelectRecord[]]
    confirm: [value: string | string[] | undefined, rows: MaterialSelectRecord[]]
    clear: []
  }>()

  const selectorComponent = computed<Component>(() =>
    props.multiple ? ArtTableMultipleSelect : ArtTableSingleSelect
  )

  const getMaterial = (row: DataSelectRecord): MaterialSelectRecord => row as MaterialSelectRecord

  const getMaterialLabel = (row: DataSelectRecord): string =>
    getMaterial(row).materialName || '未命名物料'

  const getMaterialDescription = (row: DataSelectRecord): string =>
    getMaterial(row).materialCode || '未维护编码'

  const columns: DataSelectColumn[] = [
    { prop: 'materialCode', label: '物料编码', minWidth: 150 },
    { prop: 'materialName', label: '物料名称', minWidth: 180 },
    { prop: 'description', label: '物料描述', minWidth: 220 },
    { prop: 'specificationModel', label: '规格型号', minWidth: 150 },
    { prop: 'drawingNo', label: '图号', minWidth: 130 },
    { prop: 'materialComposition', label: '材质', minWidth: 120 },
    { prop: 'brand', label: '品牌', minWidth: 120 },
    { prop: 'category.categoryName', label: '物料分类', minWidth: 140 },
    {
      prop: 'materialTypeRef.typeName',
      label: '物料类型',
      minWidth: 120,
      formatter: (row) => {
        const material = getMaterial(row)
        return material.materialTypeRef?.typeName || material.materialType || '—'
      }
    },
    {
      prop: 'materialSource',
      label: '物料来源',
      minWidth: 110,
      dict: { code: 'mdmMaterialSource' }
    },
    {
      prop: 'specialPurchaseType',
      label: '特殊采购类',
      minWidth: 120,
      dict: { code: 'mdmMaterialSpecialPurchaseType', display: 'tag' }
    }
  ]

  const navigation = computed<DataSelectNavigation>(() => ({
    data: props.categories.map((category) => ({ ...category })),
    title: '物料分类',
    rowKey: 'id',
    parentKey: 'parentId',
    labelKey: 'categoryName',
    descriptionKey: 'categoryCode',
    filterKey: 'categoryId',
    allLabel: '全部分类',
    allDescription: `${props.categories.length} 个分类节点`,
    searchPlaceholder: '搜索分类名称或编码',
    emptyText: '暂无物料分类'
  }))

  const normalizeValue = (
    value: DataSelectKey | DataSelectKey[] | undefined
  ): string | undefined => {
    const selectedValue = Array.isArray(value) ? value[0] : value
    return selectedValue == null ? undefined : String(selectedValue)
  }

  const updateValue = (value: DataSelectKey | DataSelectKey[] | undefined): void => {
    if (props.multiple) emit('update:modelValues', normalizeStringList(value))
    else emit('update:modelValue', normalizeValue(value))
  }

  const normalizeRows = (rows: DataSelectRecord[]): MaterialSelectRecord[] => rows.map(getMaterial)

  const normalizedEventValue = (
    value: DataSelectKey | DataSelectKey[] | undefined
  ): string | string[] | undefined =>
    props.multiple ? normalizeStringList(value) : normalizeValue(value)

  const handleSelectedDataChange = (rows: DataSelectRecord[]): void =>
    emit('update:selectedData', normalizeRows(rows))

  const handleChange = (
    value: DataSelectKey | DataSelectKey[] | undefined,
    rows: DataSelectRecord[]
  ): void => emit('change', normalizedEventValue(value), normalizeRows(rows))

  const handleConfirm = (
    value: DataSelectKey | DataSelectKey[] | undefined,
    rows: DataSelectRecord[]
  ): void => emit('confirm', normalizedEventValue(value), normalizeRows(rows))
</script>
