<template>
  <footer class="art-sticky-action-bar art-card-xs">
    <div v-if="$slots.summary" class="art-sticky-action-bar__summary">
      <slot name="summary" />
    </div>
    <div class="art-sticky-action-bar__actions">
      <slot />
    </div>
  </footer>
</template>

<script setup lang="ts">
  defineOptions({ name: 'ArtStickyActionBar' })
</script>

<style scoped lang="scss">
  .art-sticky-action-bar {
    position: sticky;
    bottom: var(--art-sticky-offset);
    z-index: 20;
    display: flex;
    gap: var(--art-space-4);
    align-items: center;
    justify-content: space-between;
    min-width: 0;
    padding: var(--art-space-3) var(--art-section-padding);
    border-color: color-mix(
      in srgb,
      var(--el-color-primary) 12%,
      var(--art-card-border)
    ) !important;
    box-shadow: 0 8px 28px rgb(0 0 0 / 10%) !important;
    backdrop-filter: blur(12px);

    &__summary {
      flex: 1;
      min-width: 0;
    }

    &__actions {
      display: flex;
      flex: none;
      gap: var(--art-space-2);
      align-items: center;
      justify-content: flex-end;
    }

    @media (width <= 640px) {
      bottom: var(--art-space-2);
      flex-direction: column;
      align-items: stretch;
      padding: var(--art-space-3);

      &__actions {
        flex-wrap: wrap;
        justify-content: flex-start;
        width: 100%;
      }
    }
  }
</style>
