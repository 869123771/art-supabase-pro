<template><HrWorkspacePage workspace-key="personnelChange" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrPersonnelChange' })
  const permissions = {
    view: 'Hr:PersonnelChange:View',
    add: 'Hr:PersonnelChange:Add',
    edit: 'Hr:PersonnelChange:Edit',
    delete: 'Hr:PersonnelChange:Delete',
    submit: 'Hr:PersonnelChange:Submit',
    effect: 'Hr:PersonnelChange:Effect'
  }
</script>
