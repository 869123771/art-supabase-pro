<template>
  <aside class="monitor-detail">
    <section class="detail-panel">
      <div class="detail-panel__title">
        <div>
          <strong>车辆详情</strong>
          <span><i />运输中</span>
        </div>
        <ElButton
          link
          :icon="MoreFilled"
          title="查看运输详情"
          aria-label="查看运输详情"
          @click="emit('open-detail')"
        />
      </div>

      <ArtAsyncState
        class="detail-state"
        :empty="!order"
        empty-text="暂无车辆详情"
        :empty-image-size="86"
        :min-height="0"
        full-height
      >
        <div v-if="order" class="detail-layout">
          <ElScrollbar class="detail-scrollbar">
            <div class="detail-content">
              <div class="detail-summary">
                <div class="detail-vehicle">
                  <div class="detail-vehicle__icon">
                    <img
                      :src="order.vehicleImage"
                      :alt="order.vehicleTypeLabel"
                      width="64"
                      height="42"
                    />
                  </div>
                  <div>
                    <small>实时车辆</small>
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
                    <strong>{{ order.speed }}<small>km/h</small></strong>
                  </div>
                  <div>
                    <span>剩余里程</span>
                    <strong>{{ order.remainingKm }}<small>km</small></strong>
                  </div>
                </div>
              </div>

              <div class="detail-waybill">
                <div class="detail-section-title">
                  <span>当前运单</span>
                  <strong :title="order.orderNo">{{ order.orderNo }}</strong>
                </div>
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
                  <div class="detail-section-title">
                    <span>货物信息</span>
                    <small>{{ order.cargoSummary.length }} 项</small>
                  </div>
                  <div class="detail-cargo__grid">
                    <p v-for="item in order.cargoSummary" :key="item.label">
                      <span>{{ item.label }}</span>
                      <b :title="item.value">{{ item.value }}</b>
                    </p>
                  </div>
                </div>

                <div class="detail-driver">
                  <div class="detail-driver__avatar">{{ order.driverName.slice(0, 1) }}</div>
                  <div>
                    <small>承运司机</small>
                    <strong>{{ order.driverName }}</strong>
                    <p>{{ order.driverPhone }}</p>
                  </div>
                  <span><ArtSvgIcon icon="ri:phone-line" /></span>
                </div>
              </div>
            </div>
          </ElScrollbar>

          <div class="detail-actions">
            <div class="detail-actions__label">
              <span>快捷处置</span>
              <small>关键操作将记录处理时间</small>
            </div>
            <ElButton
              class="detail-actions__ai"
              type="primary"
              plain
              :icon="MagicStick"
              @click="emit('analyze-anomaly')"
            >
              AI 异常研判
            </ElButton>
            <div class="detail-actions__row">
              <ElButton type="primary" :icon="Phone" @click="emit('contact-driver')">
                联系司机
              </ElButton>
              <ElButton type="warning" :icon="Warning" @click="emit('send-reminder')">
                发送提醒
              </ElButton>
            </div>
          </div>
        </div>
      </ArtAsyncState>
    </section>
  </aside>
</template>

