<template>
  <ArtDescriptions
    class="vehicle-query-info-grid"
    :data="descriptionData"
    :items="descriptionItems"
    :columns="column"
  />
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import type { InfoItem } from './types'
  import { formatValue } from './query-format'

  defineOptions({ name: 'VehicleQueryInfoGrid' })

  const props = withDefaults(
    defineProps<{
      items: InfoItem[]
      column?: number
    }>(),
    {
      column: 3
    }
  )

  const descriptionData = Object.freeze({})
  const descriptionItems = computed<ArtDescriptionItem[]>(() =>
    props.items.map((item, index) => ({
      key: `${item.label}-${index}`,
      label: item.label,
      value: item.value,
      dictCode: item.dictCode,
      dictDisplay: item.dictCode ? 'text' : undefined,
      formatter: item.dictCode ? undefined : () => formatValue(item.value, item.suffix)
    }))
  )
</script>

<style scoped lang="scss">
  .vehicle-query-info-grid {
    :deep(.el-descriptions__label) {
      width: 128px;
      font-weight: 600;
      color: var(--el-text-color-primary);
      background: var(--el-fill-color-lighter);
    }

    :deep(.el-descriptions__content) {
      min-width: 180px;
      color: var(--el-text-color-secondary);
      overflow-wrap: anywhere;
    }
  }
</style>
