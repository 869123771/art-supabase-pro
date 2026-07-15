<template>
  <article class="recent-orders art-card-xs">
    <header
      ><div><p>最新业务</p><h2>最近订单</h2></div
      ><button type="button" @click="emit('view-orders')"
        >全部订单 <ElIcon><ArrowRight /></ElIcon></button
    ></header>
    <div class="recent-orders__head"
      ><span>订单编号</span><span>运输线路</span><span>车辆 / 司机</span><span>运费</span
      ><span>状态</span></div
    >
    <ElScrollbar class="recent-orders__list">
      <button
        v-for="item in orders"
        :key="item.id || item.orderNo"
        type="button"
        class="recent-orders__row"
        @click="emit('open-order', item.id)"
      >
        <strong>{{ item.orderNo }}</strong>
        <span>{{ item.originStation || '-' }} → {{ item.destinationStation || '-' }}</span>
        <span
          >{{ item.dispatchPlateNo || '待配载'
          }}<em>{{ item.dispatchDriverName || '司机待分配' }}</em></span
        >
        <b>¥ {{ formatMoney(item.totalFee) }}</b>
        <ElTag size="small" :type="getOrderTagType(item.orderStatus)" effect="plain">{{
          getOrderStatusLabel(item.orderStatus)
        }}</ElTag>
      </button>
      <ElEmpty v-if="orders.length === 0" description="暂无订单数据" :image-size="62" />
    </ElScrollbar>
  </article>
</template>

<script setup lang="ts">
  import { ArrowRight } from '@element-plus/icons-vue'
  import type { DashboardOrder } from './types'

  defineProps<{ orders: DashboardOrder[] }>()
  const emit = defineEmits<{ 'view-orders': []; 'open-order': [id?: string] }>()
  const labelMap: Record<string, string> = {
    pending_load: '待配载',
    pending_order: '待发车',
    transporting: '运输中',
    signed: '待结案',
    completed: '已完成',
    cancelled: '已取消'
  }
  const tagMap: Record<string, 'primary' | 'success' | 'warning' | 'info' | 'danger'> = {
    pending_load: 'primary',
    pending_order: 'warning',
    transporting: 'success',
    signed: 'warning',
    completed: 'info',
    cancelled: 'danger'
  }
  const getOrderStatusLabel = (status?: string | null): string =>
    labelMap[String(status ?? '')] ?? '待处理'
  const getOrderTagType = (
    status?: string | null
  ): 'primary' | 'success' | 'warning' | 'info' | 'danger' => tagMap[String(status ?? '')] ?? 'info'
  const formatMoney = (value?: number | string | null): string =>
    Number(value ?? 0).toLocaleString('zh-CN', { maximumFractionDigits: 2 })
</script>

<style scoped lang="scss">
  .recent-orders {
    min-width: 0;
    padding: 21px 24px 8px;
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
  .recent-orders__head,
  .recent-orders__row {
    display: grid;
    grid-template-columns: 1.15fr 1.4fr 1.1fr 0.72fr 0.65fr;
    gap: 14px;
    align-items: center;
  }
  .recent-orders__head {
    padding: 16px 8px 9px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }
  .recent-orders__list {
    height: 206px;
  }
  .recent-orders__row {
    width: 100%;
    min-height: 47px;
    padding: 7px 8px;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
    border-top: 1px solid var(--el-border-color-lighter);
    transition: background 0.16s ease;
  }
  .recent-orders__row:hover {
    background: var(--el-fill-color-light);
  }
  .recent-orders__row strong,
  .recent-orders__row > span {
    min-width: 0;
    overflow: hidden;
    font-size: 13px;
    color: var(--el-text-color-primary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .recent-orders__row > span {
    color: var(--el-text-color-regular);
  }
  .recent-orders__row span em {
    display: block;
    overflow: hidden;
    margin-top: 3px;
    font-size: 11px;
    font-style: normal;
    color: var(--el-text-color-placeholder);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .recent-orders__row b {
    font-size: 12px;
    color: var(--el-text-color-regular);
  }
  .recent-orders__row :deep(.el-tag) {
    justify-self: start;
    width: fit-content;
    min-width: 0;
  }
  @media screen and (max-width: 720px) {
    .recent-orders__head,
    .recent-orders__row {
      grid-template-columns: 1fr 1fr auto;
    }
    .recent-orders__head span:nth-child(3),
    .recent-orders__head span:nth-child(4),
    .recent-orders__row > span:nth-child(3),
    .recent-orders__row > b {
      display: none;
    }
  }
</style>
