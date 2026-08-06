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
    position: relative;
    min-width: 0;
    padding: 24px 26px 17px;
    overflow: hidden;

    &::before {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 3px;
      content: '';
      background: linear-gradient(90deg, var(--el-color-primary), #38d9ff, transparent 72%);
    }

    header {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;

      :deep(.el-radio-group) {
        padding: 3px;
        background: var(--el-fill-color-light);
        border-radius: 999px;
      }

      :deep(.el-radio-button__inner) {
        border: 0;
        border-radius: 999px !important;
        box-shadow: none;
      }
    }

    p {
      margin: 0 0 5px;
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.8px;
    }

    h2 {
      margin: 0;
      font-size: 18px;
      color: var(--el-text-color-primary);
    }

    &__summary {
      display: flex;
      gap: 24px;
      align-items: center;
      margin: 25px 0 1px;

      div {
        display: grid;
        gap: 5px;
      }

      span {
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 23px;
        line-height: 1.1;
        color: var(--el-text-color-primary);
      }

      em {
        font-size: 12px;
        font-style: normal;
        font-weight: 500;
        color: var(--el-text-color-placeholder);
      }

      > i {
        width: 1px;
        height: 34px;
        background: var(--el-border-color-lighter);
      }
    }

    @media screen and (width <= 560px) {
      padding: 21px 18px 13px;

      header {
        align-items: flex-start;
      }

      :deep(.el-radio-button__inner) {
        padding-right: 8px;
        padding-left: 8px;
      }
    }
  }
</style>
