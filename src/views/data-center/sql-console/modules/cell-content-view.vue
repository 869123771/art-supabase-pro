<template>
  <ArtDrawer
    ref="drawerRef"
    size="50%"
    :show-footer="false"
    append-to-body
    class="cell-content-drawer"
  >
    <template #header>
      <div class="flex items-center">
        <span class="text-lg font-medium mr-2">查看 </span>
        <el-tag>{{ columnName }}</el-tag>
      </div>
    </template>

    <div class="cell-content-view__editor">
      <Editor v-model="formattedContent" :language="language" :read-only="true" />
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { ref } from 'vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import Editor from './editor.vue'

  export interface CellContentOpenData {
    content: string
    columnName: string
  }

  export interface CellContentViewExpose {
    handleOpen: (data: CellContentOpenData) => Promise<void>
  }

  const drawerRef = ref<ArtDrawerExpose<CellContentOpenData>>()
  const columnName = ref('')
  const language = ref('text')
  const formattedContent = ref('')

  const resolveContentLanguage = (content: string) => {
    try {
      const json = JSON.parse(content)
      if (json && typeof json === 'object') {
        return 'json'
      }
    } catch {
      // Plain text content is expected for most table cells.
    }
    return 'text'
  }

  const formatContent = (content: string) => {
    try {
      const json = JSON.parse(content)
      return JSON.stringify(json, null, 2)
    } catch {
      return content
    }
  }

  const handleOpen = async (data: CellContentOpenData) => {
    columnName.value = data.columnName
    language.value = resolveContentLanguage(data.content)
    formattedContent.value = formatContent(data.content)

    await drawerRef.value?.handleOpen(data, {
      title: '查看',
      size: '50%',
      showFooter: false
    })
  }

  defineExpose<CellContentViewExpose>({ handleOpen })
</script>

<style scoped lang="scss">
  :deep(.cell-content-drawer) {
    display: flex;
    flex-direction: column;

    .el-drawer__header {
      flex: 0 0 auto;
    }

    .el-drawer__body {
      --art-drawer-content-padding: 0;

      display: flex;
      flex: 1;
      flex-direction: column;
      height: auto;
      min-height: 0;
      padding: 0;
      overflow: hidden;
    }

    .art-drawer__content {
      display: flex;
      flex: 1;
      height: auto;
      min-height: 0;
      overflow: hidden;
    }
  }

  .cell-content-view__editor {
    flex: 1;
    height: 100%;
    min-height: 0;
  }
</style>
