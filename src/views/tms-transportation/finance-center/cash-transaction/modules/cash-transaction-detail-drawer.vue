<template>
  <ArtDrawer ref="drawerRef">
    <ElSkeleton :loading="detail.loading" animated :rows="8">
      <div v-if="detail.data" class="cash-detail">
        <ArtSectionTitle>{{ directionLabel }}概览</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="收款单号">{{ detail.data.transactionNo }}</ElDescriptionsItem>
          <ElDescriptionsItem label="状态">
            <ArtDictDisplay
              dict-code="tmsCashTransactionStatus"
              :value="detail.data.status"
              display="tag"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem
            :label="detail.data.direction === 'receipt' ? '收款客户' : '付款承运商'"
          >
            {{ detail.data.counterpartyName }}
          </ElDescriptionsItem>
          <ElDescriptionsItem :label="`${directionLabel}日期`">
            {{ detail.data.transactionDate }}
          </ElDescriptionsItem>
          <ElDescriptionsItem :label="`${directionLabel}金额`">
            {{ formatMoney(detail.data.amount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="已核销金额">
            {{ formatMoney(detail.data.allocatedAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="未核销金额">
            {{ formatMoney(detail.data.unallocatedAmount) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem :label="`${directionLabel}方式`">
            <ArtDictDisplay
              dict-code="tmsCashPaymentMethod"
              :value="detail.data.paymentMethod"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="银行流水号">
            {{ detail.data.bankReference || '-' }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="登记人">
            {{ detail.data.createBy || '-' }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="登记时间">
            {{ formatDateTime(detail.data.createTime) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="备注">
            {{ detail.data.remark || '-' }}
          </ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.data.status === 'voided'" label="作废原因" :span="2">
            {{ detail.data.voidReason || '-' }}
          </ElDescriptionsItem>
        </ElDescriptions>

        <template v-if="detail.data.voucherUrls?.length">
          <ArtSectionTitle class="cash-detail__section">{{ directionLabel }}凭证</ArtSectionTitle>
          <div class="cash-detail__vouchers">
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
        </template>

        <ArtSectionTitle class="cash-detail__section">核销记录</ArtSectionTitle>
        <ArtTable
          :data="detail.data.allocations ?? []"
          :columns="allocationColumns"
          :pagination="false"
          :show-table-header="false"
          max-height="430px"
          border
        />
      </div>
    </ElSkeleton>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElMessageBox, ElTag, ElTooltip } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
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
  } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsCashTransactionDetailDrawer' })

  type CashTransaction = Api.Tms.Finance.CashTransactionRecord
  interface DetailAllocation {
    id: string
    allocatedAmount: number
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
  const directionLabel = computed(() => (detail.data?.direction === 'payment' ? '付款' : '收款'))

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function formatDateTime(value?: string | null): string {
    return value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm') ?? '-') : '-'
  }

  const allocationColumns: ColumnOption<DetailAllocation>[] = [
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
    {
      prop: 'allocatedAmount',
      label: '核销金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.allocatedAmount)
    },
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
        row.isActive ? (
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
  ]

  async function loadDetail(id: string): Promise<void> {
    detail.loading = true
    try {
      const { data } = await fetchCashTransactionDetail(id)
      detail.data = data
    } finally {
      detail.loading = false
    }
  }

  async function handleReverse(row: DetailAllocation): Promise<void> {
    try {
      const { value } = await ElMessageBox.prompt(
        `撤销后将释放 ${formatMoney(row.allocatedAmount)}，并自动回退收款及对账单状态。`,
        '撤销核销',
        {
          type: 'warning',
          confirmButtonText: '确认撤销',
          cancelButtonText: '取消',
          inputType: 'textarea',
          inputPlaceholder: '请填写撤销原因',
          inputValidator: (text) => Boolean(text?.trim()) || '撤销原因不能为空'
        }
      )
      if (detail.data?.direction === 'payment') {
        await reverseCarrierCashAllocation(row.id, value.trim())
      } else {
        await reverseCashAllocation(row.id, value.trim())
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
      size: 'min(1080px, 94vw)',
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
      margin-top: 24px;
    }

    &__vouchers {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
    }

    &__voucher {
      width: 112px;
      height: 112px;
      border-radius: var(--el-border-radius-base);
    }
  }
</style>
