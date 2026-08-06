<template>
  <div class="art-icon-picker">
    <ElInput
      :model-value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :clearable="clearable"
      @update:model-value="handleInput"
      @change="handleInputChange"
      @clear="handleClear"
    >
      <template #prepend>
        <ArtSvgIcon
          v-if="isRemixIcon"
          :icon="normalizedModelValue"
          class="art-icon-picker__preview"
        />
        <ElIcon v-else class="art-icon-picker__placeholder-icon">
          <Picture />
        </ElIcon>
      </template>
      <template #append>
        <ElButton :disabled="disabled || readonly" @click="handleOpen">选择图标</ElButton>
      </template>
    </ElInput>

    <ArtDialog ref="dialogRef">
      <div class="art-icon-picker__toolbar">
        <ElInput
          v-model="keyword"
          clearable
          size="large"
          placeholder="搜索图标名称，如 user、menu、setting"
        >
          <template #prefix>
            <ElIcon><Search /></ElIcon>
          </template>
        </ElInput>
        <div class="art-icon-picker__meta">
          <ElTag effect="plain" round>Remix Icon</ElTag>
          <span>共 {{ filteredIcons.length }} 个</span>
        </div>
      </div>

      <div class="art-icon-picker__panel">
        <ElScrollbar ref="scrollbarRef" height="52vh" always @scroll="handleScroll">
          <div v-if="visibleIcons.length" class="art-icon-picker__grid">
            <ElTooltip
              v-for="icon in visibleIcons"
              :key="icon"
              :content="icon"
              placement="top"
              :show-after="400"
            >
              <button
                type="button"
                class="art-icon-picker__item"
                :class="{ 'is-selected': icon === modelValue }"
                :aria-label="`选择图标 ${icon}`"
                @click="handleSelect(icon)"
              >
                <ArtSvgIcon :icon="icon" class="art-icon-picker__icon" />
              </button>
            </ElTooltip>
          </div>

          <div v-else-if="loading" class="art-icon-picker__state">
            <ElIcon class="is-loading" :size="28"><Loading /></ElIcon>
            <span>正在加载图标...</span>
          </div>

          <div v-else-if="loadError" class="art-icon-picker__state">
            <ArtEmptyState
              title="图标数据加载失败"
              description="请检查网络连接后重新加载。"
              :visual-size="82"
              size="compact"
            >
              <ElButton type="primary" @click="loadIcons(true)">重新加载</ElButton>
            </ArtEmptyState>
          </div>

          <ArtEmptyState
            v-else
            title="没有匹配的图标"
            description="尝试使用更简短的关键词。"
            :visual-size="82"
            size="compact"
            class="art-icon-picker__state"
          />
        </ElScrollbar>

        <div class="art-icon-picker__summary">
          <span> 已显示 {{ visibleIcons.length }} / {{ filteredIcons.length }} 个图标 </span>
          <span v-if="hasMore">向下滚动加载更多</span>
        </div>
      </div>

      <template #footer="{ api }">
        <div class="art-icon-picker__footer">
          <ElButton :disabled="!modelValue" @click="handleClear">清空</ElButton>
          <ElButton type="primary" @click="api.handleClose()">关闭</ElButton>
        </div>
      </template>
    </ArtDialog>
  </div>
</template>

