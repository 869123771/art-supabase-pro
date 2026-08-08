<template>
  <ArtDrawer ref="drawerRef">
    <ElSkeleton v-if="state.loading" :rows="8" animated />
    <template v-else-if="state.detail">
      <section class="reimbursement-detail__summary art-card-xs">
        <div>
          <span>报销金额</span>
          <strong>{{ money(state.detail.totalAmount) }}</strong>
        </div>
        <div>
          <span>费用笔数</span>
          <strong>{{ state.detail.itemCount }}</strong>
        </div>
        <div>
          <span>关联运单</span>
          <strong>{{ state.detail.waybillCount }}</strong>
        </div>
      </section>

      <ArtSectionTitle>报销信息</ArtSectionTitle>
      <ArtDescriptions
        class="reimbursement-detail__descriptions"
        :data="state.detail"
        :items="descriptionItems"
        :columns="isCompact ? 1 : 2"
      />

      <ArtSectionTitle>逐笔核销明细</ArtSectionTitle>
      <ArtTable
        :data="state.detail.items ?? []"
        :columns="columns"
        :pagination="false"
        :show-table-header="false"
        table-layout="fixed"
        border
      />
    </template>
    <ElEmpty v-else description="报销单不存在或无权查看" />
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { useMediaQuery } from '@vueuse/core'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchExpenseReimbursementDetail } from '@/api/tms'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsExpenseReimbursementDetailDrawer' })

  type Reimbursement = Api.Tms.Finance.ExpenseReimbursementRecord
  type Item = Api.Tms.Finance.ExpenseReimbursementItem

  const isCompact = useMediaQuery('(max-width: 767px)')
  const drawerRef = ref<ArtDrawerExpose<Reimbursement>>()
  const state = reactive<{ loading: boolean; detail?: Reimbursement }>({
    loading: false,
    detail: undefined
  })
  const descriptionItems: ArtDescriptionItem<Reimbursement>[] = [
    { key: 'reimbursementNo', label: '报销单号', field: 'reimbursementNo', copyable: true },
    {
      key: 'status',
      label: '审批状态',
      field: 'status',
      dictCode: 'tmsReimbursementApprovalStatus',
      dictDisplay: 'tag'
    },
    { key: 'applicantNameSnapshot', label: '申请人', field: 'applicantNameSnapshot' },
    { key: 'payeeName', label: '收款人', field: 'payeeName' },
    { key: 'plannedPaymentDate', label: '计划付款日', field: 'plannedPaymentDate' },
    {
      key: 'paymentMethod',
      label: '付款方式',
      field: 'paymentMethod',
      dictCode: 'tmsCashPaymentMethod',
      dictDisplay: 'tag'
    },
    {
      key: 'paymentNo',
      label: '付款单号',
      value: (data: Reimbursement) => data.paymentNo || '未支付',
      copyable: true
    },
    {
      key: 'paymentReference',
      label: '银行流水',
      value: (data: Reimbursement) => data.paymentReference || '--',
      copyable: true
    },
    {
      key: 'remark',
      label: '报销说明',
      value: (data: Reimbursement) => data.remark || '--',
      span: 2
    }
  ]
  const columns: ColumnOption<Item>[] = [
    { prop: 'expenseNoSnapshot', label: '申报单号', width: 190 },
    { prop: 'waybillNoSnapshot', label: '运单号', width: 180 },
    {
      prop: 'expenseTypeSnapshot',
      label: '费用类型',
      width: 130,
      dict: { code: 'tmsInTransitExpenseType', display: 'tag' }
    },
    {
      prop: 'occurredAtSnapshot',
      label: '发生日期',
      width: 120,
      formatter: (row) => formatWithDayjs(row.occurredAtSnapshot, 'YYYY-MM-DD')
    },
    {
      prop: 'amountSnapshot',
      label: '核销金额',
      width: 130,
      align: 'right',
      formatter: (row) => money(row.amountSnapshot)
    }
  ]

  function money(value?: number | null): string {
    return formatCurrencyValue(Number(value ?? 0))
  }

  async function handleOpen(row: Reimbursement): Promise<void> {
    state.detail = undefined
    await drawerRef.value?.handleOpen(row, {
      title: `报销详情 · ${row.reimbursementNo}`,
      subtitle: '费用申报、成本台账与付款核销一一对应',
      size: 'xl',
      showFooter: false,
      contentHeight: 'calc(100vh - 150px)',
      loading: true,
      onOpen: async (_data, api) => {
        state.loading = true
        try {
          const { data } = await fetchExpenseReimbursementDetail(row.id)
          state.detail = data
        } finally {
          state.loading = false
          api.setLoading(false)
        }
      },
      drawerProps: { appendToBody: true, resizable: true }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .reimbursement-detail {
    &__summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: var(--art-space-3);
      padding: var(--art-space-4);
      margin-bottom: var(--art-space-5);

      > div {
        display: flex;
        flex-direction: column;
        gap: var(--art-space-1);
      }

      span {
        font-size: 12px;
        color: var(--art-text-gray-500);
      }

      strong {
        font-size: 20px;
        color: var(--art-text-gray-900);
      }
    }

    &__descriptions {
      margin-bottom: var(--art-space-5);
    }

    @media (width <= 640px) {
      &__summary {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
