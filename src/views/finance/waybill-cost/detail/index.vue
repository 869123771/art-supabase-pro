<template>
  <ArtPageShell
    class="waybill-cost-detail"
    :loading="detail.loading"
    loading-mode="skeleton"
    :error="detail.error"
    :empty="detail.loaded && !detail.data"
    empty-text="未找到该运单费用单"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.costNo || '运单费用详情'"
      subtitle="运单费用单据详情"
      show-back
      @back="goBack"
    >
      <template #status>
        <div v-if="detail.data" class="waybill-cost-detail__header-status">
          <ArtDictDisplay
            dict-code="tmsCostAuditStatus"
            :value="detail.data.auditStatus"
            display="tag"
          />
          <ArtDictDisplay
            dict-code="tmsWaybillCostSettlementStatus"
            :value="detail.data.settlementStatus"
            display="tag"
          />
        </div>
      </template>
      <template #meta>
        <div v-if="detail.data" class="waybill-cost-detail__header-meta">
          <span>
            <ArtSvgIcon icon="ri:calendar-event-line" aria-hidden="true" />
            发生于 {{ formatDate(detail.data.occurredOn) }}
          </span>
          <span>
            <ArtSvgIcon icon="ri:user-3-line" aria-hidden="true" />
            {{ detail.data.reporterNameSnapshot || detail.data.createBy || '上报人待补充' }}
          </span>
          <span>
            <ArtSvgIcon icon="ri:time-line" aria-hidden="true" />
            更新于 {{ formatDateTime(detail.data.updateTime) }}
          </span>
        </div>
      </template>
      <ElButton v-if="detail.data?.waybillId" @click="openWaybillDetail">
        <ArtSvgIcon icon="ri:route-line" aria-hidden="true" />
        查看关联运单
      </ElButton>
    </ArtPageHeader>

    <section v-if="detail.data" class="waybill-cost-detail__overview art-card-xs">
      <article v-for="item in overviewItems" :key="item.label">
        <span :class="`is-${item.tone}`">
          <ArtSvgIcon :icon="item.icon" aria-hidden="true" />
        </span>
        <div>
          <small>{{ item.label }}</small>
          <strong :title="item.value">{{ item.value }}</strong>
          <p>{{ item.hint }}</p>
        </div>
      </article>
    </section>

    <div v-if="detail.data" class="waybill-cost-detail__content">
      <section class="waybill-cost-detail__section art-card-xs">
        <ArtSectionTitle>费用信息</ArtSectionTitle>
        <ArtDescriptions :data="detail.data" :items="expenseItems" :columns="4" />
      </section>

      <section class="waybill-cost-detail__section art-card-xs">
        <ArtSectionTitle>运输关联</ArtSectionTitle>
        <ArtDescriptions :data="detail.data" :items="transportItems" :columns="4">
          <template #item-waybillNo>
            <RouterLink
              v-if="detail.data.waybillId"
              class="waybill-cost-detail__inline-link"
              :to="{ name: 'TmsWaybillDetail', params: { id: detail.data.waybillId } }"
            >
              {{ waybillNo }}
            </RouterLink>
            <span v-else>{{ waybillNo }}</span>
          </template>
        </ArtDescriptions>
      </section>

      <section class="waybill-cost-detail__section art-card-xs">
        <ArtSectionTitle>发生地点</ArtSectionTitle>
        <ArtDescriptions :data="detail.data" :items="locationItems" :columns="4" />
      </section>

      <section class="waybill-cost-detail__section art-card-xs">
        <ArtSectionTitle>审核、报销与支付</ArtSectionTitle>
        <ArtDescriptions :data="detail.data" :items="settlementItems" :columns="4">
          <template #item-reimbursementNo>
            <RouterLink
              v-if="detail.data.reimbursement?.id"
              class="waybill-cost-detail__inline-link"
              :to="getExpenseReimbursementDetailPath(detail.data.reimbursement.id)"
            >
              {{ detail.data.reimbursement.reimbursementNo || '--' }}
            </RouterLink>
            <span v-else>{{ detail.data.reimbursement?.reimbursementNo || '--' }}</span>
          </template>
        </ArtDescriptions>
      </section>

      <section class="waybill-cost-detail__section art-card-xs">
        <ArtSectionTitle>票据附件</ArtSectionTitle>
        <div v-if="attachments.length" class="waybill-cost-detail__attachments">
          <div v-for="file in attachments" :key="file.url" class="waybill-cost-detail__attachment">
            <span><ArtSvgIcon icon="ri:attachment-2" aria-hidden="true" /></span>
            <ArtAttachmentLink :file="file" />
          </div>
        </div>
        <div v-else class="waybill-cost-detail__empty-inline">
          <ArtSvgIcon icon="ri:file-damage-line" aria-hidden="true" />
          当前费用单未上传票据附件
        </div>
      </section>

      <section v-if="detail.data.id" class="waybill-cost-detail__section art-card-xs">
        <WorkflowBusinessHistory business-type="tms_waybill_cost" :business-id="detail.data.id" />
      </section>
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import type { FilePreviewTarget } from '@/hooks/core/useFilePreview'
  import ArtAttachmentLink from '@/components/core/media/art-file-viewer/attachment-link.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtPageHeader from '@/components/core/layouts/art-page-header/index.vue'
  import ArtPageShell from '@/components/core/layouts/art-page-shell/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import { fetchWaybillCostDetail } from '@/api/finance'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue, formatNumberValue } from '@/utils/ui'
  import { getExpenseReimbursementDetailPath } from '@/router/business-paths'

  defineOptions({ name: 'FinanceWaybillCostDetail' })

  type Expense = Api.Finance.WaybillCostRecord

  interface DetailState {
    data?: Expense
    error: Error | null
    loaded: boolean
    loading: boolean
  }

  interface OverviewItem {
    label: string
    value: string
    hint: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  const route = useRoute()
  const router = useRouter()
  const detail = reactive<DetailState>({
    data: undefined,
    error: null,
    loaded: false,
    loading: false
  })

  const waybillNo = computed(
    () => detail.data?.waybillNoSnapshot || detail.data?.waybill?.waybillNo || '--'
  )
  const orderNo = computed(
    () => detail.data?.orderNoSnapshot || detail.data?.waybill?.order?.orderNo || '--'
  )
  const routeSummary = computed(
    () =>
      detail.data?.routeSnapshot ||
      [detail.data?.waybill?.originCity, detail.data?.waybill?.destinationCity]
        .filter(Boolean)
        .join(' → ') ||
      '--'
  )
  const attachments = computed<FilePreviewTarget[]>(() =>
    (detail.data?.attachments ?? []).map((url, index) => ({
      url,
      name: `费用票据 ${index + 1}`
    }))
  )
  const overviewItems = computed<OverviewItem[]>(() => [
    {
      label: '申报金额',
      value: formatCurrencyValue(detail.data?.amount),
      hint: '本次费用申报金额',
      icon: 'ri:money-cny-circle-line',
      tone: 'primary'
    },
    {
      label: '费用项目',
      value: detail.data?.expenseItem?.itemName || '--',
      hint: detail.data?.expenseItem?.itemCode || '费用口径待补充',
      icon: 'ri:price-tag-3-line',
      tone: 'warning'
    },
    {
      label: '关联运单',
      value: waybillNo.value,
      hint: routeSummary.value,
      icon: 'ri:truck-line',
      tone: 'success'
    },
    {
      label: '票据材料',
      value: `${attachments.value.length} 份`,
      hint: detail.data?.invoiceNo || '未填写票据号码',
      icon: 'ri:attachment-2',
      tone: 'info'
    }
  ])

  const expenseItems: ArtDescriptionItem<Expense>[] = [
    { key: 'costNo', label: '费用单号', field: 'costNo', copyable: true },
    {
      key: 'expenseItem',
      label: '费用项目',
      value: (data: Expense) => data.expenseItem?.itemName
    },
    { key: 'amount', label: '申报金额', field: 'amount', format: 'money' },
    { key: 'occurredOn', label: '发生日期', field: 'occurredOn', format: 'date' },
    {
      key: 'quantity',
      label: '数量/用量',
      field: 'quantity',
      formatter: (value) => formatOptionalNumber(value)
    },
    {
      key: 'unitPrice',
      label: '单价',
      field: 'unitPrice',
      formatter: (value) => formatOptionalMoney(value)
    },
    { key: 'providerName', label: '服务商', field: 'providerName' },
    { key: 'payeeName', label: '收款方', field: 'payeeName' },
    { key: 'paymentChannel', label: '支付渠道', field: 'paymentChannel' },
    { key: 'invoiceNo', label: '票据号码', field: 'invoiceNo', copyable: true },
    { key: 'meterNo', label: '表号/桩号', field: 'meterNo' },
    { key: 'remark', label: '费用说明', field: 'remark', span: 2 }
  ]

  const transportItems: ArtDescriptionItem<Expense>[] = [
    { key: 'waybillNo', label: '运单号', value: () => waybillNo.value },
    { key: 'orderNo', label: '订单号', value: () => orderNo.value, copyable: true },
    { key: 'plateNo', label: '车牌号', field: 'plateNoSnapshot' },
    { key: 'driverName', label: '司机', field: 'driverNameSnapshot' },
    { key: 'driverPhone', label: '司机电话', field: 'driverPhoneSnapshot' },
    {
      key: 'carrier',
      label: '承运商',
      value: (data: Expense) => data.waybill?.carrier?.companyName
    },
    { key: 'route', label: '运输路线', value: () => routeSummary.value, span: 2 }
  ]

  const locationItems: ArtDescriptionItem<Expense>[] = [
    { key: 'expenseRegion', label: '所在区域', field: 'expenseRegion', span: 2 },
    { key: 'expenseLocation', label: '详细地点', field: 'expenseLocation', span: 2 },
    {
      key: 'coordinates',
      label: '经纬度',
      value: (data: Expense) => formatCoordinates(data.expenseLongitude, data.expenseLatitude),
      span: 2
    },
    { key: 'coordinateSource', label: '定位来源', field: 'expenseCoordinateSource' },
    { key: 'coordinateSystem', label: '坐标系', field: 'expenseCoordinateSystem' },
    { key: 'geocodeProvider', label: '地理编码服务', field: 'expenseGeocodeProvider' },
    {
      key: 'geocodedAt',
      label: '定位确认时间',
      field: 'expenseGeocodedAt',
      format: 'datetime'
    }
  ]

  const settlementItems: ArtDescriptionItem<Expense>[] = [
    {
      key: 'auditStatus',
      label: '审核状态',
      field: 'auditStatus',
      dictCode: 'tmsCostAuditStatus'
    },
    { key: 'submittedAt', label: '提交时间', field: 'submittedAt', format: 'datetime' },
    { key: 'submittedBy', label: '提交人', field: 'submittedBy' },
    { key: 'reviewedAt', label: '审核时间', field: 'reviewedAt', format: 'datetime' },
    { key: 'reviewedBy', label: '审核人', field: 'reviewedBy' },
    { key: 'reviewRemark', label: '审核意见', field: 'reviewRemark', span: 2 },
    {
      key: 'settlementStatus',
      label: '核销状态',
      field: 'settlementStatus',
      dictCode: 'tmsWaybillCostSettlementStatus'
    },
    {
      key: 'reimbursementNo',
      label: '报销单号',
      value: (data: Expense) => data.reimbursement?.reimbursementNo,
      copyable: true
    },
    {
      key: 'paymentNo',
      label: '付款单号',
      value: (data: Expense) => data.expensePayment?.paymentNo,
      copyable: true
    },
    {
      key: 'paymentDate',
      label: '付款日期',
      value: (data: Expense) => data.expensePayment?.paymentDate,
      format: 'date'
    },
    {
      key: 'bankReference',
      label: '银行流水号',
      value: (data: Expense) => data.expensePayment?.bankReference,
      copyable: true
    },
    { key: 'paidAt', label: '核销时间', field: 'paidAt', format: 'datetime' },
    {
      key: 'ocrStatus',
      label: 'OCR 状态',
      field: 'ocrStatus',
      dictCode: 'tmsExpenseOcrStatus'
    }
  ]

  onMounted(() => {
    void loadDetail()
  })

  async function loadDetail(): Promise<void> {
    const costId = String(route.params.id || '')
    if (!costId) {
      Object.assign(detail, { error: new Error('缺少费用单标识'), loaded: true })
      return
    }

    detail.loading = true
    detail.error = null
    try {
      const { data } = await fetchWaybillCostDetail(costId)
      detail.data = data ?? undefined
    } catch (error) {
      detail.error = error instanceof Error ? error : new Error('费用单详情加载失败，请稍后重试')
    } finally {
      detail.loaded = true
      detail.loading = false
    }
  }

  function openWaybillDetail(): void {
    if (!detail.data?.waybillId) return
    void router.push({ name: 'TmsWaybillDetail', params: { id: detail.data.waybillId } })
  }

  function goBack(): void {
    void router.back()
  }

  function formatDate(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD') || '--'
  }

  function formatDateTime(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '--'
  }

  function formatOptionalNumber(value: unknown): string {
    return value === null || value === undefined || value === '' ? '--' : formatNumberValue(value)
  }

  function formatOptionalMoney(value: unknown): string {
    return value === null || value === undefined || value === '' ? '--' : formatCurrencyValue(value)
  }

  function formatCoordinates(
    longitude?: number | string | null,
    latitude?: number | string | null
  ): string {
    if (
      longitude === null ||
      longitude === undefined ||
      latitude === null ||
      latitude === undefined
    ) {
      return '--'
    }
    return `${longitude}, ${latitude}`
  }
</script>

<style scoped lang="scss">
  .waybill-cost-detail {
    min-height: 100%;
    padding: 12px 16px 18px;
    background: var(--art-main-bg-color);

    &__header-status,
    &__header-meta,
    &__attachments,
    &__attachment {
      display: flex;
      align-items: center;
    }

    &__header-status {
      flex-wrap: wrap;
      gap: var(--art-space-2);
    }

    &__header-meta {
      flex-wrap: wrap;
      gap: var(--art-space-3);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
      }
    }

    &__overview {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      padding: 0;
      margin-top: var(--art-space-3);
      overflow: hidden;

      article {
        display: flex;
        gap: var(--art-space-3);
        min-width: 0;
        padding: var(--art-space-4);

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 42px;
          height: 42px;
          font-size: 20px;
          border-radius: var(--el-border-radius-base);

          &.is-primary {
            color: var(--el-color-primary);
            background: var(--el-color-primary-light-9);
          }

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          &.is-warning {
            color: var(--el-color-warning);
            background: var(--el-color-warning-light-9);
          }

          &.is-info {
            color: var(--el-color-info);
            background: var(--el-color-info-light-9);
          }
        }

        > div {
          display: grid;
          gap: 2px;
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
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 17px;
          font-variant-numeric: tabular-nums;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }

        p {
          margin: 0;
          font-size: 11px;
        }
      }
    }

    &__content {
      display: flex;
      flex-direction: column;
      gap: var(--art-space-3);
      margin-top: var(--art-space-3);
    }

    &__section {
      min-width: 0;
      padding: var(--art-space-5);
    }

    &__inline-link {
      font-weight: 600;
      color: var(--theme-color);
      text-decoration: none;

      &:hover {
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      &:focus-visible {
        outline: 2px solid var(--theme-color);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }

    &__attachments {
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__attachment {
      gap: var(--art-space-2);
      min-width: 180px;
      max-width: 100%;
      padding: 10px 12px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 30px;
        height: 30px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, transparent);
        border-radius: var(--el-border-radius-small);
      }
    }

    &__empty-inline {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;
      color: var(--el-text-color-secondary);
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 132px;
      font-weight: 600;
    }

    @media (width <= 1100px) {
      &__overview {
        grid-template-columns: repeat(2, minmax(0, 1fr));

        article:nth-child(2) {
          border-right: 0;
        }

        article:nth-child(-n + 2) {
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }

    @media (width <= 640px) {
      padding-inline: 10px;

      &__overview {
        grid-template-columns: 1fr;

        article {
          border-right: 0 !important;

          &:not(:last-child) {
            border-bottom: 1px solid var(--el-border-color-lighter);
          }
        }
      }

      &__section {
        padding: var(--art-space-4);
      }
    }
  }
</style>
