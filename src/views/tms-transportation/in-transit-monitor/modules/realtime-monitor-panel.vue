<template>
  <aside class="monitor-sidebar">
    <section class="monitor-panel monitor-panel--filters">
      <ElInput v-model="keyword" :prefix-icon="Search" clearable placeholder="请输入车辆或运单号" />
      <ElSelect v-model="status" clearable placeholder="所有状态">
        <ElOption
          v-for="item in statusOptions"
          :key="String(item.value)"
          :label="item.label"
          :value="String(item.value)"
        />
      </ElSelect>
      <ElSelect v-model="region" clearable placeholder="所有区域">
        <ElOption
          v-for="item in regionOptions"
          :key="item.value"
          :label="item.label"
          :value="item.value"
        />
      </ElSelect>
      <div class="monitor-metrics">
        <div class="monitor-metric">
          <span>今日运输量</span>
          <strong>{{ overview.todayCount }}</strong>
          <em>较昨日 +{{ overview.growthRate }}%</em>
        </div>
        <div class="monitor-metric">
          <span>准时到达率</span>
          <strong>{{ overview.onTimeRate }}%</strong>
          <em :class="{ 'is-warning': overview.delayedCount > 0 }">
            延误 {{ overview.delayedCount }} 单
          </em>
        </div>
      </div>
    </section>

    <section class="monitor-panel monitor-panel--list">
      <div class="monitor-panel__title">
        <strong>在线车辆（{{ orders.length }}/{{ totalCount }}）</strong>
      </div>
      <ElScrollbar class="vehicle-list">
        <button
          v-for="item in orders"
          :key="item.id"
          type="button"
          class="vehicle-card"
          :class="{ 'is-active': item.id === selectedId }"
          @click="emit('select', item.id)"
        >
          <div class="vehicle-card__top">
            <strong>{{ item.plateNo }}</strong>
            <span
              class="vehicle-card__status"
              :style="{
                color: item.statusColor,
                backgroundColor: withAlpha(item.statusColor, 0.18)
              }"
            >
              {{ item.statusLabel }}
            </span>
          </div>
          <p>
            <ArtDictDisplay
              dict-code="vehicleType"
              :value="item.vehicleTypeCode || undefined"
              display="text"
              :empty-text="item.vehicleTypeLabel"
            />
          </p>
          <div class="vehicle-card__line">
            <span class="vehicle-card__driver">
              <ElIcon><UserFilled /></ElIcon>
              {{ item.driverName }}
            </span>
            <span>{{ item.progress }}%</span>
          </div>
          <div class="vehicle-card__geo">
            <span class="vehicle-card__poi">
              <ElIcon><Location /></ElIcon>
              <span class="vehicle-card__poi-text">{{ getPoiText(item) }}</span>
            </span>
            <span
              class="vehicle-card__poi-refresh"
              :class="{ 'is-loading': isPoiLoading(item) }"
              role="button"
              tabindex="0"
              title="刷新当前位置"
              @click.stop="emit('refresh-poi', item)"
              @keydown.enter.stop.prevent="emit('refresh-poi', item)"
            >
              <ElIcon><RefreshRight /></ElIcon>
            </span>
          </div>
          <div class="vehicle-card__order">
            运单：{{ item.orderNo }}
            <span
              v-if="item.status === 'arrived'"
              class="vehicle-card__arrival"
              :class="{ 'is-delayed': item.arrivalDelayed }"
            >
              <ElIcon>
                <Clock v-if="item.arrivalDelayed" />
                <CircleCheckFilled v-else />
              </ElIcon>
              {{ item.arrivalText }}
            </span>
            <em v-else-if="item.delayed">延误{{ item.delayText }}</em>
          </div>
        </button>
        <ElEmpty v-if="orders.length === 0" description="暂无在途车辆" :image-size="72" />
      </ElScrollbar>
    </section>
  </aside>
</template>

<script setup lang="ts">
  import {
    CircleCheckFilled,
    Clock,
    Location,
    RefreshRight,
    Search,
    UserFilled
  } from '@element-plus/icons-vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { MonitorOrder, MonitorOverview, RegionOption, TransitStatus } from './monitor-types'

  defineOptions({ name: 'TmsRealtimeMonitorPanel' })

  const keyword = defineModel<string>('keyword', { required: true })
  const status = defineModel<TransitStatus | ''>('status', { required: true })
  const region = defineModel<string>('region', { required: true })

  defineProps<{
    getPoiText: (order: MonitorOrder) => string
    isPoiLoading: (order: MonitorOrder) => boolean
    orders: MonitorOrder[]
    overview: MonitorOverview
    regionOptions: RegionOption[]
    selectedId?: string
    statusOptions: Api.DataCenter.DictListItem[]
    totalCount: number
  }>()

  const emit = defineEmits<{
    'refresh-poi': [order: MonitorOrder]
    select: [id: string]
  }>()

  function withAlpha(color: string, alpha: number): string {
    if (/^#[\da-f]{6}$/i.test(color)) {
      const numeric = Number.parseInt(color.slice(1), 16)
      return `rgba(${(numeric >> 16) & 255}, ${(numeric >> 8) & 255}, ${numeric & 255}, ${alpha})`
    }
    return color
  }
