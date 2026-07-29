<!-- 导入 Excel 文件 -->
<template>
  <div class="inline-block">
    <ElUpload
      ref="uploadRef"
      :auto-upload="false"
      :accept="accept"
      :disabled="isDisabled"
      :show-file-list="false"
      @change="handleFileChange"
    >
      <ElButton v-bind="buttonProps" :disabled="isDisabled" v-ripple>
        <template v-if="icon" #icon>
          <component v-if="typeof icon !== 'string'" :is="icon" />
          <ArtSvgIcon v-else :icon="icon" />
        </template>
        <slot>导入 Excel</slot>
      </ElButton>
    </ElUpload>
  </div>
</template>

<script setup lang="ts">
  import type { UploadFile, UploadInstance } from 'element-plus'
  import type { Component } from 'vue'
  import { importExcelFile } from '@/utils/file'

  defineOptions({ name: 'ArtExcelImport' })

  const props = withDefaults(
    defineProps<{
      accept?: string
      disabled?: boolean
      icon?: string | Component
      buttonProps?: Record<string, unknown>
      parseExcel?: boolean
    }>(),
    {
      accept: '.xlsx, .xls',
      disabled: false,
      buttonProps: () => ({ type: 'primary' }),
      parseExcel: true
    }
  )

  const emit = defineEmits<{
    'file-change': [file: File, uploadFile: UploadFile]
    'import-success': [data: Array<Record<string, unknown>>]
    'import-error': [error: Error]
  }>()

  const uploadRef = ref<UploadInstance>()
  const isDisabled = computed(() => props.disabled || Boolean(props.buttonProps?.loading))

  const handleFileChange = async (uploadFile: UploadFile) => {
    try {
      if (!uploadFile.raw) return
      if (!props.parseExcel) {
        emit('file-change', uploadFile.raw, uploadFile)
        return
      }
      const results = await importExcelFile(uploadFile.raw)
      emit('import-success', results)
    } catch (error) {
      emit('import-error', error as Error)
    } finally {
      uploadRef.value?.clearFiles()
    }
  }
</script>
