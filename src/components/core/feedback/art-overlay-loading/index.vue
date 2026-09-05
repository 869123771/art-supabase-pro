<template>
  <div
    class="art-overlay-loading"
    :class="[
      {
        'is-loading': loading,
        'is-overlay': overlay,
        'is-compact': size === 'compact'
      },
      customClass
    ]"
    :style="loadingStyle"
    :aria-busy="loading"
  >
    <div v-if="loading" class="art-overlay-loading__state" role="status" aria-live="polite">
      <div class="art-overlay-loading__visual" aria-hidden="true">
        <span class="art-overlay-loading__orbit" />
        <span class="art-overlay-loading__icon">
          <ArtSvgIcon icon="ri:loader-4-line" />
        </span>
      </div>
      <strong>{{ text || '正在加载内容…' }}</strong>
      <span v-if="description">{{ description }}</span>
    </div>

    <div class="art-overlay-loading__content" :aria-hidden="loading || undefined">
      <slot />
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { CSSProperties } from 'vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'ArtOverlayLoading' })

  const props = withDefaults(
    defineProps<{
      loading?: boolean
      text?: string
      description?: string
      minHeight?: string | number
      background?: string
      customClass?: string
      overlay?: boolean
      size?: 'compact' | 'default'
    }>(),
    {
      loading: false,
      text: '',
      description: '正在获取最新数据，请稍候',
      minHeight: 'clamp(320px, 54dvh, 580px)',
      background: '',
      customClass: '',
      overlay: false,
      size: 'default'
    }
  )

  const loadingStyle = computed<CSSProperties>(() => ({
    '--art-overlay-loading-min-height':
      typeof props.minHeight === 'number' ? `${props.minHeight}px` : props.minHeight,
    '--art-overlay-loading-background': props.background || undefined
  }))
</script>

<style scoped lang="scss">
  .art-overlay-loading {
    position: relative;
    min-width: 0;
    height: 100%;

    &.is-loading:not(.is-overlay) {
      min-height: min(var(--art-overlay-loading-min-height), calc(100dvh - 220px));
      overflow: hidden;
    }

    &.is-overlay {
      position: absolute;
      inset: 0;
      z-index: 20;
      overflow: hidden;
    }

    &__state {
      position: absolute;
      inset: 0;
      z-index: 2;
      display: flex;
      flex-direction: column;
      gap: 7px;
      align-items: center;
      justify-content: center;
      padding: var(--art-space-5);
      text-align: center;
      background: var(--art-overlay-loading-background, var(--default-box-color));
      border-radius: var(--art-control-radius);
    }

    &__visual {
      position: relative;
      display: grid;
      place-items: center;
      width: 58px;
      height: 58px;
      margin-bottom: 3px;
    }

    &__orbit {
      position: absolute;
      inset: 0;
      background: conic-gradient(
          from 20deg,
          transparent 0 24%,
          var(--theme-color) 44%,
          transparent 64%
        )
        border-box;
      border: 2px solid transparent;
      border-radius: 50%;
      mask:
        linear-gradient(#000 0 0) padding-box,
        linear-gradient(#000 0 0);
      mask-composite: exclude;
      animation: art-overlay-loading-spin 1.15s linear infinite;
    }

    &__icon {
      display: grid;
      place-items: center;
      width: 40px;
      height: 40px;
      font-size: 20px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--default-box-color));
      border: 1px solid color-mix(in srgb, var(--theme-color) 18%, transparent);
      border-radius: 50%;
      box-shadow: 0 8px 22px color-mix(in srgb, var(--theme-color) 14%, transparent);
    }

    &__state strong {
      font-size: var(--art-font-size-body);
      font-weight: 600;
      line-height: 1.5;
      color: var(--el-text-color-primary);
    }

    &__state > span:last-child {
      max-width: 320px;
      font-size: var(--art-font-size-caption);
      line-height: 1.5;
      color: var(--el-text-color-secondary);
    }

    &.is-compact &__state {
      gap: var(--art-space-1);
      padding: var(--art-space-3);
    }

    &.is-compact &__visual {
      width: 42px;
      height: 42px;
      margin-bottom: 0;
    }

    &.is-compact &__icon {
      width: 30px;
      height: 30px;
      font-size: 16px;
      box-shadow: 0 5px 14px color-mix(in srgb, var(--theme-color) 12%, transparent);
    }

    &.is-compact &__state strong,
    &.is-compact &__state > span:last-child {
      font-size: var(--art-font-size-caption);
    }

    &__content {
      min-width: 0;
      height: 100%;
    }

    &.is-loading &__content {
      position: absolute;
      inset: 0;
      visibility: hidden;
      pointer-events: none;
    }
  }

  @keyframes art-overlay-loading-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .art-overlay-loading__orbit {
      animation-duration: 2.4s;
    }
  }
</style>
