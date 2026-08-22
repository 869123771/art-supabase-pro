<template>
  <div
    class="business-workspace-page art-full-height fms-accounting-page accounting-workspace-shell"
  >
    <slot />
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'FinanceAccountingWorkspaceShell' })
</script>

<style scoped lang="scss">
  @use '@/views/fms/modules/accounting-workspace.scss' as accounting;

  .accounting-workspace-shell {
    @include accounting.accounting-workspace-layout;
  }
</style>
