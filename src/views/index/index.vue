<!-- 布局容器 -->
<template>
  <div class="app-layout">
    <aside id="app-sidebar">
      <ArtSidebarMenu />
    </aside>

    <main id="app-main">
      <ElScrollbar
        class="app-main__scrollbar"
        wrap-class="app-main__scroll-wrap"
        view-class="app-main__scroll-view"
      >
        <div id="app-header">
          <ArtHeaderBar />
        </div>
        <div id="app-content">
          <ArtPageContent />
        </div>
      </ElScrollbar>
    </main>

    <div id="app-global">
      <ArtGlobalComponent />
    </div>
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'AppLayout' })
</script>

<style lang="scss" scoped>
  @use './style';
</style>
