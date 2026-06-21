<template>
  <nav class="vehicle-query-side-tabs">
    <button
      v-for="tab in tabs"
      :key="tab.key"
      type="button"
      class="vehicle-query-side-tabs__item"
      :class="{ 'is-active': modelValue === tab.key }"
      @click="emit('update:modelValue', tab.key)"
    >
      {{ tab.label }}
    </button>
  </nav>
</template>

<script setup lang="ts">
  import type { VehicleQueryTab, VehicleQueryTabKey } from './types'

  defineOptions({ name: 'VehicleQuerySideTabs' })

  defineProps<{
    modelValue: VehicleQueryTabKey
    tabs: VehicleQueryTab[]
  }>()

  const emit = defineEmits<{
    (e: 'update:modelValue', value: VehicleQueryTabKey): void
  }>()
</script>

<style scoped lang="scss">
  .vehicle-query-side-tabs {
    display: flex;
    flex-direction: column;
    width: 136px;
    min-height: 100%;
    padding: 0;
    overflow: hidden;
    background: var(--el-bg-color);
    border-right: 1px solid var(--el-border-color-lighter);

    &__item {
      height: 64px;
      padding: 0 16px;
      font-size: 15px;
      color: var(--el-text-color-secondary);
      text-align: center;
      cursor: pointer;
      background: transparent;
      border: 0;

      &:hover {
        color: var(--el-color-primary);
      }

      &.is-active {
        font-weight: 600;
        color: var(--el-color-primary);
        box-shadow: inset 4px 0 0 var(--el-color-primary);
      }
    }
  }
</style>
