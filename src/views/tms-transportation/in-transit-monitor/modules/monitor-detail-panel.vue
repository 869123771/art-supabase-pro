<template>
  <aside class="monitor-detail">
    <section class="detail-panel">
      <div class="detail-panel__title">
        <strong>车辆详情</strong>
        <ElButton link :icon="MoreFilled" @click="emit('open-detail')" />
      </div>

      <div v-if="order" class="detail-content">
        <div class="detail-summary">
          <div class="detail-vehicle">
            <div class="detail-vehicle__icon">
              <img :src="order.vehicleImage" :alt="order.vehicleTypeLabel" />
            </div>
            <div>
              <strong>{{ order.plateNo }}</strong>
              <p>
                <ArtDictDisplay
                  dict-code="vehicleType"
                  :value="order.vehicleTypeCode || undefined"
                  display="text"
                  :empty-text="order.vehicleTypeLabel"
                />
              </p>
            </div>
          </div>

          <div class="detail-speed">
            <div>
              <span>当前速度</span>
              <strong>{{ order.speed }}km/h</strong>
            </div>
            <div>
              <span>剩余里程</span>
              <strong>{{ order.remainingKm }}km</strong>
            </div>
          </div>
        </div>

        <div class="detail-waybill">
          <span>当前运单</span>
          <strong>{{ order.orderNo }}</strong>
          <div class="detail-route">
            <div>
              <b>{{ order.origin }}</b>
              <small>出发时间</small>
              <em>{{ formatDateTime(order.plannedDepartureTime) }}</em>
            </div>
            <i>{{ order.progress }}%</i>
            <div>
              <b>{{ order.destination }}</b>
              <small>预计到达</small>
              <em>{{ formatDateTime(order.plannedArrivalTime) }}</em>
            </div>
          </div>
          <div class="detail-progress">
            <div>
              <span>运输进度</span>
              <b>{{ order.completedKm }}/{{ order.totalKm }} km</b>
            </div>
            <i><b :style="{ width: `${order.progress}%` }" /></i>
          </div>
        </div>

        <div class="detail-bottom">
          <div class="detail-cargo">
            <strong>货物信息</strong>
            <p v-for="item in order.cargoSummary" :key="item.label">
              <span>{{ item.label }}</span>
              <b>{{ item.value }}</b>
            </p>
          </div>

          <div class="detail-driver">
            <div class="detail-driver__avatar">{{ order.driverName.slice(0, 1) }}</div>
            <div>
              <strong>{{ order.driverName }}</strong>
              <p>{{ order.driverPhone }}</p>
            </div>
          </div>

          <div class="detail-actions">
            <ElButton type="primary" :icon="Phone" @click="emit('contact-driver')">
              联系司机
            </ElButton>
            <ElButton type="warning" :icon="Warning" @click="emit('send-reminder')">
              发送提醒
            </ElButton>
          </div>
        </div>
      </div>
      <ElEmpty v-else class="detail-empty" description="暂无车辆详情" :image-size="86" />
    </section>
  </aside>
</template>

<script setup lang="ts">
  import { MoreFilled, Phone, Warning } from '@element-plus/icons-vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import type { MonitorOrder } from './monitor-types'

  defineOptions({ name: 'TmsMonitorDetailPanel' })

  defineProps<{
    order?: MonitorOrder
  }>()

  const emit = defineEmits<{
    'contact-driver': []
    'open-detail': []
    'send-reminder': []
  }>()

  function formatDateTime(value?: string | null): string {
    return value ? formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '-' : '-'
  }
</script>

<style scoped lang="scss">
  .monitor-detail {
    min-width: 0;
    min-height: 0;
  }

  .detail-panel {
    display: flex;
    flex-direction: column;
    min-width: 0;
    height: 100%;
    min-height: 0;
    padding: 12px;
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
  }

  .detail-content {
    display: flex;
    flex: 1;
    flex-direction: column;
    justify-content: space-between;
    min-height: 0;
  }

  .detail-summary {
    flex: 0 0 auto;
  }

  .detail-bottom {
    flex: 0 0 auto;
  }

  .detail-empty {
    flex: 1;
  }

  .detail-vehicle {
    display: flex;
    gap: 10px;
    align-items: center;
    min-height: 68px;
    padding: 2px 0 10px;

    &__icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 72px;
      height: 52px;
      background: rgb(7 16 25 / 58%);
      border-radius: var(--el-border-radius-base);

      img {
        width: 64px;
        height: 42px;
        object-fit: contain;
      }
    }

    strong {
      font-size: 17px;
    }

    p {
      margin: 4px 0 0;
      font-size: 13px;
      color: #8fb2c6;
    }
  }

  .detail-speed {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin-top: 10px;

    div {
      min-width: 0;
      padding: 12px;
      background: rgb(7 16 25 / 50%);
      border-radius: var(--el-border-radius-base);
    }

    span {
      display: block;
      margin-bottom: 6px;
      font-size: 12px;
      color: #8fb2c6;
    }

    strong {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 21px;
      line-height: 1.15;
      white-space: nowrap;
    }
  }

  .detail-waybill {
    flex: 0 0 auto;
    padding: 18px 0;
    border-top: 1px solid rgb(255 255 255 / 7%);
    border-bottom: 1px solid rgb(255 255 255 / 7%);

    > span {
      display: block;
      color: #8fb2c6;
    }

    > strong {
      display: block;
      margin: 8px 0 16px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 16px;
      white-space: nowrap;
    }
  }

  .detail-route {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 50px minmax(0, 1fr);
    gap: 8px;
    align-items: center;
    text-align: center;

    b,
    small,
    em {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      margin-top: 5px;
      font-size: 11px;
      color: #7399ae;
    }

    em {
      margin-top: 4px;
      font-size: 12px;
      font-style: normal;
      color: #8fb2c6;
    }

    i {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      height: 50px;
      font-size: 12px;
      font-style: normal;
      color: #fff;
      border: 3px solid #315cff;
      border-radius: 50%;
    }
  }

  .detail-progress {
    margin-top: 16px;

    > div {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 7px;
      font-size: 12px;

      span {
        color: #b9d8e7;
      }

      b {
        color: #f2f8ff;
      }
    }

    > i {
      display: block;
      height: 6px;
      overflow: hidden;
      background: rgb(255 255 255 / 10%);
      border-radius: 999px;

      b {
        display: block;
        height: 100%;
        background: linear-gradient(90deg, #315cff, #26e0a8);
      }
    }
  }

  .detail-cargo {
    min-height: 0;
    padding-top: 0;
    margin-top: 0;

    strong {
      display: block;
      margin-bottom: 12px;
    }

    p {
      display: flex;
      gap: 10px;
      justify-content: space-between;
      margin: 0 0 8px;
      font-size: 13px;
      color: #91adbe;

      b {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        color: #eef7ff;
        white-space: nowrap;
      }
    }
  }

  .detail-driver {
    display: flex;
    gap: 10px;
    align-items: center;
    padding-top: 18px;
    margin-top: 18px;
    border-top: 1px solid rgb(255 255 255 / 7%);

    &__avatar {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 44px;
      height: 44px;
      font-weight: 700;
      background: #315cff;
      border-radius: 50%;
    }

    p {
      margin: 3px 0 0;
      color: #8fb2c6;
    }
  }

  .detail-actions {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
    padding-bottom: 2px;
    margin-top: 16px;
  }
</style>
