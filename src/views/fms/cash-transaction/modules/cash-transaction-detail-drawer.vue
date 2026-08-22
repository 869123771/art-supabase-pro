<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="detail.loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail.data"
      empty-text="暂无收付款详情"
      @retry="retryLoad"
    >
      <div v-if="detail.data" class="cash-detail">
        <ArtSectionTitle>{{ directionLabel }}概览</ArtSectionTitle>
        <ArtDescriptions :data="detail.data" :items="descriptionItems" :columns="2" />

        <template v-if="canViewField(detail.data.fieldAccess, 'voucherEvidence')">
          <ArtSectionTitle class="cash-detail__section">{{ directionLabel }}凭证</ArtSectionTitle>
          <div v-if="detail.data.voucherUrls?.length" class="cash-detail__vouchers">
            <ElImage
              v-for="(url, index) in detail.data.voucherUrls"
              :key="url"
              :src="url"
              :preview-src-list="detail.data.voucherUrls"
              :initial-index="index"
              preview-teleported
              fit="cover"
              class="cash-detail__voucher"
            />
          </div>
          <div v-else class="cash-detail__restricted">
            {{
              getFieldAccess(detail.data.fieldAccess, 'voucherEvidence') === 'masked'
                ? '凭证内容已脱敏'
                : '暂无收付款凭证'
            }}
          </div>
        </template>

        <ArtSectionTitle class="cash-detail__section">核销记录</ArtSectionTitle>
        <ArtTable
          :data="detail.data.allocations ?? []"
          :columns="allocationColumns"
          :pagination="false"
          :show-table-header="false"
          table-layout="fixed"
          empty-height="180px"
          max-height="430px"
          empty-text="暂无核销记录"
          border
        />
      </div>
    </ArtAsyncState>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElTag, ElTooltip } from 'element-plus'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    fetchCashTransactionDetail,
    reverseCarrierCashAllocation,
    reverseCashAllocation
  } from '@/api/fms'
  import { formatWithDayjs } from '@/utils/time'
  import {
    canEditField,
    canViewField,
    formatSensitiveNumber,
    getFieldAccess
  } from '@/utils/field-permission'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'

  defineOptions({ name: 'FinanceCashTransactionDetailDrawer' })

  const { promptReason } = useArtFeedback()

  type CashTransaction = Api.Fms.CashTransactionRecord
  interface DetailAllocation {
    id: string
    allocatedAmount?: Api.Tms.BasicData.SensitiveNumber
    allocatedAt: string
    allocatedBy?: string | null
    isActive: boolean
    reverseReason?: string | null
    statement?: {
      statementNo: string
      periodStart: string
      periodEnd: string
    } | null
  }

  interface DetailGroup {
    data?: CashTransaction
    loading: boolean
  }

  const emit = defineEmits<{ changed: [] }>()
  const drawerRef = ref<ArtDrawerExpose<CashTransaction>>()
  const detail = reactive<DetailGroup>({ data: undefined, loading: false })
  const loadError = shallowRef<Error | null>(null)
  const directionLabel = computed(() => (detail.data?.direction === 'payment' ? '付款' : '收款'))

  function formatMoney(value?: Api.Tms.BasicData.SensitiveNumber): string {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
  }

  function formatDateTime(value?: string | null): string {
    return value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '-') : '-'
  }

  const descriptionItems = computed<ArtDescriptionItem<CashTransaction>[]>(() => [
    {
      key: 'transactionNo',
      label: `${directionLabel.value}单号`,
      field: 'transactionNo',
      copyable: true
    },
    {
      key: 'status',
      label: '状态',
      field: 'status',
      dictCode: 'tmsCashTransactionStatus',
      dictDisplay: 'tag'
    },
    {
      key: 'counterpartyName',
      label: detail.data?.direction === 'receipt' ? '收款客户' : '付款承运商',
      field: 'counterpartyName'
    },
    {
      key: 'transactionDate',
      label: `${directionLabel.value}日期`,
      field: 'transactionDate',
      format: 'date'
    },
    ...(canViewField(detail.data?.fieldAccess, 'transactionAmounts')
      ? [
          {
            key: 'amount',
            label: `${directionLabel.value}金额`,
            field: 'amount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'allocatedAmount',
            label: '已核销金额',
            field: 'allocatedAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'unallocatedAmount',
            label: '未核销金额',
            field: 'unallocatedAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          }
        ]
      : []),
    {
      key: 'paymentMethod',
      label: `${directionLabel.value}方式`,
      field: 'paymentMethod',
      dictCode: 'tmsCashPaymentMethod',
      dictDisplay: 'text'
    },
    ...(canViewField(detail.data?.fieldAccess, 'bankDetails')
      ? [
          {
            key: 'fundAccount',
            label: '资金账户',
            field: 'fundAccount' as const,
            formatter: (_value: unknown, row: CashTransaction) =>
              row.fundAccount
                ? `${row.fundAccount.accountName} · ${row.fundAccount.accountNoMasked}`
                : '历史未关联'
          },
          {
            key: 'bankReference',
            label: '银行流水号',
            field: 'bankReference' as const,
            copyable: detail.data?.bankReference !== '***'
          }
        ]
      : []),
    { key: 'createBy', label: '登记人', field: 'createBy' },
    {
      key: 'createTime',
      label: '登记时间',
      field: 'createTime',
      formatter: (value) => formatDateTime(value as string | null | undefined)
    },
    { key: 'remark', label: '备注', field: 'remark' },
    ...(detail.data?.status === 'voided'
      ? [{ key: 'voidReason', label: '作废原因', field: 'voidReason', span: 2 }]
      : [])
  ])

  const allocationColumns = computed<ColumnOption<DetailAllocation>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 66 },
    {
      prop: 'statementNo',
      label: '对账单号',
      width: 190,
      formatter: (row) => row.statement?.statementNo ?? '-'
    },
    {
      prop: 'period',
      label: '对账账期',
      minWidth: 195,
      formatter: (row) =>
        row.statement ? `${row.statement.periodStart} 至 ${row.statement.periodEnd}` : '-'
    },
    ...(canViewField(detail.data?.fieldAccess, 'transactionAmounts')
      ? [
          {
            prop: 'allocatedAmount',
            label: '核销金额',
            width: 130,
            align: 'right' as const,
            formatter: (row: DetailAllocation) => formatMoney(row.allocatedAmount)
          }
        ]
      : []),
    {
      prop: 'allocatedAt',
      label: '核销时间',
      width: 165,
      formatter: (row) => formatDateTime(row.allocatedAt)
    },
    {
      prop: 'allocatedBy',
      label: '核销人',
      width: 120,
      showOverflowTooltip: true
    },
    {
      prop: 'isActive',
      label: '状态',
      width: 95,
      formatter: (row) =>
        row.isActive ? <ElTag type="success">有效</ElTag> : <ElTag type="info">已撤销</ElTag>
    },
    {
      prop: 'operation',
      label: '操作',
      width: 86,
      fixed: 'right',
      formatter: (row) =>
        row.isActive && canEditField(detail.data?.fieldAccess, 'transactionAmounts') ? (
          <ElTooltip content="撤销核销" placement="top">
            <ArtButtonTable
              icon="ri:arrow-go-back-line"
              iconClass="bg-error/12 text-error"
              onClick={() => void handleReverse(row)}
            />
          </ElTooltip>
        ) : (
          <ElTooltip content={row.reverseReason || '核销已撤销'} placement="top">
            <ElTag type="info">查看</ElTag>
          </ElTooltip>
        )
    }
  ])

  async function loadDetail(id: string): Promise<void> {
    detail.loading = true
    loadError.value = null
    try {
      const { data } = await fetchCashTransactionDetail(id)
      detail.data = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('收付款详情加载失败')
    } finally {
      detail.loading = false
    }
  }

  function retryLoad(): void {
    if (detail.data?.id) void loadDetail(detail.data.id)
  }

  async function handleReverse(row: DetailAllocation): Promise<void> {
    try {
      const reason = await promptReason(
        `撤销后将释放 ${formatMoney(row.allocatedAmount)}，并自动回退收款及对账单状态。`,
        '撤销核销',
        {
          confirmButtonText: '确认撤销',
          placeholder: '请填写撤销原因',
          emptyMessage: '撤销原因不能为空'
        }
      )
      if (detail.data?.direction === 'payment') {
        await reverseCarrierCashAllocation(row.id, reason)
      } else {
        await reverseCashAllocation(row.id, reason)
      }
      if (detail.data) await loadDetail(detail.data.id)
      emit('changed')
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleOpen(row: CashTransaction): Promise<void> {
    detail.data = row
    await drawerRef.value?.handleOpen(row, {
      title: `${row.direction === 'payment' ? '付款' : '收款'}详情 · ${row.transactionNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .cash-detail {
    &__section {
      margin-top: var(--art-space-6);
    }

    &__vouchers {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__voucher {
      width: 112px;
      height: 112px;
      border-radius: var(--el-border-radius-base);
    }

    &__restricted {
      padding: var(--art-space-4);
      color: var(--el-text-color-secondary);
      text-align: center;
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }
  }
</style>