</script>

<style scoped lang="scss">
  .monitor-sidebar {
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    gap: 12px;
    min-width: 0;
    min-height: 0;
  }

  .monitor-panel {
    min-width: 0;
    min-height: 0;
    padding: 14px;
    background: rgb(16 31 47 / 86%);
    border-radius: var(--el-border-radius-base);
    box-shadow: 0 16px 38px rgb(0 0 0 / 20%);
    backdrop-filter: blur(10px);

    &__title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;

      strong {
        font-size: 15px;
        color: #f7fbff;
      }
    }

    &--filters {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px 8px;
      padding: 12px;

      :deep(.el-input) {
        grid-column: 1 / -1;
      }

      :deep(.el-input__wrapper),
      :deep(.el-select__wrapper) {
        min-height: 34px;
        background: rgb(255 255 255 / 8%);
        border: 0;
        box-shadow: none;
      }
    }

    &--list {
      display: flex;
      flex-direction: column;
    }
  }

  .monitor-metrics {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    grid-column: 1 / -1;
    gap: 10px;
  }

  .monitor-metric {
    min-width: 0;
    padding: 14px;
    background: rgb(7 16 25 / 60%);
    border-radius: var(--el-border-radius-base);

    span,
    em {
      display: block;
      font-size: 12px;
      font-style: normal;
      color: #8fb2c6;
    }

    strong {
      display: block;
      margin: 8px 0 4px;
      font-size: 28px;
      line-height: 1;
    }

    em {
      color: #23d18b;

      &.is-warning {
        color: #ffb04f;
      }
    }
  }

  .vehicle-list {
    flex: 1;
    min-height: 0;
  }

  .vehicle-card {
    display: block;
    width: 100%;
    padding: 14px;
    margin-bottom: 10px;
    color: #dcecf6;
    text-align: left;
    cursor: pointer;
    background: rgb(7 16 25 / 44%);
    border: 0;
    border-radius: var(--el-border-radius-base);
    transition: 0.18s ease;

    &:hover,
    &.is-active {
      background: rgb(29 49 78 / 86%);
      box-shadow: inset 0 0 0 1px rgb(76 125 255 / 68%);
    }

    p {
      margin: 5px 0 12px;
      font-size: 12px;
      color: #8fb2c6;
    }

    &__top,
    &__line,
    &__order {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
    }

    &__top strong {
      font-size: 15px;
      color: #fff;
    }

    &__line,
    &__order {
      font-size: 12px;
      color: #cfe6f6;
    }

    &__driver {
      display: inline-flex;
      gap: 4px;
      align-items: center;
      min-width: 0;

      .el-icon {
        flex: 0 0 auto;
        color: #96d8ff;
      }
    }

    &__order {
      margin-top: 10px;

      em {
        font-style: normal;
        color: #ffb04f;
      }
    }

    &__arrival {
      display: inline-flex;
      flex: 0 0 auto;
      gap: 4px;
      align-items: center;
      font-weight: 700;
      color: #2ecc71;

      &.is-delayed {
        color: #ff9f43;
      }
    }

    &__geo {
      display: flex;
      gap: 8px;
      align-items: stretch;
      justify-content: space-between;
      min-width: 0;
      margin-top: 10px;
      font-size: 12px;
      color: #83a9bd;
    }

    &__poi {
      display: inline-flex;
      flex: 1;
      gap: 4px;
      align-items: flex-start;
      min-width: 0;

      .el-icon {
        flex: 0 0 auto;
        margin-top: 2px;
        color: #4cbbff;
      }
    }

    &__poi-text {
      display: -webkit-box;
      overflow: hidden;
      -webkit-line-clamp: 2;
      line-height: 18px;
      -webkit-box-orient: vertical;
    }

    &__poi-refresh {
      display: inline-flex;
      flex: 0 0 auto;
      align-items: center;
      align-self: center;
      justify-content: center;
      width: 20px;
      height: 20px;
      color: #9bc4d9;
      cursor: pointer;
      border-radius: 50%;

      &:hover,
      &:focus-visible {
        color: #fff;
        outline: 0;
        background: rgb(76 125 255 / 58%);
      }

      &.is-loading .el-icon {
        animation: monitorPoiRefresh 0.9s linear infinite;
      }
    }

    &__status {
      padding: 3px 8px;
      font-size: 12px;
      border-radius: 999px;
    }
  }

  @keyframes monitorPoiRefresh {
    to {
      transform: rotate(360deg);
    }
  }
</style>
