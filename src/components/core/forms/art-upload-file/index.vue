<template>
  <div
    class="art-upload-file"
    :class="{
      'is-readonly': readonly,
      'is-disabled': disabled,
      'is-trigger-only': !showTip && !showFileList,
      'is-inline': inline && !showTip && !showFileList,
      'has-hover-effect': hoverEffect && !readonly
    }"
  >
    <div
      v-if="!readonly"
      class="art-upload-file__controls"
      :class="{ 'has-resource-mode': showResourcePicker }"
    >
      <ElUpload
        v-if="!resourceMode"
        v-model:file-list="fileList"
        :http-request="handleUpload"
        :before-upload="beforeUpload"
        :on-success="handleSuccess"
        :on-error="handleError"
        :on-exceed="handleExceed"
        :multiple="multiple"
        :limit="limit"
        :accept="accept"
        :disabled="disabled || uploading"
        :show-file-list="false"
        v-bind="$attrs"
      >
        <slot name="trigger" :uploading="uploading">
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
      </ElUpload>
      <button
        v-else
        type="button"
        class="art-upload-file__trigger"
        :disabled="disabled || uploading || pickerAtLimit"
        :title="pickerAtLimit ? `最多关联 ${limit} 个文件，请先移除一个` : undefined"
        @click="resourcePickerVisible = true"
      >
        <ArtSvgIcon icon="ri:folder-open-line" aria-hidden="true" />
        从资源管理器选择
      </button>
      <ArtTooltip v-if="showResourcePicker" :content="sourceTooltip">
        <ElCheckbox
          v-model="resourceMode"
          class="art-upload-file__source-toggle"
          :disabled="disabled || uploading"
          aria-label="从资源管理器选择文件"
        />
      </ArtTooltip>
    </div>
    <div v-if="!readonly && showTip" class="art-upload-file__tip">
      <slot name="tip">{{ resolvedTip }}</slot>
    </div>

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

    <ArtResourcePicker
      v-if="showResourcePicker && !readonly"
      v-model:visible="resourcePickerVisible"
      title="从资源管理器选择文件"
      :multiple="multiple"
      :limit="multiple ? Math.max(limit - fileList.length, 0) : 1"
      @confirm="handleResourceConfirm"
    />
  </div>
</template>

