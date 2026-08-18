<template>
  <div class="business-workspace-page art-full-height fms-accounting-page ledger-center-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="FINANCIAL LEDGERS"
      title="账簿查询"
      description="基于已记账凭证形成科目余额、总账和明细账，支持按账套、会计年度、期间及辅助核算维度连续追溯。"
      icon="ri:book-open-line"
      :tags="[
        { label: '已记账口径', type: 'primary' },
        { label: '逐级钻取', type: 'success' },
        { label: '租户数据隔离', type: 'info' }
      ]"
      :metrics="metrics"
    />

    <ElAlert
      type="info"
      :closable="false"
      show-icon
      title="报表仅统计已记账及其冲销凭证，已确认期初余额自动纳入期初数；原凭证与冲销凭证均保留，确保账簿结果可审计、可追溯。"
    />

    <ElTabs v-model="activeTab" class="ledger-center-page__tabs">
      <ElTabPane name="balance">
        <template #label>
          <span class="ledger-center-page__tab-label">
            <ArtSvgIcon icon="ri:scales-3-line" />
            <span>
              <strong>科目余额表</strong>
              <small>核对期初、发生额、累计额与期末余额</small>
            </span>
          </span>
        </template>

        <ArtTableQuery
          ref="balanceTableRef"
          v-model="balanceSearch"
          :search-items="balanceSearchItems"
          :api-fn="fetchBalanceTableData"
          :columns-factory="balanceColumnsFactory"
          :header-actions="balanceHeaderActions"
          :immediate="false"
          :search-bar-props="{ span: 6, labelWidth: 82, showExpand: true }"
          :table-props="{
            rowKey: 'subjectId',
            tableLayout: 'fixed',
            emptyText: '暂无科目余额',
            emptyDescription: '请选择账套和会计年度查询，已记账凭证及已确认期初余额会在此汇总。'
          }"
          focusable
        />
      </ElTabPane>

      <ElTabPane name="general">
        <template #label>
          <span class="ledger-center-page__tab-label">
            <ArtSvgIcon icon="ri:book-2-line" />
            <span>
              <strong>总账</strong>
              <small>按期间查看指定科目的连续余额</small>
            </span>
          </span>
        </template>

        <ArtTableQuery
          ref="generalTableRef"
          v-model="generalSearch"
          :search-items="generalSearchItems"
          :api-fn="fetchGeneralTableData"
          :columns-factory="generalColumnsFactory"
          :header-actions="generalHeaderActions"
          :immediate="false"
          :search-bar-props="{ span: 6, labelWidth: 82, showExpand: true }"
          :table-props="{
            rowKey: 'periodNo',
            tableLayout: 'fixed',
            emptyText: '暂无总账数据',
            emptyDescription: '请选择账套、会计年度和会计科目后查询。'
          }"
          focusable
        />
      </ElTabPane>

      <ElTabPane name="subsidiary">
        <template #label>
          <span class="ledger-center-page__tab-label">
            <ArtSvgIcon icon="ri:file-list-3-line" />
            <span>
              <strong>明细 / 辅助账</strong>
              <small>追溯凭证明细、外币、数量与辅助核算</small>
            </span>
          </span>
        </template>

        <ArtTableQuery
          ref="subsidiaryTableRef"
          v-model="subsidiarySearch"
          :search-items="subsidiarySearchItems"
          :api-fn="fetchSubsidiaryTableData"
          :columns-factory="subsidiaryColumnsFactory"
          :header-actions="subsidiaryHeaderActions"
          :immediate="false"
          :search-bar-props="{ span: 6, labelWidth: 82, showExpand: true }"
          :table-props="{
            rowKey: subsidiaryRowKey,
            tableLayout: 'fixed',
            emptyText: '暂无明细账数据',
            emptyDescription:
              '请选择账套、会计年度和会计科目；如需辅助账，可继续选择辅助核算类型与项目。'
          }"
          focusable
        />
      </ElTabPane>
    </ElTabs>
  </div>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../modules/accounting-select-text'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import {
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    fetchAuxiliaryItemList,
    fetchAuxiliaryTypeList,
    fetchGeneralLedgerReport,
    fetchSubjectBalanceReport,
    fetchSubjectList,
    fetchSubsidiaryLedgerReport
  } from '@/api/fms'

  defineOptions({ name: 'FinanceLedgerCenter' })

  type LedgerTab = 'balance' | 'general' | 'subsidiary'
  type BalanceRecord = Api.Fms.SubjectBalanceReportRecord
  type GeneralRecord = Api.Fms.GeneralLedgerReportRecord
  type SubsidiaryRecord = Api.Fms.SubsidiaryLedgerReportRecord
  type TablePageParams = Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface LedgerOptionContext {
    periods: Api.Fms.AccountingPeriodRecord[]
    subjects: Api.Fms.SubjectRecord[]
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const activeTab = ref<LedgerTab>('balance')
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const balanceTableRef = ref<ArtTableQueryExpose>()
  const generalTableRef = ref<ArtTableQueryExpose>()
  const subsidiaryTableRef = ref<ArtTableQueryExpose>()
  const balanceRows = ref<BalanceRecord[]>([])
  const generalRows = ref<GeneralRecord[]>([])
  const subsidiaryRows = ref<SubsidiaryRecord[]>([])

  const contexts = reactive<Record<LedgerTab, LedgerOptionContext>>({
    balance: { periods: [], subjects: [], auxiliaryTypes: [], auxiliaryItems: [] },
    general: { periods: [], subjects: [], auxiliaryTypes: [], auxiliaryItems: [] },
    subsidiary: { periods: [], subjects: [], auxiliaryTypes: [], auxiliaryItems: [] }
  })

  const balanceSearch = reactive<Api.Fms.SubjectBalanceReportParams>({
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    periodFrom: 1,
    periodTo: 12,
    subjectId: null,
    hideZero: true
  })
  const generalSearch = reactive<Api.Fms.LedgerReportParams>({
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    periodFrom: 1,
    periodTo: 12,
    subjectId: null
  })
  const subsidiarySearch = reactive<Api.Fms.SubsidiaryLedgerReportParams>({
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    periodFrom: 1,
    periodTo: 12,
    subjectId: '',
    auxiliaryTypeId: null,
    auxiliaryItemId: null
  })

  const getSearch = (tab: LedgerTab) => {
    if (tab === 'balance') return balanceSearch
    if (tab === 'general') return generalSearch
    return subsidiarySearch
  }

  const getTableRef = (tab: LedgerTab): ArtTableQueryExpose | undefined => {
    if (tab === 'balance') return balanceTableRef.value
    if (tab === 'general') return generalTableRef.value
    return subsidiaryTableRef.value
  }

  const yearOptions = (tab: LedgerTab) =>
    [...new Set(contexts[tab].periods.map((item) => item.fiscalYear))]
      .sort((a, b) => b - a)
      .map((value) => ({ label: `${value} 年`, value }))

  const periodOptions = (tab: LedgerTab) => {
    const fiscalYear = getSearch(tab).fiscalYear
    return contexts[tab].periods
      .filter((item) => item.fiscalYear === fiscalYear)
      .map((item) => ({
        label: `第 ${item.periodNo} 期`,
        value: item.periodNo,
        status: item.status
      }))
  }

  const subjectOptions = (tab: LedgerTab) =>
    contexts[tab].subjects.map((item) => ({
      label: `${item.subjectCode} ${item.subjectName}${item.isEnabled ? '' : '（停用）'}`,
      value: item.id
    }))

  const auxiliaryTypeOptions = computed(() =>
    contexts.subsidiary.auxiliaryTypes
      .filter((item) => item.isEnabled)
      .map((item) => ({ label: `${item.typeCode} ${item.typeName}`, value: item.id }))
  )

  const auxiliaryItemOptions = computed(() =>
    contexts.subsidiary.auxiliaryItems
      .filter((item) => item.isEnabled)
      .map((item) => ({ label: `${item.itemCode} ${item.itemName}`, value: item.id }))
  )

  function commonSearchItems(tab: LedgerTab): SearchFormItem[] {
    return [
      {
        label: '账套',
        key: 'accountSetId',
        type: 'select',
        props: {
          options: accountSetOptions.value,
          filterable: true,
          placeholder: '请选择账套',
          noDataText: ACCOUNTING_SELECT_EMPTY_TEXT.accountSet,
          onChange: (value: string) => void handleAccountSetChange(tab, value)
        }
      },
      {
        label: '会计年度',
        key: 'fiscalYear',
        type: 'select',
        props: {
          options: yearOptions(tab),
          placeholder: '请选择年度',
          disabled: !getSearch(tab).accountSetId,
          noDataText: getSearch(tab).accountSetId
            ? ACCOUNTING_SELECT_EMPTY_TEXT.fiscalYear
            : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet,
          onChange: () => handleFiscalYearChange(tab)
        }
      },
      {
        label: '会计科目',
        key: 'subjectId',
        type: 'select',
        props: {
          options: subjectOptions(tab),
          filterable: true,
          clearable: tab === 'balance',
          placeholder: tab === 'balance' ? '全部科目' : '请选择科目',
          disabled: !getSearch(tab).accountSetId,
          noDataText: getSearch(tab).accountSetId
            ? ACCOUNTING_SELECT_EMPTY_TEXT.subject
            : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
        }
      },
      {
        label: '起始期间',
        key: 'periodFrom',
        type: 'select',
        props: {
          options: periodOptions(tab),
          placeholder: '起始期间',
          disabled: !getSearch(tab).accountSetId,
          noDataText: getSearch(tab).accountSetId
            ? ACCOUNTING_SELECT_EMPTY_TEXT.accountingPeriod
            : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
        }
      },
      {
        label: '截止期间',
        key: 'periodTo',
        type: 'select',
        props: {
          options: periodOptions(tab),
          placeholder: '截止期间',
          disabled: !getSearch(tab).accountSetId,
          noDataText: getSearch(tab).accountSetId
            ? ACCOUNTING_SELECT_EMPTY_TEXT.accountingPeriod
            : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
        }
      }
    ]
  }

  const balanceSearchItems = computed<SearchFormItem[]>(() => [
    ...commonSearchItems('balance'),
    {
      label: '隐藏零余额',
      key: 'hideZero',
      type: 'select',
      props: {
        options: (getDictMap.value.commonBoolean ?? []).map((item) => ({
          ...item,
          value: item.value === 'true'
        }))
      }
    }
  ])

  const generalSearchItems = computed<SearchFormItem[]>(() => commonSearchItems('general'))

  const subsidiarySearchItems = computed<SearchFormItem[]>(() => [
    ...commonSearchItems('subsidiary'),
    {
      label: '辅助类型',
      key: 'auxiliaryTypeId',
      type: 'select',
      props: {
        options: auxiliaryTypeOptions.value,
        filterable: true,
        clearable: true,
        placeholder: '全部辅助类型',
        disabled: !subsidiarySearch.accountSetId,
        noDataText: subsidiarySearch.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.auxiliaryType
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet,
        onChange: (value: string) => void handleAuxiliaryTypeChange(value)
      }
    },
    {
      label: '辅助项目',
      key: 'auxiliaryItemId',
      type: 'select',
      props: {
        options: auxiliaryItemOptions.value,
        filterable: true,
        clearable: true,
        disabled: !subsidiarySearch.auxiliaryTypeId,
        placeholder: subsidiarySearch.auxiliaryTypeId ? '全部辅助项目' : '请先选择辅助类型',
        noDataText: subsidiarySearch.auxiliaryTypeId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.auxiliaryItem
          : '请先选择辅助类型'
      }
    }
  ])

  const balanceHeaderActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'export',
      exportFilename: '科目余额表',
      exportSheetName: '科目余额表',
      exportColumns: [
        { key: 'subjectCode', title: '科目编码', width: 18 },
        { key: 'subjectName', title: '科目名称', width: 24 },
        {
          key: 'category',
          title: '科目类别',
          formatter: (value) => dictLabel('fmsSubjectCategory', value)
        },
        { key: 'openingDebit', title: '期初借方' },
        { key: 'openingCredit', title: '期初贷方' },
        { key: 'periodDebit', title: '本期借方' },
        { key: 'periodCredit', title: '本期贷方' },
        { key: 'yearToDateDebit', title: '本年累计借方' },
        { key: 'yearToDateCredit', title: '本年累计贷方' },
        {
          key: 'endingDirection',
          title: '期末方向',
          formatter: (value) => dictLabel('fmsBalanceDirection', value)
        },
        { key: 'endingBalance', title: '期末余额' }
      ]
    }
  ])

  const generalHeaderActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'export',
      exportFilename: '总账',
      exportSheetName: '总账',
      exportColumns: [
        { key: 'periodNo', title: '会计期间' },
        { key: 'periodStart', title: '期间开始' },
        { key: 'periodEnd', title: '期间结束' },
        {
          key: 'openingDirection',
          title: '期初方向',
          formatter: (value) => dictLabel('fmsBalanceDirection', value)
        },
        { key: 'openingBalance', title: '期初余额' },
        { key: 'debitAmount', title: '本期借方' },
        { key: 'creditAmount', title: '本期贷方' },
        { key: 'yearToDateDebit', title: '本年累计借方' },
        { key: 'yearToDateCredit', title: '本年累计贷方' },
        {
          key: 'endingDirection',
          title: '期末方向',
          formatter: (value) => dictLabel('fmsBalanceDirection', value)
        },
        { key: 'endingBalance', title: '期末余额' },
        { key: 'voucherCount', title: '凭证数' },
        { key: 'lineCount', title: '分录数' }
      ]
    }
  ])

  const subsidiaryHeaderActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'export',
      exportFilename: '明细辅助账',
      exportSheetName: '明细辅助账',
      exportColumns: [
        { key: 'voucherDate', title: '日期' },
        { key: 'periodNo', title: '期间' },
        { key: 'voucherNo', title: '凭证号', width: 18 },
        {
          key: 'voucherType',
          title: '凭证类型',
          formatter: (value) => dictLabel('fmsVoucherType', value)
        },
        { key: 'summary', title: '摘要', width: 30 },
        { key: 'auxiliaryDisplay', title: '辅助核算', width: 28 },
        { key: 'currencyCode', title: '币种' },
        { key: 'originalAmount', title: '原币金额' },
        { key: 'quantity', title: '数量' },
        { key: 'unitName', title: '单位' },
        { key: 'debitAmount', title: '借方金额' },
        { key: 'creditAmount', title: '贷方金额' },
        {
          key: 'balanceDirection',
          title: '余额方向',
          formatter: (value) => dictLabel('fmsBalanceDirection', value)
        },
        { key: 'balanceAmount', title: '余额' }
      ]
    }
  ])

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    if (activeTab.value === 'general') return generalMetrics()
    if (activeTab.value === 'subsidiary') return subsidiaryMetrics()
    return balanceMetrics()
  })

  function balanceMetrics(): BusinessWorkspaceMetric[] {
    const rows = balanceRows.value.filter((item) => item.isLeaf)
    const debit = sumRows(rows, 'periodDebit')
    const credit = sumRows(rows, 'periodCredit')
    return [
      metric('subjects', '末级科目', rows.length, '当前筛选范围', 'ri:node-tree', 'primary'),
      metric(
        'debit',
        '本期借方',
        formatCurrencyValue(debit),
        '末级科目汇总',
        'ri:add-line',
        'success'
      ),
      metric(
        'credit',
        '本期贷方',
        formatCurrencyValue(credit),
        '末级科目汇总',
        'ri:subtract-line',
        'warning'
      ),
      metric(
        'balanced',
        '借贷平衡',
        Math.abs(debit - credit) < 0.005 ? '平衡' : '待核对',
        `差额 ${formatCurrencyValue(Math.abs(debit - credit))}`,
        'ri:scales-3-line',
        Math.abs(debit - credit) < 0.005 ? 'success' : 'danger'
      )
    ]
  }

  function generalMetrics(): BusinessWorkspaceMetric[] {
    const rows = generalRows.value
    const last = rows.at(-1)
    return [
      metric('periods', '会计期间', rows.length, '当前总账跨度', 'ri:calendar-2-line', 'primary'),
      metric(
        'debit',
        '期间借方',
        formatCurrencyValue(sumRows(rows, 'debitAmount')),
        '期间发生额合计',
        'ri:add-line',
        'success'
      ),
      metric(
        'credit',
        '期间贷方',
        formatCurrencyValue(sumRows(rows, 'creditAmount')),
        '期间发生额合计',
        'ri:subtract-line',
        'warning'
      ),
      metric(
        'ending',
        '期末余额',
        formatCurrencyValue(last?.endingBalance ?? 0),
        dictLabel('fmsBalanceDirection', last?.endingDirection) || '当前末期',
        'ri:wallet-3-line',
        'info'
      )
    ]
  }

  function subsidiaryMetrics(): BusinessWorkspaceMetric[] {
    const transactions = subsidiaryRows.value.filter((item) => item.rowType === 'transaction')
    const last = subsidiaryRows.value.at(-1)
    return [
      metric(
        'entries',
        '明细分录',
        transactions.length,
        '当前筛选范围',
        'ri:file-list-3-line',
        'primary'
      ),
      metric(
        'debit',
        '明细借方',
        formatCurrencyValue(sumRows(transactions, 'debitAmount')),
        '分录发生额合计',
        'ri:add-line',
        'success'
      ),
      metric(
        'credit',
        '明细贷方',
        formatCurrencyValue(sumRows(transactions, 'creditAmount')),
        '分录发生额合计',
        'ri:subtract-line',
        'warning'
      ),
      metric(
        'ending',
        '滚动余额',
        formatCurrencyValue(last?.balanceAmount ?? 0),
        dictLabel('fmsBalanceDirection', last?.balanceDirection) || '当前末笔',
        'ri:line-chart-line',
        'info'
      )
    ]
  }

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

  function sumRows<T extends object>(rows: T[], key: keyof T): number {
    return rows.reduce((sum, row) => sum + Number(row[key] || 0), 0)
  }

  function dictLabel(code: string, value: unknown): string {
    if (value === null || value === undefined || value === '') return ''
    const option = (getDictMap.value[code] ?? []).find(
      (item) => String(item.value) === String(value)
    )
    return option?.label ?? String(value)
  }

  function moneyCell(value: number): string {
    return formatCurrencyValue(Number(value || 0))
  }

  function balanceColumnsFactory(): ColumnOption<BalanceRecord>[] {
    return [
      {
        prop: 'subjectCode',
        label: '科目',
        minWidth: 250,
        fixed: 'left',
        formatter: (row) => (
          <div
            class="ledger-center-page__subject"
            style={{ paddingLeft: `${Math.max(row.subjectLevel - 1, 0) * 14}px` }}
          >
            <strong translate="no">{row.subjectCode}</strong>
            <span>{row.subjectName}</span>
            {!row.isLeaf ? (
              <ElTag size="small" type="info" effect="plain">
                汇总
              </ElTag>
            ) : null}
          </div>
        )
      },
      { prop: 'category', label: '科目类别', width: 100, dict: { code: 'fmsSubjectCategory' } },
      {
        prop: 'openingDebit',
        label: '期初借方',
        width: 130,
        align: 'right',
        formatter: (row) => moneyCell(row.openingDebit)
      },
      {
        prop: 'openingCredit',
        label: '期初贷方',
        width: 130,
        align: 'right',
        formatter: (row) => moneyCell(row.openingCredit)
      },
      {
        prop: 'periodDebit',
        label: '本期借方',
        width: 130,
        align: 'right',
        formatter: (row) => moneyCell(row.periodDebit)
      },
      {
        prop: 'periodCredit',
        label: '本期贷方',
        width: 130,
        align: 'right',
        formatter: (row) => moneyCell(row.periodCredit)
      },
      {
        prop: 'yearToDateDebit',
        label: '本年累计借方',
        width: 145,
        align: 'right',
        formatter: (row) => moneyCell(row.yearToDateDebit)
      },
      {
        prop: 'yearToDateCredit',
        label: '本年累计贷方',
        width: 145,
        align: 'right',
        formatter: (row) => moneyCell(row.yearToDateCredit)
      },
      {
        prop: 'endingDirection',
        label: '期末方向',
        width: 90,
        dict: { code: 'fmsBalanceDirection', display: 'tag' }
      },
      {
        prop: 'endingBalance',
        label: '期末余额',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.endingBalance)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 96,
        fixed: 'right',
        formatter: (row) => (
          <ArtButtonTable
            type="view"
            label="查看总账"
            onClick={() => void openGeneralLedger(row)}
          />
        )
      }
    ]
  }

  function generalColumnsFactory(): ColumnOption<GeneralRecord>[] {
    return [
      {
        prop: 'periodNo',
        label: '会计期间',
        minWidth: 150,
        fixed: 'left',
        formatter: (row) => (
          <div class="ledger-center-page__period">
            <strong>第 {row.periodNo} 期</strong>
            <small>
              {row.periodStart && row.periodEnd
                ? `${formatWithDayjs(row.periodStart, 'MM-DD')} 至 ${formatWithDayjs(row.periodEnd, 'MM-DD')}`
                : '--'}
            </small>
          </div>
        )
      },
      {
        prop: 'openingDirection',
        label: '期初方向',
        width: 90,
        dict: { code: 'fmsBalanceDirection', display: 'tag' }
      },
      {
        prop: 'openingBalance',
        label: '期初余额',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.openingBalance)
      },
      {
        prop: 'debitAmount',
        label: '本期借方',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.debitAmount)
      },
      {
        prop: 'creditAmount',
        label: '本期贷方',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.creditAmount)
      },
      {
        prop: 'yearToDateDebit',
        label: '本年累计借方',
        width: 145,
        align: 'right',
        formatter: (row) => moneyCell(row.yearToDateDebit)
      },
      {
        prop: 'yearToDateCredit',
        label: '本年累计贷方',
        width: 145,
        align: 'right',
        formatter: (row) => moneyCell(row.yearToDateCredit)
      },
      {
        prop: 'endingDirection',
        label: '期末方向',
        width: 90,
        dict: { code: 'fmsBalanceDirection', display: 'tag' }
      },
      {
        prop: 'endingBalance',
        label: '期末余额',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.endingBalance)
      },
      { prop: 'voucherCount', label: '凭证数', width: 90, align: 'right' },
      { prop: 'lineCount', label: '分录数', width: 90, align: 'right' },
      {
        prop: 'operation',
        label: '操作',
        width: 108,
        fixed: 'right',
        formatter: (row) => (
          <ArtButtonTable
            type="view"
            label="查看明细"
            onClick={() => void openSubsidiaryLedger(row)}
          />
        )
      }
    ]
  }

  function subsidiaryColumnsFactory(): ColumnOption<SubsidiaryRecord>[] {
    return [
      {
        prop: 'voucherDate',
        label: '日期 / 期间',
        width: 130,
        fixed: 'left',
        formatter: (row) => (
          <div class="ledger-center-page__period">
            <strong>
              {row.rowType === 'opening'
                ? '期初余额'
                : formatWithDayjs(row.voucherDate, 'YYYY-MM-DD')}
            </strong>
            <small>第 {row.periodNo} 期</small>
          </div>
        )
      },
      {
        prop: 'voucherNo',
        label: '凭证',
        minWidth: 160,
        formatter: (row) =>
          row.rowType === 'opening' ? (
            <ElTag size="small" type="info" effect="plain">
              期初
            </ElTag>
          ) : (
            <div class="ledger-center-page__period">
              <strong translate="no">{row.voucherNo || '--'}</strong>
              <small>{dictLabel('fmsVoucherType', row.voucherType)}</small>
            </div>
          )
      },
      { prop: 'summary', label: '摘要', minWidth: 220, showOverflowTooltip: true },
      {
        prop: 'auxiliaryDisplay',
        label: '辅助核算',
        minWidth: 190,
        showOverflowTooltip: true,
        formatter: (row) => row.auxiliaryDisplay || '--'
      },
      {
        prop: 'originalAmount',
        label: '外币 / 数量',
        minWidth: 150,
        formatter: (row) => (
          <div class="ledger-center-page__period">
            <strong>
              {row.currencyCode
                ? `${row.currencyCode} ${Number(row.originalAmount || 0).toLocaleString('zh-CN')}`
                : '--'}
            </strong>
            <small>
              {row.quantity
                ? `${Number(row.quantity).toLocaleString('zh-CN')} ${row.unitName || ''}`
                : '无数量核算'}
            </small>
          </div>
        )
      },
      {
        prop: 'debitAmount',
        label: '借方金额',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.debitAmount)
      },
      {
        prop: 'creditAmount',
        label: '贷方金额',
        width: 135,
        align: 'right',
        formatter: (row) => moneyCell(row.creditAmount)
      },
      {
        prop: 'balanceDirection',
        label: '余额方向',
        width: 90,
        dict: { code: 'fmsBalanceDirection', display: 'tag' }
      },
      {
        prop: 'balanceAmount',
        label: '滚动余额',
        width: 135,
        align: 'right',
        fixed: 'right',
        formatter: (row) => moneyCell(row.balanceAmount)
      }
    ]
  }

  function normalizePeriodRange(search: Api.Fms.LedgerReportParams): void {
    const from = Number(search.periodFrom || 1)
    const to = Number(search.periodTo || 12)
    search.periodFrom = Math.min(from, to)
    search.periodTo = Math.max(from, to)
  }

  function pagedResult<T>(rows: T[], params: TablePageParams) {
    const { from, to } = pageInfoHandler(params)
    return { data: rows.slice(from, to + 1), total: rows.length }
  }

  async function fetchBalanceTableData(
    params: Api.Fms.SubjectBalanceReportParams & TablePageParams
  ) {
    if (!params.accountSetId || !params.fiscalYear) return pagedResult([], params)
    normalizePeriodRange(balanceSearch)
    const { data } = await fetchSubjectBalanceReport({
      ...params,
      periodFrom: Math.min(Number(params.periodFrom || 1), Number(params.periodTo || 12)),
      periodTo: Math.max(Number(params.periodFrom || 1), Number(params.periodTo || 12))
    })
    balanceRows.value = data ?? []
    return pagedResult(balanceRows.value, params)
  }

  async function fetchGeneralTableData(params: Api.Fms.LedgerReportParams & TablePageParams) {
    if (!params.accountSetId || !params.fiscalYear || !params.subjectId) {
      generalRows.value = []
      return pagedResult([], params)
    }
    normalizePeriodRange(generalSearch)
    const { data } = await fetchGeneralLedgerReport({
      ...params,
      subjectId: params.subjectId,
      periodFrom: Math.min(Number(params.periodFrom || 1), Number(params.periodTo || 12)),
      periodTo: Math.max(Number(params.periodFrom || 1), Number(params.periodTo || 12))
    })
    generalRows.value = data ?? []
    return pagedResult(generalRows.value, params)
  }

  async function fetchSubsidiaryTableData(
    params: Api.Fms.SubsidiaryLedgerReportParams & TablePageParams
  ) {
    if (!params.accountSetId || !params.fiscalYear || !params.subjectId) {
      subsidiaryRows.value = []
      return pagedResult([], params)
    }
    normalizePeriodRange(subsidiarySearch)
    const { data } = await fetchSubsidiaryLedgerReport({
      ...params,
      periodFrom: Math.min(Number(params.periodFrom || 1), Number(params.periodTo || 12)),
      periodTo: Math.max(Number(params.periodFrom || 1), Number(params.periodTo || 12))
    })
    subsidiaryRows.value = data ?? []
    return pagedResult(subsidiaryRows.value, params)
  }

  async function loadContext(tab: LedgerTab, accountSetId: string): Promise<void> {
    const context = contexts[tab]
    context.periods = []
    context.subjects = []
    context.auxiliaryTypes = []
    context.auxiliaryItems = []
    if (!accountSetId) return

    const [periodResult, subjectResult, auxiliaryTypeResult] = await Promise.all([
      fetchAccountingPeriodList(accountSetId),
      fetchSubjectList(accountSetId),
      tab === 'subsidiary' ? fetchAuxiliaryTypeList(accountSetId) : Promise.resolve({ data: [] })
    ])
    context.periods = periodResult.data ?? []
    context.subjects = subjectResult.data ?? []
    context.auxiliaryTypes = auxiliaryTypeResult.data ?? []
  }

  function applyContextDefaults(tab: LedgerTab, preferredSubjectId?: string): void {
    const search = getSearch(tab)
    const years = yearOptions(tab)
    if (!years.some((item) => item.value === search.fiscalYear)) {
      search.fiscalYear = years[0]?.value ?? new Date().getFullYear()
    }
    handleFiscalYearChange(tab)
    if (tab === 'balance') {
      balanceSearch.subjectId = preferredSubjectId ?? null
      return
    }
    const fallbackSubjectId = contexts[tab].subjects[0]?.id ?? ''
    search.subjectId = preferredSubjectId || fallbackSubjectId
    if (tab === 'subsidiary') {
      subsidiarySearch.auxiliaryTypeId = null
      subsidiarySearch.auxiliaryItemId = null
    }
  }

  async function handleAccountSetChange(tab: LedgerTab, accountSetId: string): Promise<void> {
    const search = getSearch(tab)
    search.accountSetId = accountSetId || ''
    await loadContext(tab, search.accountSetId)
    applyContextDefaults(tab)
  }

  function handleFiscalYearChange(tab: LedgerTab): void {
    const search = getSearch(tab)
    const periods = periodOptions(tab)
    search.periodFrom = periods[0]?.value ?? 1
    search.periodTo = periods.at(-1)?.value ?? 12
  }

  async function handleAuxiliaryTypeChange(auxiliaryTypeId: string): Promise<void> {
    subsidiarySearch.auxiliaryTypeId = auxiliaryTypeId || null
    subsidiarySearch.auxiliaryItemId = null
    contexts.subsidiary.auxiliaryItems = []
    if (!subsidiarySearch.accountSetId || !auxiliaryTypeId) return
    const { data } = await fetchAuxiliaryItemList(subsidiarySearch.accountSetId, auxiliaryTypeId)
    contexts.subsidiary.auxiliaryItems = data ?? []
  }

  async function prepareTargetTab(
    tab: Exclude<LedgerTab, 'balance'>,
    source: Api.Fms.LedgerReportParams,
    subjectId: string
  ): Promise<void> {
    const target = getSearch(tab)
    target.accountSetId = source.accountSetId
    target.fiscalYear = source.fiscalYear
    target.periodFrom = source.periodFrom
    target.periodTo = source.periodTo
    await loadContext(tab, source.accountSetId)
    applyContextDefaults(tab, subjectId)
    target.fiscalYear = source.fiscalYear
    target.periodFrom = source.periodFrom
    target.periodTo = source.periodTo
    activeTab.value = tab
    await nextTick()
    await getTableRef(tab)?.getData()
  }

  async function openGeneralLedger(row: BalanceRecord): Promise<void> {
    await prepareTargetTab('general', balanceSearch, row.subjectId)
  }

  async function openSubsidiaryLedger(row: GeneralRecord): Promise<void> {
    if (!generalSearch.subjectId) return
    const scopedSearch = {
      ...generalSearch,
      periodFrom: row.periodNo,
      periodTo: row.periodNo
    }
    await prepareTargetTab('subsidiary', scopedSearch, generalSearch.subjectId)
  }

  const subsidiaryRowKey = (row: Record<string, unknown>): string =>
    String(row.voucherLineId || `opening-${row.periodNo}-${row.summary}`)

  async function initialize(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    const defaultAccountSetId = accountSetOptions.value[0]?.value ?? ''
    if (!defaultAccountSetId) return

    balanceSearch.accountSetId = defaultAccountSetId
    generalSearch.accountSetId = defaultAccountSetId
    subsidiarySearch.accountSetId = defaultAccountSetId
    await Promise.all([
      loadContext('balance', defaultAccountSetId),
      loadContext('general', defaultAccountSetId),
      loadContext('subsidiary', defaultAccountSetId)
    ])
    applyContextDefaults('balance')
    applyContextDefaults('general')
    applyContextDefaults('subsidiary')
    await nextTick()
    await Promise.all([
      balanceTableRef.value?.getData(),
      generalTableRef.value?.getData(),
      subsidiaryTableRef.value?.getData()
    ])
  }

  onMounted(() => void initialize())
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .ledger-center-page {
    @include accounting.accounting-workspace-layout;

    &__tabs {
      @include accounting.accounting-workspace-tabs(640px, 540px);
    }

    &__subject,
    &__period {
      display: flex;
      min-width: 0;
    }

    &__tab-label {
      @include accounting.accounting-workspace-tab-label;
    }

    &__subject {
      gap: 8px;
      align-items: center;

      strong {
        flex: 0 0 auto;
        font-variant-numeric: tabular-nums;
        color: var(--el-color-primary);
      }

      span {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__period {
      flex-direction: column;
      line-height: 1.35;

      strong {
        font-weight: 600;
        color: var(--el-text-color-primary);
      }

      small {
        margin-top: 2px;
        color: var(--el-text-color-secondary);
      }
    }

    :deep(.el-table .cell) {
      font-variant-numeric: tabular-nums;
    }

    @media (width <= 640px) {
      &__tab-label > span small {
        display: none;
      }
    }
  }
</style>
