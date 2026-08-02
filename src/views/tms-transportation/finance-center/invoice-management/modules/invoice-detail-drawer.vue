<template>
  <ArtDrawer ref="drawerRef" :loading="loading" :show-footer="false">
    <div v-if="detail" class="invoice-detail">
      <ArtSectionTitle>发票信息</ArtSectionTitle>
      <ElDescriptions :column="2" border>
        <ElDescriptionsItem label="登记单号">{{ detail.invoiceRecordNo }}</ElDescriptionsItem>
        <ElDescriptionsItem label="发票状态">
          <ArtDictDisplay dict-code="tmsInvoiceStatus" :value="detail.status" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="发票方向">
          <ArtDictDisplay dict-code="tmsInvoiceDirection" :value="detail.direction" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="发票类型">
          <ArtDictDisplay dict-code="tmsInvoiceType" :value="detail.invoiceType" />
        </ElDescriptionsItem>
        <ElDescriptionsItem label="往来单位">{{
          detail.counterpartyNameSnapshot
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="开票日期">{{ detail.issueDate }}</ElDescriptionsItem>
        <ElDescriptionsItem label="发票代码">{{ detail.invoiceCode || '-' }}</ElDescriptionsItem>
        <ElDescriptionsItem label="发票号码">{{ detail.invoiceNo || '-' }}</ElDescriptionsItem>
        <ElDescriptionsItem label="发票抬头">{{ detail.invoiceTitle || '-' }}</ElDescriptionsItem>
        <ElDescriptionsItem label="纳税人识别号">{{ detail.taxNumber || '-' }}</ElDescriptionsItem>
        <ElDescriptionsItem label="不含税金额">{{
          formatMoney(detail.amountExcludingTax)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="税率"
          >{{ Number(detail.taxRate).toFixed(2) }}%</ElDescriptionsItem
        >
        <ElDescriptionsItem label="税额">{{ formatMoney(detail.taxAmount) }}</ElDescriptionsItem>
        <ElDescriptionsItem label="价税合计">{{
          formatMoney(detail.totalAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="已关联金额">{{
          formatMoney(detail.linkedAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="未关联金额">{{
          formatMoney(detail.unlinkedAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="备注" :span="2">{{ detail.remark || '-' }}</ElDescriptionsItem>
      </ElDescriptions>

      <section class="invoice-detail__section">
        <ArtSectionTitle>关联对账单</ArtSectionTitle>
        <ElTable
          :data="detail.statementLinks ?? []"
          table-layout="fixed"
          empty-text="暂未关联对账单"
        >
          <ElTableColumn prop="statementNo" label="对账单号" min-width="180" />
          <ElTableColumn
            prop="counterpartyName"
            label="往来单位"
            min-width="180"
            show-overflow-tooltip
          />
          <ElTableColumn label="账期" width="205">
            <template #default="{ row }">{{ row.periodStart }} 至 {{ row.periodEnd }}</template>
          </ElTableColumn>
          <ElTableColumn label="对账金额" width="135" align="right">
            <template #default="{ row }">{{ formatMoney(row.statementAmount) }}</template>
          </ElTableColumn>
          <ElTableColumn label="关联金额" width="135" align="right">
            <template #default="{ row }">{{ formatMoney(row.linkedAmount) }}</template>
          </ElTableColumn>
        </ElTable>
      </section>

      <section class="invoice-detail__section">
        <ArtSectionTitle>处理记录</ArtSectionTitle>
        <ElTimeline>
          <ElTimelineItem :timestamp="formatTime(detail.createTime)" type="primary">
            {{ detail.createBy || '系统用户' }} 登记发票
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.submittedAt"
            :timestamp="formatTime(detail.submittedAt)"
            type="warning"
          >
            {{ detail.submittedBy || '系统用户' }} 提交复核
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.reviewedAt"
            :timestamp="formatTime(detail.reviewedAt)"
            type="success"
          >
            {{ detail.reviewedBy || '系统用户' }} 完成复核
            <span v-if="detail.reviewRemark">：{{ detail.reviewRemark }}</span>
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.voidedAt"
            :timestamp="formatTime(detail.voidedAt)"
            type="danger"
          >
            {{ detail.voidedBy || '系统用户' }} 作废发票：{{ detail.voidReason }}
          </ElTimelineItem>
        </ElTimeline>
      </section>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchInvoiceDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsInvoiceDetailDrawer' })

  type Invoice = Api.Tms.Finance.InvoiceRecord

  const drawerRef = ref<ArtDrawerExpose<Invoice>>()
  const detail = shallowRef<Invoice>()
  const loading = ref(false)

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function formatTime(value?: string | null): string {
    return value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '-') : '-'
  }

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    try {
      const { data } = await fetchInvoiceDetail(id)
      detail.value = data ?? undefined
    } finally {
      loading.value = false
    }
  }

  async function handleOpen(row: Invoice): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `发票详情 · ${row.invoiceNo || row.invoiceRecordNo}`,
      size: 'min(1080px, 94vw)',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .invoice-detail {
    &__section {
      margin-top: 24px;
    }
  }
</style>
