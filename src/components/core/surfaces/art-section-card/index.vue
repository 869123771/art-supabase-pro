<template>
  <section class="art-section-card art-card-xs" :class="rootClass" :aria-busy="loading">
    <slot v-if="$slots.header" name="header" />
    <header v-else-if="hasHeader" class="art-section-card__header">
      <div class="art-section-card__identity">
        <ArtSectionTitle :show-line="false" :show-marker="showMarker">{{ title }}</ArtSectionTitle>
        <p v-if="subtitle">{{ subtitle }}</p>
      </div>
      <div v-if="$slots.actions" class="art-section-card__actions">
        <slot name="actions" />
      </div>
    </header>

    <slot v-if="preserveContentStructure && !hasActiveState" />
    <ArtAsyncState
      v-else
      class="art-section-card__body"
      :class="bodyClass"
      :loading="loading"
      :loading-mode="loadingMode"
      :skeleton-rows="skeletonRows"
      :error="error"
      :error-title="errorTitle"
      :retryable="retryable"
      :empty="empty"
      :empty-text="emptyTitle"
      :empty-description="emptyDescription"
      :empty-image-size="emptyVisualSize"
      :min-height="stateMinHeight"
      @retry="emit('retry')"
    >
      <slot />

      <template v-if="$slots['empty-action']" #empty-action>
        <slot name="empty-action" />
      </template>
      <template v-if="$slots['error-action']" #error-action>
        <slot name="error-action" />
      </template>
    </ArtAsyncState>
  </section>
</template>

<script setup lang="ts">
  import ArtSectionCard from '@/components/core/surfaces/art-section-card/index.vue'
  import ArtSectionTitle from '@/components/core/surfaces/art-section-title/index.vue'
  import ArtAsyncState from '@/components/core/feedback/art-async-state/index.vue'

  defineOptions({ name: 'ArtSectionCard' })

  type SectionClass = string | Record<string, boolean> | SectionClass[]

  interface Props {
    title?: string
    subtitle?: string
    rootClass?: SectionClass
    bodyClass?: SectionClass
    showMarker?: boolean
    loading?: boolean
    loadingMode?: 'mask' | 'skeleton'
    skeletonRows?: number
    error?: string | Error | null
    errorTitle?: string
    retryable?: boolean
    empty?: boolean
    emptyTitle?: string
    emptyDescription?: string
    emptyVisualSize?: number
    minHeight?: string | number
    preserveContentStructure?: boolean
  }

  const props = withDefaults(defineProps<Props>(), {
    title: '',
    subtitle: '',
    rootClass: '',
    bodyClass: '',
    showMarker: true,
    loading: false,
    loadingMode: 'skeleton',
    skeletonRows: 6,
    error: null,
    errorTitle: '内容加载失败',
    retryable: true,
    empty: false,
    emptyTitle: '暂无数据',
    emptyDescription: '',
    emptyVisualSize: 96,
    minHeight: 180,
    preserveContentStructure: false
  })

  const emit = defineEmits<{ retry: [] }>()
  const slots = useSlots()
  const hasHeader = computed(() => Boolean(props.title || props.subtitle || slots.actions))
  const stateMinHeight = computed(() =>
    props.loading || props.error || props.empty ? props.minHeight : 0
  )
  const hasActiveState = computed(() => Boolean(props.loading || props.error || props.empty))
</script>

<style scoped lang="scss">
  .art-section-card {
    min-width: 0;
    padding: var(--art-section-padding);

    &__header {
      display: flex;
      gap: var(--art-space-3);
      align-items: flex-start;
      justify-content: space-between;
      min-width: 0;
      margin-bottom: var(--art-space-4);
    }

    &__identity {
      flex: 1;
      min-width: 0;

      :deep(.art-section-title) {
        margin: 0;
        font-size: var(--art-font-size-section-title);
      }

      p {
        margin: var(--art-space-1) 0 0 11px;
        font-size: var(--art-font-size-caption);
        line-height: 20px;
        color: var(--el-text-color-secondary);
      }
    }

    &__actions {
      display: flex;
      flex: none;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      align-items: center;
      justify-content: flex-end;
      min-width: 0;
    }

    &__body {
      min-width: 0;
    }

    @media (width <= 640px) {
      padding: var(--art-space-4);

      &__header {
        flex-direction: column;
      }

      &__actions {
        justify-content: flex-start;
        width: 100%;
      }
    }
  }
</style>
