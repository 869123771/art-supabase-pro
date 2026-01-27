<template>
  <el-drawer
    v-model="visible"
    title="Viewing cell details"
    size="50%"
    :with-header="true"
    append-to-body
    class="cell-content-drawer"
  >
    <template #header>
      <div class="flex items-center">
        <span class="text-lg font-medium mr-2">Viewing cell details on column:</span>
        <el-tag>{{ columnName }}</el-tag>
      </div>
    </template>
    <div class="h-full flex flex-col">
      <Editor v-model="formattedContent" :language="language" :read-only="true" />
    </div>
  </el-drawer>
</template>

<script setup lang="ts">
  import { computed } from 'vue'
  import Editor from './editor.vue'

  interface Props {
    modelValue: boolean
    content: string
    columnName: string
  }

  const props = withDefaults(defineProps<Props>(), {
    modelValue: false,
    content: '',
    columnName: ''
  })

  const emit = defineEmits<{
    (e: 'update:modelValue', value: boolean): void
  }>()

  const visible = computed({
    get: () => props.modelValue,
    set: (val) => emit('update:modelValue', val)
  })

  const language = computed(() => {
    try {
      const json = JSON.parse(props.content)
      if (json && typeof json === 'object') {
        return 'json'
      }
    } catch (e) {
      console.error(e)
    }
    return 'text'
  })

  const formattedContent = computed({
    get: () => {
      try {
        // Try to parse as JSON and format
        const json = JSON.parse(props.content)
        return JSON.stringify(json, null, 2)
      } catch (e) {
        console.log(e)
        // If not JSON, return as is
        return props.content
      }
    },
    set: () => {} // Readonly
  })
</script>

<style scoped lang="scss">
  .cell-content-drawer {
    :deep(.el-drawer__body) {
      padding: 0;
    }
  }
</style>
