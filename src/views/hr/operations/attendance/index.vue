<template><HrWorkspacePage workspace-key="attendance" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrAttendance' })
  const permissions = {
    view: 'Hr:Attendance:View',
    add: 'Hr:Attendance:Add',
    edit: 'Hr:Attendance:Edit',
    delete: 'Hr:Attendance:Delete'
  }
</script>