<script setup lang="ts">
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import { Loading, Picture, Search } from '@element-plus/icons-vue'
  import type { ScrollbarInstance } from 'element-plus'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'

  defineOptions({ name: 'ArtIconPicker' })

  interface Props {
    placeholder?: string
    title?: string
    prefix?: string
    collectionUrl?: string
    pageSize?: number
    clearable?: boolean
    disabled?: boolean
    readonly?: boolean
    closeOnSelect?: boolean
  }

  interface IconifyCollectionResponse {
    prefix?: string
    total?: number
    uncategorized?: string[]
    categories?: Record<string, string[]>
    aliases?: Record<string, { parent?: string }>
  }

  interface ScrollPayload {
    scrollTop: number
  }

  const props = withDefaults(defineProps<Props>(), {
    placeholder: '请选择图标',
    title: '选择图标',
    prefix: 'ri',
    collectionUrl: 'https://api.iconify.design/collection',
    pageSize: 140,
    clearable: true,
    disabled: false,
    readonly: false,
    closeOnSelect: true
  })

  const emit = defineEmits<{
    change: [value: string]
    select: [value: string]
    clear: []
  }>()

  const modelValue = defineModel<string>({ default: '' })
  const dialogRef = ref<ArtDialogExpose<void>>()
  const scrollbarRef = ref<ScrollbarInstance>()
  const keyword = ref('')
  const iconNames = shallowRef<string[]>([])
  const visibleCount = ref(props.pageSize)
  const loading = ref(false)
  const loadError = ref(false)

  const CACHE_VERSION = 1
  const CACHE_TTL = 7 * 24 * 60 * 60 * 1000

  const fallbackIcons = [
    'home-line',
    'dashboard-line',
    'menu-line',
    'settings-3-line',
    'user-line',
    'user-settings-line',
    'team-line',
    'admin-line',
    'shield-user-line',
    'lock-line',
    'key-line',
    'folder-line',
    'folder-open-line',
    'file-list-3-line',
    'database-2-line',
    'table-line',
    'bar-chart-box-line',
    'pie-chart-line',
    'line-chart-line',
    'search-line',
    'add-line',
    'edit-line',
    'delete-bin-line',
    'eye-line',
    'download-line',
    'upload-line',
    'notification-3-line',
    'mail-line',
    'phone-line',
    'calendar-line',
    'time-line',
    'global-line',
    'links-line',
    'terminal-box-line',
    'code-box-line',
    'bug-line',
    'tools-line',
    'question-line',
    'information-line',
    'checkbox-circle-line'
  ]

  const cacheKey = computed(() => `art-icon-picker:${props.prefix}:v${CACHE_VERSION}`)

  const filteredIcons = computed(() => {
    const normalizedKeyword = keyword.value.trim().toLowerCase()
    if (!normalizedKeyword) return iconNames.value

    return iconNames.value.filter((icon) => icon.toLowerCase().includes(normalizedKeyword))
  })

  const visibleIcons = computed(() => filteredIcons.value.slice(0, visibleCount.value))
  const hasMore = computed(() => visibleCount.value < filteredIcons.value.length)
  const normalizedModelValue = computed(() => modelValue.value.trim())
  const isRemixIcon = computed(() =>
    /^ri:[a-z0-9]+(?:-[a-z0-9]+)*$/i.test(normalizedModelValue.value)
  )

  watch(keyword, () => {
    visibleCount.value = props.pageSize
    scrollbarRef.value?.setScrollTop(0)
  })

  const normalizeIcons = (names: string[]): string[] => {
    return [...new Set(names)]
      .filter(Boolean)
      .sort((left, right) => left.localeCompare(right))
      .map((name) => `${props.prefix}:${name}`)
  }

  const readCache = (): string[] | undefined => {
    try {
      const rawCache = localStorage.getItem(cacheKey.value)
      if (!rawCache) return

      const cache = JSON.parse(rawCache) as {
        expiresAt?: number
        icons?: string[]
      }
      if (!cache.expiresAt || cache.expiresAt < Date.now() || !Array.isArray(cache.icons)) {
        localStorage.removeItem(cacheKey.value)
        return
      }
      return cache.icons
    } catch {
      return
    }
  }

  const writeCache = (icons: string[]): void => {
    try {
      localStorage.setItem(
        cacheKey.value,
        JSON.stringify({
          expiresAt: Date.now() + CACHE_TTL,
          icons
        })
      )
    } catch {
      // Storage quota or privacy mode should not block icon selection.
    }
  }

  const parseCollection = (collection: IconifyCollectionResponse): string[] => {
    const names = new Set<string>(collection.uncategorized ?? [])
    Object.values(collection.categories ?? {}).forEach((icons) => {
      icons.forEach((icon) => names.add(icon))
    })
    Object.keys(collection.aliases ?? {}).forEach((icon) => names.add(icon))
    return normalizeIcons([...names])
  }

  const loadIcons = async (force = false): Promise<void> => {
    if (loading.value || (iconNames.value.length && !force)) return

    const cachedIcons = force ? undefined : readCache()
    if (cachedIcons?.length) {
      iconNames.value = cachedIcons
      loadError.value = false
      return
    }

    loading.value = true
    loadError.value = false
    try {
      const requestUrl = new URL(props.collectionUrl)
      requestUrl.searchParams.set('prefix', props.prefix)
      const response = await fetch(requestUrl, {
        headers: { Accept: 'application/json' }
      })
      if (!response.ok) throw new Error(`Icon collection request failed: ${response.status}`)

      const icons = parseCollection((await response.json()) as IconifyCollectionResponse)
      if (!icons.length) throw new Error('Icon collection is empty')

      iconNames.value = icons
      writeCache(icons)
    } catch {
      iconNames.value = normalizeIcons(fallbackIcons)
      loadError.value = iconNames.value.length === 0
    } finally {
      loading.value = false
    }
  }

  const handleOpen = async (): Promise<void> => {
    if (props.disabled || props.readonly) return

    keyword.value = ''
    visibleCount.value = props.pageSize
    await dialogRef.value?.handleOpen(undefined, {
      title: props.title,
      width: 'min(1180px, calc(100vw - 48px))',
      dialogProps: {
        appendToBody: true,
        closeOnClickModal: false,
        class: 'art-icon-picker-dialog'
      },
      onOpen: () => loadIcons()
    })
  }

  const handleSelect = (icon: string): void => {
    modelValue.value = icon
    emit('change', icon)
    emit('select', icon)
    if (props.closeOnSelect) {
      void dialogRef.value?.handleClose()
    }
  }

  const handleInput = (value: string): void => {
    modelValue.value = value
  }

  const handleInputChange = (value: string): void => {
    emit('change', value)
  }

  const handleClear = (): void => {
    modelValue.value = ''
    emit('change', '')
    emit('clear')
  }

  const handleScroll = ({ scrollTop }: ScrollPayload): void => {
    const wrap = scrollbarRef.value?.wrapRef
    if (!wrap || !hasMore.value) return

    const remaining = wrap.scrollHeight - scrollTop - wrap.clientHeight
    if (remaining <= 160) {
      visibleCount.value = Math.min(visibleCount.value + props.pageSize, filteredIcons.value.length)
    }
  }

  defineExpose({
    handleOpen,
    handleClear,
    reload: () => loadIcons(true)
  })
