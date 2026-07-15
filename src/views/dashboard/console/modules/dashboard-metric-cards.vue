<template>
  <section class="metric-cards">
    <article v-for="item in items" :key="item.key" class="metric-card art-card-xs">
      <span class="metric-card__icon" :class="`metric-card__icon--${item.tone}`">
        <ArtSvgIcon :icon="item.icon" />
      </span>
      <div>
        <p>{{ item.label }}</p>
        <strong>{{ item.value }}</strong>
        <small>{{ item.hint }}</small>
      </div>
    </article>
  </section>
</template>

<script setup lang="ts">
  import type { DashboardMetric } from './types'

  defineProps<{ items: DashboardMetric[] }>()
</script>

<style scoped lang="scss">
  .metric-cards {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 16px;
  }
  .metric-card {
    display: flex;
    gap: 13px;
    align-items: center;
    min-width: 0;
    min-height: 96px;
    padding: 18px 20px;
  }
  .metric-card__icon {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    width: 39px;
    height: 39px;
    font-size: 19px;
    border-radius: var(--el-border-radius-base);
  }
  .metric-card__icon--blue {
    color: var(--el-color-primary);
    background: color-mix(in srgb, var(--el-color-primary) 15%, var(--el-bg-color));
  }
  .metric-card__icon--orange {
    color: var(--el-color-warning);
    background: color-mix(in srgb, var(--el-color-warning) 15%, var(--el-bg-color));
  }
  .metric-card__icon--green {
    color: var(--el-color-success);
    background: color-mix(in srgb, var(--el-color-success) 15%, var(--el-bg-color));
  }
  .metric-card__icon--red {
    color: var(--el-color-danger);
    background: color-mix(in srgb, var(--el-color-danger) 15%, var(--el-bg-color));
  }
  .metric-card div {
    display: grid;
    min-width: 0;
    gap: 3px;
  }
  .metric-card p,
  .metric-card small {
    margin: 0;
    overflow: hidden;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .metric-card strong {
    font-size: 23px;
    line-height: 1.2;
    color: var(--el-text-color-primary);
  }
  .metric-card small {
    color: var(--el-text-color-placeholder);
  }

  @media screen and (max-width: 960px) {
    .metric-cards {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media screen and (max-width: 560px) {
    .metric-cards {
      grid-template-columns: 1fr;
    }
  }
</style>
