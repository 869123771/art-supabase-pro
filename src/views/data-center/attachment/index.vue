<template>
  <div class="page-content art-full-height">
    <ArtResourcePanel v-model="model" :show-action="false" />
  </div>
</template>

<script setup lang="ts">
  import ArtResourcePanel from '@/components/core/forms/art-resource-picker/panel.vue'
  const model = ref<any>()
</script>

<style scoped lang="scss"></style>