</script>

<style scoped lang="scss">
  .art-icon-picker {
    width: 100%;

    :deep(.el-input-group__prepend) {
      box-sizing: border-box;
      width: var(--el-component-size);
      min-width: var(--el-component-size);
      padding: 0;
    }

    :deep(.el-input-group__prepend > *) {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 50%;
      height: 50%;
    }
  }

  .art-icon-picker__preview,
  .art-icon-picker__placeholder-icon {
    font-size: 20px;
  }

  .art-icon-picker__placeholder-icon {
    color: var(--el-text-color-placeholder);
  }

  .art-icon-picker__toolbar {
    display: flex;
    gap: 20px;
    align-items: center;
    padding: 18px 24px;
    margin-bottom: 20px;
    border: 1px solid var(--el-border-color);
    border-radius: 8px;
  }

  .art-icon-picker__toolbar :deep(.el-input) {
    width: min(680px, 70%);
  }

  .art-icon-picker__meta {
    display: flex;
    flex: none;
    gap: 12px;
    align-items: center;
    margin-left: auto;
    color: var(--el-text-color-secondary);
    white-space: nowrap;
  }

  .art-icon-picker__panel {
    padding: 24px 24px 14px;
    border: 1px solid var(--el-border-color);
    border-radius: 8px;
  }

  .art-icon-picker__grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(108px, 1fr));
    gap: 12px;
    padding-right: 14px;
  }

  .art-icon-picker__item {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 0;
    aspect-ratio: 1.55;
    color: var(--el-text-color-regular);
    cursor: pointer;
    background: var(--el-fill-color-blank);
    border: 1px solid var(--el-border-color);
    border-radius: 8px;
    transition:
      color 0.15s ease,
      background-color 0.15s ease,
      border-color 0.15s ease;

    &:hover {
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-color: var(--el-color-primary-light-5);
    }

    &.is-selected {
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-color: var(--el-color-primary);
    }
  }

  .art-icon-picker__icon {
    font-size: 28px;
  }

  .art-icon-picker__state {
    display: flex;
    flex-direction: column;
    gap: 12px;
    align-items: center;
    justify-content: center;
    min-height: 360px;
    color: var(--el-text-color-secondary);
  }

  .art-icon-picker__summary {
    display: flex;
    justify-content: space-between;
    padding-top: 14px;
    margin-top: 14px;
    font-size: 13px;
    color: var(--el-text-color-secondary);
    border-top: 1px solid var(--el-border-color-lighter);
  }

  .art-icon-picker__footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  @media (width <= 640px) {
    .art-icon-picker__toolbar {
      flex-direction: column;
      align-items: stretch;
      padding: 14px;
    }

    .art-icon-picker__toolbar :deep(.el-input) {
      width: 100%;
    }

    .art-icon-picker__meta {
      margin-left: 0;
    }

    .art-icon-picker__panel {
      padding: 14px 14px 10px;
    }

    .art-icon-picker__grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;
    }
  }
</style>
