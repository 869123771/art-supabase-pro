<template>
  <header class="screen-panel-heading">
    <div class="screen-panel-heading__icon"><ArtSvgIcon :icon="icon" /></div>
    <div>
      <span>{{ eyebrow }}</span>
      <h2>{{ title }}</h2>
    </div>
    <div v-if="$slots.aside" class="screen-panel-heading__aside"><slot name="aside" /></div>
  </header>
</template>

<script setup lang="ts">
  defineProps<{ eyebrow: string; title: string; icon: string }>()
</script>

<style scoped lang="scss">
  .screen-panel-heading {
    display: grid;
    grid-template-columns: 34px minmax(0, 1fr) auto;
    gap: 10px;
    align-items: center;
    min-width: 0;

    &__icon {
      display: grid;
      place-items: center;
      width: 34px;
      height: 34px;
      font-size: 17px;
      color: var(--screen-accent-soft);
      background: rgb(71 128 255 / 12%);
      border: 1px solid rgb(124 167 255 / 18%);
      border-radius: var(--el-border-radius-small);
    }

    span {
      display: block;
      margin-bottom: 3px;
      font-size: 9px;
      font-weight: 650;
      color: var(--screen-text-muted);
      letter-spacing: 0.9px;
      opacity: 0.82;
    }

    h2 {
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 15px;
      font-weight: 650;
      line-height: 1.2;
      color: var(--screen-text-strong);
      white-space: nowrap;
    }

    &__aside {
      min-width: 0;
    }
  }
</style>
