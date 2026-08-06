<template>
  <section class="metric-cards">
    <article
      v-for="(item, index) in items"
      :key="item.key"
      class="metric-card art-card-xs"
      :class="`metric-card--${item.tone}`"
    >
      <span class="metric-card__index">0{{ index + 1 }}</span>
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
    gap: var(--art-space-4);
  }

  .metric-card {
    --metric-color: var(--el-color-primary);

    position: relative;
    display: flex;
    gap: 15px;
    align-items: center;
    min-width: 0;
    min-height: 112px;
    padding: 20px 22px;
    overflow: hidden;
    border-color: color-mix(in srgb, var(--metric-color) 15%, var(--el-border-color-lighter));
    transition:
      border-color 0.2s ease,
      box-shadow 0.2s ease,
      transform 0.2s ease;

    &::before {
      position: absolute;
      top: 0;
      left: 0;
      width: 4px;
      height: 100%;
      content: '';
      background: var(--metric-color);
    }

    &::after {
      position: absolute;
      top: -48px;
      right: -48px;
      width: 110px;
      height: 110px;
      content: '';
      background: color-mix(in srgb, var(--metric-color) 9%, transparent);
      border-radius: 50%;
    }

    &:hover {
      border-color: color-mix(in srgb, var(--metric-color) 30%, var(--el-border-color));
      box-shadow: 0 14px 32px color-mix(in srgb, var(--metric-color) 10%, transparent);
      transform: translateY(-2px);
    }

    &--orange {
      --metric-color: var(--el-color-warning);
    }

    &--green {
      --metric-color: var(--el-color-success);
    }

    &--red {
      --metric-color: var(--el-color-danger);
    }
  }

  .metric-card__index {
    position: absolute;
    top: 13px;
    right: 15px;
    z-index: 1;
    font-size: 9px;
    font-weight: 700;
    color: color-mix(in srgb, var(--metric-color) 50%, var(--el-text-color-placeholder));
    letter-spacing: 1px;
  }

  .metric-card__icon {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    width: 46px;
    height: 46px;
    font-size: 21px;
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
    gap: 4px;
    min-width: 0;
  }

  .metric-card p,
  .metric-card small {
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    white-space: nowrap;
  }

  .metric-card strong {
    font-size: 25px;
    line-height: 1.2;
    color: var(--el-text-color-primary);
  }

  .metric-card small {
    color: var(--el-text-color-placeholder);
  }

  @media screen and (width <= 960px) {
    .metric-cards {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media screen and (width <= 560px) {
    .metric-cards {
      grid-template-columns: 1fr;
    }
  }
</style>
