<template>
  <header class="setting-header">
    <div class="setting-header__identity">
      <span class="setting-header__mark">
        <ArtSvgIcon icon="ri:palette-line" />
      </span>
      <div>
        <span>APPEARANCE STUDIO</span>
        <h2>界面工作室</h2>
        <p>让工作台更鲜明、更高效，也更像你的产品。</p>
      </div>
    </div>
    <button
      type="button"
      class="setting-header__close"
      aria-label="关闭界面设置"
      @click="$emit('close')"
    >
      <ArtSvgIcon icon="ri:close-line" />
    </button>
  </header>
</template>

<script setup lang="ts">
  defineEmits<{
    close: []
  }>()
</script>
