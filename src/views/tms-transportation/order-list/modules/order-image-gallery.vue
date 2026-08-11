<template>
  <div v-if="imageUrls.length" class="order-image-gallery">
    <div class="order-image-gallery__list" :aria-label="`订单图片，共 ${imageUrls.length} 张`">
      <button
        v-for="(url, index) in imageUrls"
        :key="url"
        type="button"
        class="order-image-gallery__item"
        :aria-label="`预览订单图片 ${index + 1}`"
        :title="`预览订单图片 ${index + 1}`"
        @click="openPreview(index)"
      >
        <ElImage
          :src="url"
          :alt="`订单图片 ${index + 1}`"
          class="order-image-gallery__image"
          fit="cover"
          loading="lazy"
        >
          <template #placeholder>
            <span class="order-image-gallery__state" aria-label="图片加载中">
              <ArtSvgIcon icon="ri:loader-4-line" class="order-image-gallery__spinner" />
            </span>
          </template>
          <template #error>
            <span class="order-image-gallery__state order-image-gallery__state--error">
              <ArtSvgIcon icon="ri:image-line" />
              <small>加载失败</small>
            </span>
          </template>
        </ElImage>
        <span class="order-image-gallery__preview" aria-hidden="true">
          <ArtSvgIcon icon="ri:zoom-in-line" />
          <span>预览</span>
        </span>
      </button>
    </div>

    <span class="order-image-gallery__count">
      共 <strong>{{ imageUrls.length }}</strong> 张
    </span>
  </div>

  <span v-else class="order-image-gallery__empty">
    <ArtSvgIcon icon="ri:image-line" />
    暂无图片
  </span>
</template>

<script setup lang="ts">
  import { compact, uniq } from 'lodash-es'
  import { useImageViewer } from '@/hooks'

  defineOptions({ name: 'OrderImageGallery' })

  const props = withDefaults(
    defineProps<{
      urls?: string[] | null
    }>(),
    {
      urls: () => []
    }
  )

  const imageUrls = computed(() =>
    uniq(compact((props.urls ?? []).map((url) => url?.trim()))).filter((url) => url.length > 0)
  )

  function openPreview(index: number): void {
    useImageViewer(imageUrls.value, { initialIndex: index })
  }
</script>

<style scoped lang="scss">
  .order-image-gallery {
    display: flex;
    flex-wrap: wrap;
    gap: var(--art-space-3);
    align-items: flex-end;
    min-width: 0;

    &__list {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      min-width: 0;
    }

    &__item {
      position: relative;
      display: inline-flex;
      width: 88px;
      height: 88px;
      padding: 0;
      overflow: hidden;
      cursor: zoom-in;
      outline: none;
      background: var(--el-fill-color-lighter);
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--el-border-radius-base);
      transition:
        border-color 0.18s ease,
        box-shadow 0.18s ease,
        transform 0.18s ease;

      &:hover,
      &:focus-visible {
        transform: translateY(-1px);

        .order-image-gallery__preview {
          opacity: 1;
        }
      }
    }

    &__image,
    &__state {
      width: 100%;
      height: 100%;
    }

    &__state {
      display: flex;
      flex-direction: column;
      gap: 4px;
      align-items: center;
      justify-content: center;
      color: var(--el-text-color-placeholder);
      background: var(--el-fill-color-lighter);

      &--error {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }
    }

    &__spinner {
      animation: order-image-spin 1s linear infinite;
    }

    &__preview {
      position: absolute;
      inset: auto 0 0;
      display: flex;
      gap: 4px;
      align-items: center;
      justify-content: center;
      min-height: 30px;
      font-size: 12px;
      color: var(--el-color-white);
      pointer-events: none;
      background: rgb(15 23 42 / 68%);
      opacity: 0;
      transition: opacity 0.18s ease;
    }

    &__count {
      padding-bottom: 4px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      white-space: nowrap;

      strong {
        color: var(--el-text-color-primary);
      }
    }

    &__empty {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      color: var(--el-text-color-placeholder);
    }
  }

  :global([data-box-mode='border-mode'] .order-image-gallery__item:hover),
  :global([data-box-mode='border-mode'] .order-image-gallery__item:focus-visible) {
    border-color: color-mix(in srgb, var(--theme-color) 52%, var(--el-border-color-light));
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--theme-color) 16%, transparent);
  }

  :global([data-box-mode='shadow-mode'] .order-image-gallery__item:hover),
  :global([data-box-mode='shadow-mode'] .order-image-gallery__item:focus-visible) {
    border-color: transparent;
    box-shadow: 0 8px 20px color-mix(in srgb, var(--theme-color) 18%, transparent);
  }

  @keyframes order-image-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .order-image-gallery {
      &__item,
      &__preview {
        transition: none;
      }

      &__spinner {
        animation: none;
      }
    }
  }

  @media (width <= 640px) {
    .order-image-gallery {
      align-items: flex-start;

      &__item {
        width: 72px;
        height: 72px;
      }

      &__count {
        flex-basis: 100%;
        padding-bottom: 0;
      }
    }
  }
</style>
