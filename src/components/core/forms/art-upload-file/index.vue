<template>
  <div class="art-upload-file" :class="{ 'is-readonly': readonly }">
    <ElUpload
      v-model:file-list="fileList"
      :http-request="handleUpload"
      :before-upload="beforeUpload"
      :on-success="handleSuccess"
      :on-error="handleError"
      :on-exceed="handleExceed"
      :multiple="multiple"
      :limit="limit"
      :accept="accept"
      :disabled="disabled"
      :show-file-list="false"
      v-bind="$attrs"
    >
      <slot v-if="!readonly" name="trigger" :uploading="uploading">
        <span
          class="art-upload-file__trigger"
          :class="{ 'is-disabled': disabled, 'is-loading': uploading }"
        >
          <ArtSvgIcon
            :icon="uploading ? 'ri:loader-4-line' : 'ri:attachment-2'"
            :class="{ 'art-upload-file__spinner': uploading }"
            aria-hidden="true"
          />
          {{ uploading ? '上传中…' : title }}
        </span>
      </slot>

      <template v-if="showTip" #tip>
        <div class="art-upload-file__tip">
          <slot name="tip">{{ resolvedTip }}</slot>
        </div>
      </template>
    </ElUpload>

    <ul v-if="showFileList && fileList.length" class="art-upload-file__list">
      <li
        v-for="(file, index) in fileList"
        :key="file.uid ?? file.url ?? `${file.name}-${index}`"
        class="art-upload-file__item"
      >
        <div class="art-upload-file__identity">
          <ArtSvgIcon
            :icon="file.status === 'uploading' ? 'ri:loader-4-line' : 'ri:file-line'"
            :class="{ 'art-upload-file__spinner': file.status === 'uploading' }"
            aria-hidden="true"
          />
          <ArtAttachmentLink v-if="file.url" :file="getFileTarget(file)" />
          <span v-else class="art-upload-file__pending-name">{{ file.name }}</span>
        </div>

        <div class="art-upload-file__actions">
          <ArtIconButton
            class="art-upload-file__action"
            icon="ri:download-2-line"
            label="下载附件"
            :disabled="!file.url"
            @click.stop="handleDownload(file)"
          />
          <ArtIconButton
            class="art-upload-file__action"
            icon="ri:eye-line"
            label="查看附件"
            :disabled="!file.url"
            @click.stop="handlePreview(file)"
          />
          <ArtIconButton
            v-if="!readonly"
            class="art-upload-file__action"
            icon="ri:delete-bin-2-line"
            label="删除附件"
            tone="danger"
            @click.stop="handleRemoveFile(file)"
          />
        </div>
      </li>
    </ul>
  </div>
</template>

