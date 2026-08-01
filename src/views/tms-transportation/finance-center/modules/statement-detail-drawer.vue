<template>
  <ArtDrawer ref="drawerRef">
    <div v-if="currentRow" class="statement-detail">
      <ArtSectionTitle>对账概览</ArtSectionTitle>
      <ElDescriptions :column="2" border>
        <ElDescriptionsItem label="对账单号">{{ currentRow.statementNo }}</ElDescriptionsItem>
        <ElDescriptionsItem label="账期">{{ currentRow.period }}</ElDescriptionsItem>
        <ElDescriptionsItem label="结算对象">{{ currentRow.counterpartyName }}</ElDescriptionsItem>
        <ElDescriptionsItem label="运单数量">{{ currentRow.waybillCount }} 单</ElDescriptionsItem>
        <ElDescriptionsItem label="对账金额">{{
          formatMoney(currentRow.statementAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="未结金额">{{
          formatMoney(currentRow.outstandingAmount)
        }}</ElDescriptionsItem>
        <ElDescriptionsItem label="负责人">{{ currentRow.ownerName }}</ElDescriptionsItem>
        <ElDescriptionsItem label="创建时间">{{ currentRow.createTime }}</ElDescriptionsItem>
      </ElDescriptions>

      <ArtSectionTitle class="statement-detail__section">关联运单（业务接入预留）</ArtSectionTitle>
      <ElEmpty description="下一阶段接入对账明细、费用调整和审核记录" :image-size="100" />
    </div>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import { formatMoney } from './finance-scaffold-data'
  import type { SettlementStatementRecord } from './finance-types'

  defineOptions({ name: 'TmsStatementDetailDrawer' })

  const drawerRef = ref<ArtDrawerExpose<SettlementStatementRecord>>()
  const currentRow = ref<SettlementStatementRecord>()

  async function handleOpen(row: SettlementStatementRecord): Promise<void> {
    currentRow.value = row
    await drawerRef.value?.handleOpen(row, {
      title: row.settlementType === 'customer_receivable' ? '客户对账单详情' : '承运商对账单详情',
      size: 'min(760px, 92vw)',
      contentHeight: 'calc(100vh - 132px)',
      drawerProps: { appendToBody: true, resizable: true }
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
