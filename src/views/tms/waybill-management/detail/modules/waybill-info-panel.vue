<template>
  <div class="waybill-info-panel">
    <div class="waybill-info-panel__top-grid">
      <section class="waybill-info-panel__section art-card-xs">
        <ArtSectionTitle title="执行概览" />
        <div class="waybill-info-panel__route">
          <div class="waybill-info-panel__route-endpoint">
            <span class="is-origin">发</span>
            <div>
              <small>起运地</small>
              <strong>{{ waybill.originCity || waybill.order?.originStation || '-' }}</strong>
              <p>{{ waybill.shipperAddress || waybill.order?.shippingAddressDetail || '-' }}</p>
            </div>
          </div>
          <div class="waybill-info-panel__route-line">
            <i></i>
            <ArtSvgIcon icon="ri:truck-line" aria-hidden="true" />
            <i></i>
          </div>
          <div class="waybill-info-panel__route-endpoint is-destination">
            <span class="is-destination">收</span>
            <div>
              <small>目的地</small>
              <strong>{{
                waybill.destinationCity || waybill.order?.destinationStation || '-'
              }}</strong>
              <p>{{ waybill.receiverAddress || waybill.order?.receivingAddressDetail || '-' }}</p>
            </div>
          </div>
        </div>
        <dl class="waybill-info-panel__facts">
          <div v-for="item in executionFacts" :key="item.label">
            <dt>{{ item.label }}</dt>
            <dd>{{ item.value }}</dd>
          </div>
        </dl>
      </section>

      <section class="waybill-info-panel__section art-card-xs">
        <ArtSectionTitle title="费用与结算" />
        <div class="waybill-info-panel__amount">
          <div>
            <small>运单运费</small>
            <strong>{{ money(waybill.freightAmount ?? waybill.order?.totalFee) }}</strong>
          </div>
          <ArtDictDisplay
            v-if="waybill.order?.paymentMethod"
            dict-code="tmsOrderPaymentMethod"
            :value="waybill.order.paymentMethod"
            display="tag"
          />
        </div>
        <dl class="waybill-info-panel__fee-list">
          <div v-for="item in feeItems" :key="item.label">
            <dt>{{ item.label }}</dt>
            <dd>{{ money(item.value) }}</dd>
          </div>
        </dl>
        <div class="waybill-info-panel__payment-summary">
          <span>应收/付款合计</span>
          <strong>{{ money(waybill.order?.paymentTotal) }}</strong>
        </div>
      </section>
    </div>

    <section class="waybill-info-panel__section art-card-xs">
      <ArtSectionTitle title="承运资源" />
      <div class="waybill-info-panel__resource-grid">
        <article>
          <span class="waybill-info-panel__resource-icon">
            <ArtSvgIcon icon="ri:steering-2-line" aria-hidden="true" />
          </span>
          <div>
            <small>承运司机</small>
            <strong>{{ waybill.driver?.driverName || '暂未分配' }}</strong>
            <p>{{ waybill.driver?.phone || '-' }}</p>
          </div>
          <ElTag v-if="waybill.driver?.licenseType" size="small" type="info">
            {{ waybill.driver.licenseType }} 驾照
          </ElTag>
        </article>
        <article>
          <span class="waybill-info-panel__resource-icon">
            <ArtSvgIcon icon="ri:truck-line" aria-hidden="true" />
          </span>
          <div>
            <small>执行车辆</small>
            <strong>{{ waybill.vehicle?.plateNo || '暂未分配' }}</strong>
            <p>{{ vehicleSummary }}</p>
          </div>
          <ElTag v-if="waybill.vehicle?.approvedLoadMass != null" size="small" type="info">
            核载 {{ waybill.vehicle.approvedLoadMass }} t
          </ElTag>
        </article>
        <article>
          <span class="waybill-info-panel__resource-icon">
            <ArtSvgIcon icon="ri:building-2-line" aria-hidden="true" />
          </span>
          <div>
            <small>承运商</small>
            <strong>{{ waybill.carrier?.companyName || '自营运输' }}</strong>
            <p>{{ carrierContact }}</p>
          </div>
        </article>
      </div>
    </section>

    <section class="waybill-info-panel__section art-card-xs">
      <ArtSectionTitle title="发收货与联系信息" />
      <div class="waybill-info-panel__contact-grid">
        <article>
          <div class="waybill-info-panel__contact-heading">
            <span class="is-shipper">发</span>
            <div>
              <small>发货方</small>
              <strong>{{
                waybill.shipperName || waybill.order?.shippingContactName || '-'
              }}</strong>
            </div>
          </div>
          <p><ArtSvgIcon icon="ri:phone-line" aria-hidden="true" />{{ shipperPhone }}</p>
          <p><ArtSvgIcon icon="ri:map-pin-line" aria-hidden="true" />{{ shipperAddress }}</p>
        </article>
        <div class="waybill-info-panel__contact-arrow" aria-hidden="true">
          <i></i><ArtSvgIcon icon="ri:arrow-right-line" /><i></i>
        </div>
        <article>
          <div class="waybill-info-panel__contact-heading">
            <span class="is-receiver">收</span>
            <div>
              <small>收货方</small>
              <strong>{{
                waybill.receiverName || waybill.order?.receivingContactName || '-'
              }}</strong>
            </div>
          </div>
          <p><ArtSvgIcon icon="ri:phone-line" aria-hidden="true" />{{ receiverPhone }}</p>
          <p><ArtSvgIcon icon="ri:map-pin-line" aria-hidden="true" />{{ receiverAddress }}</p>
        </article>
      </div>
    </section>

    <div class="waybill-info-panel__bottom-grid">
      <section class="waybill-info-panel__section art-card-xs">
        <ArtSectionTitle title="货物明细" />
        <div class="waybill-info-panel__cargo-summary">
          <div>
            <span><ArtSvgIcon icon="ri:stack-line" aria-hidden="true" /></span>
            <div
              ><small>总件数</small><strong>{{ cargoQuantity }}</strong></div
            >
          </div>
          <div>
            <span><ArtSvgIcon icon="ri:scales-3-line" aria-hidden="true" /></span>
            <div
              ><small>总重量</small><strong>{{ cargoWeight }}</strong></div
            >
          </div>
          <div>
            <span><ArtSvgIcon icon="ri:box-3-line" aria-hidden="true" /></span>
            <div
              ><small>总体积</small><strong>{{ cargoVolume }}</strong></div
            >
          </div>
        </div>
        <div v-if="cargoItems.length" class="waybill-info-panel__cargo-list">
          <article v-for="(item, index) in cargoItems" :key="`${item.cargoId || index}`">
            <span>{{ index + 1 }}</span>
            <div>
              <strong>{{ item.cargoName || waybill.cargoName || '未命名货物' }}</strong>
              <small>{{
                [item.cargoCode, item.packageType].filter(Boolean).join(' · ') || '普通货物'
              }}</small>
            </div>
            <p>{{ formatCargoItem(item) }}</p>
          </article>
        </div>
        <ArtEmptyState
          v-else
          title="暂无货物明细"
          description="已展示运单汇总数据，关联订单尚未录入分项货物。"
          size="compact"
          :visual-size="64"
        />
      </section>

      <section class="waybill-info-panel__section art-card-xs">
        <ArtSectionTitle title="关联与审计" />
        <div v-if="waybill.order" class="waybill-info-panel__order">
          <div>
            <small>订单号</small>
            <ElLink type="primary" underline="never" @click="emit('open-order')">
              {{ waybill.order.orderNo }}
            </ElLink>
          </div>
          <div
            ><small>货号</small><strong>{{ waybill.order.cargoNo || '-' }}</strong></div
          >
          <div>
            <small>订单状态</small>
            <ArtDictDisplay dict-code="tmsOrderStatus" :value="waybill.order.orderStatus" />
          </div>
          <div>
            <small>配送方式</small>
            <ArtDictDisplay
              dict-code="tmsOrderDeliveryMethod"
              :value="waybill.order.deliveryMethod"
            />
          </div>
          <div>
            <small>运输方式</small>
            <ArtDictDisplay
              dict-code="tmsOrderTransportMode"
              :value="waybill.order.transportMode"
            />
          </div>
          <div
            ><small>调度人</small><strong>{{ waybill.order.dispatchBy || '-' }}</strong></div
          >
          <div
            ><small>调度时间</small><strong>{{ date(waybill.order.dispatchedAt) }}</strong></div
          >
          <div
            ><small>开单时间</small><strong>{{ date(waybill.order.createTime) }}</strong></div
          >
        </div>
        <ArtEmptyState
          v-else
          title="未关联订单"
          description="该运单没有可访问的关联订单。"
          size="compact"
          :visual-size="64"
        />
        <div class="waybill-info-panel__remarks">
          <div>
            <span>运单备注</span>
            <p>{{ waybill.remark || '无' }}</p>
          </div>
          <div>
            <span>订单备注</span>
            <p>{{ waybill.order?.orderRemark || '无' }}</p>
          </div>
          <div>
            <span>调度备注</span>
            <p>{{ waybill.order?.dispatchRemark || '无' }}</p>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'TmsWaybillInfoPanel' })

  type CargoItem = Api.Tms.Order.CargoItem
  const props = defineProps<{ waybill: Api.Tms.Waybill.WaybillDetailRecord }>()
  const emit = defineEmits<{ 'open-order': [] }>()

  const executionFacts = computed(() => [
    { label: '运单状态', value: statusLabel(props.waybill.status) },
    { label: '计划装货', value: date(props.waybill.plannedLoadTime) },
    { label: '实际装货', value: date(props.waybill.loadedAt) },
    { label: '发车时间', value: date(props.waybill.departedAt) },
    { label: '到达时间', value: date(props.waybill.arrivedAt) },
    { label: '实际卸货', value: date(props.waybill.unloadedAt) },
    { label: '完成时间', value: date(props.waybill.completedAt) },
    {
      label: '剩余里程',
      value:
        props.waybill.remainingDistanceKm == null ? '-' : `${props.waybill.remainingDistanceKm} km`
    }
  ])

  const feeItems = computed(() => [
    { label: '运输费', value: props.waybill.order?.transportFee },
    { label: '送货费', value: props.waybill.order?.deliveryFee },
    { label: '卸货费', value: props.waybill.order?.unloadingFee },
    { label: '中转费', value: props.waybill.order?.transferFee },
    {
      label: '保价/保险',
      value: sum(props.waybill.order?.declaredValue, props.waybill.order?.insuranceFee)
    },
    {
      label: '其他费用',
      value: sum(
        props.waybill.order?.collectPaymentFee,
        props.waybill.order?.packageFee,
        props.waybill.order?.otherFee,
        props.waybill.order?.handlingFee
      )
    }
  ])

  const cargoItems = computed(() => props.waybill.order?.cargoItems ?? [])
  const cargoQuantity = computed(
    () => props.waybill.cargoQuantity ?? props.waybill.order?.cargoQuantityTotal ?? '-'
  )
  const cargoWeight = computed(() =>
    formatUnit(props.waybill.cargoWeightTon ?? props.waybill.order?.cargoWeightTotal, 't')
  )
  const cargoVolume = computed(() =>
    formatUnit(props.waybill.cargoVolumeM3 ?? props.waybill.order?.cargoVolumeTotal, 'm³')
  )
  const vehicleSummary = computed(
    () =>
      [props.waybill.vehicle?.vehicleType, props.waybill.vehicle?.brandModel]
        .filter(Boolean)
        .join(' · ') || '-'
  )
  const carrierContact = computed(
    () =>
      [props.waybill.carrier?.contactName, props.waybill.carrier?.contactPhone]
        .filter(Boolean)
        .join(' · ') || '-'
  )
  const shipperPhone = computed(
    () => props.waybill.shipperPhone || props.waybill.order?.shippingContactPhone || '-'
  )
  const receiverPhone = computed(
    () => props.waybill.receiverPhone || props.waybill.order?.receivingContactPhone || '-'
  )
  const shipperAddress = computed(
    () => props.waybill.shipperAddress || props.waybill.order?.shippingAddressDetail || '-'
  )
  const receiverAddress = computed(
    () => props.waybill.receiverAddress || props.waybill.order?.receivingAddressDetail || '-'
  )

  function formatCargoItem(item: CargoItem): string {
    return [
      item.quantity != null ? `${item.quantity}${item.unit || '件'}` : null,
      item.weightKg != null ? `${item.weightKg} kg` : null,
      item.volumeM3 != null ? `${item.volumeM3} m³` : null
    ]
      .filter(Boolean)
      .join(' · ')
  }

  function statusLabel(status: string): string {
    const labels: Record<string, string> = {
      pending: '待接单',
      accepted: '已接单',
      loading: '装货中',
      transporting: '运输中',
      unloading: '卸货中',
      signed: '已签收',
      completed: '已完成',
      cancelled: '已取消'
    }
    return labels[status] || status || '-'
  }

  function sum(...values: Array<number | null | undefined>): number {
    return values.reduce<number>((total, value) => total + Number(value || 0), 0)
  }

  function money(value?: number | null): string {
    return value == null ? '-' : formatCurrencyValue(value)
  }

  function formatUnit(value: number | null | undefined, unit: string): string {
    return value == null ? '-' : `${value} ${unit}`
  }

  function date(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '-'
  }
