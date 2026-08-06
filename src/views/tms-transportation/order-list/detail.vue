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
        <span>总数量：{{ formatNumber(detail.data?.cargoQuantityTotal, 0) }}</span>
        <span>总重量：{{ formatNumber(detail.data?.cargoWeightTotal) }}kg</span>
        <span>总体积：{{ formatNumber(detail.data?.cargoVolumeTotal, 3) }}方</span>
      </div>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="费用信息" />
      <ArtDescriptions :data="descriptionData" :items="feeItems" :columns="4" />
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="付款方式" />
      <ArtDescriptions :data="descriptionData" :items="paymentItems" :columns="4" />
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="其他信息" />
      <ArtDescriptions :data="descriptionData" :items="otherItems" :columns="4" />
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
      pending_pickup: detail.data?.driverWaybillLoadedAt ?? detail.data?.driverWaybillDepartedAt,
      transporting: detail.data?.driverWaybillDepartedAt ?? detail.data?.driverWaybillLoadedAt,
      signed: detail.data?.signedAt ?? getCurrentStatusFallbackTime('signed'),
      completed: detail.data?.signedAt,
      cancelled: detail.data?.updateTime
    }

    return formatStepTime(statusTimeMap[status] ?? getCurrentStatusFallbackTime(status))
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
      gap: 8px;
      margin-top: var(--art-space-3);
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
      gap: 28px;
      justify-content: flex-end;
      padding-top: 14px;
      color: var(--art-text-gray-700);
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
      &__contact-card {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
