<template>
  <ElDescriptions
    class="vehicle-query-info-grid"
    :column="column"
    border
    label-class-name="vehicle-query-info-grid__label"
    class-name="vehicle-query-info-grid__value"
  >
    <ElDescriptionsItem v-for="item in items" :key="item.label" :label="item.label">
      <template #default>
        <ArtDictDisplay
          v-if="item.dictCode"
          :dict-code="item.dictCode"
          :value="formatDictValue(item.value)"
          display="text"
          :empty-text="formatValue(item.value, item.suffix)"
        />
        <template v-else>{{ formatValue(item.value, item.suffix) }}</template>
      </template>
    </ElDescriptionsItem>
  </ElDescriptions>
</template>

<script setup lang="ts">
  import { ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { InfoItem } from './types'
  import { formatValue } from './query-format'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleQueryInfoGrid' })

  withDefaults(
    defineProps<{
      items: InfoItem[]
      column?: number
    }>(),
    {
      column: 3
    }
  )

  const formatDictValue = (value?: unknown): string | undefined => {
    if (isNil(value) || value === '') return undefined
    return String(value)
  }
</script>

<style scoped lang="scss">
  .vehicle-query-info-grid {
    :deep(.vehicle-query-info-grid__label) {
      width: 128px;
      font-weight: 600;
      color: var(--el-text-color-primary);
      background: var(--el-fill-color-lighter);
    }

    :deep(.vehicle-query-info-grid__value) {
      min-width: 180px;
      color: var(--el-text-color-secondary);
      overflow-wrap: anywhere;
    }
  }
</style>
