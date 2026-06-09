<!-- 导入 Excel 文件 -->
<template>
  <div class="inline-block">
    <ElUpload
      :auto-upload="false"
      :accept="accept"
      :show-file-list="false"
      @change="handleFileChange"
    >
      <ElButton v-bind="buttonProps" :disabled="disabled" v-ripple>
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
  import * as XLSX from 'xlsx'
  import type { UploadFile } from 'element-plus'
  import type { Component } from 'vue'

  defineOptions({ name: 'ArtExcelImport' })

  withDefaults(
    defineProps<{
      accept?: string
      disabled?: boolean
      icon?: string | Component
      buttonProps?: Record<string, any>
    }>(),
    {
      accept: '.xlsx, .xls',
      disabled: false,
      buttonProps: () => ({ type: 'primary' })
    }
  )

  // Excel 导入工具函数
  async function importExcel(file: File): Promise<Array<Record<string, unknown>>> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()

      reader.onload = (e) => {
        try {
          const data = e.target?.result
          const workbook = XLSX.read(data, { type: 'array' })
          const firstSheetName = workbook.SheetNames[0]
          const worksheet = workbook.Sheets[firstSheetName]
          const results = XLSX.utils.sheet_to_json(worksheet)
          resolve(results as Array<Record<string, unknown>>)
        } catch (error) {
          reject(error)
        }
      }

      reader.onerror = (error) => reject(error)
      reader.readAsArrayBuffer(file)
    })
  }

  const emit = defineEmits<{
    'import-success': [data: Array<Record<string, unknown>>]
    'import-error': [error: Error]
  }>()

  const handleFileChange = async (uploadFile: UploadFile) => {
    try {
      if (!uploadFile.raw) return
      const results = await importExcel(uploadFile.raw)
      emit('import-success', results)
    } catch (error) {
      emit('import-error', error as Error)
    }
  }
</script>
