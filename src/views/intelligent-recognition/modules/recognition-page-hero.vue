<template>
  <section class="recognition-hero art-card-xs">
    <div class="recognition-hero__copy">
      <span class="recognition-hero__icon"><ArtSvgIcon icon="ri:scan-2-line" /></span>
      <div>
        <div class="recognition-hero__eyebrow">
          <span>智能单据中台</span>
          <i aria-hidden="true"></i>
          <span>人工复核闭环</span>
        </div>
        <h1>{{ title }}</h1>
        <p>{{ subtitle }}</p>
      </div>
    </div>
    <div class="recognition-hero__metrics" aria-label="识别数据概览">
      <article v-for="item in metrics" :key="item.label">
        <small>{{ item.label }}</small>
        <strong>{{ item.value }}</strong>
        <span>{{ item.note }}</span>
      </article>
    </div>
    <div v-if="$slots.action" class="recognition-hero__action"><slot name="action" /></div>
  </section>
</template>

<script setup lang="ts">
  interface MetricItem {
    label: string
    value: string | number
    note: string
  }

  defineProps<{ title: string; subtitle: string; metrics: MetricItem[] }>()
</script>

<style scoped lang="scss">
  .recognition-hero {
    position: relative;
    display: grid;
    grid-template-columns: minmax(320px, 1.2fr) minmax(420px, 1fr) auto;
    gap: 20px;
    align-items: center;
    padding: 22px 24px;
    margin-bottom: 14px;
    overflow: hidden;
    background: var(--art-main-bg-color);

    &::before {
      position: absolute;
      top: 0;
      bottom: 0;
      left: 0;
      width: 3px;
      content: '';
      background: var(--theme-color);
    }

    &__copy,
    &__metrics {
      display: flex;
      align-items: center;
    }

    &__copy {
      gap: 13px;
      min-width: 0;

      h1 {
        margin: 5px 0 6px;
        font-size: 22px;
        line-height: 1.25;
        color: var(--art-text-gray-900);
      }

      p {
        max-width: 620px;
        margin: 0;
        font-size: 13px;
        line-height: 1.65;
        color: var(--art-text-gray-500);
      }
    }

    &__icon {
      display: grid;
      flex: 0 0 48px;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 23px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 9%, transparent);
      border: 1px solid color-mix(in srgb, var(--theme-color) 18%, transparent);
      border-radius: var(--custom-radius);
    }

    &__eyebrow {
      display: flex;
      gap: 7px;
      align-items: center;
      font-size: 11px;
      font-weight: 600;
      color: var(--art-text-gray-500);

      i {
        width: 3px;
        height: 3px;
        background: var(--theme-color);
        border-radius: 50%;
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(100px, 1fr));
      gap: 8px;

      article {
        min-width: 0;
        padding: 10px 12px;
        background: var(--art-gray-50);
        border: 1px solid var(--art-card-border);
        border-radius: var(--custom-radius);
      }

      small,
      strong,
      span {
        display: block;
      }

      small,
      span {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }

      small {
        font-size: 11px;
      }

      strong {
        margin: 3px 0 1px;
        font-size: 20px;
        color: var(--art-text-gray-900);
      }

      span {
        font-size: 10px;
      }
    }

    &__action {
      justify-self: end;
    }
  }

  @media (width <= 1180px) {
    .recognition-hero {
      grid-template-columns: 1fr auto;

      &__metrics {
        grid-row: 2;
        grid-column: 1 / -1;
      }
    }
  }

  @media (width <= 720px) {
    .recognition-hero {
      grid-template-columns: 1fr;
      padding: 18px;

      &__copy {
        align-items: flex-start;

        h1 {
          font-size: 21px;
        }
      }

      &__metrics {
        grid-template-columns: repeat(3, minmax(0, 1fr));
        grid-row: auto;
        grid-column: auto;
      }

      &__action,
      &__action :deep(.el-button) {
        width: 100%;
      }
    }
  }

  @media (width <= 520px) {
    .recognition-hero {
      &__copy {
        display: block;
      }

      &__icon {
        margin-bottom: 12px;
      }

      &__metrics {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
