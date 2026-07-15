<template>
  <ElLink
    class="art-attachment-link"
    type="primary"
    :href="file.url || '#'"
    :title="file.url ? `预览 ${displayName}` : `${displayName}（无可用地址）`"
    :underline="false"
    @click.prevent.stop="handlePreview"
  >
    {{ displayName }}
  </ElLink>
</template>

<script setup lang="ts">
  import { ElLink, ElMessage } from 'element-plus'
  import { openFilePreview, type FilePreviewTarget } from '@/hooks/core/useFilePreview'

  defineOptions({ name: 'ArtAttachmentLink' })

  const props = defineProps<{
    file: FilePreviewTarget
  }>()

  const displayName = computed(() => props.file.name?.trim() || '未命名附件')

  const handlePreview = (): void => {
    const result = openFilePreview(props.file)
    if (result === 'missing-url') ElMessage.warning('附件没有可用的预览地址')
    if (result === 'blocked') ElMessage.warning('浏览器阻止了新页签，请允许本站打开弹出式窗口')
  }
</script>

<style scoped lang="scss">
  .art-attachment-link {
    max-width: 100%;
    font-weight: 500;
    vertical-align: middle;

    :deep(.el-link__inner) {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
</style>
