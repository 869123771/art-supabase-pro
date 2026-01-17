<template>
  <el-upload
    v-model:file-list="fileList"
    class="art-upload"
    :before-upload="beforeUpload"
    :http-request="handleUpload"
    :on-success="handleSuccess"
    :on-exceed="handleExceed"
    :on-error="handleError"
    :multiple="multiple"
    :limit="limit"
    :accept="fileType"
    v-bind="$attrs"
  >
    <slot name="default">
      <component :is="btnRender()" v-show="fileList.length === 0" ref="uploadBtnRef" />
    </slot>
    <template #file="{ file, index }">
      <div class="preview-list upload-container relative" :style="getSize">
        <div class="preview-mask">
          <i @click="handleView">
            <ArtSvgIcon icon="ri-eye-line" class="icon text-[20px]" />
          </i>
          <i @click="handleRemove(index)">
            <ArtSvgIcon icon="ri-delete-bin-2-line" class="icon" />
          </i>
        </div>
        <el-image
          ref="ElImageRefs"
          :src="file?.url"
          class="absolute rounded-md"
          :style="getSize"
          fit="cover"
          :zoom-rate="1.2"
          :max-scale="7"
          :min-scale="0.2"
          :preview-src-list="previewList"
          :initial-index="index"
        />
      </div>
      <component
        :is="btnRender()"
        v-if="index === fileList.length - 1 && multiple && fileList.length < limit"
        class="cursor-pointer"
        @click="() => uploadBtnRef?.click?.()"
      />
    </template>
    <template #tip>
      <div v-if="fileList.length < 1" class="pt-1 text-sm text-dark-50 dark-text-gray-3">
        <slot name="tip">
          {{ $attrs?.tip }}
        </slot>
      </div>
    </template>
    <ArtResourcePicker
      v-model:visible="isOpenResource"
      :multiple="multiple"
      :limit="limit"
      @confirm="handleConfirm"
    />
  </el-upload>
</template>

<script setup lang="tsx">
  import { ElMessage, UploadUserFile, UploadRequestOptions } from 'element-plus'
  import { isArray } from 'lodash-es'
  import ArtResourcePicker from '@/components/core/forms/art-resource-picker/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ResourceListItem = Api.DataCenter.Resources.ResourceListItem
  import { uploadAttachment } from '@/api/common'

  const {
    modelValue = null,
    title = null,
    size = 120,
    fileSize = 10 * 1024 * 1024,
    fileType = 'image/*',
    limit = 5,
    multiple = false
  } = defineProps<{
    modelValue?: string | string[] | null
    title?: string
    size?: number
    fileSize?: number
    fileType?: string
    limit?: number
    multiple?: boolean
  }>()

  const emit = defineEmits<{
    (e: 'update:modelValue', value: string | string[]): void
  }>()

  const uploadBtnRef = ref<HTMLElement>()
  const isOpenResource = ref<boolean>(false)
  const previewList = ref<string[]>([])
  const ElImageRefs = ref([])

  const getSize = computed(() => {
    return {
      width: `${size ?? 120}px`,
      height: `${size ?? 120}px`
    }
  })

  function btnRender() {
    return (
      <a class="upload-container" style={getSize.value}>
        <el-tooltip content="打开资源选择器">
          <a
            class="resource-btn"
            onClick={(e: MouseEvent) => {
              e.stopPropagation()
              isOpenResource.value = true
            }}
          >
            <ArtSvgIcon icon="ri-folder-open-line" class="text-[18px]" />
          </a>
        </el-tooltip>
        <div class="mt-[18%] flex flex-col items-center">
          <ArtSvgIcon icon="ri-add-line" class="text-[20px]" />
          <span class="mt-1 text-[14px]">{title ?? '上传图片'}</span>
        </div>
      </a>
    )
  }

  const fileList = ref<UploadUserFile[]>([])

  watch(
    () => fileList.value.length,
    (length: number) => {
      const uploadTextDom: HTMLElement | null = document.querySelector(
        `.art-upload .el-upload--text`
      )
      if (uploadTextDom) {
        uploadTextDom.style.display = length > 0 ? 'none' : 'block'
      }
    },
    { immediate: true }
  )

  const setPreviewData = useDebounceFn(() => {
    previewList.value = []
    fileList.value?.map((item: any) => {
      previewList.value.push(item.url)
    })
  })

  watch(
    () => fileList.value,
    async () => {
      await setPreviewData()
    },
    { immediate: true, deep: true }
  )

  watch(
    () => modelValue,
    (val: string | string[] | null) => {
      if (!val) {
        fileList.value = []
        return false
      }

      if (isArray(val)) {
        fileList.value = val.map((item: string) => {
          return {
            name: item.split('/').pop() as string,
            url: item
          }
        })
      } else {
        fileList.value = [{ name: val?.split('/')?.pop() as string, url: val }]
      }
    },
    { immediate: true, deep: true }
  )

  function updateModelValue() {
    emit(
      'update:modelValue',
      (multiple ? fileList.value.map((file) => file.url!) : fileList.value[0]?.url) as
        | string
        | string[]
    )
  }

  function handleSuccess(res: any) {
    const [{ id, origin_name, url }] = res ?? []
    const index = fileList.value.findIndex((item: any) => item.response[0]?.id === id)
    fileList.value[index].name = origin_name
    fileList.value[index].url = url

    updateModelValue()
  }

  function beforeUpload(rawFile: File) {
    /*if (!fileType.includes(rawFile.type)) {
      ElMessage.error(`只允许上传：${fileType.join(', ')}`)
      return false
    }*/
    if (fileSize < rawFile.size) {
      ElMessage.error(`只允许上传${fileSize}字节大小的文件`)
      return false
    }

    return true
  }

  function handleExceed() {
    ElMessage.error(`当前最多只能上传 ${limit} 张图片，请重新选择上传！`)
  }

  function handleError() {
    ElMessage.error(`图片上传失败，请您重新上传！`)
  }

  const handleView = () => {
    ElImageRefs.value?.$el?.children[0]?.click?.()
  }

  const handleRemove = (index: number) => {
    fileList.value.splice(index, 1)
    updateModelValue()
  }

  const handleConfirm = (selected: ResourceListItem[]) => {
    fileList.value = selected.map((item: any) => {
      return { name: item.ogirinName, url: item.url }
    })
    updateModelValue()
  }

  const handleUpload = async (options: UploadRequestOptions): Promise<unknown> => {
    return await uploadAttachment(options.file)
  }
