<template>
  <section class="smis-evidence art-card-xs">
    <div class="smis-evidence__header">
      <div>
        <strong>{{ title }}</strong>
        <p>{{ description }}</p>
      </div>
      <ElUpload
        v-if="!readonly"
        :show-file-list="false"
        :http-request="handleUpload"
        :disabled="uploading || modelValue.length >= maxCount"
        multiple
      >
        <span
          class="smis-evidence__upload-trigger"
          :class="{ 'is-disabled': uploading || modelValue.length >= maxCount }"
        >
          <ArtSvgIcon :icon="uploading ? 'ri:loader-4-line' : 'ri:attachment-2'" />
          {{ uploading ? '上传中' : '上传附件' }}
        </span>
      </ElUpload>
    </div>

    <div v-if="modelValue.length" class="smis-evidence__list">
      <article v-for="(file, index) in modelValue" :key="file.id || file.url || index">
        <ArtSvgIcon :icon="getFileIcon(file)" />
        <div>
          <a v-if="file.url" :href="file.url" target="_blank" rel="noopener noreferrer">
            {{ getFileName(file, index) }}
          </a>
          <span v-else>{{ getFileName(file, index) }}</span>
          <small>{{ getFileMeta(file) }}</small>
        </div>
        <ElButton
          v-if="!readonly"
          type="danger"
          text
          aria-label="移除附件引用"
          @click="removeFile(index)"
        >
          <ArtSvgIcon icon="ri:close-line" />
        </ElButton>
      </article>
    </div>
    <ArtEmptyState
      v-else
      compact
      title="暂无附件证据"
      :description="
        readonly ? '本次记录未上传附件。' : `支持图片、文档等证据，最多 ${maxCount} 份。`
      "
    />
  </section>
</template>

<script setup lang="ts">
  import { ElMessage, type UploadRequestOptions } from 'element-plus'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import { uploadAttachment } from '@/api/common'
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'

  defineOptions({ name: 'SmisAttachmentEvidence' })
  type Attachment = Api.Smis.InspectionControl.AttachmentRef
  const props = withDefaults(
    defineProps<{
      modelValue: Attachment[]
      title?: string
      description?: string
      readonly?: boolean
      maxCount?: number
    }>(),
    {
      title: '附件证据',
      description: '附件统一保存到系统资源库，业务单据仅保存引用。',
      readonly: false,
      maxCount: 10
    }
  )
  const emit = defineEmits<{ 'update:modelValue': [value: Attachment[]] }>()
  const uploading = ref(false)

  const handleUpload = async (options: UploadRequestOptions): Promise<void> => {
    if (props.modelValue.length >= props.maxCount) return
    uploading.value = true
    try {
      const [resource] = await uploadAttachment(options.file)
      if (!resource?.url) throw new Error('附件上传失败')
      if (props.modelValue.some((item) => item.id === resource.id || item.url === resource.url)) {
        ElMessage.info('该附件已存在')
        return
      }
      emit('update:modelValue', [...props.modelValue, resource as unknown as Attachment])
      options.onSuccess(resource)
      ElMessage.success('附件上传成功')
    } catch (error) {
      const uploadError = Object.assign(
        error instanceof Error ? error : new Error('附件上传失败'),
        { status: 0, method: 'POST', url: '' }
      )
      options.onError(uploadError)
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件上传失败'))
    } finally {
      uploading.value = false
    }
  }
  const removeFile = (index: number): void => {
    emit(
      'update:modelValue',
      props.modelValue.filter((_, itemIndex) => itemIndex !== index)
    )
  }
  const getFileName = (file: Attachment, index: number): string =>
    file.originName || String(file.name || '') || `附件 ${index + 1}`
  const getFileMeta = (file: Attachment): string =>
    [file.suffix, file.sizeInfo].filter(Boolean).join(' · ') || '系统附件'
  const getFileIcon = (file: Attachment): string => {
    const suffix = String(file.suffix || '').toLowerCase()
    if (['png', 'jpg', 'jpeg', 'webp', 'gif'].includes(suffix)) return 'ri:image-line'
    if (suffix === 'pdf') return 'ri:file-pdf-2-line'
    return 'ri:file-line'
  }
</script>

<style scoped lang="scss">
  .smis-evidence {
    display: grid;
    gap: 12px;
    padding: 14px;

    &__header {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;

      strong {
        font-size: 14px;
      }

      p {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--art-text-gray-600);
      }
    }

    &__list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;

      article {
        display: flex;
        gap: 10px;
        align-items: center;
        min-width: 0;
        padding: 10px 12px;
        background: var(--art-main-bg-color);
        border: 1px solid var(--art-card-border);
        border-radius: 8px;
      }

      article > div {
        display: grid;
        flex: 1;
        gap: 2px;
        min-width: 0;
      }

      a,
      span {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--art-gray-900);
        white-space: nowrap;
      }

      a:hover {
        color: var(--el-color-primary);
      }

      small {
        color: var(--art-text-gray-600);
      }
    }

    &__upload-trigger {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      min-height: 32px;
      padding: 5px 12px;
      color: var(--el-button-text-color, var(--el-text-color-regular));
      cursor: pointer;
      background: var(--el-fill-color-blank);
      border: 1px solid var(--el-border-color);
      border-radius: var(--el-border-radius-base);
      transition: border-color var(--el-transition-duration-fast);

      &:hover {
        color: var(--el-color-primary);
        border-color: var(--el-color-primary-light-5);
      }

      &.is-disabled {
        color: var(--el-text-color-placeholder);
        cursor: not-allowed;
        background: var(--el-fill-color-light);
        border-color: var(--el-border-color-light);
      }
    }
  }

  @media (width <= 640px) {
    .smis-evidence__header {
      flex-direction: column;
    }

    .smis-evidence__list {
      grid-template-columns: 1fr;
    }
  }
</style>
