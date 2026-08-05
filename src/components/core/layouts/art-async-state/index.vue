<template>
  <div
    v-loading="loading && loadingMode === 'mask'"
    class="art-async-state"
    :class="{ 'is-full-height': fullHeight }"
    :style="{ minHeight: normalizedMinHeight }"
  >
    <ElSkeleton
      v-if="loading && loadingMode === 'skeleton'"
      animated
      :rows="skeletonRows"
      class="art-async-state__skeleton"
    />

    <ElResult
      v-else-if="errorMessage"
      icon="error"
      :title="errorTitle"
      :sub-title="errorMessage"
      class="art-async-state__result"
    >
      <template #extra>
        <slot name="error-action">
          <ElButton v-if="retryable" type="primary" @click="emit('retry')">重新加载</ElButton>
        </slot>
      </template>
    </ElResult>

    <ElEmpty
      v-else-if="empty"
      :description="emptyText"
      :image-size="emptyImageSize"
      class="art-async-state__empty"
    >
      <slot name="empty-action" />
    </ElEmpty>

    <slot v-else />
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'ArtAsyncState' })

  interface Props {
    loading?: boolean
    loadingMode?: 'mask' | 'skeleton'
    skeletonRows?: number
    error?: string | Error | null
    errorTitle?: string
    retryable?: boolean
    empty?: boolean
    emptyText?: string
    emptyImageSize?: number
    fullHeight?: boolean
    minHeight?: string | number
  }

  const props = withDefaults(defineProps<Props>(), {
    loading: false,
    loadingMode: 'mask',
    skeletonRows: 6,
    error: null,
    errorTitle: '内容加载失败',
    retryable: true,
    empty: false,
    emptyText: '暂无数据',
    emptyImageSize: 96,
    fullHeight: false,
    minHeight: 180
  })

  const emit = defineEmits<{ retry: [] }>()

  const errorMessage = computed(() => {
    if (props.error instanceof Error) return props.error.message
    return props.error ?? ''
  })

  const normalizedMinHeight = computed(() =>
    typeof props.minHeight === 'number' ? `${props.minHeight}px` : props.minHeight
  )
</script>

<style scoped lang="scss">
  .art-async-state {
    position: relative;
    min-width: 0;

    &.is-full-height {
      height: 100%;
    }

    &__skeleton {
      padding: var(--art-space-4);
    }

    &__result,
    &__empty {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: inherit;
    }
  }
</style>
