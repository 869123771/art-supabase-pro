<template>
  <ArtDialog ref="dialogRef" size="xl">
    <WorkflowAnalyticsPanel />
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import WorkflowAnalyticsPanel from '../../modules/workflow-analytics-panel.vue'

  defineOptions({ name: 'WorkflowAnalyticsDialog' })
  const dialogRef = ref<ArtDialogExpose>()

  async function handleOpen(): Promise<void> {
    await dialogRef.value?.handleOpen(undefined, {
      title: '审批运营分析',
      subtitle: '从经营结果到节点瓶颈，提供租户安全的流程治理依据。',
      contentMaxHeight: '78vh',
      showFooter: false
    })
  }

  defineExpose({ handleOpen })
</script>
