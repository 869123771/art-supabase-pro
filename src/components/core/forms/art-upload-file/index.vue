<template>
  <div class="art-upload-file" :class="{ 'is-readonly': readonly }">
    <ElUpload
      v-model:file-list="fileList"
      :http-request="handleUpload"
      :before-upload="beforeUpload"
      :on-success="handleSuccess"
      :on-remove="handleRemove"
      :on-error="handleError"
      :on-exceed="handleExceed"
      :multiple="multiple"
      :limit="limit"
      :accept="accept"
      :disabled="disabled || readonly"
      :show-file-list="showFileList"
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

  const handleRemove = (): void => updateModelValue()

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

    :deep(.el-upload-list) {
      margin-top: 12px;
    }

    :deep(.el-upload-list__item) {
      min-height: 32px;
      padding-inline: 8px;
      border-radius: var(--el-border-radius-base);
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
