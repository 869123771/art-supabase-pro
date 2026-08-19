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
    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户关账结果；执行检查、结账、取消和反结账仅平台超级管理员可操作。"
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
        emptyText: '暂无关账批次',
        emptyDescription: isPlatformSuper
          ? '选择开放期间执行月末关账检查。'
          : '当前租户暂无关账记录。'
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
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Row) => Promise<void> }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const summary = ref(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, status: undefined }
  })
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
    {
      key: 'checking',
      label: '关账进行中',
      value: summary.value.checkingCount,
      description: '检查或待确认',
      icon: 'ri:loader-4-line',
      tone: 'warning'
    },
    {
      key: 'blocking',
      label: '阻断事项',
      value: summary.value.blockingCount,
      description: summary.value.latestCompletedAt
        ? `最近结账 ${formatWithDayjs(summary.value.latestCompletedAt, 'YYYY-MM-DD')}`
        : '暂无结账记录',
      icon: 'ri:alarm-warning-line',
      tone: summary.value.blockingCount ? 'danger' : 'info'
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
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [
          {
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
        ]
      : []
  )
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
      { prop: 'passedCount', label: '通过项', width: 90, align: 'right' },
      { prop: 'warningCount', label: '提醒项', width: 90, align: 'right' },
      {
        prop: 'blockingCount',
        label: '阻断项',
        width: 90,
        align: 'right',
        formatter: (row) => (
          <strong class={row.blockingCount ? 'period-close-blocking' : ''}>
            {row.blockingCount}
          </strong>
        )
      },
      {
        prop: 'completedAt',
        label: '结账时间',
        minWidth: 155,
        formatter: (row) => formatWithDayjs(row.completedAt, 'YYYY-MM-DD HH:mm') || '--'
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsPeriodCloseRunStatus', display: 'tag' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: isPlatformSuper.value ? 170 : 76,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="view" onClick={() => void drawerRef.value?.handleOpen(row)} />
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
    if (row.status === 'checking')
      return [
        {
          key: 'carryforward',
          label: '生成损益结转凭证',
          icon: 'ri:exchange-funds-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'recheck',
          label: '重新检查',
          icon: 'ri:refresh-line',
          color: 'var(--el-color-primary)'
        },
        {
          key: 'cancel',
          label: '取消关账',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'ready')
      return [
        {
          key: 'carryforward',
          label: '生成损益结转凭证',
          icon: 'ri:exchange-funds-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'recheck',
          label: '重新检查',
          icon: 'ri:refresh-line',
          color: 'var(--el-color-primary)'
        },
        {
          key: 'close',
          label: '确认结账',
          icon: 'ri:lock-2-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'cancel',
          label: '取消关账',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'closed')
      return [
        {
          key: 'reopen',
          label: '反结账',
          icon: 'ri:lock-unlock-line',
          color: 'var(--el-color-warning)'
        }
      ]
    return []
  }
  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchPeriodCloseRuns({ ...params, from, to })
  }
  async function loadSummary() {
    if (!table.search.accountSetId) return void (summary.value = emptySummary())
    const { data } = await fetchPeriodCloseSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
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
