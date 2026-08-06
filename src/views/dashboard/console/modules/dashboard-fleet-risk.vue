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
      <div v-if="reminders.length === 0" class="fleet-risk__empty">
        <ArtSvgIcon icon="ri:shield-check-line" /> 当前无风险提醒
      </div>
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
    position: relative;
    min-width: 0;
    padding: 24px 25px;
    overflow: hidden;

    &::before {
      position: absolute;
      top: -60px;
      right: -60px;
      width: 150px;
      height: 150px;
      content: '';
      background: color-mix(in srgb, var(--el-color-danger) 8%, transparent);
      border-radius: 50%;
    }

    header {
      position: relative;
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;

      > span {
        padding: 5px 9px;
        font-size: 11px;
        font-weight: 650;
        color: var(--el-color-danger);
        background: color-mix(in srgb, var(--el-color-danger) 10%, transparent);
        border-radius: 999px;
      }
    }

    p {
      margin: 0 0 5px;
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-danger);
      letter-spacing: 0.8px;
    }

    h2 {
      margin: 0;
      font-size: 18px;
      color: var(--el-text-color-primary);
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      padding: 17px 0;
      margin-top: 22px;
      background: linear-gradient(
        120deg,
        var(--el-fill-color-light),
        color-mix(in srgb, var(--el-color-primary) 6%, var(--el-fill-color-light))
      );
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      div {
        display: grid;
        gap: 6px;
        padding-left: 15px;
        border-left: 1px solid var(--el-border-color-lighter);

        &:first-child {
          border-left: 0;
        }
      }

      span {
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 22px;
        color: var(--el-text-color-primary);
      }
    }

    &__reminders {
      display: grid;
      gap: 2px;
      margin-top: 16px;

      button {
        display: grid;
        grid-template-columns: 7px minmax(0, 1fr) auto auto;
        gap: 8px;
        align-items: center;
        width: 100%;
        padding: 7px 3px;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 0;
        border-radius: var(--el-border-radius-small);

        &:hover {
          background: var(--el-fill-color-light);
        }
      }

      i {
        width: 6px;
        height: 6px;
        border-radius: 50%;

        &.is-danger {
          background: var(--el-color-danger);
        }

        &.is-warning {
          background: var(--el-color-warning);
        }
      }

      span {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--el-text-color-regular);
        white-space: nowrap;
      }

      strong {
        font-size: 12px;
        color: var(--el-text-color-primary);
      }

      .el-icon {
        font-size: 13px;
        color: var(--el-text-color-placeholder);
      }
    }

    &__empty {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: center;
      min-height: 88px;
      font-size: 12px;
      color: var(--el-color-success);
    }
  }
</style>
