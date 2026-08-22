<template><HrWorkspacePage workspace-key="compliance" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrCompliance' })
  const permissions = {
    view: 'Hr:Compliance:View',
    add: 'Hr:Compliance:Add',
    edit: 'Hr:Compliance:Edit',
    delete: 'Hr:Compliance:Delete'
  }
</script>
