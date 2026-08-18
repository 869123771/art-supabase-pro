<template>
  <div class="business-workspace-page art-full-height fms-accounting-page payroll-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="PAYROLL ACCOUNTING"
      title="薪资核算"
      description="按会计期间维护员工薪资快照，统一计算应发、扣款、企业成本和实发金额，并衔接计提与支付凭证。"
      icon="ri:team-line"
      :tags="[
        { label: '员工快照', type: 'primary' },
        { label: '审批计提', type: 'warning' },
        { label: '支付入账', type: 'success' }
      ]"
      :metrics="metrics"
    />
    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户薪资核算结果；批次、明细、审批和支付仅平台超级管理员可执行。"
    />
    <ArtTableQuery
      ref="tableRef"
      v-model="table.search"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无薪资批次',
        emptyDescription: isPlatformSuper
          ? '选择开放会计期间创建薪资批次。'
          : '当前租户暂无可查看的薪资核算记录。'
      }"
      focusable
    />
    <PayrollRunDialog ref="dialogRef" @success="refreshAll" />
    <PayrollDetailDrawer ref="drawerRef" @success="refreshAll" />
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
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    actPayrollRun,
    fetchAccountSetOptions,
    fetchPayrollRunList,
    fetchPayrollSummary
  } from '@/api/fms'
  import PayrollRunDialog from './modules/payroll-run-dialog.vue'
  import PayrollDetailDrawer from './modules/payroll-detail-drawer.vue'

  defineOptions({ name: 'FinancePayroll' })
  type Run = Api.Fms.PayrollRunRecord
  type SearchParams = Api.Fms.PayrollRunSearchParams
  type TableParams = SearchParams & { current: number; size: number }
  const emptySummary = (): Api.Fms.PayrollSummary => ({
    runCount: 0,
    employeeCount: 0,
    grossAmount: 0,
    netAmount: 0,
    pendingCount: 0
  })
  const { confirmAction, promptReason } = useArtFeedback()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: (row?: Run) => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Run) => Promise<void> }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const summary = ref<Api.Fms.PayrollSummary>(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, status: undefined }
  })
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'run',
      label: '薪资批次',
      value: summary.value.runCount,
      description: `${summary.value.pendingCount} 个待完成`,
      icon: 'ri:file-list-3-line',
      tone: 'primary'
    },
    {
      key: 'employee',
      label: '核算人次',
      value: summary.value.employeeCount,
      description: '批次员工快照合计',
      icon: 'ri:user-follow-line',
      tone: 'info'
    },
    {
      key: 'gross',
      label: '应发合计',
      value: formatCurrencyValue(summary.value.grossAmount),
      description: '税前应发口径',
      icon: 'ri:money-cny-circle-line',
      tone: 'warning'
    },
    {
      key: 'net',
      label: '实发合计',
      value: formatCurrencyValue(summary.value.netAmount),
      description: '扣款后支付口径',
      icon: 'ri:secure-payment-line',
      tone: 'success'
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
      label: '批次状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsPayrollRunStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    }
  ])
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [{ type: 'add', label: '新建薪资批次', onClick: () => void dialogRef.value?.handleOpen() }]
      : []
  )
  function columnsFactory(): ColumnOption<Run>[] {
    return [
      { prop: 'runNo', label: '批次号', minWidth: 160, fixed: 'left' },
      {
        prop: 'payrollMonth',
        label: '薪资月份',
        width: 120,
        formatter: (row) => formatWithDayjs(row.payrollMonth, 'YYYY-MM')
      },
      { prop: 'employeeCount', label: '员工数', width: 90, align: 'right' },
      {
        prop: 'grossAmount',
        label: '应发金额',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.grossAmount)
      },
      {
        prop: 'deductionAmount',
        label: '扣款金额',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.deductionAmount)
      },
      {
        prop: 'employerCostAmount',
        label: '企业成本',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.employerCostAmount)
      },
      {
        prop: 'netAmount',
        label: '实发金额',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.netAmount)
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsPayrollRunStatus', display: 'tag' }
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
            {isPlatformSuper.value && actionItems(row).length ? (
              <ArtButtonMore
                list={actionItems(row)}
                onClick={(item: ButtonMoreItem) => void handleAction(item, row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }
  function actionItems(row: Run): ButtonMoreItem[] {
    if (row.status === 'calculated')
      return [
        {
          key: 'approve',
          label: '审批并计提',
          icon: 'ri:check-double-line',
          color: 'var(--el-color-success)'
        },
        {
          key: 'cancel',
          label: '取消批次',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    if (row.status === 'approved')
      return [
        {
          key: 'pay',
          label: '确认发放',
          icon: 'ri:secure-payment-line',
          color: 'var(--el-color-success)'
        }
      ]
    if (row.status === 'draft')
      return [
        {
          key: 'cancel',
          label: '取消批次',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      ]
    return []
  }
  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchPayrollRunList({ ...params, from, to })
  }
  async function loadSummary(): Promise<void> {
    if (!table.search.accountSetId) return void (summary.value = emptySummary())
    const { data } = await fetchPayrollSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
  }
  async function handleAction(item: ButtonMoreItem, row: Run): Promise<void> {
    try {
      if (item.key === 'cancel') {
        const reason = await promptReason('请填写取消薪资批次的原因。', '取消薪资批次', {
          emptyMessage: '取消原因不能为空'
        })
        await actPayrollRun(row.id, 'cancel', { reason })
      } else {
        await confirmAction(
          item.key === 'approve'
            ? '审批后将锁定员工薪资明细并生成计提入账事件。'
            : '确认工资已完成发放并生成支付入账事件。',
          item.label,
          { type: 'warning', confirmButtonText: item.label }
        )
        await actPayrollRun(row.id, item.key as Api.Fms.PayrollRunAction)
      }
      await refreshAll()
    } catch {
      /* 用户取消 */
    }
  }
  async function refreshAll(): Promise<void> {
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

  .payroll-page {
    @include accounting.accounting-workspace-layout;
  }
</style>