<script setup lang="ts">
  import type { UploadFile, UploadRequestOptions, UploadUserFile } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import { uploadAttachment } from '@/api/common'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import {
    normalizeUploadModelUrls,
    shouldSyncUploadFileList
  } from '@/components/core/forms/upload-model-utils'
  import ArtAttachmentLink from '@/components/core/media/art-file-viewer/attachment-link.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { downloadAttachment, getFileExtension, viewAttachment } from '@/utils/file'
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'

  defineOptions({ name: 'ArtUploadFile', inheritAttrs: false })

  const props = withDefaults(
    defineProps<{
      modelValue?: string | string[] | null
      title?: string
      tip?: string
      accept?: string
      fileSize?: number
      limit?: number
      multiple?: boolean
      readonly?: boolean
      disabled?: boolean
      showFileList?: boolean
      showTip?: boolean
    }>(),
    {
      modelValue: null,
      title: '选择附件',
      tip: '',
      accept: '',
      fileSize: 20 * 1024 * 1024,
      limit: 1,
      multiple: false,
      readonly: false,
      disabled: false,
      showFileList: true,
      showTip: true
    }
  )

  const emit = defineEmits<{
    (event: 'update:modelValue', value: string | string[]): void
    (event: 'resource-change', value: Api.DataCenter.Resources.ResourceListItem[]): void
    (
      event: 'upload-success',
      value: Api.DataCenter.Resources.ResourceListItem,
      file: UploadFile
    ): void
  }>()

  const fileList = ref<UploadUserFile[]>([])
  const lastSyncedModelUrls = ref<string[]>([])
  const uploading = ref(false)

  const formatFileSize = (bytes: number): string => {
    if (bytes >= 1024 * 1024) return `${Number((bytes / 1024 / 1024).toFixed(1))} MB`
    return `${Math.ceil(bytes / 1024)} KB`
  }

  const resolvedTip = computed(
    () => props.tip || `单个文件不超过 ${formatFileSize(props.fileSize)}`
  )

  watch(
    () => props.modelValue,
    (value) => {
      if (!shouldSyncUploadFileList(value, lastSyncedModelUrls.value)) return
      const urls = normalizeUploadModelUrls(value)
      lastSyncedModelUrls.value = urls
      fileList.value = urls.map((url) => ({
        name: decodeURIComponent(url.split('/').pop() || '附件'),
        url
      }))
    },
    { immediate: true, deep: true }
  )

  const updateModelValue = (): void => {
    const value = props.multiple
      ? fileList.value.flatMap((file) => (file.url ? [file.url] : []))
      : (fileList.value[0]?.url ?? '')
    lastSyncedModelUrls.value = normalizeUploadModelUrls(value)
    emit('update:modelValue', value)
  }

  const beforeUpload = (file: File): boolean => {
    if (file.size <= props.fileSize) return true
    ElMessage.error(`单个文件不能超过 ${formatFileSize(props.fileSize)}`)
    return false
  }

  const handleUpload = async (options: UploadRequestOptions): Promise<unknown> => {
    uploading.value = true
    try {
      return await uploadAttachment(options.file)
    } finally {
      uploading.value = false
    }
  }

  const handleSuccess = (response: unknown, uploadFile: UploadFile): void => {
    const resource = Array.isArray(response)
      ? (response[0] as Api.DataCenter.Resources.ResourceListItem | undefined)
      : undefined
    if (!resource?.url) {
      uploadFile.status = 'fail'
      handleError(new Error('附件上传未返回访问地址'))
      return
    }

    const target = fileList.value.find((file) => file.uid === uploadFile.uid)
    if (target) {
      target.url = resource.url
      target.name = resource.originName || uploadFile.name
    }
    updateModelValue()
    emit('resource-change', [resource])
    emit('upload-success', resource, uploadFile)

    if (!props.showFileList && props.modelValue == null) fileList.value = []
  }

  const getFileTarget = (file: UploadUserFile) => ({
    name: file.name,
    url: file.url,
    fileType: getFileExtension(file.name)
  })

  const handleDownload = (file: UploadUserFile): void => {
    if (!file.url) return
    downloadAttachment(getFileTarget(file))
  }

  const handlePreview = (file: UploadUserFile): void => {
    if (!file.url) return
    viewAttachment(getFileTarget(file))
  }

  const handleRemoveFile = (file: UploadUserFile): void => {
    const fileIndex = fileList.value.findIndex(
      (item) =>
        item === file ||
        (file.uid !== undefined && item.uid === file.uid) ||
        (Boolean(file.url) && item.url === file.url)
    )
    if (fileIndex < 0) return
    fileList.value.splice(fileIndex, 1)
    updateModelValue()
  }

  const handleExceed = (): void => {
    ElMessage.warning(`当前最多只能上传 ${props.limit} 个文件`)
  }

  const handleError = (error?: unknown): void => {
    uploading.value = false
    ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件上传失败，请重试'))
  }
</script>

<style scoped lang="scss">
  .art-upload-file {
    width: 100%;

    &__trigger {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      justify-content: center;
      min-height: 34px;
      padding: 0 15px;
      font-size: 14px;
      color: var(--el-color-primary);
      cursor: pointer;
      background: color-mix(in srgb, var(--el-color-primary) 4%, var(--el-bg-color));
      border: 1px solid color-mix(in srgb, var(--el-color-primary) 62%, transparent);
      border-radius: var(--el-border-radius-base);
      transition:
        color 160ms ease,
        background-color 160ms ease,
        border-color 160ms ease,
        box-shadow 160ms ease;

      &:hover {
        color: var(--el-color-primary-light-3);
        background: color-mix(in srgb, var(--el-color-primary) 9%, var(--el-bg-color));
        border-color: var(--el-color-primary);
      }

      &:focus-visible {
        outline: 2px solid color-mix(in srgb, var(--el-color-primary) 36%, transparent);
        outline-offset: 2px;
      }

      &.is-disabled {
        color: var(--el-text-color-disabled);
        cursor: not-allowed;
        background: var(--el-fill-color-light);
        border-color: var(--el-border-color-light);
      }
    }

    &__tip {
      margin-top: 7px;
      font-size: 12px;
      line-height: 1.55;
      color: var(--el-text-color-secondary);
    }

    &__spinner {
      animation: art-upload-file-spin 0.9s linear infinite;
    }

    &__list {
      display: grid;
      gap: 4px;
      padding: 0;
      margin-top: 12px;
      margin-bottom: 0;
      list-style: none;
    }

    &__item {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-width: 0;
      min-height: 36px;
      padding: 2px 4px 2px 10px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__identity {
      display: flex;
      flex: 1;
      gap: 7px;
      align-items: center;
      min-width: 0;
      color: var(--el-text-color-secondary);

      > .art-svg-icon {
        flex: 0 0 auto;
        font-size: 14px;
      }

      :deep(.art-attachment-link) {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
      }
    }

    &__actions {
      display: inline-flex;
      flex: 0 0 auto;
      gap: 2px;
      align-items: center;
    }

    &__pending-name {
      overflow: hidden;
      text-overflow: ellipsis;
      color: var(--el-text-color-secondary);
      white-space: nowrap;
    }

    &__action {
      width: 28px !important;
      height: 28px !important;
      font-size: 15px !important;
    }

    &.is-readonly {
      :deep(.el-upload) {
        display: none;
      }

      .art-upload-file__list {
        margin-top: 0;
      }
    }
  }

  @keyframes art-upload-file-spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .art-upload-file__spinner {
      animation: none;
    }
  }
</style>
