<template>
  <div class="business-workspace-page art-full-height fms-accounting-page bank-reconciliation-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="BANK RECONCILIATION"
      title="银行对账"
      description="将银行外部流水与系统资金日记账进行自动或手工匹配，在余额闭合后锁定批次并保留完整对账证据。"
      icon="ri:file-search-line"
      :tags="[
        { label: '外部事实不改业务单', type: 'primary' },
        { label: '支持分摊匹配', type: 'success' },
        { label: '余额闭环', type: 'info' }
      ]"
      :metrics="metrics"
      @metric-click="handleMetricClick"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableRef"
      v-model="table.search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 8, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无银行对账批次',
        emptyDescription: '导入银行流水后，系统将按账户、方向、金额、日期和参考号执行自动匹配。'
      }"
      focusable
    />

    <BankReconciliationImportDialog ref="importDialogRef" @success="handleImported" />
    <BankReconciliationDetailDrawer ref="drawerRef" @changed="handleChanged" />
  </div>
</template>

<script setup lang="tsx">
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { canViewField, getFieldAccess, mergeFieldAccessMaps } from '@/utils/field-permission'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAccountSetOptions,
    fetchBankReconciliationList,
    fetchFundAccountOptions
  } from '@/api/fms'
  import BankReconciliationImportDialog from './modules/bank-reconciliation-import-dialog.vue'
  import BankReconciliationDetailDrawer from './modules/bank-reconciliation-detail-drawer.vue'

  defineOptions({ name: 'FinanceBankReconciliation' })

  type Batch = Api.Fms.BankReconciliationBatchRecord
  type SearchParams = Api.Fms.BankReconciliationSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  interface ImportDialogExpose {
    handleOpen: () => Promise<void>
  }
  interface DrawerExpose {
    handleOpen: (row: Batch) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const importDialogRef = ref<ImportDialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])
  const overviewRows = ref<Batch[]>([])
  const currentRows = ref<Batch[]>([])
  const listFieldAccess = ref<Api.Fms.BankReconciliationFieldAccessMap>({})
  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess))
  )
  const canViewListField = (field: Api.Fms.BankReconciliationFieldKey): boolean =>
    canViewField(effectiveFieldAccess.value, field)
  const canViewRowField = (row: Batch, field: Api.Fms.BankReconciliationFieldKey): boolean =>
    canViewField(row.fieldAccess, field)
  const table = reactive<{ search: SearchParams }>({
    search: { keyword: '', accountSetId: undefined, fundAccountId: undefined, status: undefined }
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
      label: '对账账户',
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
      label: '对账状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsBankReconciliationStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    },
    {
      label: '对账期间',
      key: 'statementDateRange',
      type: 'daterange',
      props: { valueFormat: 'YYYY-MM-DD' }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: [
          '批次号、账户名称',
          ['read', 'edit'].includes(getFieldAccess(listFieldAccess.value, 'accountDetails'))
            ? '账号尾号'
            : '',
          ['read', 'edit'].includes(getFieldAccess(listFieldAccess.value, 'bankReferences'))
            ? '文件名'
            : ''
        ]
          .filter(Boolean)
          .join('、')
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinanceBankReconciliation:Add',
      type: 'add',
      label: '导入银行流水',
      onClick: () =>
        void runWithAccountSet(
          {
            actionLabel: '导入银行流水',
            activeRequired: true,
            accountSetId: table.search.accountSetId,
            foundationRequired: true,
            fundAccountRequired: true,
            available: accountSetOptions.value.length > 0
          },
          () => importDialogRef.value?.handleOpen()
        )
    }
  ])

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const selected = table.search.status
    const count = (status: Api.Fms.BankReconciliationStatus) =>
      overviewRows.value.filter((row) => row.status === status).length
    const unmatched = overviewRows.value.reduce(
      (sum, row) => sum + row.unmatchedCount + row.partialCount,
      0
    )
    return [
      {
        key: 'all',
        label: '对账批次',
        value: overviewRows.value.length,
        description: '当前可见批次',
        icon: 'ri:file-search-line',
        tone: 'primary',
        interactive: true,
        selected: !selected
      },
      {
        key: 'reconciling',
        label: '对账中',
        value: count('reconciling'),
        description: '仍可调整匹配关系',
        icon: 'ri:loader-2-line',
        tone: 'warning',
        interactive: true,
        selected: selected === 'reconciling'
      },
      {
        key: 'reconciled',
        label: '已完成',
        value: count('reconciled'),
        description: '余额闭合并锁定',
        icon: 'ri:checkbox-circle-line',
        tone: 'success',
        interactive: true,
        selected: selected === 'reconciled'
      },
      {
        key: 'exceptions',
        label: '待处理流水',
        value: unmatched,
        description: '未匹配与部分匹配合计',
        icon: 'ri:error-warning-line',
        tone: unmatched ? 'danger' : 'success'
      }
    ]
  })

  function columnsFactory(): ColumnOption<Batch>[] {
    return [
      {
        prop: 'batchNo',
        label: '对账批次',
        minWidth: 190,
        fixed: 'left',
        formatter: (row) => (
          <button
            class="bank-batch-link"
            type="button"
            onClick={() => void drawerRef.value?.handleOpen(row)}
          >
            <strong translate="no">{row.batchNo}</strong>
            <small>
              {canViewRowField(row, 'bankReferences')
                ? row.importedFileName || '手工录入'
                : '受控导入批次'}
            </small>
          </button>
        )
      },
      {
        prop: 'accountName',
        label: '对账账户',
        minWidth: 200,
        formatter: (row) => (
          <div class="bank-batch-account">
            <strong>{row.accountName}</strong>
            <small>
              {canViewRowField(row, 'accountDetails') && row.accountNoMasked
                ? `${row.accountNoMasked} · `
                : ''}
              {row.currencyCode}
            </small>
          </div>
        )
      },
      {
        prop: 'statementStartDate',
        label: '对账期间',
        width: 205,
        formatter: (row) => `${row.statementStartDate} 至 ${row.statementEndDate}`
      },
      ...(canViewListField('statementAmounts')
        ? ([
            {
              prop: 'closingBalance',
              label: '期末余额',
              width: 140,
              align: 'right',
              formatter: (row: Batch) => formatBankAmount(row.closingBalance, row.currencyCode)
            }
          ] as ColumnOption<Batch>[])
        : []),
      {
        prop: 'matchedCount',
        label: '匹配进度',
        width: 120,
        align: 'center',
        formatter: (row) => `${row.matchedCount + row.ignoredCount}/${row.lineCount}`
      },
      ...(canViewListField('statementAmounts')
        ? ([
            {
              prop: 'statementBalanceDifference',
              label: '余额差',
              width: 130,
              align: 'right',
              formatter: (row: Batch) =>
                formatBankAmount(row.statementBalanceDifference, row.currencyCode)
            }
          ] as ColumnOption<Batch>[])
        : []),
      {
        prop: 'status',
        label: '状态',
        width: 110,
        dict: { code: 'fmsBankReconciliationStatus', display: 'tag' }
      },
      {
        prop: 'importedAt',
        label: '导入时间',
        width: 165,
        formatter: (row) => formatWithDayjs(row.importedAt, 'YYYY-MM-DD HH:mm') || '--'
      },
      {
        prop: 'operation',
        label: '操作',
        width: 88,
        fixed: 'right',
        formatter: (row) => (
          <ArtButtonTable
            type="view"
            permission="FinanceBankReconciliation:View"
            label="进入对账"
            onClick={() => void drawerRef.value?.handleOpen(row)}
          />
        )
      }
    ]
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchBankReconciliationList({ ...params, from, to })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data ?? []
    return result
  }

  function formatBankAmount(value: unknown, currency = 'CNY'): string {
    if (value === null || value === undefined || value === '') return '--'
    return formatCurrencyValue(value, currency)
  }

  async function loadOverview(): Promise<void> {
    const result = await fetchBankReconciliationList({
      accountSetId: table.search.accountSetId,
      fundAccountId: table.search.fundAccountId,
      from: 0,
      to: 999
    })
    overviewRows.value = result.data ?? []
    listFieldAccess.value = result.fieldAccess
  }

  async function loadAccountOptions(accountSetId?: string): Promise<void> {
    table.search.fundAccountId = undefined
    if (!accountSetId) {
      accountOptions.value = []
      return
    }
    const { data } = await fetchFundAccountOptions({ accountSetId, status: 'active' })
    accountOptions.value = (data ?? []).filter((item) => item.accountType !== 'cash')
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    if (!['all', 'reconciling', 'reconciled'].includes(String(metric.key))) return
    table.search.status =
      metric.key === 'all' ? undefined : (metric.key as Api.Fms.BankReconciliationStatus)
    void tableRef.value?.getData()
  }

  async function refreshAll(mode: 'create' | 'update'): Promise<void> {
    await Promise.all([
      mode === 'create' ? tableRef.value?.refreshCreate() : tableRef.value?.refreshUpdate(),
      loadOverview()
    ])
  }

  async function handleImported(): Promise<void> {
    await refreshAll('create')
  }

  async function handleChanged(): Promise<void> {
    await refreshAll('update')
  }

  watch(
    () => [table.search.accountSetId, table.search.fundAccountId],
    () => void loadOverview()
  )

  watch(
    () => [
      canViewListField('accountDetails'),
      canViewListField('statementAmounts'),
      canViewListField('bankReferences')
    ],
    (nextVisibility, previousVisibility) => {
      if (nextVisibility.every((value, index) => value === previousVisibility?.[index])) return
      void nextTick(() => tableRef.value?.resetColumns())
    }
  )

  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    await loadOverview()
  })
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .bank-reconciliation-page {
    @include accounting.accounting-workspace-layout;
  }

  :deep(.bank-batch-link),
  :deep(.bank-batch-account) {
    display: grid;
    gap: 3px;
    min-width: 0;
    text-align: left;

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

  :deep(.bank-batch-link) {
    max-width: 100%;
    padding: 0;
    color: var(--el-color-primary);
    cursor: pointer;
    background: none;
    border: 0;
  }
</style>
