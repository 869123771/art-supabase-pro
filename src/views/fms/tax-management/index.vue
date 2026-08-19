<template>
  <div class="business-workspace-page art-full-height fms-accounting-page tax-management-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="TAX COMPLIANCE LEDGER"
      title="税务管理"
      description="按账套、会计期间和税种归集销项、进项及调整，形成测算、复核、申报、缴纳全流程税务台账。"
      icon="ri:government-line"
      :tags="[
        { label: '税率可配置', type: 'primary' },
        { label: '申报留痕', type: 'warning' },
        { label: '缴税入账', type: 'success' }
      ]"
      :metrics="metrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableRef" />
      </template>
    </BusinessWorkspaceHeader>
    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户税务台账；税额、复核、申报和缴纳仅平台超级管理员可维护。"
    />
    <ArtTableQuery
      ref="tableRef"
      v-model="table.search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无税务期间',
        emptyDescription: isPlatformSuper
          ? '按开放会计期间创建税种台账。'
          : '当前租户暂无可查看的税务数据。'
      }"
      focusable
    />
    <TaxPeriodDialog ref="dialogRef" @success="refreshAll" />
    <TaxDetailDrawer ref="drawerRef" @success="refreshAll" />
    <FundExecutionDialog ref="fundExecutionRef" @success="refreshAll" />
  </div>
</template>

