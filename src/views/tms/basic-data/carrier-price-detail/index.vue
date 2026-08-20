<template>
  <ArtPageShell
    class="rate-card-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无承运商价格详情"
    @retry="loadPage"
  >
    <ArtPageHeader
      :title="detail.data?.quoteNo || '承运商价格详情'"
      :subtitle="detail.data?.carrier?.companyName || '--'"
      show-back
      @back="goBack"
    />

    <section class="rate-card-detail__summary art-card-xs" aria-label="承运商价格概览">
      <article
        ><span>报价单号</span><strong>{{ detail.data?.quoteNo || '--' }}</strong></article
      >
      <article
        ><span>承运商</span
        ><strong>{{ detail.data?.carrier?.companyName || '--' }}</strong></article
      >
      <article
        ><span>货物明细</span><strong>{{ cargoItems.length }} 项</strong></article
      >
      <article v-if="canViewSensitiveField('costAmounts')"
        ><span>成本合计</span
        ><strong>¥ {{ formatRateMoney(detail.data?.totalFee) }}</strong></article
      >
    </section>

    <div class="rate-card-detail__content">
      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>运输路线</ArtSectionTitle>
        <div class="rate-card-detail__route">
          <div class="rate-card-detail__route-point"
            ><span>始发地</span><strong>{{ detail.data?.originRegion || '--' }}</strong></div
          >
          <span class="rate-card-detail__route-arrow" aria-hidden="true">→</span>
          <div class="rate-card-detail__route-point"
            ><span>目的地</span><strong>{{ detail.data?.destinationRegion || '--' }}</strong></div
          >
        </div>
        <ArtDescriptions :data="descriptionData" :items="routeItems" :columns="4" />
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>承运主体与运力</ArtSectionTitle>
        <div class="rate-card-detail__split">
          <article class="rate-card-detail__panel">
            <div class="rate-card-detail__panel-heading"
              ><b>承</b
              ><div><strong>承运商信息</strong><span>报价对应的承运主体与联系人</span></div></div
            >
            <ArtDescriptions :data="descriptionData" :items="carrierItems" :columns="1" />
          </article>
          <article class="rate-card-detail__panel">
            <div class="rate-card-detail__panel-heading"
              ><b class="is-orange">车</b
              ><div><strong>司机与车辆</strong><span>执行本次线路报价的运力信息</span></div></div
            >
            <ArtDescriptions :data="descriptionData" :items="capacityItems" :columns="2" />
          </article>
        </div>
      </section>

      <section class="rate-card-detail__section art-card-xs">
        <ArtSectionTitle>货物与拆分成本</ArtSectionTitle>
        <ArtTable
          :data="cargoItems"
          :columns="cargoColumns"
          :pagination="undefined"
          empty-text="暂无货物明细"
          empty-description="当前承运商价格未维护货物或拆分成本。"
          empty-height="150px"
        />
      </section>

      <section
        v-if="canViewSensitiveField('costAmounts')"
        class="rate-card-detail__section art-card-xs"
      >
        <ArtSectionTitle>成本与计费</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="costItems" :columns="4" />
      </section>

      <section
        v-if="canViewSensitiveField('paymentAmounts')"
        class="rate-card-detail__section art-card-xs"
      >
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
  import { fetchCarrierPriceDetail } from '@/api/tms'
  import {
    formatRateDateTime,
    formatRateMoney,
    formatRateNumber
  } from '../modules/rate-card-detail'
  import { canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'TmsCarrierPriceDetail' })

  type CarrierPrice = Api.Tms.BasicData.CarrierPrice
  type CargoItem = Api.Tms.BasicData.CarrierPriceCargoItem
  type CarrierPriceFieldKey = Api.Tms.BasicData.CarrierPriceFieldKey

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false, error: null as Error | null })
  const detail = reactive<{ data?: CarrierPrice }>({ data: undefined })
  const descriptionData = computed<Partial<CarrierPrice>>(() => detail.data ?? {})
  const cargoItems = computed(() => detail.data?.cargoItems ?? [])

  const routeItems: ArtDescriptionItem<Partial<CarrierPrice>>[] = [
    { key: 'quoteNo', label: '报价单号', field: 'quoteNo', copyable: true },
    {
      key: 'transportMode',
      label: '运输方式',
      field: 'transportMode',
      dictCode: 'tmsCarrierPriceTransportMode',
      dictDisplay: 'text'
    },
    {
      key: 'billingMethod',
      label: '计费方式',
      field: 'billingMethod',
      dictCode: 'tmsCustomerPriceBillingMethod',
      dictDisplay: 'text'
    },
    {
      key: 'cargoSummary',
      label: '货物汇总',
      value: (data: Partial<CarrierPrice>) =>
        `${formatRateNumber(data.cargoQuantityTotal)} 件 / ${formatRateNumber(data.cargoVolumeTotal)} m³ / ${formatRateNumber(data.cargoWeightTotal)} kg`
    }
  ]
  const carrierItems = computed<ArtDescriptionItem<Partial<CarrierPrice>>[]>(() => [
    { key: 'carrierName', label: '承运商', value: () => detail.data?.carrier?.companyName },
    {
      key: 'carrierCode',
      label: '承运商编码',
      value: () => detail.data?.carrier?.carrierCode,
      copyable: true
    },
    { key: 'contactName', label: '联系人', field: 'contactName' },
    ...(canViewSensitiveField('contactPhones')
      ? [
          {
            key: 'contactPhone',
            label: '联系电话',
            field: 'contactPhone',
            copyable: true
          } satisfies ArtDescriptionItem<Partial<CarrierPrice>>
        ]
      : [])
  ])
  const capacityItems = computed<ArtDescriptionItem<Partial<CarrierPrice>>[]>(() => [
    { key: 'driverName', label: '司机', field: 'driverName' },
    ...(canViewSensitiveField('contactPhones')
      ? [
          {
            key: 'driverPhone',
            label: '司机电话',
            field: 'driverPhone',
            copyable: true
          } satisfies ArtDescriptionItem<Partial<CarrierPrice>>
        ]
      : []),
    { key: 'plateNo', label: '车牌号', field: 'plateNo', copyable: true },
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
    }
  ])
  const costItems: ArtDescriptionItem<Partial<CarrierPrice>>[] = createMoneyItems([
    ['transportCost', '运输成本'],
    ['splitTransportFee', '拆分运输费'],
    ['loadingFee', '装卸费'],
    ['packageFee', '包装费'],
    ['otherFee', '其他费用'],
    ['totalFee', '成本合计']
  ])
  const paymentItems: ArtDescriptionItem<Partial<CarrierPrice>>[] = createMoneyItems([
    ['cashAmount', '现付'],
    ['prepaidAmount', '预付'],
    ['collectAmount', '到付'],
    ['periodicAmount', '回付/月结'],
    ['paymentTotal', '付款合计']
  ])
  const auditItems: ArtDescriptionItem<Partial<CarrierPrice>>[] = [
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
  const cargoColumns = computed<ColumnOption<CargoItem>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 68 },
    { prop: 'orderNo', label: '订单号', minWidth: 140 },
    { prop: 'cargoName', label: '货物名称', minWidth: 160 },
    {
      prop: 'quantity',
      label: '数量',
      minWidth: 90,
      align: 'right',
      formatter: (row) => formatRateNumber(row.quantity)
    },
    { prop: 'unit', label: '单位', minWidth: 90, dict: { code: 'tmsCargoUnit', display: 'text' } },
    {
      prop: 'volumeM3',
      label: '体积(m³)',
      minWidth: 110,
      align: 'right',
      formatter: (row) => formatRateNumber(row.volumeM3)
    },
    {
      prop: 'weightKg',
      label: '重量(kg)',
      minWidth: 110,
      align: 'right',
      formatter: (row) => formatRateNumber(row.weightKg)
    },
    ...(canViewSensitiveField('costAmounts')
      ? [
          {
            prop: 'splitTransportFee',
            label: '拆分运费(元)',
            minWidth: 130,
            align: 'right',
            formatter: (row) => formatRateMoney(row.splitTransportFee)
          } as ColumnOption<CargoItem>,
          {
            prop: 'loadingFee',
            label: '装卸费(元)',
            minWidth: 120,
            align: 'right',
            formatter: (row) => formatRateMoney(row.loadingFee)
          } as ColumnOption<CargoItem>,
          {
            prop: 'packageFee',
            label: '包装费(元)',
            minWidth: 120,
            align: 'right',
            formatter: (row) => formatRateMoney(row.packageFee)
          } as ColumnOption<CargoItem>
        ]
      : [])
  ])

  onMounted(() => void loadPage())

  async function loadPage(): Promise<void> {
    const id = String(route.params.id || '')
    if (!id) {
      page.error = new Error('缺少承运商价格标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchCarrierPriceDetail(id)
      detail.data = data ?? undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('承运商价格详情加载失败')
    } finally {
      page.loading = false
    }
  }

  function goBack(): void {
    void router.push({ name: 'TmsCarrierPrice' })
  }
  function canViewSensitiveField(field: CarrierPriceFieldKey): boolean {
    return canViewField(detail.data?.fieldAccess, field)
  }
  function createMoneyItems(
    entries: Array<[keyof CarrierPrice, string]>
  ): ArtDescriptionItem<Partial<CarrierPrice>>[] {
    return entries.map(([key, label]) => ({
      key: String(key),
      label,
      field: String(key),
      formatter: (value) => `¥ ${formatRateMoney(value as number | string | null)}`
    }))
  }
</script>

<style scoped lang="scss" src="../modules/rate-card-detail.scss"></style>
