<template>
  <aside class="monitor-sidebar">
    <section class="monitor-panel monitor-panel--summary">
      <div class="monitor-panel__title">
        <strong>车辆监控</strong>
        <span>定位已连接</span>
      </div>
      <div class="summary-grid">
        <div>
          <strong>{{ vehicleOrders.length }}</strong>
          <span>监控车辆</span>
        </div>
        <div>
          <strong>{{ overview.onTimeRate }}%</strong>
          <span>准时运输</span>
        </div>
        <div>
          <strong>{{ averageProgress }}%</strong>
          <span>运输完成率</span>
        </div>
      </div>
      <ElInput
        v-model="keyword"
        :prefix-icon="Search"
        clearable
        placeholder="请输入车牌号、司机或运单号"
      />
    </section>

    <section class="monitor-panel monitor-panel--list">
      <div class="monitor-panel__title">
        <strong>车辆列表（{{ filteredOrders.length }}）</strong>
        <span>{{ overview.delayedCount ? `${overview.delayedCount} 辆需关注` : '运行正常' }}</span>
      </div>
      <ElScrollbar class="monitor-list">
        <ArtAsyncState
          :empty="filteredOrders.length === 0"
          empty-text="暂无匹配车辆"
          empty-description="可调整车辆状态、区域或关键字后重新筛选"
          :empty-image-size="72"
          :min-height="540"
        >
          <button
            v-for="item in filteredOrders"
            :key="item.plateNo"
            type="button"
            class="vehicle-monitor-card"
            :class="{ 'is-active': item.id === selectedId }"
            @click="emit('select', item.id)"
          >
            <div class="vehicle-monitor-card__heading">
              <span
                ><ElIcon><Van /></ElIcon
              ></span>
              <div>
                <strong>{{ item.plateNo }}</strong>
                <small>{{ item.vehicleTypeLabel }}</small>
              </div>
              <em
                :style="{
                  color: item.statusColor,
                  backgroundColor: withAlpha(item.statusColor, 0.18)
                }"
              >
                {{ item.statusLabel }}
              </em>
            </div>
            <dl class="vehicle-monitor-card__details">
              <div>
                <dt>司机姓名</dt>
                <dd>{{ item.driverName }}</dd>
              </div>
              <div>
                <dt>手机号码</dt>
                <dd>{{ item.driverPhone }}</dd>
              </div>
              <div class="is-wide">
                <dt>运输信息</dt>
                <dd>{{ item.orderNo }}</dd>
              </div>
            </dl>
            <MonitorRouteCard :order="item" />
          </button>
        </ArtAsyncState>
      </ElScrollbar>
    </section>
  </aside>
</template>

<script setup lang="ts">
  import { Search, Van } from '@element-plus/icons-vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import MonitorRouteCard from './monitor-route-card.vue'
  import type { MonitorOrder, MonitorOverview } from './monitor-types'

  defineOptions({ name: 'TmsVehicleMonitorPanel' })

  const keyword = defineModel<string>('keyword', { required: true })

  const props = defineProps<{
    orders: MonitorOrder[]
    overview: MonitorOverview
    selectedId?: string
  }>()

  const emit = defineEmits<{
    select: [id: string]
  }>()

  const vehicleOrders = computed(() => {
    const ordersByPlate = new Map<string, MonitorOrder>()
    props.orders.forEach((item) => {
      if (item.plateNo === '未配车') return
      const existing = ordersByPlate.get(item.plateNo)
      if (!existing || getVehicleOrderPriority(item) > getVehicleOrderPriority(existing)) {
        ordersByPlate.set(item.plateNo, item)
      }
    })
    return [...ordersByPlate.values()]
  })

  const filteredOrders = computed(() => {
    const normalizedKeyword = keyword.value.trim().toLowerCase()
    if (!normalizedKeyword) return vehicleOrders.value

    return vehicleOrders.value.filter((item) =>
      [item.plateNo, item.vehicleTypeLabel, item.driverName, item.driverPhone, item.orderNo]
        .join(' ')
        .toLowerCase()
        .includes(normalizedKeyword)
    )
  })

  const averageProgress = computed(() => {
    if (!vehicleOrders.value.length) return 0
    return Math.round(
      vehicleOrders.value.reduce((sum, item) => sum + item.progress, 0) / vehicleOrders.value.length
    )
  })

  function getVehicleOrderPriority(item: MonitorOrder): number {
    if (item.status === 'delayed') return 4
    if (item.status === 'transporting') return 3
    if (item.status === 'pending') return 2
    return 1
  }

  function withAlpha(color: string, alpha: number): string {
    if (/^#[\da-f]{6}$/i.test(color)) {
      const numeric = Number.parseInt(color.slice(1), 16)
      return `rgba(${(numeric >> 16) & 255}, ${(numeric >> 8) & 255}, ${numeric & 255}, ${alpha})`
    }
    return color
  }
</script>

<style scoped lang="scss">
  @use './monitor-panel-foundation' as monitor;

  @include monitor.panel-foundation($meta-color: #6fbf9d);
  @include monitor.summary-grid(#36d99f, #ffad4d);

  .monitor-panel {
    &--summary {
      :deep(.el-input__wrapper) {
        min-height: 36px;
        margin-top: 12px;
        background: rgb(255 255 255 / 8%);
        box-shadow: none;
      }
    }
  }

  .monitor-list {
    flex: 1;
    min-height: 0;
  }

  .vehicle-monitor-card {
    display: block;
    width: 100%;
    padding: 14px;
    margin-bottom: 10px;
    color: #dcecf6;
    text-align: left;
    cursor: pointer;
    background: rgb(7 16 25 / 48%);
    border: 0;
    border-radius: var(--el-border-radius-base);
    transition:
      background-color 0.18s ease,
      box-shadow 0.18s ease;

    &:hover,
    &.is-active {
      background: rgb(29 49 78 / 88%);
      box-shadow: inset 0 0 0 1px rgb(76 125 255 / 70%);
    }

    &__heading {
      display: grid;
      grid-template-columns: 38px minmax(0, 1fr) auto;
      gap: 10px;
      align-items: center;

      > span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 38px;
        height: 38px;
        font-size: 22px;
        color: #fff;
        background: linear-gradient(135deg, #315cff, #517fff);
        border-radius: var(--el-border-radius-small);
      }

      strong,
      small {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        color: #fff;
      }

      small {
        margin-top: 3px;
        font-size: 11px;
        color: #86a9bc;
      }

      em {
        padding: 3px 8px;
        font-size: 11px;
        font-style: normal;
        border-radius: 999px;
      }
    }

    &__details {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px 12px;
      padding: 11px 0 0;
      margin: 0;

      div {
        min-width: 0;

        &.is-wide {
          grid-column: 1 / -1;
        }
      }

      dt,
      dd {
        display: inline;
        margin: 0;
        font-size: 11px;
      }

      dt {
        color: #7699ab;

        &::after {
          content: '：';
        }
      }

      dd {
        color: #d9e9f2;
      }
    }
  }
</style>
