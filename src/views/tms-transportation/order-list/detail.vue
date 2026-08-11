<template>
  <ArtPageShell
    class="order-detail"
    :loading="detail.loading"
    loading-mode="skeleton"
    :error="detail.error"
    :empty="!detail.data"
    empty-text="暂无订单详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.orderNo || '订单详情'"
      :subtitle="
        [detail.data?.originStation, detail.data?.destinationStation].filter(Boolean).join(' → ') ||
        '--'
      "
      show-back
      @back="goBack"
    />

    <section class="order-detail__section order-detail__steps-card art-card-xs">
      <OrderStatusSteps :steps="detail.statusSteps" :active-index="detail.activeStep" />
      <div
        v-if="deliveryAudit.visible"
        class="order-detail__delivery-audit"
        :class="{ 'is-warning': deliveryAudit.missingSignature }"
      >
        <span class="order-detail__delivery-audit-icon">
          <ArtSvgIcon
            :icon="deliveryAudit.missingSignature ? 'ri:alert-line' : 'ri:verified-badge-line'"
          />
        </span>
        <div class="order-detail__delivery-audit-copy">
          <strong>{{ deliveryAudit.title }}</strong>
          <span>{{ deliveryAudit.description }}</span>
        </div>
        <div v-if="!deliveryAudit.missingSignature" class="order-detail__delivery-audit-meta">
          <span>{{ deliveryAudit.operator }}</span>
          <span>{{ deliveryAudit.proofCount }} 张回单</span>
          <span>{{ deliveryAudit.time }}</span>
        </div>
      </div>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="基础信息" />
      <ArtDescriptions :data="descriptionData" :items="basicItems" :columns="4" />

      <div class="order-detail__contact-card">
        <div class="order-detail__contact-panel">
          <div class="order-detail__contact-heading">
            <span class="order-detail__contact-mark order-detail__contact-mark--send">寄</span>
            <strong>发货人信息</strong>
          </div>
          <ArtDescriptions
            :data="descriptionData"
            :items="shippingItems"
            :columns="1"
            :border="false"
          />
        </div>
        <div class="order-detail__contact-panel">
          <div class="order-detail__contact-heading">
            <span class="order-detail__contact-mark order-detail__contact-mark--receive">收</span>
            <strong>收货人信息</strong>
          </div>
          <ArtDescriptions
            :data="descriptionData"
            :items="receivingItems"
            :columns="1"
            :border="false"
          />
        </div>
      </div>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="货物信息" />
      <ArtTable
        :data="detail.cargoItems"
        :columns="detail.cargoColumns"
        :pagination="false"
        row-key="cargoName"
      />
      <div class="order-detail__summary">
        <div>
          <span>总数量</span>
          <strong>{{ formatNumber(detail.data?.cargoQuantityTotal, 0) }}</strong>
        </div>
        <div>
          <span>总重量</span>
          <strong>{{ formatNumber(detail.data?.cargoWeightTotal) }} kg</strong>
        </div>
        <div>
          <span>总体积</span>
          <strong>{{ formatNumber(detail.data?.cargoVolumeTotal, 3) }} 方</strong>
        </div>
      </div>
    </section>

    <div class="order-detail__finance-grid">
      <section class="order-detail__section art-card-xs">
        <ArtSectionTitle title="费用信息" />
        <ArtDescriptions :data="descriptionData" :items="feeItems" :columns="2" />
      </section>

      <section class="order-detail__section art-card-xs">
        <ArtSectionTitle title="付款方式" />
        <ArtDescriptions :data="descriptionData" :items="paymentItems" :columns="2" />
      </section>
    </div>

    <div class="order-detail__support-grid">
      <section class="order-detail__section art-card-xs">
        <ArtSectionTitle title="其他信息" />
        <ArtDescriptions :data="descriptionData" :items="otherItems" :columns="2" />
      </section>

      <section class="order-detail__section art-card-xs">
        <ArtSectionTitle title="物流信息" />
        <ArtEmptyState
          title="暂无物流跟踪信息"
          description="产生运输节点后，轨迹会显示在这里。"
          :visual-size="76"
          size="compact"
        />
      </section>
    </div>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { toNumber } from 'lodash-es'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { fetchOrderDetail } from '@/api/tms'
  import OrderStatusSteps from './modules/order-status-steps.vue'

  defineOptions({ name: 'TmsOrderDetail' })

  type OrderRecord = Api.Tms.Order.OrderRecord
  type CargoItem = Api.Tms.Order.CargoItem

  interface StatusStep {
    label: string
    value: string
    timeText?: string
  }

  type OrderStatusValue =
    | 'created'
    | 'pending_load'
    | 'pending_order'
    | 'pending_pickup'
    | 'transporting'
    | 'signed'
    | 'completed'
    | 'cancelled'

  const orderStatusStepValues: OrderStatusValue[] = [
    'created',
    'pending_load',
    'pending_order',
    'pending_pickup',
    'transporting',
    'signed',
    'completed'
  ]
  const orderStatusStepOrder: OrderStatusValue[] = [...orderStatusStepValues, 'cancelled']

  interface DetailGroup {
    loading: boolean
    error: Error | null
    data?: OrderRecord
    statusSteps: ComputedRef<StatusStep[]>
    activeStep: ComputedRef<number>
    cargoItems: ComputedRef<CargoItem[]>
    cargoColumns: ComputedRef<ColumnOption<CargoItem>[]>
  }

  const route = useRoute()
  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const normalizedOrderStatus = computed(() => normalizeOrderStatus(detail.data?.orderStatus))
  const detail: UnwrapNestedRefs<DetailGroup> = reactive<DetailGroup>({
    loading: false,
    error: null,
    data: undefined,
    statusSteps: computed(() => {
      const values: OrderStatusValue[] =
        normalizedOrderStatus.value === 'cancelled'
          ? [...orderStatusStepValues, 'cancelled']
          : orderStatusStepValues

      return values.map((value) => ({
        value,
        label: getOrderStatusLabel(value),
        timeText: getOrderStatusTimeText(value)
      }))
    }),
    activeStep: computed(() => {
      const index = detail.statusSteps.findIndex(
        (item) => item.value === normalizedOrderStatus.value
      )
      return index < 0 ? 0 : index
    }),
    cargoItems: computed(() => detail.data?.cargoItems ?? []),
    cargoColumns: computed<ColumnOption<CargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'cargoName', label: '货物名称', minWidth: 180 },
      {
        prop: 'packageType',
        label: '包装',
        width: 130,
        dict: { code: 'tmsCargoUnit', display: 'text' }
      },
      { prop: 'quantity', label: '数量（箱/袋）', width: 140 },
      { prop: 'weightKg', label: '重量(kg)', width: 140 },
      { prop: 'volumeM3', label: '体积(方)', width: 140 }
    ])
  })

  const descriptionData = computed<Partial<OrderRecord>>(() => detail.data ?? {})
  const deliveryAudit = computed(() => {
    const data = detail.data
    const status = normalizedOrderStatus.value
    const signatureTime = data?.signedAt ?? data?.driverWaybillSignedAt
    const proofCount = data?.driverWaybillSignatureProofCount ?? data?.receiptImageUrls?.length ?? 0
    const reachedDelivery = status === 'signed' || status === 'completed'
    const missingSignature = status === 'completed' && !signatureTime

    if (!reachedDelivery) {
      return {
        visible: false,
        missingSignature: false,
        title: '',
        description: '',
        operator: '',
        proofCount,
        time: ''
      }
    }

    if (missingSignature) {
      return {
        visible: true,
        missingSignature: true,
        title: '签收记录缺失',
        description: proofCount
          ? `该订单已完成并发现 ${proofCount} 张回单，但没有独立的确认签收记录，请核对交付凭证。`
          : '该订单已完成，但没有签收时间、操作人或回单凭证，请尽快核对交付过程。',
        operator: '',
        proofCount,
        time: ''
      }
    }

    return {
      visible: true,
      missingSignature: false,
      title: '签收凭证已归档',
      description:
        status === 'completed' ? '交付与完成节点记录完整' : '已完成签收，等待最终确认完成运单',
      operator: data?.driverWaybillSignedBy || data?.dispatchDriverName || '系统记录',
      proofCount,
      time: formatWithDayjs(signatureTime, 'YYYY-MM-DD HH:mm') || '-'
    }
  })
  const basicItems: ArtDescriptionItem<Partial<OrderRecord>>[] = [
    { key: 'orderNo', label: '订单号', field: 'orderNo', copyable: true },
    { key: 'cargoNo', label: '货号', field: 'cargoNo', copyable: true },
    { key: 'createBy', label: '开单人', field: 'createBy' },
    { key: 'createTime', label: '开单时间', field: 'createTime', format: 'datetime' },
    { key: 'originStation', label: '发货站', field: 'originStation' },
    { key: 'destinationStation', label: '到货站', field: 'destinationStation' },
    { key: 'transferStation', label: '中转站', field: 'transferStation' },
    {
      key: 'deliveryMethod',
      label: '配送方式',
      field: 'deliveryMethod',
      dictCode: 'tmsOrderDeliveryMethod'
    },
    {
      key: 'orderStatus',
      label: '当前状态',
      value: (data: Partial<OrderRecord>) => normalizeOrderStatus(data.orderStatus),
      dictCode: 'tmsOrderStatus'
    },
    {
      key: 'transportMode',
      label: '运输方式',
      field: 'transportMode',
      dictCode: 'tmsOrderTransportMode'
    }
  ]
  const shippingItems: ArtDescriptionItem<Partial<OrderRecord>>[] = [
    { key: 'shippingContactName', label: '姓名', field: 'shippingContactName' },
    { key: 'shippingContactPhone', label: '手机号', field: 'shippingContactPhone', copyable: true },
    { key: 'shippingAddressDetail', label: '发货地址', field: 'shippingAddressDetail' }
  ]
  const receivingItems: ArtDescriptionItem<Partial<OrderRecord>>[] = [
    { key: 'receivingContactName', label: '姓名', field: 'receivingContactName' },
    {
      key: 'receivingContactPhone',
      label: '手机号',
      field: 'receivingContactPhone',
      copyable: true
    },
    { key: 'receivingAddressDetail', label: '收货地址', field: 'receivingAddressDetail' }
  ]
  const feeItems = createMoneyDescriptionItems([
    ['transportFee', '基础运费'],
    ['deliveryFee', '配送费'],
    ['unloadingFee', '卸货费'],
    ['collectPaymentFee', '回款费'],
    ['transferFee', '中转费'],
    ['declaredValue', '声明价值'],
    ['insuranceFee', '保费'],
    ['packageFee', '包装费'],
    ['otherFee', '其他费用'],
    ['totalFee', '运费合计', true]
  ])
  const paymentItems: ArtDescriptionItem<Partial<OrderRecord>>[] = [
    {
      key: 'paymentMethod',
      label: '付款方式',
      field: 'paymentMethod',
      dictCode: 'tmsOrderPaymentMethod'
    },
    ...createMoneyDescriptionItems([
      ['cashAmount', '现付'],
      ['collectAmount', '到付'],
      ['monthlyAmount', '月结'],
      ['codAmount', '代收货款'],
      ['handlingFee', '手续费'],
      ['paymentTotal', '付款合计', true]
    ])
  ]
  const otherItems: ArtDescriptionItem<Partial<OrderRecord>>[] = [
    { key: 'orderRemark', label: '订单备注', field: 'orderRemark', span: 2 },
    {
      key: 'imageUrls',
      label: '图片',
      span: 2,
      value: (data: Partial<OrderRecord>) =>
        data.imageUrls?.length ? `${data.imageUrls.length} 张` : undefined
    }
  ]

  onMounted(() => {
    void loadDetail()
  })

  async function loadDetail(): Promise<void> {
    const id = String(route.params.id || '')
    if (!id) {
      detail.error = new Error('缺少订单标识')
      return
    }

    detail.loading = true
    detail.error = null
    try {
      const { data } = await fetchOrderDetail(id)
      detail.data = data ?? undefined
    } catch (error) {
      detail.error = error instanceof Error ? error : new Error('订单详情加载失败')
    } finally {
      detail.loading = false
    }
  }

  function goBack(): void {
    void router.back()
  }

  function normalizeOrderStatus(status?: string): OrderStatusValue | undefined {
    if (!status) return undefined
    if (status === 'loaded') return 'pending_order'
    return status as OrderStatusValue
  }

  function getOrderStatusLabel(status: OrderStatusValue): string {
    if (status === 'created') return '开单'

    const normalizedStatus = normalizeOrderStatus(status)
    const dictItem = getDictMap.value.tmsOrderStatus?.find(
      (item) => item.value === normalizedStatus
    )
    return dictItem?.label || normalizedStatus || '-'
  }

  function getOrderStatusTimeText(status: OrderStatusValue): string {
    if (!isOrderStatusReached(status)) return '-'

    const statusTimeMap: Partial<Record<OrderStatusValue, string | null | undefined>> = {
      created: detail.data?.createTime,
      pending_load: detail.data?.createTime,
      pending_order: detail.data?.dispatchedAt,
      pending_pickup: detail.data?.driverWaybillAcceptedAt,
      transporting: detail.data?.driverWaybillDepartedAt ?? detail.data?.driverWaybillLoadedAt,
      signed: detail.data?.signedAt ?? detail.data?.driverWaybillSignedAt,
      completed: detail.data?.driverWaybillCompletedAt,
      cancelled: detail.data?.updateTime
    }

    const value = statusTimeMap[status] ?? getCurrentStatusFallbackTime(status)
    if (status === 'signed' && normalizedOrderStatus.value === 'completed' && !value) {
      return '记录缺失'
    }
    return formatStepTime(value)
  }

  function isOrderStatusReached(status: OrderStatusValue): boolean {
    const currentStatus = normalizedOrderStatus.value
    if (!currentStatus) return false

    const statusIndex = orderStatusStepOrder.indexOf(status)
    const currentIndex = orderStatusStepOrder.indexOf(currentStatus)
    return statusIndex >= 0 && currentIndex >= 0 && statusIndex <= currentIndex
  }

  function getCurrentStatusFallbackTime(status: OrderStatusValue): string | null | undefined {
    return normalizedOrderStatus.value === status ? detail.data?.updateTime : undefined
  }

  function formatStepTime(value?: string | null): string {
    const date = formatWithDayjs(value, 'YYYY-MM-DD')
    const time = formatWithDayjs(value, 'HH:mm')
    return date && time ? `${date}\n${time}` : '-'
  }

  function formatNumber(value?: number | string | null, precision = 2): string {
    const parsed = toNumber(value ?? 0)
    if (!Number.isFinite(parsed)) return '0'

    const formatted = parsed
      .toFixed(precision)
      .replace(/(\.\d*?)0+$/, '$1')
      .replace(/\.$/, '')
    return formatted || '0'
  }

  function formatCurrency(value?: number | string | null): string {
    const parsed = toNumber(value ?? 0)
    return `¥${Number.isFinite(parsed) ? parsed.toFixed(2) : '0.00'}`
  }

  function createMoneyDescriptionItems(
    items: Array<[key: string, label: string, strong?: boolean]>
  ): ArtDescriptionItem<Partial<OrderRecord>>[] {
    return items.map(([key, label, strong]) => ({
      key,
      label,
      field: key,
      formatter: (value) => formatCurrency(value as number | string | null | undefined),
      className: strong ? 'order-detail__strong' : undefined
    }))
  }
