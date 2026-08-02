<template>
  <ArtDrawer ref="drawerRef">
    <ElSkeleton :loading="loading" animated :rows="8">
      <div v-if="detail" class="statement-detail">
        <ArtSectionTitle>对账概览</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="对账单号">{{ detail.statementNo }}</ElDescriptionsItem>
          <ElDescriptionsItem label="状态"
            ><ArtDictDisplay dict-code="tmsSettlementStatus" :value="detail.status" display="tag"
          /></ElDescriptionsItem>
          <ElDescriptionsItem label="对账承运商">{{ detail.carrierName }}</ElDescriptionsItem>
          <ElDescriptionsItem label="账期"
            >{{ detail.periodStart }} 至 {{ detail.periodEnd }}</ElDescriptionsItem
          >
          <ElDescriptionsItem label="费用 / 运单"
            >{{ detail.costCount }} 笔 / {{ detail.waybillCount }} 单</ElDescriptionsItem
          >
          <ElDescriptionsItem label="应付金额">{{
            formatMoney(detail.statementAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="已付金额">{{
            formatMoney(detail.settledAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="未付金额">{{
            formatMoney(detail.outstandingAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="创建人">{{ detail.createBy || '-' }}</ElDescriptionsItem>
          <ElDescriptionsItem label="创建时间">{{
            formatDateTime(detail.createTime)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="备注" :span="2">{{ detail.remark || '-' }}</ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.reviewRemark" label="审核意见" :span="2">{{
            detail.reviewRemark
          }}</ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.voidReason" label="作废原因" :span="2">{{
            detail.voidReason
          }}</ElDescriptionsItem>
        </ElDescriptions>
        <ArtSectionTitle class="statement-detail__section">费用明细</ArtSectionTitle>
        <ArtTable
          :data="detail.items ?? []"
          :columns="itemColumns"
          :pagination="false"
          :show-table-header="false"
          max-height="430px"
          border
        />
      </div>
    </ElSkeleton>
    <template #footer="{ api }"><ElButton @click="api.handleClose()">关闭</ElButton></template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCarrierStatementDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsCarrierStatementDetailDrawer' })
  type Statement = Api.Tms.Finance.CarrierStatementRecord
  type Item = Api.Tms.Finance.CarrierStatementItem
  const drawerRef = ref<ArtDrawerExpose<Statement>>()
  const loading = ref(false)
  const detail = ref<Statement>()
  const formatMoney = (v?: number | null) =>
    `¥${Number(v ?? 0).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  const formatDateTime = (v?: string | null) =>
    v ? (formatWithDayjs(v, 'YYYY-MM-DD HH:mm') ?? '-') : '-'
  const itemColumns: ColumnOption<Item>[] = [
    { type: 'globalIndex', label: '序号', width: 66 },
    { prop: 'waybillNoSnapshot', label: '运单号', width: 175 },
    {
      prop: 'costTypeSnapshot',
      label: '费用类型',
      width: 130,
      dict: { code: 'tmsWaybillCostType', display: 'text' }
    },
    { prop: 'occurredOnSnapshot', label: '发生日期', width: 115 },
    { prop: 'payeeNameSnapshot', label: '收款方', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'costAmount',
      label: '费用金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.costAmount)
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
      label: '应付金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.lineAmount)
    }
  ]
  async function loadDetail(id: string) {
    loading.value = true
    try {
      const { data } = await fetchCarrierStatementDetail(id)
      detail.value = data
    } finally {
      loading.value = false
    }
  }
  async function handleOpen(row: Statement) {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `承运商对账单 · ${row.statementNo}`,
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
  }
</style>
