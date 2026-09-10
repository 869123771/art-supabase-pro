<template>
  <div class="business-table-row-actions"><slot /></div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'BusinessTableRowActions' })
</script>

<style scoped lang="scss">
  .business-table-row-actions {
    display: inline-flex;
    gap: 8px;
    align-items: center;
    justify-content: flex-start;
    min-width: 0;
    white-space: nowrap;

    :deep(.art-button-table) {
      flex: 0 0 auto;
      margin-right: 0;
    }

    :deep(.el-dropdown) {
      display: inline-flex;
    }

    // 兼容存量 formatter 的单层布局容器；新代码直接把按钮作为插槽子项。
    :deep(> :is(div, span):has(> .art-button-table, > .el-dropdown)) {
      display: contents;
    }
  }
</style>
