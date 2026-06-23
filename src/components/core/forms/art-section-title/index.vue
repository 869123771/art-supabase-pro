<template>
  <div
    :class="[
      'art-section-title',
      {
        'art-section-title--with-line': showLine,
        'art-section-title--with-marker': showMarker
      }
    ]"
  >
    <template v-if="showLabel">
      <slot>
        <component v-if="typeof title !== 'string'" :is="title" />
        <span v-else>{{ title }}</span>
      </slot>
    </template>
  </div>
</template>

<script setup lang="ts">
  import type { Component, VNodeChild } from 'vue'

  defineOptions({ name: 'ArtSectionTitle' })

  export type ArtSectionTitleContent = string | (() => VNodeChild) | Component

  withDefaults(
    defineProps<{
      title?: ArtSectionTitleContent
      showLine?: boolean
      showLabel?: boolean
      showMarker?: boolean
    }>(),
    {
      title: '',
      showLine: true,
      showLabel: true,
      showMarker: true
    }
  )
</script>

<style scoped lang="scss">
  .art-section-title {
    display: flex;
    align-items: center;
    width: 100%;
    margin: 4px 0 14px;
    color: var(--el-text-color-primary);
    font-weight: 600;
    line-height: 24px;

    &--with-marker::before {
      width: 3px;
      height: 14px;
      margin-right: 8px;
      content: '';
      border-radius: 999px;
      background: var(--el-color-primary);
    }

    &--with-line::after {
      flex: 1;
      height: 1px;
      margin-left: 12px;
      content: '';
      background: var(--el-border-color-lighter);
    }
  }
</style>
