<template>
  <div class="business-workspace-page art-full-height fms-accounting-page financial-reports-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="FINANCIAL STATEMENTS"
      title="财务报表"
      description="以账套为边界生成资产负债表、利润表和现金流量表，统一管理科目映射、合计公式与凭证现金流归集口径。"
      icon="ri:file-chart-line"
      :tags="[
        { label: '已记账口径', type: 'primary' },
        { label: '公式可审计', type: 'success' },
        {
          label: canEditConfig ? '口径可维护' : '口径只读',
          type: canEditConfig ? 'warning' : 'info'
        }
      ]"
      :metrics="metrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ElAlert
      :type="activeType === 'cash_flow_statement' ? 'warning' : 'info'"
      :closable="false"
      show-icon
      :title="statementNotice"
    />

    <ElTabs v-model="activeType" class="financial-reports-page__tabs" @tab-change="handleTabChange">
      <ElTabPane
        v-for="option in statementOptions"
        :key="String(option.value)"
        :name="option.value"
      >
        <template #label>
          <span class="financial-reports-page__tab-label">
            <ArtSvgIcon :icon="statementIcon(option.value)" />
            <span>
              <strong>{{ option.label }}</strong>
              <small>{{ statementCaption(option.value) }}</small>
            </span>
          </span>
        </template>
      </ElTabPane>
    </ElTabs>

    <ArtTableQuery
      ref="tableRef"
      v-model="search"
      class="financial-reports-page__table"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :immediate="false"
      :search-bar-props="{ span: 6, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'itemId',
        tableLayout: 'fixed',
        rowClassName: statementRowClass,
        emptyText: '暂无财务报表数据',
        emptyDescription: accountSetOptions.length
          ? '请选择账套和会计期间查询；如尚未配置，可从“取数口径”初始化标准项目。'
          : '当前没有可用账套，请先完成企业账套和会计期间配置。'
      }"
      focusable
    />

    <StatementConfigDrawer ref="configDrawerRef" @success="refreshReport" />
  </div>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../modules/accounting-select-text'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import StatementConfigDrawer from './modules/statement-config-drawer.vue'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import { useAuth } from '@/hooks/core/useAuth'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import {
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    fetchFinancialStatementReport
  } from '@/api/fms'

  defineOptions({ name: 'FinanceFinancialReports' })

  type StatementType = Api.Fms.FinancialStatementType
  type ReportRow = Api.Fms.FinancialStatementReportRecord
  type TablePageParams = Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type SearchData = Omit<Api.Fms.FinancialStatementReportParams, 'statementType'>

  const { getDictMap } = storeToRefs(useUserStore())
  const { hasAuth } = useAuth()
  const canEditConfig = computed(() => hasAuth('FinanceFinancialReports:EditConfig'))
  const activeType = ref<StatementType>('balance_sheet')
  const { ensureAccountSet } = useFinanceAccountSetPrerequisite()
  const tableRef = ref<ArtTableQueryExpose>()
  const configDrawerRef = ref<InstanceType<typeof StatementConfigDrawer>>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const periods = ref<Api.Fms.AccountingPeriodRecord[]>([])
  const reportRows = ref<ReportRow[]>([])
  const search = reactive<SearchData>({
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    periodFrom: 1,
    periodTo: 12
  })

  const statementOptions = computed(() =>
    (getDictMap.value.fmsFinancialStatementType ?? []).map((item) => ({
      label: item.label,
      value: item.value as StatementType
    }))
  )

  const yearOptions = computed(() =>
    [...new Set(periods.value.map((item) => item.fiscalYear))]
      .sort((a, b) => b - a)
      .map((value) => ({ label: `${value} 年`, value }))
  )

  const periodOptions = computed(() =>
    periods.value
      .filter((item) => item.fiscalYear === search.fiscalYear)
      .map((item) => ({ label: `第 ${item.periodNo} 期`, value: item.periodNo }))
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        filterable: true,
        placeholder: '请选择账套',
        noDataText: ACCOUNTING_SELECT_EMPTY_TEXT.accountSet,
        onChange: (value: string) => void handleAccountSetChange(value)
      }
    },
    {
      label: '会计年度',
      key: 'fiscalYear',
      type: 'select',
      props: {
        options: yearOptions.value,
        placeholder: '请选择年度',
        disabled: !search.accountSetId,
        noDataText: search.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.fiscalYear
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet,
        onChange: handleFiscalYearChange
      }
    },
    {
      label: '起始期间',
      key: 'periodFrom',
      type: 'select',
      props: {
        options: periodOptions.value,
        placeholder: '起始期间',
        disabled: !search.accountSetId,
        noDataText: search.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.accountingPeriod
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
      }
    },
    {
      label: '截止期间',
      key: 'periodTo',
      type: 'select',
      props: {
        options: periodOptions.value,
        placeholder: '截止期间',
        disabled: !search.accountSetId,
        noDataText: search.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.accountingPeriod
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      key: 'statement-config',
      label: canEditConfig.value ? '取数口径' : '查看口径',
      icon: canEditConfig.value ? 'ri:settings-3-line' : 'ri:eye-line',
      permission: canEditConfig.value
        ? 'FinanceFinancialReports:EditConfig'
        : 'FinanceFinancialReports:ViewConfig',
      onClick: openConfiguration
    },
    {
      permission: 'FinanceFinancialReports:Export',
      type: 'export',
      exportFilename: () => `${activeStatementLabel.value}-${search.fiscalYear}年`,
      exportSheetName: activeStatementLabel.value,
      exportColumns: () => [
        { key: 'lineNo', title: '行次' },
        { key: 'itemCode', title: '项目编码', width: 16 },
        { key: 'itemName', title: '项目名称', width: 32 },
        { key: 'primaryAmount', title: primaryAmountLabel.value },
        { key: 'secondaryAmount', title: secondaryAmountLabel.value },
        {
          key: 'calculationMethod',
          title: '计算方式',
          formatter: (value) => dictLabel('fmsStatementCalculationMethod', value)
        },
        {
          key: 'mappingCount',
          title: activeType.value === 'cash_flow_statement' ? '归集笔数' : '取数规则数'
        }
      ]
    }
  ])

  const activeStatementLabel = computed(() =>
    dictLabel('fmsFinancialStatementType', activeType.value)
  )
  const primaryAmountLabel = computed(() =>
    activeType.value === 'balance_sheet' ? '年初余额' : '本期金额'
  )
  const secondaryAmountLabel = computed(() =>
    activeType.value === 'balance_sheet' ? '期末余额' : '本年累计'
  )
  const statementNotice = computed(() => {
    if (activeType.value === 'balance_sheet') {
      return '资产负债表按科目净额生成年初与期末余额；资产总计应与负债和所有者权益总计保持平衡。'
    }
    if (activeType.value === 'income_statement') {
      return '利润表按会计期间统计已记账发生额，营业利润、利润总额和净利润由可审计公式逐项计算。'
    }
    return '现金流量表来自凭证中现金及现金等价物分录的流量项目归集；未完成归集的凭证不能提交记账。'
  })

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const dataRows = reportRows.value.filter((item) => item.calculationMethod === 'mapping')
    const populatedRows = dataRows.filter((item) => Number(item.mappingCount) > 0)
    if (activeType.value === 'balance_sheet') {
      const asset = amountByCode('BS199', 'secondaryAmount')
      const liabilities = amountByCode('BS499', 'secondaryAmount')
      const difference = Math.abs(asset - liabilities)
      return [
        metric(
          'items',
          '报表项目',
          reportRows.value.length,
          '当前账套启用行',
          'ri:list-check-3',
          'primary'
        ),
        metric('assets', '资产总计', money(asset), '期末口径', 'ri:building-2-line', 'success'),
        metric(
          'liabilities',
          '负债与权益',
          money(liabilities),
          '期末口径',
          'ri:scales-3-line',
          'warning'
        ),
        metric(
          'balance',
          '报表平衡',
          difference < 0.005 ? '平衡' : '待核对',
          `差额 ${money(difference)}`,
          'ri:checkbox-circle-line',
          difference < 0.005 ? 'success' : 'danger'
        )
      ]
    }
    const totalCode = activeType.value === 'income_statement' ? 'IS399' : 'CF399'
    return [
      metric(
        'items',
        '报表项目',
        reportRows.value.length,
        '当前账套启用行',
        'ri:list-check-3',
        'primary'
      ),
      metric(
        'coverage',
        activeType.value === 'cash_flow_statement' ? '已归集项目' : '已有取数行',
        populatedRows.length,
        `共 ${dataRows.length} 个明细行`,
        'ri:links-line',
        'info'
      ),
      metric(
        'period',
        activeType.value === 'income_statement' ? '本期净利润' : '本期净增加额',
        money(amountByCode(totalCode, 'primaryAmount')),
        '当前期间范围',
        'ri:line-chart-line',
        'success'
      ),
      metric(
        'year',
        activeType.value === 'income_statement' ? '本年净利润' : '本年净增加额',
        money(amountByCode(totalCode, 'secondaryAmount')),
        '年初至截止期间',
        'ri:bar-chart-box-line',
        'warning'
      )
    ]
  })

  function metric(
    key: string,
    label: string,
    value: string | number,
    description: string,
    icon: string,
    tone: NonNullable<BusinessWorkspaceMetric['tone']>
  ): BusinessWorkspaceMetric {
    return { key, label, value, description, icon, tone }
  }

  function money(value: number): string {
    return formatCurrencyValue(Number(value || 0))
  }

  function amountByCode(code: string, key: 'primaryAmount' | 'secondaryAmount'): number {
    return Number(reportRows.value.find((item) => item.itemCode === code)?.[key] ?? 0)
  }

  function dictLabel(code: string, value: unknown): string {
    if (value === null || value === undefined || value === '') return ''
    return (
      (getDictMap.value[code] ?? []).find((item) => String(item.value) === String(value))?.label ??
      String(value)
    )
  }

  function statementIcon(value: unknown): string {
    if (value === 'balance_sheet') return 'ri:scales-3-line'
    if (value === 'income_statement') return 'ri:line-chart-line'
    return 'ri:water-flash-line'
  }

  function statementCaption(value: unknown): string {
    if (value === 'balance_sheet') return '年初与期末财务状况'
    if (value === 'income_statement') return '本期与本年经营成果'
    return '现金流入、流出与净额'
  }

  function columnsFactory(): ColumnOption<ReportRow>[] {
    return [
      { prop: 'lineNo', label: '行次', width: 72, align: 'center', fixed: 'left' },
      {
        prop: 'itemName',
        label: '报表项目',
        minWidth: 300,
        fixed: 'left',
        formatter: (row) => (
          <div
            class="financial-reports-page__item"
            style={{ paddingLeft: `${Math.max(row.itemLevel - 1, 0) * 16}px` }}
          >
            <div>
              <strong>{row.itemName}</strong>
              {row.displayStyle !== 'normal' ? (
                <ElTag
                  size="small"
                  type={row.displayStyle === 'total' ? 'success' : 'primary'}
                  effect="plain"
                >
                  {dictLabel('fmsStatementDisplayStyle', row.displayStyle)}
                </ElTag>
              ) : null}
            </div>
            <small translate="no">{row.itemCode}</small>
          </div>
        )
      },
      {
        prop: 'primaryAmount',
        label: primaryAmountLabel.value,
        width: 170,
        align: 'right',
        formatter: (row) => (row.calculationMethod === 'label' ? '--' : money(row.primaryAmount))
      },
      {
        prop: 'secondaryAmount',
        label: secondaryAmountLabel.value,
        width: 170,
        align: 'right',
        formatter: (row) => (row.calculationMethod === 'label' ? '--' : money(row.secondaryAmount))
      },
      {
        prop: 'calculationMethod',
        label: '计算方式',
        width: 112,
        dict: { code: 'fmsStatementCalculationMethod', display: 'tag' }
      },
      {
        prop: 'mappingCount',
        label: activeType.value === 'cash_flow_statement' ? '归集笔数' : '取数规则数',
        width: 108,
        align: 'right',
        formatter: (row) => (row.calculationMethod === 'label' ? '--' : row.mappingCount)
      }
    ]
  }

  function statementRowClass({ row }: { row: Record<string, unknown> }): string {
    return `financial-reports-page__row--${String(row.displayStyle || 'normal')}`
  }

  function pagedResult(rows: ReportRow[], params: TablePageParams) {
    const { from, to } = pageInfoHandler(params)
    return { data: rows.slice(from, to + 1), total: rows.length }
  }

  async function fetchTableData(params: SearchData & TablePageParams) {
    if (!params.accountSetId || !params.fiscalYear) {
      reportRows.value = []
      return pagedResult([], params)
    }
    const periodFrom = Math.min(Number(params.periodFrom || 1), Number(params.periodTo || 12))
    const periodTo = Math.max(Number(params.periodFrom || 1), Number(params.periodTo || 12))
    search.periodFrom = periodFrom
    search.periodTo = periodTo
    const { data } = await fetchFinancialStatementReport({
      accountSetId: params.accountSetId,
      statementType: activeType.value,
      fiscalYear: params.fiscalYear,
      periodFrom,
      periodTo
    })
    reportRows.value = data ?? []
    return pagedResult(reportRows.value, params)
  }

  async function handleAccountSetChange(value: string): Promise<void> {
    search.accountSetId = value || ''
    periods.value = []
    if (!value) return
    const { data } = await fetchAccountingPeriodList(value)
    periods.value = data ?? []
    if (!yearOptions.value.some((item) => item.value === search.fiscalYear)) {
      search.fiscalYear = yearOptions.value[0]?.value ?? new Date().getFullYear()
    }
    handleFiscalYearChange()
  }

  function handleFiscalYearChange(): void {
    search.periodFrom = periodOptions.value[0]?.value ?? 1
    search.periodTo = periodOptions.value.at(-1)?.value ?? 12
  }

  function handleTabChange(): void {
    reportRows.value = []
    void nextTick(() => tableRef.value?.getData())
  }

  async function openConfiguration(): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: canEditConfig.value ? '维护财务报表取数口径' : '查看财务报表取数口径',
        activeRequired: true,
        available: Boolean(search.accountSetId)
      }))
    )
      return
    await configDrawerRef.value?.handleOpen(search.accountSetId, activeType.value)
  }

  function refreshReport(): void {
    void tableRef.value?.getData()
  }

  async function initialize(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    search.accountSetId = accountSetOptions.value[0]?.value ?? ''
    if (!search.accountSetId) return
    await handleAccountSetChange(search.accountSetId)
    await nextTick()
    await tableRef.value?.getData()
  }

  onMounted(() => void initialize())
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .financial-reports-page {
    @include accounting.accounting-workspace-layout;

    &__tabs {
      flex: 0 0 auto;

      :deep(.el-tabs__header) {
        margin: 0;
      }

      :deep(.el-tabs__nav-wrap) {
        padding-inline: var(--art-space-2);
      }

      :deep(.el-tabs__item) {
        height: 58px;
        padding-inline: var(--art-space-4);
      }

      :deep(.el-tabs__content) {
        display: none;
      }
    }

    &__tab-label {
      display: flex;
      gap: var(--art-space-2);
      align-items: center;

      > svg {
        flex: 0 0 auto;
        width: 19px;
        height: 19px;
      }

      > span {
        display: flex;
        flex-direction: column;
        min-width: 0;
        line-height: 1.25;
      }

      strong {
        font-size: 14px;
      }

      small {
        margin-top: 2px;
        font-size: 11px;
        color: var(--art-text-gray-500);
      }
    }

    &__table {
      flex: 1 1 auto;
      min-height: 0;
    }

    &__item {
      display: flex;
      flex-direction: column;
      gap: 3px;
      min-width: 0;

      > div {
        display: flex;
        gap: var(--art-space-2);
        align-items: center;
        min-width: 0;
      }

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        font-size: 11px;
        color: var(--art-text-gray-500);
      }
    }

    :deep(.financial-reports-page__row--subtotal td) {
      font-weight: 600;
      background: var(--el-fill-color-light) !important;
    }

    :deep(.financial-reports-page__row--total td) {
      font-weight: 700;
      color: var(--el-color-primary-dark-2);
      background: var(--el-color-primary-light-9) !important;
    }
  }

  @media (width <= 720px) {
    .financial-reports-page {
      &__tabs :deep(.el-tabs__item) {
        height: 48px;
        padding-inline: var(--art-space-3);
      }

      &__tab-label small {
        display: none;
      }
    }
  }
</style>