<script setup lang="ts">
  import { MagicStick, MoreFilled, Phone, Warning } from '@element-plus/icons-vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import type { MonitorOrder } from './monitor-types'

  defineOptions({ name: 'TmsMonitorDetailPanel' })

  defineProps<{
    order?: MonitorOrder
  }>()

  const emit = defineEmits<{
    'analyze-anomaly': []
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
    padding: 0;
    overflow: hidden;
    background: var(--transit-panel-bg);
    border: 1px solid var(--transit-panel-border);
    border-radius: var(--el-border-radius-base);
    box-shadow: 0 16px 38px var(--transit-panel-shadow);
    backdrop-filter: blur(10px);

    &__title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 12px 0;
      margin-bottom: 12px;

      > div {
        display: flex;
        gap: 9px;
        align-items: center;

        strong {
          font-size: 15px;
          color: #f7fbff;
        }

        span {
          display: inline-flex;
          gap: 5px;
          align-items: center;
          padding: 3px 7px;
          font-size: 10px;
          color: #78edbd;
          background: rgb(38 224 168 / 9%);
          border: 1px solid rgb(38 224 168 / 18%);
          border-radius: 999px;

          i {
            width: 5px;
            height: 5px;
            background: #26e0a8;
            border-radius: 50%;
          }
        }
      }
    }
  }

  .detail-state {
    flex: 1;
    min-height: 0;
  }

  .detail-scrollbar {
    flex: 1;
    height: 100%;
    min-height: 0;
  }

  .detail-layout {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .detail-content {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 0 12px 14px;
  }

  .detail-summary {
    flex: 0 0 auto;
  }

  .detail-bottom {
    display: grid;
    gap: 14px;
  }

  .detail-vehicle {
    display: flex;
    gap: 10px;
    align-items: center;
    min-height: 68px;
    padding: 4px 0 2px;

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

    > div:last-child {
      min-width: 0;
    }

    small {
      display: block;
      margin-bottom: 3px;
      font-size: 10px;
      color: #7399ae;
      letter-spacing: 0.4px;
    }

    strong {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 17px;
      color: #f7fbff;
      white-space: nowrap;
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
      display: flex;
      gap: 3px;
      align-items: baseline;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 21px;
      line-height: 1.15;
      color: #f7fbff;
      white-space: nowrap;

      small {
        font-size: 10px;
        font-weight: 500;
        color: #7399ae;
      }
    }
  }

  .detail-waybill {
    flex: 0 0 auto;
    padding: 15px 0;
    border-top: 1px solid rgb(255 255 255 / 7%);
    border-bottom: 1px solid rgb(255 255 255 / 7%);
  }

  .detail-section-title {
    display: flex;
    gap: 10px;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 14px;

    > span {
      font-size: 12px;
      color: #8fb2c6;
    }

    > strong {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 13px;
      color: #f4f8fb;
      white-space: nowrap;
    }

    > small {
      font-size: 10px;
      color: #7399ae;
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
    padding: 14px;
    background: rgb(7 16 25 / 40%);
    border: 1px solid rgb(255 255 255 / 5%);
    border-radius: var(--el-border-radius-base);

    .detail-section-title {
      margin-bottom: 10px;
    }

    &__grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px 14px;
    }

    p {
      min-width: 0;
      margin: 0;
      font-size: 13px;

      span,
      b {
        display: block;
      }

      span {
        margin-bottom: 3px;
        font-size: 10px;
        color: #7399ae;
      }

      b {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: #eef7ff;
        white-space: nowrap;
      }
    }
  }

  .detail-driver {
    display: flex;
    gap: 10px;
    align-items: center;
    padding: 12px;
    background: rgb(7 16 25 / 32%);
    border: 1px solid rgb(255 255 255 / 5%);
    border-radius: var(--el-border-radius-base);

    &__avatar {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 38px;
      height: 38px;
      font-weight: 700;
      background: #315cff;
      border-radius: 50%;
    }

    > div:nth-child(2) {
      flex: 1;
      min-width: 0;

      small {
        display: block;
        margin-bottom: 2px;
        font-size: 10px;
        color: #7399ae;
      }
    }

    p {
      margin: 3px 0 0;
      color: #8fb2c6;
    }

    > span {
      display: grid;
      flex: none;
      place-items: center;
      width: 28px;
      height: 28px;
      color: #7fa6ff;
      background: rgb(49 92 255 / 12%);
      border-radius: 50%;
    }
  }

  .detail-actions {
    flex: none;
    padding: 12px;
    background: linear-gradient(180deg, rgb(16 31 47 / 12%), rgb(16 31 47 / 98%) 24%);
    border-top: 1px solid rgb(255 255 255 / 7%);

    &__label {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 9px;

      span {
        font-size: 12px;
        font-weight: 600;
        color: #dcecf6;
      }

      small {
        font-size: 9px;
        color: #668ca2;
      }
    }

    &__row {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 8px;

      .el-button {
        width: 100%;
        margin: 0;
      }
    }

    &__ai {
      width: 100%;
      margin: 0;
      color: #a8bdff;
      background: rgb(49 92 255 / 10%);
      border-color: rgb(126 159 255 / 38%);
    }

    :deep(.el-button) {
      height: 34px;
      border-radius: var(--el-border-radius-base);
    }

    :deep(.el-button__text) {
      min-width: 0;
    }
  }
</style>
