<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无承运商对账详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="statement-detail">
        <ArtSectionTitle>对账概览</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />
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
    </ArtAsyncState>
    <template #footer="{ api }"><ElButton @click="api.handleClose()">关闭</ElButton></template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCarrierStatementDetail } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'TmsCarrierStatementDetailDrawer' })
  type Statement = Api.Tms.Finance.CarrierStatementRecord
  type Item = Api.Tms.Finance.CarrierStatementItem
  const drawerRef = ref<ArtDrawerExpose<Statement>>()
  const loading = ref(false)
  const detail = ref<Statement>()
  const loadError = shallowRef<Error | null>(null)
  const formatMoney = (v?: number | null) => formatCurrencyValue(v ?? 0)
  const formatDateTime = (v?: string | null) =>
    v ? (formatWithDayjs(v, 'YYYY-MM-DD HH:mm') ?? '-') : '-'
  const descriptionItems = computed<ArtDescriptionItem<Statement>[]>(() => [
    { key: 'statementNo', label: '对账单号', field: 'statementNo', copyable: true },
    {
      key: 'status',
      label: '状态',
      field: 'status',
      dictCode: 'tmsSettlementStatus',
      dictDisplay: 'tag'
    },
    { key: 'carrierName', label: '对账承运商', field: 'carrierName' },
    {
      key: 'period',
      label: '账期',
      value: (data: Statement) => `${data.periodStart} 至 ${data.periodEnd}`
    },
    {
      key: 'counts',
      label: '费用 / 运单',
      value: (data: Statement) => `${data.costCount} 笔 / ${data.waybillCount} 单`
    },
    { key: 'statementAmount', label: '应付金额', field: 'statementAmount', format: 'money' },
    { key: 'settledAmount', label: '已付金额', field: 'settledAmount', format: 'money' },
    { key: 'outstandingAmount', label: '未付金额', field: 'outstandingAmount', format: 'money' },
    { key: 'createBy', label: '创建人', field: 'createBy' },
    {
      key: 'createTime',
      label: '创建时间',
      field: 'createTime',
      formatter: (value) => formatDateTime(value as string | null | undefined)
    },
    { key: 'remark', label: '备注', field: 'remark', span: 2 },
    ...(detail.value?.reviewRemark
      ? [{ key: 'reviewRemark', label: '审核意见', field: 'reviewRemark', span: 2 }]
      : []),
    ...(detail.value?.voidReason
      ? [{ key: 'voidReason', label: '作废原因', field: 'voidReason', span: 2 }]
      : [])
  ])
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
    loadError.value = null
    try {
      const { data } = await fetchCarrierStatementDetail(id)
      detail.value = data
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('承运商对账详情加载失败')
    } finally {
      loading.value = false
    }
  }
  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }
  async function handleOpen(row: Statement) {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `承运商对账单 · ${row.statementNo}`,
      size: 'xl',
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
      margin-top: var(--art-space-6);
    }
  }
</style>
