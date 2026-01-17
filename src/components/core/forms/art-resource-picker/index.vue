<template>
  <ElDialog
    v-model="dialogVisible"
    title="资源选择器"
    append-to-body
    destroy-on-close
    align-center
    :footer="false"
  >
    <div class="h-[595px]">
      <ResourcePanel v-bind="attrs" @cancel="onCancel" @confirm="onConfirm" />
    </div>
  </ElDialog>
</template>

<script setup lang="ts">
  import { omit } from 'lodash-es'
  import ResourcePanel from './panel.vue'
  import type { Resource } from './type.ts'

  defineOptions({ name: 'MaResourcePicker' })

  const emit = defineEmits<{
    cancel: []
    confirm: [selected: Resource[]]
  }>()
  const dialogVisible = defineModel<boolean>('visible', { default: false })
  function onCancel() {
    dialogVisible.value = false
    emit('cancel')
  }

  function onConfirm(selected: any[]) {
    dialogVisible.value = false
    emit('confirm', selected)
  }

  // 获得所有attrs
  const attrs = omit(useAttrs(), ['onConfirm', 'onCancel'])
</script>

<style scoped lang="scss"></style>