<script setup lang="tsx">
  import { storeToRefs } from 'pinia'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import FundExecutionDialog, {
    type FundExecutionOptions,
    type FundExecutionPayload
  } from '../modules/fund-execution-dialog.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    actTaxPeriod,
    fetchAccountSetOptions,
    fetchTaxPeriodList,
    fetchTaxSummary
  } from '@/api/fms'
  import TaxPeriodDialog from './modules/tax-period-dialog.vue'
  import TaxDetailDrawer from './modules/tax-detail-drawer.vue'
  defineOptions({ name: 'FinanceTaxManagement' })
  type Row = Api.Fms.TaxPeriodRecord
  type SearchParams = Api.Fms.TaxPeriodSearchParams
  type TableParams = SearchParams & { current: number; size: number }
  const emptySummary = (): Api.Fms.TaxSummary => ({
    periodCount: 0,
    outputTaxAmount: 0,
    inputTaxAmount: 0,
    payableAmount: 0,
    pendingCount: 0
  })
  const { confirmAction, promptReason } = useArtFeedback()
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: (row?: Row) => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Row) => Promise<void> }>()
  const fundExecutionRef = ref<{
    handleOpen: (
      options: FundExecutionOptions,
      onSubmit: (payload: FundExecutionPayload) => Promise<void>
    ) => Promise<void>
  }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const summary = ref(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, taxType: undefined, status: undefined }
  })
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'period',
      label: '税务期间',
      value: summary.value.periodCount,
      description: `${summary.value.pendingCount} 个待完成`,
      icon: 'ri:calendar-check-line',
      tone: 'primary'
    },
    {
      key: 'output',
      label: '销项税额',
      value: formatCurrencyValue(summary.value.outputTaxAmount),
      description: '本账套累计',
      icon: 'ri:arrow-up-circle-line',
      tone: 'warning'
    },
    {
      key: 'input',
      label: '进项税额',
      value: formatCurrencyValue(summary.value.inputTaxAmount),
      description: '本账套累计',
      icon: 'ri:arrow-down-circle-line',
      tone: 'success'
    },
    {
      key: 'payable',
      label: '应纳税额',
      value: formatCurrencyValue(summary.value.payableAmount),
      description: '测算应缴口径',
      icon: 'ri:government-line',
      tone: 'info'
    }
  ])
  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        clearable: false,
        filterable: true,
        placeholder: '选择核算账套'
      }
    },
    {
      label: '税种',
      key: 'taxType',
      type: 'select',
      props: {
        options: getDictMap.value.fmsTaxType ?? [],
        clearable: true,
        placeholder: '全部税种'
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsTaxPeriodStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    }
  ])
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [
          {
            type: 'add',
            label: '新建税务期间',
            onClick: () =>
              void runWithAccountSet(
                {
                  actionLabel: '新建税务期间',
                  activeRequired: true,
                  accountSetId: table.search.accountSetId,
                  foundationRequired: true,
                  available: accountSetOptions.value.length > 0
                },
                () => dialogRef.value?.handleOpen()
              )
          }
        ]
      : []
  )
  function columnsFactory(): ColumnOption<Row>[] {
    return [
      {
        prop: 'taxType',
        label: '税种',
        minWidth: 150,
        fixed: 'left',
        dict: { code: 'fmsTaxType' }
      },
      {
        prop: 'period',
        label: '会计期间',
        minWidth: 130,
        formatter: (row) =>
          row.period ? `${row.period.fiscalYear} 年第 ${row.period.periodNo} 期` : '--'
      },
      {
        prop: 'outputTaxAmount',
        label: '销项税额',
        minWidth: 125,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.outputTaxAmount)
      },
      {
        prop: 'inputTaxAmount',
        label: '进项税额',
        minWidth: 125,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.inputTaxAmount)
      },
      {
        prop: 'adjustmentAmount',
        label: '调整金额',
        minWidth: 125,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.adjustmentAmount)
      },
      {
        prop: 'payableAmount',
        label: '应纳税额',
        minWidth: 125,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.payableAmount)
      },
      {
        prop: 'filingReference',
        label: '申报凭证号',
        minWidth: 150,
        formatter: (row) => row.filingReference || '--'
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsTaxPeriodStatus', display: 'tag' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: isPlatformSuper.value ? 160 : 76,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="view" onClick={() => void drawerRef.value?.handleOpen(row)} />
            {isPlatformSuper.value && ['draft', 'calculated'].includes(row.status) ? (
              <ArtButtonTable type="edit" onClick={() => void dialogRef.value?.handleOpen(row)} />
            ) : null}
            {isPlatformSuper.value && actions(row).length ? (
              <ArtButtonMore
                list={actions(row)}
                onClick={(item: ButtonMoreItem) => void handleAction(item, row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }
  function actions(row: Row): ButtonMoreItem[] {
    if (row.status === 'calculated')
      return [
        {
          key: 'review',
          label: '复核税额',
          icon: 'ri:check-double-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'cancel',
          label: '取消期间',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'reviewed')
      return [
        {
          key: 'file',
          label: '确认申报',
          icon: 'ri:file-check-line',
          color: 'var(--el-color-primary)'
        }
      ]
    if (row.status === 'filed')
      return [
        {
          key: 'pay',
          label: '确认缴税',
          icon: 'ri:secure-payment-line',
          color: 'var(--el-color-success)'
        }
      ]
    if (row.status === 'draft')
      return [
        {
          key: 'cancel',
          label: '取消期间',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    return []
  }
  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchTaxPeriodList({ ...params, from, to })
  }
  async function loadSummary() {
    if (!table.search.accountSetId) return void (summary.value = emptySummary())
    const { data } = await fetchTaxSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
  }
  async function handleAction(item: ButtonMoreItem, row: Row) {
    try {
      if (item.key === 'cancel') {
        const reason = await promptReason('请填写取消税务期间的原因。', '取消税务期间', {
          emptyMessage: '取消原因不能为空'
        })
        await actTaxPeriod(row.id, 'cancel', { reason })
      } else if (item.key === 'file') {
        const filingReference = await promptReason(
          '请输入电子税务局申报凭证号或申报回执编号。',
          '确认税务申报',
          { emptyMessage: '申报凭证号不能为空', placeholder: '例如：VAT-202608-001' }
        )
        await actTaxPeriod(row.id, 'file', { filingReference })
      } else if (item.key === 'pay') {
        await runWithAccountSet(
          {
            actionLabel: '确认缴纳税款',
            accountSetId: row.accountSetId,
            available: true,
            foundationRequired: true,
            fundAccountRequired: true
          },
          () =>
            fundExecutionRef.value?.handleOpen(
              {
                accountSetId: row.accountSetId,
                amount: row.payableAmount,
                direction: 'outflow',
                title: `确认缴税 · ${row.taxType}`,
                subtitle: '选择实际扣款账户，系统会同步登记资金日记账和税费支付凭证',
                confirmText: '确认缴税并入账',
                accountLabel: '缴税账户'
              },
              async (payload) => {
                await actTaxPeriod(row.id, 'pay', payload)
              }
            )
        )
        return
      } else {
        await confirmAction(
          item.key === 'review'
            ? '复核后税额进入锁定状态并生成税费计提事件。'
            : '确认税款已完成缴纳并生成支付入账事件。',
          item.label,
          { type: 'warning', confirmButtonText: item.label }
        )
        await actTaxPeriod(row.id, item.key as Api.Fms.TaxPeriodAction)
      }
      await refreshAll()
    } catch {
      /* 用户取消 */
    }
  }
  async function refreshAll() {
    await Promise.all([tableRef.value?.refreshUpdate(), loadSummary()])
  }
  watch(() => table.search.accountSetId, loadSummary)
  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    table.search.accountSetId = accountSetOptions.value[0]?.value
    await loadSummary()
    await tableRef.value?.getData()
  })
</script>
<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .tax-management-page {
    @include accounting.accounting-workspace-layout;
  }
</style>
