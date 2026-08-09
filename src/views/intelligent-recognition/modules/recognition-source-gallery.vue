<template>
  <div
    class="recognition-source-gallery"
    :class="{ 'is-compact': compact, 'is-empty': !urls.length }"
  >
    <template v-if="urls.length">
      <div class="recognition-source-gallery__images">
        <figure v-for="(url, index) in visibleUrls" :key="url">
          <ElImage
            :src="url"
            :preview-src-list="urls"
            :initial-index="index"
            :preview-teleported="true"
            fit="cover"
            loading="lazy"
            :alt="`第 ${index + 1} 张原始票据`"
          >
            <template #placeholder>
              <span class="recognition-source-gallery__state" aria-label="原始票据加载中">
                <ArtSvgIcon icon="ri:loader-4-line" />
              </span>
            </template>
            <template #error>
              <span
                class="recognition-source-gallery__state is-error"
                aria-label="原始票据加载失败"
              >
                <ArtSvgIcon icon="ri:image-close-line" />
              </span>
            </template>
          </ElImage>
          <figcaption v-if="!compact">第 {{ index + 1 }} 张</figcaption>
        </figure>
      </div>
      <span v-if="compact" class="recognition-source-gallery__count">{{ urls.length }} 张</span>
    </template>

    <div v-else class="recognition-source-gallery__empty">
      <ArtSvgIcon icon="ri:image-off-line" />
      <div>
        <strong>{{ compact ? '未留存' : '暂无原始票据' }}</strong>
        <span v-if="!compact">
          {{
            expectedCount
              ? `该任务记录了 ${expectedCount} 张票据，但创建时尚未留存原图地址。`
              : '该识别任务没有可供预览的原图。'
          }}
        </span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'

  defineOptions({ name: 'RecognitionSourceGallery' })

  const props = withDefaults(
    defineProps<{
      urls: string[]
      expectedCount?: number
      compact?: boolean
    }>(),
    {
      expectedCount: 0,
      compact: false
    }
  )

  const visibleUrls = computed(() => props.urls.slice(0, props.compact ? 3 : 5))
</script>

<style scoped lang="scss">
  .recognition-source-gallery {
    min-width: 0;

    &__images {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(132px, 1fr));
      gap: 10px;
    }

    figure {
      min-width: 0;
      margin: 0;
      overflow: hidden;
      background: var(--art-gray-50);
      border: 1px solid var(--art-card-border);
      border-radius: var(--el-border-radius-base);
    }

    .el-image {
      display: block;
      width: 100%;
      height: 156px;
      cursor: zoom-in;
    }

    figcaption {
      padding: 7px 9px;
      font-size: 11px;
      line-height: 16px;
      color: var(--art-text-gray-500);
      text-align: center;
      background: var(--default-box-color);
      border-top: 1px solid var(--art-card-border);
    }

    &__state {
      display: grid;
      place-items: center;
      width: 100%;
      height: 100%;
      color: var(--art-text-gray-400);
      background: var(--art-gray-50);

      .art-svg-icon {
        font-size: 22px;
        animation: source-gallery-spin 1s linear infinite;
      }

      &.is-error {
        color: var(--el-color-danger);

        .art-svg-icon {
          animation: none;
        }
      }
    }

    &__empty {
      display: flex;
      gap: 11px;
      align-items: center;
      min-height: 82px;
      padding: 13px 15px;
      color: var(--art-text-gray-400);
      background: var(--art-gray-50);
      border: 1px dashed var(--art-card-border);
      border-radius: var(--el-border-radius-base);

      > .art-svg-icon {
        flex: 0 0 auto;
        font-size: 25px;
      }

      strong,
      span {
        display: block;
      }

      strong {
        font-size: 12px;
        color: var(--art-text-gray-700);
      }

      span {
        margin-top: 3px;
        font-size: 11px;
        line-height: 1.55;
        color: var(--art-text-gray-500);
      }
    }

    &.is-compact {
      display: flex;
      gap: 7px;
      align-items: center;

      .recognition-source-gallery__images {
        display: flex;
        gap: 0;
      }

      figure {
        width: 34px;
        height: 34px;
        border-radius: var(--el-border-radius-small);

        + figure {
          margin-left: -7px;
        }
      }

      .el-image {
        width: 34px;
        height: 34px;
      }

      .recognition-source-gallery__count {
        flex: 0 0 auto;
        font-size: 11px;
        color: var(--art-text-gray-500);
      }

      .recognition-source-gallery__empty {
        gap: 5px;
        min-height: 0;
        padding: 0;
        font-size: 11px;
        background: transparent;
        border: 0;

        > .art-svg-icon {
          font-size: 16px;
        }

        strong {
          font-size: 11px;
          font-weight: 500;
          color: var(--art-text-gray-400);
        }
      }
    }
  }

  @keyframes source-gallery-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (width <= 640px) {
    .recognition-source-gallery {
      &__images {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .el-image {
        height: 132px;
      }
    }
  }
</style>
