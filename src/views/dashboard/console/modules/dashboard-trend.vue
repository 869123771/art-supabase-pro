<template>
  <article class="dashboard-trend art-card-xs">
    <header>
      <div><p>经营态势</p><h2>订单趋势</h2></div>
      <ElRadioGroup
        :model-value="days"
        size="small"
        @update:model-value="emit('update:days', Number($event))"
      >
        <ElRadioButton :value="7">近 7 天</ElRadioButton>
        <ElRadioButton :value="14">近 14 天</ElRadioButton>
        <ElRadioButton :value="30">近 30 天</ElRadioButton>
      </ElRadioGroup>
    </header>
    <div class="dashboard-trend__summary">
      <div
        ><span>期间订单</span><strong>{{ data.orderCount }} <em>单</em></strong></div
      >
      <i />
      <div
        ><span>开单运费</span><strong>¥ {{ formatMoney(data.freightAmount) }}</strong></div
      >
    </div>
    <ArtLineChart
      height="230px"
      :data="data.values"
      :x-axis-data="data.labels"
      :show-area-color="true"
      :show-axis-line="false"
      :show-legend="false"
      :loading="loading"
    />
  </article>
</template>

<script setup lang="ts">
  import type { DashboardTrendData } from './types'

  defineProps<{ days: number; data: DashboardTrendData; loading: boolean }>()
  const emit = defineEmits<{ 'update:days': [days: number] }>()

  function formatMoney(value: number): string {
    return value.toLocaleString('zh-CN', { maximumFractionDigits: 2 })
  }
</script>

<style scoped lang="scss">
  .dashboard-trend {
    min-width: 0;
    padding: 21px 24px 15px;
  }
  header {
    display: flex;
    gap: 16px;
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
  .dashboard-trend__summary {
    display: flex;
    gap: 21px;
    align-items: center;
    margin: 22px 0 0;
  }
  .dashboard-trend__summary div {
    display: grid;
    gap: 5px;
  }
  .dashboard-trend__summary span {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }
  .dashboard-trend__summary strong {
    font-size: 21px;
    color: var(--el-text-color-primary);
  }
  .dashboard-trend__summary em {
    font-size: 12px;
    font-style: normal;
    font-weight: 500;
    color: var(--el-text-color-placeholder);
  }
  .dashboard-trend__summary > i {
    width: 1px;
    height: 29px;
    background: var(--el-border-color-lighter);
  }
</style>
