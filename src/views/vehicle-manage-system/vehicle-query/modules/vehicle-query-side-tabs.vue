<template>
  <ElScrollbar class="vehicle-query-side-tabs">
    <nav class="vehicle-query-side-tabs__list" aria-label="车辆详情分类">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="vehicle-query-side-tabs__item"
        :class="{ 'is-active': modelValue === tab.key }"
        :aria-current="modelValue === tab.key ? 'page' : undefined"
        @click="emit('update:modelValue', tab.key)"
      >
        {{ tab.label }}
      </button>
    </nav>
  </ElScrollbar>
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
    width: 136px;
    height: 100%;
    min-height: 100%;
    background: var(--el-bg-color);
    border-right: 1px solid var(--el-border-color-lighter);

    &__list {
      display: flex;
      flex-direction: column;
    }

    &__item {
      flex: none;
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
        background: var(--el-fill-color-light);
      }

      &:focus-visible {
        outline: 2px solid var(--el-color-primary-light-3);
        outline-offset: -2px;
      }

      &.is-active {
        font-weight: 600;
        color: var(--el-color-primary);
        box-shadow: inset 4px 0 0 var(--el-color-primary);
      }
    }

    @media (width <= 900px) {
      width: 100%;
      height: 56px;
      min-height: 56px;
      border-right: 0;
      border-bottom: 1px solid var(--el-border-color-lighter);

      &__list {
        flex-direction: row;
        width: max-content;
        min-width: 100%;
      }

      &__item {
        min-width: 104px;
        height: 56px;
        padding-inline: var(--art-space-3);

        &.is-active {
          box-shadow: inset 0 -3px 0 var(--el-color-primary);
        }
      }
    }
  }
</style>
