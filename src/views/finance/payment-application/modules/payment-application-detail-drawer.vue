<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无付款申请详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="payment-application-detail">
        <ArtSectionTitle>申请信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <section class="payment-application-detail__section">
          <ArtSectionTitle>付款明细</ArtSectionTitle>
          <ArtTable
            :data="detail.items ?? []"
            :columns="itemColumns"
            :pagination="false"
            :show-table-header="false"
            table-layout="fixed"
            empty-height="180px"
            max-height="320px"
            empty-text="暂无付款明细"
            border
          />
        </section>

        <section v-if="detail.basisUrls?.length" class="payment-application-detail__section">
          <ArtSectionTitle>付款依据</ArtSectionTitle>
          <div class="payment-application-detail__evidence">
            <ElImage
              v-for="url in detail.basisUrls"
              :key="url"
              :src="url"
              :preview-src-list="detail.basisUrls"
              fit="cover"
              class="payment-application-detail__evidence-image"
              preview-teleported
            />
          </div>
        </section>

        <section class="payment-application-detail__section">
          <WorkflowBusinessHistory
            business-type="tms_carrier_payment_application"
            :business-id="detail.id"
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
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import { fetchCarrierPaymentApplicationDetail } from '@/api/finance'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinancePaymentApplicationDetailDrawer' })

  type Application = Api.Finance.CarrierPaymentApplicationRecord
  type ApplicationItem = Api.Finance.CarrierPaymentApplicationItem

  const drawerRef = ref<ArtDrawerExpose<Application>>()
  const detail = shallowRef<Application>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const descriptionItems: ArtDescriptionItem<Application>[] = [
    { key: 'applicationNo', label: '付款申请单号', field: 'applicationNo', copyable: true },
    {
      key: 'status',
      label: '申请状态',
      field: 'status',
      dictCode: 'tmsCarrierPaymentApplicationStatus'
    },
    { key: 'carrierName', label: '承运商', field: 'carrierName' },
    { key: 'amount', label: '申请金额', field: 'amount', format: 'money' },
    {
      key: 'plannedPaymentDate',
      label: '计划付款日期',
      field: 'plannedPaymentDate',
      format: 'date'
    },
    {
      key: 'paymentMethod',
      label: '付款方式',
      field: 'paymentMethod',
      dictCode: 'tmsCashPaymentMethod'
    },
    {
      key: 'statementCount',
      label: '对账单数',
      field: 'statementCount',
      formatter: (value) => `${Number(value ?? 0)} 份`
    },
    {
      key: 'paidTransactionNo',
      label: '付款流水号',
      field: 'paidTransactionNo',
      copyable: true
    },
    { key: 'remark', label: '申请说明', field: 'remark', span: 2 },
    { key: 'reviewRemark', label: '审批意见', field: 'reviewRemark', span: 2 },
    { key: 'cancelReason', label: '取消原因', field: 'cancelReason', span: 2 }
  ]

  const itemColumns: ColumnOption<ApplicationItem>[] = [
    { prop: 'statementNoSnapshot', label: '对账单号', minWidth: 190 },
    {
      prop: 'statementAmountSnapshot',
      label: '对账金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.statementAmountSnapshot)
    },
    {
      prop: 'outstandingAmountSnapshot',
      label: '申请时未付',
      width: 135,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.outstandingAmountSnapshot)
    },
    {
      prop: 'appliedAmount',
      label: '本次付款',
      width: 135,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.appliedAmount)
    }
  ]

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchCarrierPaymentApplicationDetail(id)
      detail.value = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('付款申请详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: Application): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `付款申请详情 · ${row.applicationNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .payment-application-detail {
    min-width: 0;

    &__section {
      margin-top: var(--art-space-6);
    }

    &__evidence {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__evidence-image {
      width: 96px;
      height: 96px;
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--el-border-radius-base);
    }
  }
</style>
