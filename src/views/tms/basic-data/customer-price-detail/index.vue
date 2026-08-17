<template>
  <ArtPageShell
    class="rate-card-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无客户价格详情"
    @retry="loadPage"
  >
    <ArtPageHeader
      :title="detail.data?.customer?.customerName || '客户价格详情'"
      :subtitle="routeSubtitle"
      show-back
      @back="goBack"
    />

    <section class="rate-card-detail__summary art-card-xs" aria-label="客户价格概览">
      <article
        ><span>客户编码</span
        ><strong>{{ detail.data?.customer?.customerCode || '--' }}</strong></article
      >
      <article
        ><span>运输类型</span><strong>{{ transportTypeLabel }}</strong></article
      >
      <article
        ><span>货物明细</span><strong>{{ cargoItems.length }} 项</strong></article
      >
      <article
        ><span>报价合计</span
        ><strong>¥ {{ formatRateMoney(detail.data?.totalFee) }}</strong></article
      >
    </section>

    <div class="rate-card-detail__content">
      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>客户与运输路线</ArtSectionTitle>
        <div class="rate-card-detail__route">
          <div class="rate-card-detail__route-point"
            ><span>始发地</span><strong>{{ detail.data?.originRegion || '--' }}</strong></div
          >
          <span class="rate-card-detail__route-arrow" aria-hidden="true">→</span>
          <div class="rate-card-detail__route-point"
            ><span>目的地</span><strong>{{ detail.data?.destinationRegion || '--' }}</strong></div
          >
        </div>
        <ArtDescriptions :data="descriptionData" :items="baseItems" :columns="4" />
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>收发货信息</ArtSectionTitle>
        <div class="rate-card-detail__split">
          <article class="rate-card-detail__panel">
            <div class="rate-card-detail__panel-heading"
              ><b>发</b
              ><div><strong>发货信息</strong><span>客户默认或已指定的发货地址</span></div></div
            >
            <ArtDescriptions :data="descriptionData" :items="shippingItems" :columns="1" />
          </article>
          <article class="rate-card-detail__panel">
            <div class="rate-card-detail__panel-heading"
              ><b class="is-green">收</b
              ><div><strong>收货信息</strong><span>本次报价对应的收货地址</span></div></div
            >
            <ArtDescriptions :data="descriptionData" :items="receivingItems" :columns="1" />
          </article>
        </div>
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>货物信息</ArtSectionTitle>
        <ArtTable
          :data="cargoItems"
          :columns="cargoColumns"
          :pagination="undefined"
          empty-text="暂无货物明细"
          empty-description="当前客户价格未维护货物明细。"
          empty-height="150px"
        />
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>车辆与结算费用</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="vehicleItems" :columns="4" />
        <div class="rate-card-detail__section-gap" aria-hidden="true"></div>
        <ArtDescriptions :data="descriptionData" :items="feeItems" :columns="4" />
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>付款方式</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="paymentItems" :columns="4" />
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>备注与审计信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="auditItems" :columns="4" />
      </section>
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCustomerPriceDetail } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import {
    formatRateAddress,
    formatRateDateTime,
    formatRateMoney,
    formatRateNumber
  } from '../modules/rate-card-detail'

  defineOptions({ name: 'TmsCustomerPriceDetail' })

  type CustomerPrice = Api.Tms.BasicData.CustomerPrice
  type CargoItem = Api.Tms.BasicData.CustomerPriceCargoItem

  const route = useRoute()
  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const page = reactive({ loading: false, error: null as Error | null })
  const detail = reactive<{ data?: CustomerPrice }>({ data: undefined })
  const descriptionData = computed<Partial<CustomerPrice>>(() => detail.data ?? {})
  const cargoItems = computed(() => detail.data?.cargoItems ?? [])
  const routeSubtitle = computed(() =>
    detail.data
      ? `${detail.data.originRegion || '--'} → ${detail.data.destinationRegion || '--'}`
      : '--'
  )
  const transportTypeLabel = computed(() =>
    getDictLabel('tmsCustomerPriceTransportType', detail.data?.transportType)
  )

  const baseItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = [
    { key: 'customerName', label: '客户名称', value: () => detail.data?.customer?.customerName },
    {
      key: 'customerCode',
      label: '客户编码',
      value: () => detail.data?.customer?.customerCode,
      copyable: true
    },
    {
      key: 'transportType',
      label: '运输类型',
      field: 'transportType',
      dictCode: 'tmsCustomerPriceTransportType',
      dictDisplay: 'text'
    },
    {
      key: 'cargoType',
      label: '货物类型',
      field: 'cargoType',
      dictCode: 'tmsCustomerPriceCargoType',
      dictDisplay: 'text'
    }
  ]
  const shippingItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = [
    { key: 'shippingContactName', label: '联系人', field: 'shippingContactName' },
    {
      key: 'shippingContactPhone',
      label: '联系电话',
      field: 'shippingContactPhone',
      copyable: true
    },
    {
      key: 'shippingAddress',
      label: '详细地址',
      value: (data: Partial<CustomerPrice>) =>
        formatRateAddress(data.originRegion, data.shippingAddressDetail)
    },
    {
      key: 'shippingCoordinate',
      label: '经纬度',
      value: (data: Partial<CustomerPrice>) =>
        formatCoordinate(data.shippingLongitude, data.shippingLatitude)
    }
  ]
  const receivingItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = [
    { key: 'receivingContactName', label: '联系人', field: 'receivingContactName' },
    {
      key: 'receivingContactPhone',
      label: '联系电话',
      field: 'receivingContactPhone',
      copyable: true
    },
    {
      key: 'receivingAddress',
      label: '详细地址',
      value: (data: Partial<CustomerPrice>) =>
        formatRateAddress(data.destinationRegion, data.receivingAddressDetail)
    },
    {
      key: 'receivingCoordinate',
      label: '经纬度',
      value: (data: Partial<CustomerPrice>) =>
        formatCoordinate(data.receivingLongitude, data.receivingLatitude)
    }
  ]
  const vehicleItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = [
    {
      key: 'vehicleType',
      label: '车型',
      field: 'vehicleType',
      dictCode: 'tmsCustomerPriceVehicleType',
      dictDisplay: 'text'
    },
    {
      key: 'vehicleLength',
      label: '车长',
      field: 'vehicleLength',
      dictCode: 'tmsCustomerPriceVehicleLength',
      dictDisplay: 'text'
    },
    {
      key: 'vehicleCount',
      label: '车辆数',
      field: 'vehicleCount',
      formatter: (value) => formatRateNumber(value as number | null, 0)
    },
    {
      key: 'billingMethod',
      label: '计费方式',
      field: 'billingMethod',
      dictCode: 'tmsCustomerPriceBillingMethod',
      dictDisplay: 'text'
    }
  ]
  const feeItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = createMoneyItems([
    ['transportFee', '运输费'],
    ['insuranceFee', '保险费'],
    ['packageFee', '包装费'],
    ['loadingFee', '装卸费'],
    ['transferFee', '中转费'],
    ['fuelFee', '燃油费'],
    ['serviceFee', '服务费'],
    ['otherFee', '其他费用'],
    ['totalFee', '费用合计']
  ])
  const paymentItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = createMoneyItems([
    ['cashAmount', '现付'],
    ['prepaidAmount', '预付'],
    ['collectAmount', '到付'],
    ['periodicAmount', '回付/月结'],
    ['paymentTotal', '付款合计']
  ])
  const auditItems: ArtDescriptionItem<Partial<CustomerPrice>>[] = [
    { key: 'remark', label: '备注', field: 'remark', span: 4 },
    { key: 'createBy', label: '创建人', field: 'createBy' },
    {
      key: 'createTime',
      label: '创建时间',
      field: 'createTime',
      formatter: (value) => formatRateDateTime(value as string | null)
    },
    { key: 'updateBy', label: '更新人', field: 'updateBy' },
    {
      key: 'updateTime',
      label: '更新时间',
      field: 'updateTime',
      formatter: (value) => formatRateDateTime(value as string | null)
    }
  ]
  const cargoColumns: ColumnOption<CargoItem>[] = [
    { type: 'globalIndex', label: '序号', width: 68 },
    { prop: 'cargoName', label: '货物名称', minWidth: 180 },
    {
      prop: 'quantity',
      label: '数量',
      minWidth: 100,
      align: 'right',
      formatter: (row) => formatRateNumber(row.quantity)
    },
    { prop: 'unit', label: '单位', minWidth: 100, dict: { code: 'tmsCargoUnit', display: 'text' } },
    {
      prop: 'volumeM3',
      label: '体积(m³)',
      minWidth: 120,
      align: 'right',
      formatter: (row) => formatRateNumber(row.volumeM3)
    },
    {
      prop: 'weightKg',
      label: '重量(kg)',
      minWidth: 120,
      align: 'right',
      formatter: (row) => formatRateNumber(row.weightKg)
    }
  ]

  onMounted(() => void loadPage())

  async function loadPage(): Promise<void> {
    const id = String(route.params.id || '')
    if (!id) {
      page.error = new Error('缺少客户价格标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchCustomerPriceDetail(id)
      detail.data = data ?? undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('客户价格详情加载失败')
    } finally {
      page.loading = false
    }
  }

  function goBack(): void {
    void router.push({ name: 'TmsCustomerPrice' })
  }
  function getDictLabel(code: keyof typeof getDictMap.value, value?: string | null): string {
    if (!value) return '--'
    const item = getDictMap.value[code]?.find(
      (option) => option.value === value || option.label === value
    )
    return item?.label || item?.name || value
  }
  function formatCoordinate(
    longitude?: number | string | null,
    latitude?: number | string | null
  ): string {
    return longitude !== null &&
      longitude !== undefined &&
      latitude !== null &&
      latitude !== undefined
      ? `${longitude}, ${latitude}`
      : '--'
  }
  function createMoneyItems(
    entries: Array<[keyof CustomerPrice, string]>
  ): ArtDescriptionItem<Partial<CustomerPrice>>[] {
    return entries.map(([key, label]) => ({
      key: String(key),
      label,
      field: String(key),
      formatter: (value) => `¥ ${formatRateMoney(value as number | string | null)}`
    }))
  }
</script>

<style scoped lang="scss" src="../modules/rate-card-detail.scss"></style>
