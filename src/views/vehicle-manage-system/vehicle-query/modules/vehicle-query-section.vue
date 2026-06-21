<template>
  <section class="vehicle-query-section">
    <div class="vehicle-query-section__header">
      <ArtSectionTitle :show-line="false">{{ title }}</ArtSectionTitle>
      <div v-if="$slots.extra" class="vehicle-query-section__extra">
        <slot name="extra" />
      </div>
    </div>
    <slot />
  </section>
</template>

<script setup lang="ts">
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'

  defineOptions({ name: 'VehicleQuerySection' })

  defineProps<{
    title: string
  }>()
</script>

<style scoped lang="scss">
  .vehicle-query-section {
    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 18px;
    }

    &__extra {
      display: flex;
      gap: 8px;
      align-items: center;
    }
  }
</style>
