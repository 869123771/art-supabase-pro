<template>
  <main class="art-file-viewer-page">
    <header class="art-file-viewer-page__header">
      <div class="art-file-viewer-page__title">
        <strong>{{ preview.file?.name || '文件预览' }}</strong>
        <span v-if="preview.fileType">文件类型：{{ preview.fileType }}</span>
      </div>
    </header>

    <section class="art-file-viewer-page__body">
      <ElResult
        v-if="preview.error"
        icon="warning"
        title="无法打开文件预览"
        :sub-title="preview.error"
      />

      <FileViewer v-else-if="preview.file?.url" :url="preview.file.url" :options="viewerOptions" />
    </section>
  </main>
</template>

<script setup lang="ts">
  import { ElResult } from 'element-plus'
  import { FileViewer, type FileViewerOptions } from '@file-viewer/vue3'
  import allRenderers from '@file-viewer/preset-all'
  import '@file-viewer/vue3/dist/file-viewer3.css'
  import { getFileExtension } from '@/utils/file'
  import { getFilePreviewTarget, type FilePreviewTarget } from '@/hooks/core/useFilePreview'

  defineOptions({ name: 'ArtFileViewerPage' })

  interface PreviewState {
    file?: FilePreviewTarget
    fileType: string
    error: string
  }

  const route = useRoute()
  const queryKey = Array.isArray(route.query.key) ? route.query.key[0] : route.query.key
  const key = typeof queryKey === 'string' ? queryKey : undefined
  const file = getFilePreviewTarget(key)
  const preview: PreviewState = {
    file,
    fileType: file?.fileType || getFileExtension(file?.name, file?.fileType),
    error: file ? '' : '预览地址不存在或已过期，请从附件名称重新打开'
  }

  const viewerOptions: FileViewerOptions = {
    preset: allRenderers,
    rendererMode: 'replace',
    theme: 'system',
    toolbar: {
      position: 'bottom-right',
      zoom: true
    }
  }

  useTitle(computed(() => `${preview.file?.name || '文件预览'} - Art Supabase Pro`))
</script>

<style scoped lang="scss">
  .art-file-viewer-page {
    display: flex;
    flex-direction: column;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    background: var(--el-bg-color-page);

    &__header {
      z-index: 1;
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      min-height: 64px;
      padding: 10px 20px;
      background: var(--el-bg-color);
      border-bottom: 1px solid var(--el-border-color-light);
    }

    &__title {
      display: flex;
      flex-direction: column;
      min-width: 0;

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 16px;
        white-space: nowrap;
      }

      span {
        margin-top: 4px;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    &__body {
      flex: 1;
      min-height: 0;

      > :deep(*) {
        width: 100%;
        height: 100%;
      }
    }

    @media (width <= 768px) {
      &__header {
        padding: 8px 12px;
      }
    }
  }
</style>
