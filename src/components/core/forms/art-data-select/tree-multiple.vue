<template>
  <ArtDataSelect
    ref="selectRef"
    v-bind="props"
    mode="tree"
    multiple
    @update:model-value="(value) => emit('update:modelValue', value)"
    @update:selected-data="(rows) => emit('update:selectedData', rows)"
    @change="(value, rows) => emit('change', value, rows)"
    @confirm="(value, rows) => emit('confirm', value, rows)"
    @clear="emit('clear')"
    @open="emit('open')"
    @close="emit('close')"
  >
    <template v-if="$slots.trigger" #trigger="slotProps">
      <slot name="trigger" v-bind="slotProps" />
    </template>
  </ArtDataSelect>
</template>

<script setup lang="ts">
  import ArtDataSelect from './index.vue'
  import type { ArtDataSelectEmits, ArtDataSelectExpose, ArtDataSelectMultipleProps } from './types'

  defineOptions({ name: 'ArtTreeMultipleSelect' })

  const props = withDefaults(defineProps<ArtDataSelectMultipleProps>(), {
    data: () => [],
    selectedData: () => [],
    columns: () => [],
    title: '选择数据',
    subtitle: '',
    placeholder: '请选择',
    searchPlaceholder: '请输入关键词',
    filterPlaceholder: '请选择分类',
    filterKey: 'type',
    filterOptions: () => [],
    rowKey: 'id',
    labelKey: 'label',
    descriptionKey: undefined,
    disabledKey: 'disabled',
    childrenKey: 'children',
    resultField: 'data',
    totalField: 'total',
    dialogWidth: 'xl',
    fullscreen: false,
    pageSize: 10,
    pageSizes: () => [10, 20, 30, 50],
    showPagination: false,
    showSearch: true,
    showSelectedPanel: true,
    clearable: true,
    disabled: false,
    reserveSelected: true,
    treeCheckStrictly: true,
    maxTagCount: 2,
    emptyText: '暂无数据'
  })
  const emit = defineEmits<ArtDataSelectEmits>()
  const selectRef = ref<ArtDataSelectExpose>()

  defineExpose<ArtDataSelectExpose>({
    open: () => selectRef.value?.open() ?? Promise.resolve(),
    close: () => selectRef.value?.close(),
    clear: () => selectRef.value?.clear(),
    reload: () => selectRef.value?.reload() ?? Promise.resolve()
  })
</script>
