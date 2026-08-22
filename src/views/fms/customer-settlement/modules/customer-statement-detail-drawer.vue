<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无客户对账详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="statement-detail">
        <ArtSectionTitle>对账概览</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <ArtSectionTitle class="statement-detail__section">运单明细</ArtSectionTitle>
        <ArtTable
          :data="detail.items ?? []"
          :columns="itemColumns"
          :pagination="false"
          :show-table-header="false"
          max-height="420px"
          border
        />

        <section class="statement-detail__section">
          <WorkflowBusinessHistory
            business-type="tms_customer_statement"
            :business-id="detail.id"
          />
        </section>
      </div>
    </ArtAsyncState>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchCustomerStatementDetail } from '@/api/fms'
  import { formatWithDayjs } from '@/utils/time'
  import { canViewField, formatSensitiveNumber } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceCustomerStatementDetailDrawer' })

  type CustomerStatement = Api.Fms.CustomerStatementRecord
  type CustomerStatementItem = Api.Fms.CustomerStatementItem

  const drawerRef = ref<ArtDrawerExpose<CustomerStatement>>()
  const loading = ref(false)
  const detail = ref<CustomerStatement>()
  const loadError = shallowRef<Error | null>(null)

  const formatMoney = (value?: number | string | null): string => {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
  }

  const canView = (field: Api.Fms.CustomerStatementFieldKey): boolean =>
    canViewField(detail.value?.fieldAccess, field)

  const formatDateTime = (value?: string | null): string =>
    value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '-') : '-'

  const descriptionItems = computed<ArtDescriptionItem<CustomerStatement>[]>(() => [
    { key: 'statementNo', label: '对账单号', field: 'statementNo', copyable: true },
    {
      key: 'status',
      label: '状态',
      field: 'status',
      dictCode: 'tmsSettlementStatus',
      dictDisplay: 'tag'
    },
    { key: 'customerName', label: '对账客户', field: 'customerName' },
    {
      key: 'period',
      label: '账期',
      value: (data: CustomerStatement) => `${data.periodStart} 至 ${data.periodEnd}`
    },
    {
      key: 'waybillCount',
      label: '运单数量',
      field: 'waybillCount',
      formatter: (value) => `${Number(value ?? 0)} 单`
    },
    ...(canView('statementAmounts')
      ? [
          {
            key: 'statementAmount',
            label: '对账金额',
            field: 'statementAmount',
            formatter: (value: unknown) => formatMoney(value as number | string | null | undefined)
          }
        ]
      : []),
    ...(canView('settlementAmounts')
      ? [
          {
            key: 'settledAmount',
            label: '已结金额',
            field: 'settledAmount',
            formatter: (value: unknown) => formatMoney(value as number | string | null | undefined)
          },
          {
            key: 'outstandingAmount',
            label: '未结金额',
            field: 'outstandingAmount',
            formatter: (value: unknown) => formatMoney(value as number | string | null | undefined)
          }
        ]
      : []),
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

  const itemColumns = computed<ColumnOption<CustomerStatementItem>[]>(() => [
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
    ...(canView('statementAmounts')
      ? [
          {
            prop: 'receivableAmount',
            label: '应收金额',
            width: 125,
            align: 'right' as const,
            formatter: (row: CustomerStatementItem) => formatMoney(row.receivableAmount)
          },
          {
            prop: 'adjustmentAmount',
            label: '调整金额',
            width: 125,
            align: 'right' as const,
            formatter: (row: CustomerStatementItem) => formatMoney(row.adjustmentAmount)
          },
          {
            prop: 'lineAmount',
            label: '对账金额',
            width: 125,
            align: 'right' as const,
            formatter: (row: CustomerStatementItem) => formatMoney(row.lineAmount)
          }
        ]
      : [])
  ])

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchCustomerStatementDetail(id)
      detail.value = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('客户对账详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: CustomerStatement): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `客户对账单 · ${row.statementNo}`,
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