</script>

<style scoped lang="scss">
  :deep(.el-upload-list) {
    // @apply flex gap-1.5 flex-wrap;
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;

    .el-upload-list__item {
      // @apply w-auto outline-none b-0;
      width: auto;
      outline: 2px solid transparent;
      outline-offset: 2px;
      border: 0px;
    }

    .el-upload-list__item:hover {
      background: none;
    }

    & :last-child {
      // @apply flex gap-x-1.5;
      display: flex;
      column-gap: 0.375rem;
    }
  }

  .upload-container {
    // @apply flex items-center justify-center bg-gray-50 b-1 b-dashed rounded-md b-gray-3 dark-b-dark-50
    // transition-all duration-300 text-gray-5 dark-bg-dark-5 relative;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: var(--color-box);
    border-width: 1px;
    border-style: dashed;
    border-radius: 0.375rem;
    border-color: var(--color-g-300); /* b-gray-3 默认值 */
    transition: all 300ms ease;
    color: #6b7280; /* text-gray-5 默认值 */
    position: relative;

    // dark 模式样式（保留原自定义变量）
    @media (prefers-color-scheme: dark) {
      border-color: var(--dark-50); /* dark-b-dark-50 */
      background-color: var(--dark-5); /* dark-bg-dark-5 */
    }

    .resource-btn {
      // @apply absolute top-0 b-1 b-dashed b-gray-3 dark-b-dark-50 transition-all duration-300 rounded-t-md
      // w-[calc(100%)] mx-auto b-t-0 b-l-0 b-r-0 text-gray-5 dark-bg-dark-8 bg-gray-1 h-[calc(100%-80%)]
      // flex items-center justify-center;
      position: absolute;
      top: 0px;
      border-width: 1px;
      border-style: dashed;
      border-color: var(--default-border-dashed); /* b-gray-3 默认值 */
      transition: all 300ms ease;
      border-top-left-radius: 0.375rem;
      border-top-right-radius: 0.375rem;
      width: calc(100%);
      margin-left: auto;
      margin-right: auto;
      border-top-width: 0px;
      border-left-width: 0px;
      border-right-width: 0px;
      color: var(--color-g-500); /* text-gray-5 默认值 */
      background-color: var(--art-gray-200); /* bg-gray-1 默认值 */
      height: calc(100% - 80%);
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .preview-mask {
      // @apply absolute z-8 w-full h-full rounded-md transition-all duration-300 flex items-center justify-center gap-x-3;
      position: absolute;
      z-index: 8;
      width: 100%;
      height: 100%;
      border-radius: 0.375rem;
      transition: all 300ms ease;
      display: flex;
      align-items: center;
      justify-content: center;
      column-gap: 0.75rem;

      .icon {
        // @apply hidden text-white cursor-pointer;
        display: none;
        color: #ffffff;
        cursor: pointer;
        font-size: 20px;
      }
    }

    .preview-mask:hover {
      // @apply bg-dark-5/50%;
      background-color: var(--color-g-500);
      .icon {
        // @apply inline;
        display: inline;
      }
    }

    &:hover,
    .resource-btn:hover {
      // @apply text-[rgb(var(--ui-primary))] b-[rgb(var(--ui-primary))];
      color: var(--el-color-primary);
      border-color: var(--el-color-primary);
    }
  }
</style>
