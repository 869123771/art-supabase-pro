<template>
  <div class="business-workspace-page art-full-height fms-accounting-page fund-journal-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="TREASURY LEDGER"
      title="资金日记账"
      description="集中呈现客户收款、承运商付款、费用付款与内部调拨形成的实际资金流动，原流水与冲销流水均完整保留。"
      icon="ri:book-2-line"
      :tags="[
        { label: '业务自动登记', type: 'primary' },
        { label: '原始单据可追溯', type: 'success' },
        { label: '冲销不删记录', type: 'info' }
      ]"
      :metrics="metrics"
      @metric-click="handleMetricClick"
    />

    <ElAlert
      type="info"
      :closable="false"
      show-icon
      title="资金日记账由已实现的业务收付款与资金调拨自动生成，不允许在列表中直接修改，以保证业务单、资金流水和会计凭证链路一致。"
    />

    <ArtTableQuery
      ref="tableRef"
      v-model="table.search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :search-bar-props="{ span: 8, labelWidth: 86 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无资金流水',
        emptyDescription: '收款、付款或资金调拨执行后，系统会在此生成可审计资金流水。'
      }"
      focusable
    />
  </div>
</template>

<script setup lang="tsx">
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { fetchAccountSetOptions, fetchFundAccountOptions, fetchFundLedgerList } from '@/api/fms'

  defineOptions({ name: 'FinanceFundJournal' })

  type Ledger = Api.Fms.FundLedgerRecord
  type SearchParams = Api.Fms.FundLedgerSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  const { getDictMap } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])
  const overviewRows = ref<Ledger[]>([])
  const table = reactive<{ search: SearchParams }>({
    search: {
      keyword: '',
      accountSetId: undefined,
      fundAccountId: undefined,
      direction: undefined,
      sourceType: undefined,
      status: undefined
    }
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        clearable: true,
        filterable: true,
        placeholder: '全部账套',
        onChange: (value: string) => void loadAccountOptions(value)
      }
    },
    {
      label: '资金账户',
      key: 'fundAccountId',
      type: 'select',
      props: {
        options: accountOptions.value,
        clearable: true,
        filterable: true,
        placeholder: '全部账户'
      }
    },
    {
      label: '收支方向',
      key: 'direction',
      type: 'select',
      props: {
        options: getDictMap.value.fmsFundLedgerDirection ?? [],
        clearable: true,
        placeholder: '全部方向'
      }
    },
    {
      label: '业务来源',
      key: 'sourceType',
      type: 'select',
      props: {
        options: getDictMap.value.fmsFundLedgerSourceType ?? [],
        clearable: true,
        placeholder: '全部来源'
      }
    },
    {
      label: '入账日期',
      key: 'entryDateRange',
      type: 'daterange',
      props: { valueFormat: 'YYYY-MM-DD' }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '流水号、业务单号、摘要、对方或银行参考号' }
    }
  ])

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const rows = overviewRows.value
    const inflow = rows
      .filter((row) => row.direction === 'inflow')
      .reduce((sum, row) => sum + Number(row.amount || 0), 0)
    const outflow = rows
      .filter((row) => row.direction === 'outflow')
      .reduce((sum, row) => sum + Number(row.amount || 0), 0)
    const reversalCount = rows.filter((row) => row.reversalOfId || row.status === 'reversed').length
    return [
      {
        key: 'all',
        label: '资金流水',
        value: rows.length,
        description: '当前筛选范围记录',
        icon: 'ri:list-check-3',
        tone: 'primary',
        interactive: true,
        selected: !table.search.direction
      },
      {
        key: 'inflow',
        label: '资金流入',
        value: formatCurrencyValue(inflow),
        description: `${rows.filter((row) => row.direction === 'inflow').length} 笔`,
        icon: 'ri:arrow-left-down-line',
        tone: 'success',
        interactive: true,
        selected: table.search.direction === 'inflow'
      },
      {
        key: 'outflow',
        label: '资金流出',
        value: formatCurrencyValue(outflow),
        description: `${rows.filter((row) => row.direction === 'outflow').length} 笔`,
        icon: 'ri:arrow-right-up-line',
        tone: 'warning',
        interactive: true,
        selected: table.search.direction === 'outflow'
      },
      {
        key: 'reversal',
        label: '冲销关联',
        value: reversalCount,
        description: '原流水与反向流水均保留',
        icon: 'ri:arrow-go-back-line',
        tone: reversalCount ? 'warning' : 'info'
      }
    ]
  })

  function columnsFactory(): ColumnOption<Ledger>[] {
    return [
      {
        prop: 'entryNo',
        label: '资金流水号',
        minWidth: 190,
        fixed: 'left',
        formatter: (row) => (
          <div class="fund-ledger-identity">
            <strong translate="no">{row.entryNo}</strong>
            <small>{row.entryDate}</small>
          </div>
        )
      },
      {
        prop: 'fundAccount',
        label: '资金账户',
        minWidth: 190,
        formatter: (row) => (
          <div class="fund-ledger-identity">
            <strong>{row.fundAccount?.accountName || '--'}</strong>
            <small>{row.fundAccount?.accountNoMasked || row.fundAccountId}</small>
          </div>
        )
      },
      {
        prop: 'direction',
        label: '方向',
        width: 90,
        dict: { code: 'fmsFundLedgerDirection', display: 'tag' }
      },
      {
        prop: 'amount',
        label: '发生金额',
        width: 145,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.amount)
      },
      {
        prop: 'sourceType',
        label: '业务来源',
        width: 135,
        dict: { code: 'fmsFundLedgerSourceType', display: 'text' }
      },
      { prop: 'sourceNo', label: '业务单号', minWidth: 165, showOverflowTooltip: true },
      { prop: 'summary', label: '摘要', minWidth: 220, showOverflowTooltip: true },
      { prop: 'counterpartyName', label: '交易对方', minWidth: 150, showOverflowTooltip: true },
      { prop: 'bankReference', label: '银行参考号', minWidth: 155, showOverflowTooltip: true },
      {
        prop: 'status',
        label: '状态',
        width: 95,
        formatter: (row) =>
          row.status === 'reversed' ? '已被冲销' : row.reversalOfId ? '冲销流水' : '已入账'
      },
      {
        prop: 'postedAt',
        label: '登记时间',
        width: 165,
        formatter: (row) => formatWithDayjs(row.postedAt, 'YYYY-MM-DD HH:mm') || '--'
      }
    ]
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchFundLedgerList({ ...params, from, to })
  }

  async function loadOverview(): Promise<void> {
    const { data } = await fetchFundLedgerList({
      ...table.search,
      from: 0,
      to: 999
    })
    overviewRows.value = data ?? []
  }

  async function loadAccountOptions(accountSetId?: string): Promise<void> {
    table.search.fundAccountId = undefined
    if (!accountSetId) {
      accountOptions.value = []
      return
    }
    const { data } = await fetchFundAccountOptions({ accountSetId })
    accountOptions.value = data ?? []
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    if (!['all', 'inflow', 'outflow'].includes(String(metric.key))) return
    table.search.direction =
      metric.key === 'all' ? undefined : (metric.key as Api.Fms.FundLedgerDirection)
    void Promise.all([tableRef.value?.getData(), loadOverview()])
  }

  watch(
    () => table.search,
    () => void loadOverview(),
    { deep: true }
  )

  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    await loadOverview()
  })
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .fund-journal-page {
    @include accounting.accounting-workspace-layout;
  }

  :deep(.fund-ledger-identity) {
    display: grid;
    gap: 3px;
    min-width: 0;

    strong,
    small {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      color: var(--el-text-color-secondary);
    }
  }
</style>