<script setup lang="ts">
  import { uniqBy } from 'lodash-es'
  import type { UploadFile, UploadRequestOptions, UploadUserFile } from 'element-plus'
  import { ElMessage } from 'element-plus'
  import { uploadAttachment } from '@/api/common'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTooltip from '@/components/core/feedback/art-tooltip/index.vue'
  import ArtResourcePicker from '@/components/core/forms/art-resource-picker/index.vue'
  import type { Resource } from '@/components/core/forms/art-resource-picker/type'
  import {
    normalizeUploadModelUrls,
    shouldSyncUploadFileList
  } from '@/components/core/forms/upload-model-utils'
  import ArtAttachmentLink from '@/components/core/media/art-file-viewer/attachment-link.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { downloadAttachment, getFileExtension, viewAttachment } from '@/utils/file'
  import { isAcceptedFileType } from '@/utils/file/accept'
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
      showResourcePicker?: boolean
      hoverEffect?: boolean
      inline?: boolean
      resourceTenantId?: string
      fileName?: string
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
      showTip: true,
      showResourcePicker: true,
      hoverEffect: true,
      inline: false,
      resourceTenantId: '',
      fileName: ''
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
  const resourcePickerVisible = ref(false)
  const resourceMode = ref(false)
  const pickerAtLimit = computed(() => props.multiple && fileList.value.length >= props.limit)
  const sourceTooltip = computed(() =>
    resourceMode.value ? '取消勾选后上传本地文件' : '勾选后从资源管理器选择已有文件'
  )

  const formatFileSize = (bytes: number): string => {
    if (bytes >= 1024 * 1024) return `${Number((bytes / 1024 / 1024).toFixed(1))} MB`
    return `${Math.ceil(bytes / 1024)} KB`
  }

  const resolvedTip = computed(
    () => props.tip || `单个文件不超过 ${formatFileSize(props.fileSize)}`
  )

  watch(
    () => [props.modelValue, props.fileName] as const,
    ([value, fileName]) => {
      if (shouldSyncUploadFileList(value, lastSyncedModelUrls.value)) {
        const urls = normalizeUploadModelUrls(value)
        lastSyncedModelUrls.value = urls
        fileList.value = urls.map((url) => ({
          name: decodeURIComponent(url.split('/').pop() || '附件'),
          url
        }))
      }
      if (!props.multiple && fileName?.trim() && fileList.value[0]) {
        fileList.value[0].name = fileName.trim()
      }
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
    if (!isAcceptedFileType(file, props.accept)) {
      ElMessage.warning('文件格式不符合当前上传要求')
      return false
    }
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

  const handleResourceConfirm = (selected: Resource[]): void => {
    const resources = selected.filter((resource) => Boolean(resource.url?.trim()))
    if (!resources.length) {
      ElMessage.warning('请选择有可访问地址的文件')
      return
    }
    if (
      props.resourceTenantId &&
      resources.some((resource) => resource.tenantId !== props.resourceTenantId)
    ) {
      ElMessage.warning('所选文件不属于当前目标租户，请重新选择')
      return
    }
    if (
      resources.some(
        (resource) =>
          !isAcceptedFileType(
            {
              name: resource.originName || resource.objectName || `附件.${resource.suffix || ''}`,
              type: resource.mimeType || ''
            },
            props.accept
          )
      )
    ) {
      ElMessage.warning('所选文件格式不符合当前上传要求')
      return
    }

    const chosenFiles: UploadUserFile[] = resources.map((resource) => ({
      name: resource.originName || resource.objectName || '资源文件',
      url: resource.url
    }))
    const nextFiles = props.multiple
      ? uniqBy([...fileList.value, ...chosenFiles], (file) => file.url || file.uid)
      : chosenFiles.slice(0, 1)
    if (nextFiles.length > props.limit) {
      ElMessage.warning(`当前最多只能关联 ${props.limit} 个文件`)
      return
    }

    fileList.value = nextFiles
    updateModelValue()
    emit('resource-change', resources)
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

    &.is-trigger-only {
      width: fit-content;
      max-width: 100%;
    }

    &:not(.is-readonly) {
      padding: var(--art-space-3);
      background: var(--el-bg-color);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--el-border-radius-base);
    }

    &.is-inline:not(.is-readonly) {
      padding: 0;
      background: transparent;
      border: 0;
    }

    &:not(.is-readonly):focus-within {
      border-color: var(--theme-color);
    }

    &.has-hover-effect:not(.is-disabled) {
      transition: border-color var(--art-motion-duration-fast) var(--art-motion-ease-out);

      &:hover {
        border-color: var(--theme-color);
      }
    }

    &__controls {
      display: inline-flex;
      align-items: center;
      max-width: 100%;
    }

    &__source-toggle {
      display: inline-flex;
      flex: 0 0 38px;
      align-items: center;
      justify-content: center;
      width: 38px;
      min-height: 34px;
      margin: 0;
      cursor: pointer;
      background: var(--el-bg-color);
      border: 1px solid color-mix(in srgb, var(--el-color-primary) 62%, transparent);
      border-left: 0;
      border-radius: 0 var(--el-border-radius-base) var(--el-border-radius-base) 0;
      transition: background-color 160ms ease;

      &:hover,
      &.is-checked {
        background: color-mix(in srgb, var(--theme-color) 9%, var(--el-bg-color));
      }

      &:focus-within {
        outline: 2px solid color-mix(in srgb, var(--theme-color) 36%, transparent);
        outline-offset: 2px;
      }

      &.is-disabled {
        cursor: not-allowed;
        background: var(--el-fill-color-light);
        border-color: var(--el-border-color-light);
      }

      :deep(.el-checkbox__inner) {
        width: 16px;
        height: 16px;
      }
    }

    &__trigger {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      justify-content: center;
      height: 34px;
      min-height: 34px;
      padding: 0 15px;
      font-family: inherit;
      font-size: 14px;
      color: var(--el-color-primary);
      white-space: nowrap;
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

      &.is-disabled,
      &:disabled {
        color: var(--el-text-color-disabled);
        cursor: not-allowed;
        background: var(--el-fill-color-light);
        border-color: var(--el-border-color-light);
      }
    }

    &__controls.has-resource-mode &__trigger {
      border-radius: var(--el-border-radius-base) 0 0 var(--el-border-radius-base);
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
