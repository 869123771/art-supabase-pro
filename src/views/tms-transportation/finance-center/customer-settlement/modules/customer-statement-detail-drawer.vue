<template>
  <ArtDrawer ref="drawerRef">
    <ElSkeleton :loading="loading" animated :rows="8">
      <div v-if="detail" class="statement-detail">
        <ArtSectionTitle>对账概览</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="对账单号">{{ detail.statementNo }}</ElDescriptionsItem>
          <ElDescriptionsItem label="状态">
            <ArtDictDisplay dict-code="tmsSettlementStatus" :value="detail.status" display="tag" />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="对账客户">{{ detail.customerName }}</ElDescriptionsItem>
          <ElDescriptionsItem label="账期">
            {{ detail.periodStart }} 至 {{ detail.periodEnd }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="运单数量">{{ detail.waybillCount }} 单</ElDescriptionsItem>
          <ElDescriptionsItem label="对账金额">
            {{ formatMoney(detail.statementAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="已结金额">
            {{ formatMoney(detail.settledAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="未结金额">
            {{ formatMoney(detail.outstandingAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="创建人">{{ detail.createBy || '-' }}</ElDescriptionsItem>
          <ElDescriptionsItem label="创建时间">
            {{ formatDateTime(detail.createTime) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="备注" :span="2">{{ detail.remark || '-' }}</ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.reviewRemark" label="审核意见" :span="2">
            {{ detail.reviewRemark }}
          </ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.voidReason" label="作废原因" :span="2">
            {{ detail.voidReason }}
          </ElDescriptionsItem>
        </ElDescriptions>

        <ArtSectionTitle class="statement-detail__section">运单明细</ArtSectionTitle>
        <ArtTable
          :data="detail.items ?? []"
          :columns="itemColumns"
          :pagination="false"
          :show-table-header="false"
          max-height="420px"
          border
        />

        <ArtSectionTitle class="statement-detail__section">审核记录</ArtSectionTitle>
        <ElTimeline class="statement-detail__timeline">
          <ElTimelineItem :timestamp="formatDateTime(detail.createTime)" type="primary">
            {{ detail.createBy || '系统用户' }} 创建对账单
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.submittedAt"
            :timestamp="formatDateTime(detail.submittedAt)"
            type="warning"
          >
            {{ detail.submittedBy || '系统用户' }} 提交审核
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.reviewedAt"
            :timestamp="formatDateTime(detail.reviewedAt)"
            :type="detail.status === 'draft' ? 'danger' : 'success'"
          >
            {{ detail.reviewedBy || '系统用户' }}
            {{ detail.status === 'draft' ? '驳回对账单' : '完成审核' }}
          </ElTimelineItem>
          <ElTimelineItem
            v-if="detail.voidedAt"
            :timestamp="formatDateTime(detail.voidedAt)"
            type="danger"
          >
            {{ detail.voidedBy || '系统用户' }} 作废对账单
          </ElTimelineItem>
        </ElTimeline>
      </div>
    </ElSkeleton>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCustomerStatementDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsCustomerStatementDetailDrawer' })

  type CustomerStatement = Api.Tms.Finance.CustomerStatementRecord
  type CustomerStatementItem = Api.Tms.Finance.CustomerStatementItem

  const drawerRef = ref<ArtDrawerExpose<CustomerStatement>>()
  const loading = ref(false)
  const detail = ref<CustomerStatement>()

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const formatDateTime = (value?: string | null): string =>
    value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '-') : '-'

  const itemColumns: ColumnOption<CustomerStatementItem>[] = [
    { type: 'globalIndex', label: '序号', width: 66 },
    { prop: 'waybillNoSnapshot', label: '运单号', width: 170 },
    { prop: 'orderNoSnapshot', label: '订单号', width: 170 },
    {
      prop: 'route',
      label: '运输线路',
      minWidth: 190,
      showOverflowTooltip: true,
      formatter: (row) =>
        [row.originStationSnapshot, row.destinationStationSnapshot].filter(Boolean).join(' → ') ||
        '-'
    },
    {
      prop: 'completedAtSnapshot',
      label: '完成时间',
      width: 165,
      formatter: (row) => formatDateTime(row.completedAtSnapshot)
    },
    {
      prop: 'receivableAmount',
      label: '应收金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.receivableAmount)
    },
    {
      prop: 'adjustmentAmount',
      label: '调整金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.adjustmentAmount)
    },
    {
      prop: 'lineAmount',
      label: '对账金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.lineAmount)
    }
  ]

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    try {
      const { data } = await fetchCustomerStatementDetail(id)
      detail.value = data
    } finally {
      loading.value = false
    }
  }

  async function handleOpen(row: CustomerStatement): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `客户对账单 · ${row.statementNo}`,
      size: 'min(1080px, 94vw)',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .statement-detail {
    &__section {
      margin-top: 24px;
    }

    &__timeline {
      padding: 8px 8px 0;
    }
  }
</style>
