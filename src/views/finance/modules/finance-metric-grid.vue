<template>
  <div class="finance-metric-grid">
    <div v-for="item in items" :key="item.label" class="finance-metric-grid__item art-card-xs">
      <div :class="['finance-metric-grid__icon', `is-${item.tone}`]">
        <ArtSvgIcon :icon="item.icon" />
      </div>
      <div class="finance-metric-grid__content">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
        <small>{{ item.trend }}</small>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { FinanceMetric } from './finance-types'

  defineOptions({ name: 'FinanceMetricGrid' })
  defineProps<{ items: FinanceMetric[] }>()
</script>

<style scoped lang="scss">
  .finance-metric-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 16px;

    &__item {
      position: relative;
      display: flex;
      gap: 14px;
      align-items: center;
      min-width: 0;
      min-height: 122px;
      padding: 20px;
      overflow: hidden;
      border-top: 3px solid var(--el-color-primary-light-5);
    }

    &__icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 24px;
      border-radius: var(--art-feature-radius);

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning);
        background: var(--el-color-warning-light-9);
      }

      &.is-danger {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }
    }

    &__content {
      display: grid;
      gap: 4px;
      min-width: 0;

      span,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      strong {
        font-size: 23px;
        font-weight: 650;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }
    }
  }

  @media (width <= 1100px) {
    .finance-metric-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (width <= 640px) {
    .finance-metric-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
