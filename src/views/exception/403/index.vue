<template>
  <ArtPermissionGuard force-denied resource-name="目标页面" />
</template>

<script setup lang="ts">
  import ArtPermissionGuard from '@/components/core/feedback/art-permission-guard/index.vue'

  defineOptions({ name: 'Exception403' })
</script>
