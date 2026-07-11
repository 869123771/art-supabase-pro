<template>
  <ElTag v-if="resolvedMode === 'tag'" :type="tagType">
    {{ label }}
  </ElTag>

  <ElBadge
    v-else-if="resolvedMode === 'badge'"
    is-dot
    :color="badgeColor"
    class="art-dict-display__badge"
  >
    <span class="art-dict-display__label" :style="{ color: badgeColor }">{{ label }}</span>
  </ElBadge>

  <span v-else>{{ label }}</span>
</template>

<script setup lang="ts">
  import { ElBadge, ElTag } from 'element-plus'
  import { useUserStore } from '@/store/modules/user'
  import type { DictDisplayMode } from '@/types/component'

  defineOptions({ name: 'ArtDictDisplay' })

  interface Props {
    dictCode?: string
    value?: string | number | null
    item?: Api.DataCenter.DictListItem
    display?: DictDisplayMode
    emptyText?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    dictCode: '',
    value: undefined,
    item: undefined,
    display: 'auto',
    emptyText: '--'
  })

  const userStore = useUserStore()
  watch(
    () => props.dictCode,
    (dictCode) => {
      if (dictCode) void userStore.ensureDictLoaded(dictCode)
    },
    { immediate: true }
  )

  const dictItem = computed<Api.DataCenter.DictListItem | undefined>(
    () => props.item ?? userStore.getDictItemByValue(props.dictCode, props.value ?? undefined)
  )
  const label = computed(() => {
    if (dictItem.value?.label) return dictItem.value.label
    if (props.value === undefined || props.value === null || props.value === '') {
      return props.emptyText
    }
    return String(props.value)
  })
  const tagType = computed<Api.Common.TagPreset | undefined>(() => {
    const type = dictItem.value?.tagType
    return type ? (type as Api.Common.TagPreset) : undefined
  })
  const badgeColor = computed(() => {
    if (dictItem.value?.color) return dictItem.value.color

    const tagColorMap: Record<Api.Common.TagPreset, string> = {
      primary: 'var(--el-color-primary)',
      success: 'var(--el-color-success)',
      warning: 'var(--el-color-warning)',
      danger: 'var(--el-color-danger)',
      info: 'var(--el-color-info)'
    }
    return tagType.value ? tagColorMap[tagType.value] : 'var(--el-color-primary)'
  })
  const resolvedMode = computed<Exclude<DictDisplayMode, 'auto'>>(() => {
    if (props.display !== 'auto') return props.display
    if (tagType.value) return 'tag'
    if (dictItem.value?.color) return 'badge'
    return 'text'
  })
</script>

<style scoped lang="scss">
  .art-dict-display {
    &__badge {
      display: inline-flex;
      flex-direction: row-reverse;
      align-items: center;
      max-width: 100%;
      gap: 6px;

      :deep(.el-badge__content.is-fixed.is-dot) {
        position: static;
        flex: 0 0 auto;
        transform: none;
      }
    }

    &__label {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
</style>
