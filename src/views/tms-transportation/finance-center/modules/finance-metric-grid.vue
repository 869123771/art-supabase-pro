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

  defineOptions({ name: 'TmsFinanceMetricGrid' })
  defineProps<{ items: FinanceMetric[] }>()
</script>

<style scoped lang="scss">
  .finance-metric-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;

    &__item {
      display: flex;
      gap: 14px;
      align-items: center;
      min-height: 116px;
      padding: 18px;
    }

    &__icon {
      display: grid;
      width: 48px;
      height: 48px;
      font-size: 24px;
      border-radius: 14px;
      place-items: center;

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

      span,
      small {
        color: var(--el-text-color-secondary);
      }
      strong {
        font-size: 23px;
        font-weight: 650;
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
