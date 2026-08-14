<template>
  <section class="metric-cards" aria-label="运营关键指标">
    <button
      v-for="(item, index) in items"
      :key="item.key"
      type="button"
      class="metric-card art-card-xs"
      :class="`metric-card--${item.tone}`"
      :aria-label="`查看${item.label}详情`"
      @click="emit('select', item.route)"
    >
      <span class="metric-card__index">0{{ index + 1 }}</span>
      <span class="metric-card__icon" :class="`metric-card__icon--${item.tone}`">
        <ArtSvgIcon :icon="item.icon" />
      </span>
      <div>
        <p>{{ item.label }}</p>
        <strong
          >{{ item.value }} <em v-if="item.unit">{{ item.unit }}</em></strong
        >
        <small>{{ item.hint }}</small>
      </div>
      <ArtSvgIcon class="metric-card__arrow" icon="ri:arrow-right-s-line" aria-hidden="true" />
    </button>
  </section>
</template>

<script setup lang="ts">
  import type { DashboardMetric } from './types'

  defineProps<{ items: DashboardMetric[] }>()
  const emit = defineEmits<{ select: [route: string] }>()
</script>

<style scoped lang="scss">
  .metric-cards {
    display: grid;
    grid-template-columns: repeat(6, minmax(0, 1fr));
    gap: var(--art-space-4);
  }

  .metric-card {
    --metric-color: var(--el-color-primary);

    position: relative;
    display: flex;
    gap: 13px;
    align-items: center;
    min-width: 0;
    min-height: 106px;
    padding: 18px;
    overflow: hidden;
    font: inherit;
    text-align: left;
    cursor: pointer;
    background: var(--default-box-color);
    border-color: color-mix(in srgb, var(--metric-color) 15%, var(--el-border-color-lighter));
    transition:
      background 0.18s ease,
      border-color 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.18s ease;

    &::before {
      position: absolute;
      top: 0;
      left: 0;
      width: 3px;
      height: 100%;
      content: '';
      background: var(--metric-color);
    }

    &:focus-visible {
      outline: 2px solid color-mix(in srgb, var(--theme-color) 55%, transparent);
      outline-offset: 2px;
    }

    &--warning {
      --metric-color: var(--el-color-warning);
    }

    &--success {
      --metric-color: var(--el-color-success);
    }

    &--danger {
      --metric-color: var(--el-color-danger);
    }

    &--info {
      --metric-color: var(--el-color-info);
    }

    > div {
      display: grid;
      gap: 3px;
      min-width: 0;
    }

    p,
    small {
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 11px;
      color: var(--el-text-color-secondary);
      white-space: nowrap;
    }

    strong {
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 22px;
      line-height: 1.25;
      color: var(--el-text-color-primary);
      white-space: nowrap;

      em {
        font-size: 12px;
        font-style: normal;
        font-weight: 500;
        color: var(--el-text-color-placeholder);
      }
    }

    small {
      color: var(--el-text-color-placeholder);
    }

    &:hover .metric-card__arrow,
    &:focus-visible .metric-card__arrow {
      color: var(--theme-color);
      opacity: 1;
      transform: translateX(2px);
    }
  }

  .metric-card__index {
    position: absolute;
    top: 11px;
    right: 12px;
    font-size: 9px;
    font-weight: 700;
    color: color-mix(in srgb, var(--metric-color) 50%, var(--el-text-color-placeholder));
    letter-spacing: 0.08em;
  }

  .metric-card__icon {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    font-size: 19px;
    border-radius: var(--el-border-radius-base);

    &--primary {
      color: var(--el-color-primary);
      background: color-mix(in srgb, var(--el-color-primary) 14%, var(--el-bg-color));
    }

    &--info {
      color: var(--el-color-info);
      background: color-mix(in srgb, var(--el-color-info) 14%, var(--el-bg-color));
    }

    &--warning {
      color: var(--el-color-warning);
      background: color-mix(in srgb, var(--el-color-warning) 14%, var(--el-bg-color));
    }

    &--success {
      color: var(--el-color-success);
      background: color-mix(in srgb, var(--el-color-success) 14%, var(--el-bg-color));
    }

    &--danger {
      color: var(--el-color-danger);
      background: color-mix(in srgb, var(--el-color-danger) 14%, var(--el-bg-color));
    }
  }

  .metric-card__arrow {
    position: absolute;
    right: 12px;
    bottom: 12px;
    font-size: 17px;
    color: var(--el-text-color-placeholder);
    opacity: 0;
    transition:
      color 0.18s ease,
      opacity 0.18s ease,
      transform 0.18s ease;
  }

  :global([data-box-mode='border-mode'] .metric-card:hover),
  :global([data-box-mode='border-mode'] .metric-card:focus-visible) {
    background: color-mix(in srgb, var(--theme-color) 5%, var(--default-box-color));
    border-color: color-mix(in srgb, var(--theme-color) 28%, var(--el-border-color-lighter));
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--theme-color) 8%, transparent);
    transform: translateY(-2px);
  }

  :global([data-box-mode='shadow-mode'] .metric-card:hover),
  :global([data-box-mode='shadow-mode'] .metric-card:focus-visible) {
    background: color-mix(in srgb, var(--theme-color) 5%, var(--default-box-color));
    border-color: transparent;
    box-shadow: 0 12px 28px color-mix(in srgb, var(--theme-color) 14%, transparent);
    transform: translateY(-2px);
  }

  @media screen and (width <= 1360px) {
    .metric-cards {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }
  }

  @media screen and (width <= 760px) {
    .metric-cards {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media screen and (width <= 480px) {
    .metric-cards {
      grid-template-columns: 1fr;
    }
  }
</style>
