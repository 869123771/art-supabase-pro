<template>
  <aside class="monitor-sidebar">
    <section class="monitor-panel monitor-panel--summary">
      <div class="monitor-panel__title">
        <strong>运单在线监控</strong>
        <span>实时 {{ orders.length }} 单</span>
      </div>
      <div class="summary-grid">
        <div>
          <strong>{{ overview.todayCount }}</strong>
          <span>今日运输量</span>
        </div>
        <div>
          <strong>{{ overview.onTimeRate }}%</strong>
          <span>准时到达率</span>
        </div>
        <div>
          <strong>{{ averageProgress }}%</strong>
          <span>平均完成率</span>
        </div>
      </div>
      <ElInput
        v-model="keyword"
        :prefix-icon="Search"
        clearable
        placeholder="请输入运单号、车牌号或司机"
      />
    </section>

    <section class="monitor-panel monitor-panel--list">
      <div class="monitor-panel__title">
        <strong>在途运单（{{ filteredOrders.length }}）</strong>
        <span v-if="overview.delayedCount" class="is-warning">
          {{ overview.delayedCount }} 单延误
        </span>
      </div>
      <ElScrollbar class="monitor-list">
        <button
          v-for="item in filteredOrders"
          :key="item.id"
          type="button"
          class="waybill-card"
          :class="{ 'is-active': item.id === selectedId }"
          @click="emit('select', item.id)"
        >
          <div class="waybill-card__heading">
            <span
              ><ElIcon><Tickets /></ElIcon
            ></span>
            <div>
              <strong>{{ item.orderNo }}</strong>
              <small>{{ item.source.order?.transportMode || '公路运输' }}</small>
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
          <dl class="waybill-card__details">
            <div>
              <dt>承运单位</dt>
              <dd>{{ item.source.vehicle?.companyName || '自营运输' }}</dd>
            </div>
            <div>
              <dt>运输车辆</dt>
              <dd>{{ item.plateNo }}</dd>
            </div>
            <div>
              <dt>司机姓名</dt>
              <dd>{{ item.driverName }}</dd>
            </div>
            <div>
              <dt>手机号码</dt>
              <dd>{{ item.driverPhone }}</dd>
            </div>
          </dl>
          <MonitorRouteCard :order="item" />
        </button>
        <ElEmpty v-if="filteredOrders.length === 0" description="暂无匹配运单" :image-size="72" />
      </ElScrollbar>
    </section>
  </aside>
</template>

<script setup lang="ts">
  import { Search, Tickets } from '@element-plus/icons-vue'
  import MonitorRouteCard from './monitor-route-card.vue'
  import type { MonitorOrder, MonitorOverview } from './monitor-types'

  defineOptions({ name: 'TmsWaybillMonitorPanel' })

  const keyword = defineModel<string>('keyword', { required: true })

  const props = defineProps<{
    orders: MonitorOrder[]
    overview: MonitorOverview
    selectedId?: string
  }>()

  const emit = defineEmits<{
    select: [id: string]
  }>()

  const filteredOrders = computed(() => {
    const normalizedKeyword = keyword.value.trim().toLowerCase()
    if (!normalizedKeyword) return props.orders

    return props.orders.filter((item) =>
      [item.orderNo, item.plateNo, item.driverName, item.driverPhone, item.routeName]
        .join(' ')
        .toLowerCase()
        .includes(normalizedKeyword)
    )
  })

  const averageProgress = computed(() => {
    if (!props.orders.length) return 0
    return Math.round(
      props.orders.reduce((sum, item) => sum + item.progress, 0) / props.orders.length
    )
  })

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
    background: rgb(16 31 47 / 90%);
    border-radius: var(--el-border-radius-base);
    box-shadow: 0 16px 38px rgb(0 0 0 / 24%);
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

      span {
        font-size: 12px;
        color: #7da2b6;

        &.is-warning {
          color: #ffad4d;
        }
      }
    }

    &--summary {
      :deep(.el-input__wrapper) {
        min-height: 36px;
        margin-top: 12px;
        background: rgb(255 255 255 / 8%);
        box-shadow: none;
      }
    }

    &--list {
      display: flex;
      flex-direction: column;
    }
  }

  .summary-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 8px;

    div {
      min-width: 0;
      padding: 12px 8px;
      text-align: center;
      background: rgb(7 16 25 / 62%);
      border-radius: var(--el-border-radius-small);

      &:nth-child(2) strong {
        color: #32d99d;
      }

      &:nth-child(3) strong {
        color: #6d91ff;
      }
    }

    strong,
    span {
      display: block;
    }

    strong {
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 22px;
      color: #fff;
      white-space: nowrap;
    }

    span {
      margin-top: 5px;
      font-size: 11px;
      color: #82a5b7;
    }
  }

  .monitor-list {
    flex: 1;
    min-height: 0;
  }

  .waybill-card {
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
    transition: 0.18s ease;

    &:hover,
    &.is-active {
      background: rgb(29 49 78 / 88%);
      box-shadow: inset 0 0 0 1px rgb(76 125 255 / 70%);
    }

    &__heading {
      display: grid;
      grid-template-columns: 34px minmax(0, 1fr) auto;
      gap: 9px;
      align-items: center;

      > span {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 34px;
        height: 34px;
        font-size: 19px;
        color: #fff;
        background: #315cff;
        border-radius: 50%;
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