</script>

<style scoped lang="scss">
  .waybill-info-panel {
    display: grid;
    gap: var(--art-space-3);

    &__section {
      min-width: 0;
      padding: var(--art-section-padding);
    }

    &__top-grid,
    &__bottom-grid {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(320px, 1fr);
      gap: var(--art-space-3);
      align-items: start;
    }

    &__route {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(90px, 0.45fr) minmax(0, 1fr);
      gap: var(--art-space-3);
      align-items: center;
      padding: var(--art-space-4);
      background: linear-gradient(
        110deg,
        var(--el-color-primary-light-9),
        var(--el-fill-color-lighter)
      );
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-base);
    }

    &__route-endpoint {
      display: flex;
      gap: var(--art-space-3);
      min-width: 0;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 38px;
        height: 38px;
        color: white;
        background: var(--el-color-primary);
        border-radius: 50%;

        &.is-destination {
          background: var(--el-color-success);
        }
      }

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      small,
      p {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      strong {
        font-size: 16px;
      }

      p {
        margin: 0;
        font-size: 12px;
      }
    }

    &__route-line,
    &__contact-arrow {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;
      color: var(--el-color-primary);

      i {
        flex: 1;
        height: 1px;
        background: var(--el-color-primary-light-5);
      }
    }

    &__facts {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0;
      margin: var(--art-space-4) 0 0;
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > div {
        display: grid;
        gap: 5px;
        min-width: 0;
        padding: var(--art-space-3);
        border-right: 1px solid var(--el-border-color-lighter);
        border-bottom: 1px solid var(--el-border-color-lighter);

        &:nth-child(4n) {
          border-right: 0;
        }

        &:nth-last-child(-n + 4) {
          border-bottom: 0;
        }
      }
    }

    &__facts dt,
    &__fee-list dt,
    &__order small,
    &__cargo-summary small,
    &__amount small {
      color: var(--el-text-color-secondary);
    }

    &__facts dd,
    &__fee-list dd {
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__amount {
      display: flex;
      gap: var(--art-space-3);
      align-items: flex-start;
      justify-content: space-between;
      padding: var(--art-space-4);
      background: linear-gradient(
        120deg,
        var(--el-color-primary-light-9),
        color-mix(in srgb, var(--el-color-primary) 4%, var(--el-bg-color))
      );
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-base);

      > div {
        display: grid;
        gap: 4px;
      }

      strong {
        font-size: 24px;
        color: var(--el-color-primary);
      }
    }

    &__fee-list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--art-space-3) var(--art-space-4);
      margin: var(--art-space-4) 0;

      > div {
        display: flex;
        gap: var(--art-space-2);
        align-items: center;
        justify-content: space-between;
        min-width: 0;
        padding-bottom: var(--art-space-2);
        border-bottom: 1px dashed var(--el-border-color-lighter);
      }

      dd {
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }
    }

    &__payment-summary {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding-top: var(--art-space-3);
      color: var(--el-text-color-secondary);
      border-top: 1px dashed var(--el-border-color);

      strong {
        color: var(--el-text-color-primary);
      }
    }

    &__resource-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: var(--art-space-3);

      article {
        display: flex;
        gap: var(--art-space-3);
        align-items: center;
        min-width: 0;
        padding: var(--art-space-4);
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      article > div {
        display: grid;
        flex: 1;
        gap: 3px;
        min-width: 0;
      }

      small,
      p {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      p {
        margin: 0;
      }
    }

    &__resource-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 42px;
      height: 42px;
      font-size: 20px;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, var(--el-bg-color));
      border-radius: var(--el-border-radius-base);
    }

    &__contact-grid {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 72px minmax(0, 1fr);
      gap: var(--art-space-3);
      align-items: center;

      article {
        min-width: 0;
        padding: var(--art-space-4);
        background: linear-gradient(145deg, var(--el-fill-color-lighter), var(--el-bg-color));
        border: 1px solid var(--el-border-color-lighter);
        border-top: 2px solid var(--el-color-primary-light-5);
        border-radius: var(--el-border-radius-base);

        &:last-child {
          border-top-color: var(--el-color-success-light-5);
        }
      }

      article > p {
        display: flex;
        gap: var(--art-space-2);
        align-items: flex-start;
        margin: var(--art-space-3) 0 0;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }

      article > p .art-svg-icon {
        flex: none;
        margin-top: 3px;
        color: var(--el-text-color-secondary);
      }
    }

    &__contact-heading {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;

      > span {
        display: grid;
        place-items: center;
        width: 36px;
        height: 36px;
        color: white;
        background: var(--el-color-primary);
        border-radius: 50%;

        &.is-receiver {
          background: var(--el-color-success);
        }
      }

      > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }

    &__cargo-summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: var(--art-space-2);
      margin-bottom: var(--art-space-4);

      > div {
        display: flex;
        gap: var(--art-space-3);
        align-items: center;
        min-width: 0;
        padding: var(--art-space-3);
        background: var(--el-fill-color-lighter);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      > div > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 34px;
        height: 34px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      > div > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      strong {
        font-size: 16px;
        font-variant-numeric: tabular-nums;
      }
    }

    &__cargo-list {
      display: grid;
      gap: var(--art-space-2);

      article {
        display: grid;
        grid-template-columns: 30px minmax(0, 1fr) auto;
        gap: var(--art-space-3);
        align-items: center;
        padding: var(--art-space-3);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
        transition:
          border-color 0.2s ease,
          background-color 0.2s ease;

        &:hover {
          background: var(--el-fill-color-lighter);
          border-color: var(--el-color-primary-light-7);
        }
      }

      article > span {
        display: grid;
        place-items: center;
        width: 28px;
        height: 28px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      article > div {
        display: grid;
        gap: 2px;
        min-width: 0;
      }

      small,
      p {
        margin: 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__order {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--art-space-4);

      > div {
        display: grid;
        gap: 5px;
        min-width: 0;
        padding: var(--art-space-3);
        background: var(--el-fill-color-lighter);
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
      }

      strong,
      .el-link {
        justify-self: start;
        max-width: 100%;
        overflow-wrap: anywhere;
      }
    }

    &__remarks {
      display: grid;
      gap: var(--art-space-3);
      padding-top: var(--art-space-4);
      margin-top: var(--art-space-4);
      border-top: 1px solid var(--el-border-color-lighter);

      > div {
        display: grid;
        grid-template-columns: 76px minmax(0, 1fr);
        gap: var(--art-space-3);
        align-items: start;
        padding: var(--art-space-2) 0;
      }

      span {
        color: var(--el-text-color-secondary);
      }

      p {
        margin: 0;
        overflow-wrap: anywhere;
      }
    }
  }

  @media (width <= 1100px) {
    .waybill-info-panel {
      &__top-grid,
      &__bottom-grid {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 768px) {
    .waybill-info-panel {
      &__route,
      &__contact-grid {
        grid-template-columns: 1fr;
      }

      &__route-line,
      &__contact-arrow {
        display: none;
      }

      &__facts,
      &__resource-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__facts > div {
        &:nth-child(2n) {
          border-right: 0;
        }

        &:nth-child(odd) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        &:nth-last-child(-n + 4) {
          border-bottom: 1px solid var(--el-border-color-lighter);
        }

        &:nth-last-child(-n + 2) {
          border-bottom: 0;
        }
      }
    }
  }

  @media (width <= 520px) {
    .waybill-info-panel {
      &__facts,
      &__resource-grid,
      &__fee-list,
      &__order,
      &__cargo-summary {
        grid-template-columns: 1fr;
      }

      &__facts > div {
        border-right: 0 !important;
        border-bottom: 1px solid var(--el-border-color-lighter) !important;

        &:last-child {
          border-bottom: 0 !important;
        }
      }

      &__cargo-list article {
        grid-template-columns: 30px minmax(0, 1fr);

        > p {
          grid-column: 2;
        }
      }
    }
  }
</style>
