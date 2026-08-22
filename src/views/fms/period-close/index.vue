<template>
  <div class="business-workspace-page art-full-height fms-accounting-page period-close-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="PERIOD-END CONTROL"
      title="月末结账"
      description="按会计期间执行期初、凭证、试算、资金、资产、薪资、税务和损益结转检查，阻断项清零后方可结账。"
      icon="ri:lock-2-line"
      :tags="[
        { label: '九项检查', type: 'primary' },
        { label: '阻断控制', type: 'warning' },
        { label: '反结账审计', type: 'success' }
      ]"
      :metrics="metrics"
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
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无关账批次',
        emptyDescription: '选择开放期间执行月末关账检查。'
      }"
      focusable
    />
    <PeriodCloseStartDialog ref="dialogRef" @success="refreshAll" />
    <PeriodCloseDetailDrawer ref="drawerRef" />
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
  import { financeRouteNames } from '@/router/business-paths'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { canEditField, canViewField, mergeFieldAccessMaps } from '@/utils/field-permission'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    actPeriodCloseRun,
    fetchAccountSetOptions,
    fetchPeriodCloseRuns,
    fetchPeriodCloseSummary,
    generateProfitLossCarryforward,
    runPeriodCloseChecks
  } from '@/api/fms'
  import PeriodCloseStartDialog from './modules/period-close-start-dialog.vue'
  import PeriodCloseDetailDrawer from './modules/period-close-detail-drawer.vue'
  defineOptions({ name: 'FinancePeriodClose' })
  type Row = Api.Fms.PeriodCloseRunRecord
  type SearchParams = Api.Fms.PeriodCloseSearchParams
  type TableParams = SearchParams & { current: number; size: number }
  const emptySummary = (): Api.Fms.PeriodCloseSummary => ({
    periodCount: 0,
    closedCount: 0,
    checkingCount: 0,
    blockingCount: 0,
    latestCompletedAt: null
  })
  const { confirmAction, promptReason } = useArtFeedback()
  const router = useRouter()
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Row) => Promise<void> }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const currentRows = ref<Row[]>([])
  const listFieldAccess = ref<Api.Fms.PeriodCloseFieldAccessMap>({})
  const summary = ref(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, status: undefined }
  })
  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess))
  )
  const canViewListField = (field: Api.Fms.PeriodCloseFieldKey): boolean =>
    canViewField(effectiveFieldAccess.value, field)
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'period',
      label: '关账批次',
      value: summary.value.periodCount,
      description: '历史执行总数',
      icon: 'ri:file-list-3-line',
      tone: 'primary'
    },
    {
      key: 'closed',
      label: '已结期间',
      value: summary.value.closedCount,
      description: '会计期间已锁定',
      icon: 'ri:lock-2-line',
      tone: 'success'
    },
    ...(canViewListField('closeDiagnostics')
      ? [
          {
            key: 'checking',
            label: '关账进行中',
            value: formatProtectedCount(summary.value.checkingCount),
            description: '检查或待确认',
            icon: 'ri:loader-4-line',
            tone: 'warning' as const
          },
          {
            key: 'blocking',
            label: '阻断事项',
            value: formatProtectedCount(summary.value.blockingCount),
            description:
              canViewListField('closeAudit') && summary.value.latestCompletedAt
                ? `最近结账 ${formatWithDayjs(summary.value.latestCompletedAt, 'YYYY-MM-DD')}`
                : '关账诊断汇总',
            icon: 'ri:alarm-warning-line',
            tone: toFiniteNumber(summary.value.blockingCount)
              ? ('danger' as const)
              : ('info' as const)
          }
        ]
      : [])
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
      label: '关账状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsPeriodCloseRunStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    }
  ])
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinancePeriodClose:Add',
      type: 'add',
      label: '执行关账检查',
      icon: 'ri:shield-check-line',
      onClick: () =>
        void runWithAccountSet(
          {
            actionLabel: '执行关账检查',
            activeRequired: true,
            accountSetId: table.search.accountSetId,
            foundationRequired: true,
            available: accountSetOptions.value.length > 0
          },
          () => dialogRef.value?.handleOpen()
        )
    }
  ])
  function columnsFactory(): ColumnOption<Row>[] {
    return [
      { prop: 'runNo', label: '批次号', minWidth: 160, fixed: 'left' },
      {
        prop: 'period',
        label: '会计期间',
        minWidth: 150,
        formatter: (row) =>
          row.period ? `${row.period.fiscalYear} 年第 ${row.period.periodNo} 期` : '--'
      },
      ...(canViewListField('closeDiagnostics')
        ? [
            {
              prop: 'passedCount',
              label: '通过项',
              width: 90,
              align: 'right' as const,
              formatter: (row: Row) => formatProtectedCount(row.passedCount)
            },
            {
              prop: 'warningCount',
              label: '提醒项',
              width: 90,
              align: 'right' as const,
              formatter: (row: Row) => formatProtectedCount(row.warningCount)
            },
            {
              prop: 'blockingCount',
              label: '阻断项',
              width: 90,
              align: 'right' as const,
              formatter: (row: Row) => (
                <strong class={toFiniteNumber(row.blockingCount) ? 'period-close-blocking' : ''}>
                  {formatProtectedCount(row.blockingCount)}
                </strong>
              )
            }
          ]
        : []),
      ...(canViewListField('closeAudit')
        ? [
            {
              prop: 'completedAt',
              label: '结账时间',
              minWidth: 155,
              formatter: (row: Row) =>
                row.completedAt === '***'
                  ? row.completedAt
                  : formatWithDayjs(row.completedAt, 'YYYY-MM-DD HH:mm') || '--'
            }
          ]
        : []),
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsPeriodCloseRunStatus', display: 'tag' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 170,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable
              type="view"
              permission="FinancePeriodClose:View"
              onClick={() => void drawerRef.value?.handleOpen(row)}
            />
            {actions(row).length ? (
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
    if (row.status === 'checking')
      return [
        ...(canEditField(row.fieldAccess, 'closeDiagnostics') &&
        canEditField(row.fieldAccess, 'voucherReferences')
          ? [carryforwardAction()]
          : []),
        ...(canEditField(row.fieldAccess, 'closeDiagnostics') ? [recheckAction()] : []),
        ...(canEditField(row.fieldAccess, 'closeAudit') ? [cancelAction()] : [])
      ]
    if (row.status === 'ready')
      return [
        ...(canEditField(row.fieldAccess, 'closeDiagnostics') &&
        canEditField(row.fieldAccess, 'voucherReferences')
          ? [carryforwardAction()]
          : []),
        ...(canEditField(row.fieldAccess, 'closeDiagnostics')
          ? [
              recheckAction(),
              {
                auth: 'FinancePeriodClose:Close',
                key: 'close',
                label: '确认结账',
                icon: 'ri:lock-2-line',
                color: 'var(--el-color-success)'
              }
            ]
          : []),
        ...(canEditField(row.fieldAccess, 'closeAudit') ? [cancelAction()] : [])
      ]
    if (row.status === 'closed')
      return canEditField(row.fieldAccess, 'closeAudit')
        ? [
            {
              auth: 'FinancePeriodClose:Reopen',
              key: 'reopen',
              label: '反结账',
              icon: 'ri:lock-unlock-line',
              color: 'var(--el-color-warning)'
            }
          ]
        : []
    return []
  }
  function carryforwardAction(): ButtonMoreItem {
    return {
      auth: 'FinancePeriodClose:Carryforward',
      key: 'carryforward',
      label: '生成损益结转凭证',
      icon: 'ri:exchange-funds-line',
      color: 'var(--el-color-success)'
    }
  }
  function recheckAction(): ButtonMoreItem {
    return {
      auth: 'FinancePeriodClose:Recheck',
      key: 'recheck',
      label: '重新检查',
      icon: 'ri:refresh-line',
      color: 'var(--el-color-primary)'
    }
  }
  function cancelAction(): ButtonMoreItem {
    return {
      auth: 'FinancePeriodClose:Cancel',
      key: 'cancel',
      label: '取消关账',
      icon: 'ri:close-circle-line',
      color: 'var(--el-color-danger)'
    }
  }
  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchPeriodCloseRuns({ ...params, from, to })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data ?? []
    return result
  }
  async function loadSummary() {
    if (!table.search.accountSetId) return void (summary.value = emptySummary())
    const { data } = await fetchPeriodCloseSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
    if (data?.fieldAccess) listFieldAccess.value = data.fieldAccess
  }
  async function handleAction(item: ButtonMoreItem, row: Row) {
    try {
      if (item.key === 'recheck') {
        await runPeriodCloseChecks(row.accountingPeriodId)
      } else if (item.key === 'carryforward') {
        await confirmAction(
          '系统将按本期已记账的收入、成本和费用自动生成损益结转凭证。生成后仍需在凭证中心完成审核与记账。',
          '生成损益结转凭证',
          { type: 'warning', confirmButtonText: '确认生成' }
        )
        await generateProfitLossCarryforward(row.accountingPeriodId)
        await router.push({ name: financeRouteNames.voucherCenter })
      } else if (item.key === 'close') {
        await confirmAction(
          '结账后本期凭证和业务数据将被锁定；如需修改必须执行有原因的反结账。',
          '确认月末结账',
          { type: 'warning', confirmButtonText: '确认结账' }
        )
        await actPeriodCloseRun(row.id, 'close')
      } else {
        const reason = await promptReason(
          item.key === 'reopen' ? '请填写反结账原因和后续调整说明。' : '请填写取消本次关账的原因。',
          item.label,
          { emptyMessage: '原因不能为空', placeholder: '填写可审计的业务原因' }
        )
        await actPeriodCloseRun(row.id, item.key as Api.Fms.PeriodCloseAction, reason)
      }
      await refreshAll()
    } catch {
      /* 用户取消或关账约束阻止 */
    }
  }
  async function refreshAll() {
    await Promise.all([tableRef.value?.refreshUpdate(), loadSummary()])
  }
  function toFiniteNumber(value: Api.Tms.BasicData.SensitiveNumber | undefined | null): number {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : 0
  }
  function formatProtectedCount(
    value: Api.Tms.BasicData.SensitiveNumber | undefined | null
  ): string | number {
    if (value === null || value === undefined || value === '') return '--'
    return typeof value === 'string' ? value : value.toLocaleString('zh-CN')
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

  .period-close-page {
    @include accounting.accounting-workspace-layout;
  }

  :deep(.period-close-blocking) {
    color: var(--el-color-danger);
  }
</style>
