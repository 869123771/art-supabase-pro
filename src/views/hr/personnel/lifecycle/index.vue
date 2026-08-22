<template><HrWorkspacePage workspace-key="lifecycle" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrLifecycle' })
  const permissions = {
    view: 'Hr:Lifecycle:View',
    add: 'Hr:Lifecycle:Add',
    edit: 'Hr:Lifecycle:Edit',
    delete: 'Hr:Lifecycle:Delete',
    submit: 'Hr:Lifecycle:Submit',
    completeTask: 'Hr:Lifecycle:CompleteTask'
  }
</script>
