<template>
  <article class="order-flow art-card-xs">
    <header>
      <div><p>运输执行</p><h2>订单流转</h2></div>
      <button type="button" @click="emit('view-orders')"
        >订单列表 <ElIcon><ArrowRight /></ElIcon
      ></button>
    </header>
    <div class="order-flow__headline">
      <strong>{{ total }}</strong
      ><span>近 {{ days }} 天订单</span>
      <b>运输中 {{ inTransitCount }} 单</b>
    </div>
    <div class="order-flow__rail"
      ><i
        v-for="item in activeStatusItems"
        :key="item.key"
        :style="{ flex: item.value || 0.16, background: item.color }"
    /></div>
    <div class="order-flow__list">
      <button
        v-for="item in statusItems"
        :key="item.key"
        type="button"
        @click="emit('view-orders')"
      >
        <span :style="{ background: item.color }" />
        <em>{{ item.label }}</em>
        <strong>{{ item.value }}</strong>
        <small>{{ item.percent }}%</small>
      </button>
    </div>
  </article>
</template>

<script setup lang="ts">
  import { ArrowRight } from '@element-plus/icons-vue'
  import type { DashboardStatusItem } from './types'

  const props = defineProps<{
    days: number
    total: number
    inTransitCount: number
    statusItems: DashboardStatusItem[]
  }>()
  const emit = defineEmits<{ 'view-orders': [] }>()
  const activeStatusItems = computed(() => props.statusItems.filter((item) => item.value > 0))
</script>

<style scoped lang="scss">
  .order-flow {
    min-width: 0;
    padding: 21px 24px;
  }
  header {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
  }
  p {
    margin: 0 0 4px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }
  h2 {
    margin: 0;
    font-size: 17px;
    color: var(--el-text-color-primary);
  }
  header button {
    display: inline-flex;
    gap: 2px;
    align-items: center;
    padding: 0;
    font-size: 12px;
    color: var(--el-color-primary);
    cursor: pointer;
    background: transparent;
    border: 0;
  }
  .order-flow__headline {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 2px 8px;
    align-items: end;
    margin-top: 22px;
  }
  .order-flow__headline strong {
    font-size: 31px;
    line-height: 1;
    color: var(--el-text-color-primary);
  }
  .order-flow__headline span {
    padding-bottom: 2px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }
  .order-flow__headline b {
    grid-column: 1 / -1;
    margin-top: 6px;
    font-size: 12px;
    color: var(--el-color-success);
    font-weight: 600;
  }
  .order-flow__rail {
    display: flex;
    gap: 3px;
    height: 8px;
    margin: 17px 0 15px;
    overflow: hidden;
    border-radius: 999px;
    background: var(--el-fill-color-light);
  }
  .order-flow__rail i {
    min-width: 7px;
    height: 100%;
    border-radius: inherit;
  }
  .order-flow__list {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 7px 13px;
  }
  .order-flow__list button {
    display: grid;
    grid-template-columns: 7px minmax(0, 1fr) auto auto;
    gap: 6px;
    align-items: center;
    padding: 3px 0;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
  }
  .order-flow__list span {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .order-flow__list em {
    overflow: hidden;
    font-size: 12px;
    font-style: normal;
    color: var(--el-text-color-regular);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .order-flow__list strong {
    font-size: 12px;
    color: var(--el-text-color-primary);
  }
  .order-flow__list small {
    font-size: 11px;
    color: var(--el-text-color-placeholder);
  }
</style>
