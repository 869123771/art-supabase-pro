<template><HrWorkspacePage workspace-key="headcount" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrHeadcount' })
  const permissions = {
    view: 'Hr:Headcount:View',
    add: 'Hr:Headcount:Add',
    edit: 'Hr:Headcount:Edit',
    delete: 'Hr:Headcount:Delete'
  }
</script>
