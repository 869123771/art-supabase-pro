<template>
  <article class="dashboard-transit art-card-xs">
    <header>
      <div><p>调度中心</p><h2>实时运输</h2></div>
      <button type="button" @click="emit('monitor')"
        >在途监控 <ElIcon><ArrowRight /></ElIcon
      ></button>
    </header>
    <ElScrollbar class="dashboard-transit__list">
      <button
        v-for="item in orders"
        :key="item.id || item.orderNo"
        type="button"
        class="transit-row"
        @click="emit('open-order', item.id)"
      >
        <span class="transit-row__truck"><ArtSvgIcon icon="ri:truck-line" /></span>
        <div class="transit-row__main"
          ><strong>{{ item.dispatchPlateNo || '待分配车辆' }}</strong
          ><span>{{ item.orderNo }}</span></div
        >
        <div class="transit-row__route"
          ><b>{{ item.originStation || '始发站' }}</b
          ><i /><b>{{ item.destinationStation || '目的站' }}</b></div
        >
        <span class="transit-row__driver">{{ item.dispatchDriverName || '司机待分配' }}</span>
        <ElTag size="small" type="success" effect="light">运输中</ElTag>
      </button>
      <ElEmpty v-if="orders.length === 0" description="暂无运输中的运单" :image-size="62" />
    </ElScrollbar>
  </article>
</template>

<script setup lang="ts">
  import { ArrowRight } from '@element-plus/icons-vue'
  import type { DashboardOrder } from './types'

  defineProps<{ orders: DashboardOrder[] }>()
  const emit = defineEmits<{ monitor: []; 'open-order': [id?: string] }>()
</script>

<style scoped lang="scss">
  .dashboard-transit {
    min-width: 0;
    padding: 21px 24px 9px;
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
  .dashboard-transit__list {
    height: 282px;
    margin-top: 14px;
  }
  .transit-row {
    display: grid;
    grid-template-columns: 33px 104px minmax(120px, 1fr) 82px auto;
    gap: 9px;
    align-items: center;
    width: 100%;
    min-height: 54px;
    padding: 7px 4px;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
    border-bottom: 1px solid var(--el-border-color-lighter);
    transition: background 0.16s ease;
  }
  .transit-row:hover {
    background: var(--el-fill-color-light);
  }
  .transit-row__truck {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 31px;
    height: 31px;
    color: var(--el-color-primary);
    background: color-mix(in srgb, var(--el-color-primary) 15%, var(--el-bg-color));
    border-radius: var(--el-border-radius-small);
  }
  .transit-row__main {
    display: grid;
    min-width: 0;
    gap: 3px;
  }
  .transit-row__main strong {
    overflow: hidden;
    font-size: 13px;
    color: var(--el-text-color-primary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .transit-row__main span,
  .transit-row__driver {
    overflow: hidden;
    font-size: 11px;
    color: var(--el-text-color-placeholder);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .transit-row__route {
    display: flex;
    gap: 6px;
    align-items: center;
    min-width: 0;
    overflow: hidden;
  }
  .transit-row__route b {
    min-width: 0;
    overflow: hidden;
    font-size: 12px;
    font-weight: 500;
    color: var(--el-text-color-regular);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .transit-row__route i {
    flex: 0 0 15px;
    height: 1px;
    background: var(--el-border-color);
  }
  @media screen and (max-width: 720px) {
    .transit-row {
      grid-template-columns: 33px minmax(0, 1fr) auto;
    }
    .transit-row__route,
    .transit-row__driver {
      display: none;
    }
  }
</style>
