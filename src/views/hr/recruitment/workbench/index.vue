<template><HrWorkspacePage workspace-key="recruitment" :permissions="permissions" /></template>
<script setup lang="ts">
  import HrWorkspacePage from '@/views/hr/shared/hr-workspace-page.vue'
  defineOptions({ name: 'HrRecruitment' })
  const permissions = {
    view: 'Hr:Recruitment:View',
    add: 'Hr:Recruitment:Add',
    edit: 'Hr:Recruitment:Edit',
    delete: 'Hr:Recruitment:Delete',
    submit: 'Hr:Recruitment:Submit',
    effect: 'Hr:Recruitment:Effect'
  }
</script>
