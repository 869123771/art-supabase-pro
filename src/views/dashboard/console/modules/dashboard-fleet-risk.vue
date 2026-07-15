<template>
  <article class="fleet-risk art-card-xs">
    <header
      ><div><p>车辆健康</p><h2>风险提醒</h2></div
      ><span>{{ reminderTotal }} 项待处理</span></header
    >
    <div class="fleet-risk__stats">
      <div
        ><span>车辆总数</span><strong>{{ vehicleCount }}</strong></div
      >
      <div
        ><span>运营车辆</span><strong>{{ operatingVehicleCount }}</strong></div
      >
      <div
        ><span>待审核</span><strong>{{ pendingAuditVehicleCount }}</strong></div
      >
    </div>
    <div class="fleet-risk__reminders">
      <button
        v-for="item in reminders"
        :key="item.key"
        type="button"
        @click="emit('view-reminder')"
      >
        <i :class="`is-${item.severity}`" /><span>{{ item.label }}</span
        ><strong>{{ item.count }}</strong
        ><ElIcon><ArrowRight /></ElIcon>
      </button>
    </div>
  </article>
</template>

<script setup lang="ts">
  import { ArrowRight } from '@element-plus/icons-vue'
  import type { DashboardReminder } from './types'

  defineProps<{
    vehicleCount: number
    operatingVehicleCount: number
    pendingAuditVehicleCount: number
    reminderTotal: number
    reminders: DashboardReminder[]
  }>()
  const emit = defineEmits<{ 'view-reminder': [] }>()
</script>

<style scoped lang="scss">
  .fleet-risk {
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
  header > span {
    font-size: 12px;
    color: var(--el-color-danger);
  }
  .fleet-risk__stats {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    padding: 14px 0;
    margin-top: 18px;
    background: var(--el-fill-color-light);
    border-radius: var(--el-border-radius-base);
  }
  .fleet-risk__stats div {
    display: grid;
    gap: 5px;
    padding-left: 13px;
    border-left: 1px solid var(--el-border-color-lighter);
  }
  .fleet-risk__stats div:first-child {
    border-left: 0;
  }
  .fleet-risk__stats span {
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }
  .fleet-risk__stats strong {
    font-size: 19px;
    color: var(--el-text-color-primary);
  }
  .fleet-risk__reminders {
    display: grid;
    gap: 2px;
    margin-top: 14px;
  }
  .fleet-risk__reminders button {
    display: grid;
    grid-template-columns: 7px minmax(0, 1fr) auto auto;
    gap: 8px;
    align-items: center;
    width: 100%;
    padding: 6px 0;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
  }
  .fleet-risk__reminders i {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .fleet-risk__reminders i.is-danger {
    background: var(--el-color-danger);
  }
  .fleet-risk__reminders i.is-warning {
    background: var(--el-color-warning);
  }
  .fleet-risk__reminders span {
    overflow: hidden;
    font-size: 13px;
    color: var(--el-text-color-regular);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .fleet-risk__reminders strong {
    font-size: 13px;
    color: var(--el-text-color-primary);
  }
  .fleet-risk__reminders .el-icon {
    font-size: 13px;
    color: var(--el-text-color-placeholder);
  }
</style>
