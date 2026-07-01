<template>
  <div v-loading="detail.loading" class="order-detail">
    <section class="order-detail__section order-detail__steps-card art-card-xs">
      <ElPageHeader :icon="ArrowLeft" @back="goBack" />
      <OrderStatusSteps
        :steps="detail.statusSteps"
        :active-index="detail.activeStep"
        :time-text="formatStepTime(detail.data?.createTime)"
      />
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="基础信息" />
      <ElDescriptions :column="4" border>
        <ElDescriptionsItem label="订单号">{{
          formatValue(detail.data?.orderNo)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="货号">{{
          formatValue(detail.data?.cargoNo)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="开单人">{{
          formatValue(detail.data?.createBy)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="开单时间">
          {{ formatDate(detail.data?.createTime) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="发货站">
          {{ formatValue(detail.data?.originStation) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="到货站">
          {{ formatValue(detail.data?.destinationStation) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="中转站">
          {{ formatValue(detail.data?.transferStation) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="配送方式">
          <ArtDictDisplay dict-code="tmsOrderDeliveryMethod" :value="detail.data?.deliveryMethod" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="当前状态">
          <ArtDictDisplay
            dict-code="tmsOrderStatus"
            :value="detail.data?.orderStatus"
            display="auto"
          />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="运输方式">
          <ArtDictDisplay dict-code="tmsOrderTransportMode" :value="detail.data?.transportMode" />
        </ElDescriptionsItem>
      </ElDescriptions>

      <div class="order-detail__contact-card">
        <div class="order-detail__contact-panel">
          <div class="order-detail__contact-heading">
            <span class="order-detail__contact-mark order-detail__contact-mark--send">寄</span>
            <strong>发货人信息</strong>
          </div>
          <ElDescriptions :column="1">
            <ElDescriptionsItem label="姓名">
              {{ formatValue(detail.data?.shippingContactName) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="手机号">
              {{ formatValue(detail.data?.shippingContactPhone) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="发货地址">
              {{ formatValue(detail.data?.shippingAddressDetail) }}
            </ElDescriptionsItem>
          </ElDescriptions>
        </div>
        <div class="order-detail__contact-panel">
          <div class="order-detail__contact-heading">
            <span class="order-detail__contact-mark order-detail__contact-mark--receive">收</span>
            <strong>收货人信息</strong>
          </div>
          <ElDescriptions :column="1">
            <ElDescriptionsItem label="姓名">
              {{ formatValue(detail.data?.receivingContactName) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="手机号">
              {{ formatValue(detail.data?.receivingContactPhone) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="收货地址">
              {{ formatValue(detail.data?.receivingAddressDetail) }}
            </ElDescriptionsItem>
          </ElDescriptions>
        </div>
      </div>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="货物信息" />
      <ArtTable
        :data="detail.cargoItems"
        :columns="detail.cargoColumns"
        :pagination="undefined"
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
      <ElDescriptions :column="4" border>
        <ElDescriptionsItem label="基础运费">
          {{ formatCurrency(detail.data?.transportFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="配送费">
          {{ formatCurrency(detail.data?.deliveryFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="卸货费">
          {{ formatCurrency(detail.data?.unloadingFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="回款费">
          {{ formatCurrency(detail.data?.collectPaymentFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="中转费">
          {{ formatCurrency(detail.data?.transferFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="声明价值">
          {{ formatCurrency(detail.data?.declaredValue) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="保费">
          {{ formatCurrency(detail.data?.insuranceFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="包装费">
          {{ formatCurrency(detail.data?.packageFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="其他费用">
          {{ formatCurrency(detail.data?.otherFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="运费合计">
          <span class="order-detail__strong">{{ formatCurrency(detail.data?.totalFee) }}</span>
        </ElDescriptionsItem>
      </ElDescriptions>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="付款方式" />
      <ElDescriptions :column="4" border>
        <ElDescriptionsItem label="付款方式">
          <ArtDictDisplay dict-code="tmsOrderPaymentMethod" :value="detail.data?.paymentMethod" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="现付">
          {{ formatCurrency(detail.data?.cashAmount) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="到付">
          {{ formatCurrency(detail.data?.collectAmount) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="月结">
          {{ formatCurrency(detail.data?.monthlyAmount) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="代收货款">
          {{ formatCurrency(detail.data?.codAmount) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="手续费">
          {{ formatCurrency(detail.data?.handlingFee) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="付款合计">
          <span class="order-detail__strong">{{ formatCurrency(detail.data?.paymentTotal) }}</span>
        </ElDescriptionsItem>
      </ElDescriptions>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="其他信息" />
      <ElDescriptions :column="4" border>
        <ElDescriptionsItem label="订单备注" :span="2">
          {{ formatValue(detail.data?.orderRemark) }}
        </ElDescriptionsItem>
        <ElDescriptionsItem label="图片" :span="2">
          {{ detail.data?.imageUrls?.length ? `${detail.data.imageUrls.length} 张` : '-' }}
        </ElDescriptionsItem>
      </ElDescriptions>
    </section>

    <section class="order-detail__section art-card-xs">
      <ArtSectionTitle title="物流信息" />
      <ElEmpty description="暂无物流跟踪信息" :image-size="80" />
    </section>
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ArrowLeft } from '@element-plus/icons-vue'
  import { toNumber, trim } from 'lodash-es'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
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
  }

  interface DetailGroup {
    loading: boolean
    data?: OrderRecord
    statusSteps: ComputedRef<StatusStep[]>
    activeStep: ComputedRef<number>
    cargoItems: ComputedRef<CargoItem[]>
    cargoColumns: ComputedRef<ColumnOption<CargoItem>[]>
  }

  const route = useRoute()
  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())

  const detail: UnwrapNestedRefs<DetailGroup> = reactive<DetailGroup>({
    loading: false,
    data: undefined,
    statusSteps: computed(() =>
      (getDictMap.value.tmsOrderStatus ?? []).map((item) => ({
        label: item.label || item.name || item.value,
        value: item.value
      }))
    ),
    activeStep: computed(() => {
      const index = detail.statusSteps.findIndex((item) => item.value === detail.data?.orderStatus)
      return index < 0 ? 0 : index
    }),
    cargoItems: computed(() => detail.data?.cargoItems ?? []),
    cargoColumns: computed<ColumnOption<CargoItem>[]>(() => [
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'cargoName', label: '货物名称', minWidth: 180 },
      { prop: 'packageType', label: '包装', width: 130 },
      { prop: 'quantity', label: '数量（箱/袋）', width: 140 },
      { prop: 'weightKg', label: '重量(kg)', width: 140 },
      { prop: 'volumeM3', label: '体积(方)', width: 140 }
    ])
  })

  onMounted(() => {
    void loadDetail()
  })

  async function loadDetail(): Promise<void> {
    const id = String(route.params.id || '')
    if (!id) return

    detail.loading = true
    try {
      const { data } = await fetchOrderDetail(id)
      detail.data = data ?? undefined
    } finally {
      detail.loading = false
    }
  }

  function goBack(): void {
    void router.back()
  }

  function formatValue(value?: string | number | null): string {
    const text = trim(String(value ?? ''))
    return text || '-'
  }

  function formatDate(value?: string | null, format = 'YYYY-MM-DD HH:mm:ss'): string {
    return formatWithDayjs(value, format) || '-'
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

    &__strong {
      font-weight: 600;
      color: var(--el-color-danger);
    }

    :deep(.el-descriptions) {
      margin-top: 16px;
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