</script>

<style scoped lang="scss">
  .order-detail {
    min-height: 100%;
    padding: 12px 16px 18px;
    background: var(--art-main-bg-color);

    &__section {
      padding: 18px 20px;
      margin-bottom: 12px;
    }

    &__steps-card {
      display: grid;
      gap: 16px;
      margin-top: var(--art-space-3);
    }

    &__delivery-audit {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      padding: 14px 16px;
      margin-inline: 12px;
      color: var(--el-color-success-dark-2);
      background: var(--el-color-success-light-9);
      border: 1px solid var(--el-color-success-light-7);
      border-radius: var(--el-border-radius-base);

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-color: var(--el-color-warning-light-7);
      }
    }

    &__delivery-audit-icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 34px;
      height: 34px;
      font-size: 19px;
      background: color-mix(in srgb, currentcolor 10%, transparent);
      border-radius: 10px;
    }

    &__delivery-audit-copy {
      display: grid;
      gap: 3px;
      min-width: 0;

      strong {
        color: currentcolor;
      }

      span {
        font-size: 12px;
        line-height: 1.5;
        color: var(--el-text-color-secondary);
      }
    }

    &__delivery-audit-meta {
      display: flex;
      gap: 8px;
      align-items: center;
      font-size: 12px;
      color: var(--el-text-color-regular);

      span {
        padding: 5px 8px;
        white-space: nowrap;
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: 999px;
      }
    }

    &__finance-grid,
    &__support-grid {
      display: grid;
      gap: 12px;
      margin-bottom: 12px;

      > .order-detail__section {
        min-width: 0;
        margin-bottom: 0;
      }
    }

    &__finance-grid {
      grid-template-columns: minmax(0, 1.15fr) minmax(0, 0.85fr);
    }

    &__support-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    &__contact-card {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 18px;
      padding: 18px;
      margin-top: 20px;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__contact-panel {
      display: grid;
      gap: 12px;
      min-width: 0;
      color: var(--art-text-gray-700);
    }

    &__contact-heading {
      display: flex;
      gap: 8px;
      align-items: center;
      color: var(--art-text-gray-800);
    }

    &__contact-mark {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 28px;
      height: 28px;
      color: #fff;
      border-radius: var(--el-border-radius-base);

      &--send {
        background: #37c2ff;
      }

      &--receive {
        background: #f4c430;
      }
    }

    &__summary {
      display: flex;
      gap: 10px;
      justify-content: flex-end;
      padding-top: 14px;

      > div {
        display: grid;
        gap: 2px;
        min-width: 128px;
        padding: 10px 12px;
        text-align: right;
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);

        span {
          font-size: 10px;
          color: var(--el-text-color-secondary);
        }

        strong {
          font-size: 13px;
          font-variant-numeric: tabular-nums;
          color: var(--el-text-color-primary);
        }
      }
    }

    :deep(.order-detail__strong) {
      font-weight: 600;
      color: var(--el-color-danger);
    }

    :deep(.art-descriptions) {
      margin-top: 16px;

      .el-descriptions__body {
        background: inherit;
      }
    }
  }

  @media (width <= 992px) {
    .order-detail {
      &__delivery-audit {
        grid-template-columns: auto minmax(0, 1fr);
      }

      &__delivery-audit-meta {
        flex-wrap: wrap;
        grid-column: 2;
      }

      &__finance-grid,
      &__support-grid,
      &__contact-card {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 640px) {
    .order-detail {
      padding-inline: 10px;

      &__summary {
        display: grid;
        grid-template-columns: 1fr;

        > div {
          min-width: 0;
          text-align: left;
        }
      }

      &__delivery-audit {
        margin-inline: 0;
      }
    }
  }
</style>
