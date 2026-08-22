<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无资金调拨详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="fund-transfer-detail">
        <ArtSectionTitle>调拨信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <section
          v-if="showTransferFlow"
          class="fund-transfer-detail__flow"
          :class="{ 'is-amount-only': !canViewAccounts }"
          aria-label="资金流向"
        >
          <div v-if="canViewAccounts">
            <small>转出账户</small>
            <strong>{{ detail.sourceAccountName || '--' }}</strong>
            <span>{{ detail.sourceAccountNoMasked || '--' }}</span>
          </div>
          <div class="fund-transfer-detail__arrow">
            <ArtSvgIcon icon="ri:arrow-right-line" />
            <strong v-if="canViewAmounts">{{ formatMoney(detail.amount) }}</strong>
            <small v-if="canViewAmounts && hasFeeAmount">
              手续费 {{ formatMoney(detail.feeAmount) }}
            </small>
          </div>
          <div v-if="canViewAccounts">
            <small>转入账户</small>
            <strong>{{ detail.targetAccountName || '--' }}</strong>
            <span>{{ detail.targetAccountNoMasked || '--' }}</span>
          </div>
        </section>

        <section class="fund-transfer-detail__section">
          <ArtSectionTitle>操作轨迹</ArtSectionTitle>
          <ArtTable
            :data="actions"
            :columns="actionColumns"
            :pagination="false"
            :show-table-header="false"
            table-layout="fixed"
            empty-height="160px"
            max-height="320px"
            empty-text="暂无操作记录"
            border
          />
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import type { ColumnOption } from '@/types'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchFundTransferActions, fetchFundTransferDetail } from '@/api/fms'
  import { canViewField } from '@/utils/field-permission'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'FinanceFundTransferDetailDrawer' })

  type Transfer = Api.Fms.FundTransferRecord
  type Action = Api.Fms.FundTransferActionRecord

  const drawerRef = ref<ArtDrawerExpose<Transfer>>()
  const detail = shallowRef<Transfer>()
  const actions = shallowRef<Action[]>([])
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const canViewAccounts = computed(() =>
    canViewField(detail.value?.fieldAccess, 'transferAccounts')
  )
  const canViewAmounts = computed(() => canViewField(detail.value?.fieldAccess, 'transferAmounts'))
  const canViewBankReference = computed(() =>
    canViewField(detail.value?.fieldAccess, 'bankReference')
  )
  const showTransferFlow = computed(() => canViewAccounts.value || canViewAmounts.value)
  const hasFeeAmount = computed(() => {
    const value = detail.value?.feeAmount
    if (typeof value === 'string') return Boolean(value.trim())
    return Number(value) > 0
  })
  const descriptionItems = computed<ArtDescriptionItem<Transfer>[]>(() => [
    { key: 'transferNo', label: '调拨单号', field: 'transferNo', copyable: true },
    { key: 'status', label: '调拨状态', field: 'status', dictCode: 'fmsFundTransferStatus' },
    { key: 'transferDate', label: '调拨日期', field: 'transferDate', format: 'date' },
    { key: 'currencyCode', label: '币种', field: 'currencyCode' },
    ...(canViewBankReference.value
      ? [
          {
            key: 'bankReference',
            label: '银行参考号',
            field: 'bankReference',
            copyable: true
          } as ArtDescriptionItem<Transfer>
        ]
      : []),
    { key: 'createBy', label: '创建人', field: 'createBy' },
    { key: 'purpose', label: '调拨用途', field: 'purpose', span: 2 },
    { key: 'reviewRemark', label: '审批意见', field: 'reviewRemark', span: 2 },
    { key: 'reversalReason', label: '冲销原因', field: 'reversalReason', span: 2 }
  ])

  const actionColumns: ColumnOption<Action>[] = [
    {
      prop: 'actionTime',
      label: '时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.actionTime, 'YYYY-MM-DD HH:mm') || '--'
    },
    { prop: 'actionBy', label: '操作人', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'toStatus',
      label: '状态',
      width: 105,
      dict: { code: 'fmsFundTransferStatus', display: 'tag' }
    },
    { prop: 'actionRemark', label: '说明', minWidth: 180, showOverflowTooltip: true }
  ]

  function formatMoney(value: Api.Tms.BasicData.SensitiveNumber | undefined): string {
    if (value === null || value === undefined || value === '') return '--'
    return formatCurrencyValue(value, detail.value?.currencyCode)
  }

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const [detailResult, actionResult] = await Promise.all([
        fetchFundTransferDetail(id),
        fetchFundTransferActions(id)
      ])
      detail.value = detailResult.data ?? undefined
      actions.value = actionResult.data ?? []
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('资金调拨详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: Transfer): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `资金调拨详情 · ${row.transferNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .fund-transfer-detail {
    min-width: 0;

    &__flow {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
      gap: 20px;
      align-items: center;
      padding: 20px;
      margin-top: 20px;
      background: color-mix(in srgb, var(--el-color-primary) 4%, var(--default-box-color));
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > div:not(.fund-transfer-detail__arrow) {
        display: grid;
        gap: 6px;
        min-width: 0;

        strong,
        span {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        small,
        span {
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__arrow {
      display: grid;
      justify-items: center;
      color: var(--el-color-primary);
    }

    &__flow.is-amount-only {
      grid-template-columns: minmax(0, 1fr);
    }

    &__section {
      margin-top: var(--art-space-6);
    }

    @media (width <= 700px) {
      &__flow {
        grid-template-columns: 1fr;
      }

      &__arrow :deep(.art-svg-icon) {
        transform: rotate(90deg);
      }
    }
  }
</style>
