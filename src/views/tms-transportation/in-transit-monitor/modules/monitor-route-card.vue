<template>
  <div class="monitor-route-card">
    <div class="monitor-route-card__cities">
      <strong>{{ order.origin }}</strong>
      <span>{{ order.progress }}%</span>
      <strong>{{ order.destination }}</strong>
    </div>
    <div class="monitor-route-card__track">
      <i />
      <b :style="{ width: `${order.progress}%` }" />
      <em :style="{ left: `${order.progress}%` }" />
    </div>
    <div class="monitor-route-card__meta">
      <span>{{ formatDateTime(order.plannedDepartureTime) }}</span>
      <small>{{ order.totalKm }} km</small>
      <span>{{ formatDateTime(order.plannedArrivalTime) }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { formatWithDayjs } from '@/utils/time'
  import type { MonitorOrder } from './monitor-types'

  defineOptions({ name: 'TmsMonitorRouteCard' })

  defineProps<{
    order: MonitorOrder
  }>()

  function formatDateTime(value?: string | null): string {
    return value ? formatWithDayjs(value, 'MM-DD HH:mm') || '-' : '-'
  }
</script>

<style scoped lang="scss">
  .monitor-route-card {
    padding: 11px;
    margin-top: 11px;
    background: rgb(5 14 24 / 64%);
    border-radius: var(--el-border-radius-small);

    &__cities,
    &__meta {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 64px minmax(0, 1fr);
      gap: 8px;
      align-items: center;
    }

    &__cities {
      font-size: 12px;

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        color: #f3f8ff;
        white-space: nowrap;

        &:last-child {
          text-align: right;
        }
      }

      span {
        color: #45d7a1;
        text-align: center;
      }
    }

    &__track {
      position: relative;
      height: 12px;
      margin: 7px 4px 3px;

      i,
      b {
        position: absolute;
        top: 5px;
        left: 0;
        height: 2px;
        border-radius: 999px;
      }

      i {
        width: 100%;
        background: rgb(255 255 255 / 14%);
      }

      b {
        background: linear-gradient(90deg, #315cff, #25dba1);
      }

      em {
        position: absolute;
        top: 1px;
        width: 10px;
        height: 10px;
        background: #35ca9a;
        border: 2px solid #dffdf3;
        border-radius: 50%;
        box-shadow: 0 0 10px rgb(53 202 154 / 80%);
        transform: translateX(-50%);
      }
    }

    &__meta {
      font-size: 10px;
      color: #789caf;

      span:last-child {
        text-align: right;
      }

      small {
        color: #6c8b9c;
        text-align: center;
      }
    }
  }
</style>
