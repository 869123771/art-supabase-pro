<template>
  <FinanceAccountingWorkspaceShell class="commercial-bill-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="COMMERCIAL PAPER"
      title="票据管理"
      description="统一管理应收与应付商业汇票，从收票、出票到背书、贴现和到期结算全程留痕，并衔接自动入账。"
      icon="ri:bank-card-2-line"
      :tags="[
        { label: '全生命周期', type: 'primary' },
        { label: '到期预警', type: 'warning' },
        { label: '自动入账', type: 'success' }
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
      :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无商业票据',
        emptyDescription: '新建票据草稿，并按业务方向确认收票或出票。'
      }"
      focusable
    />

    <CommercialBillDialog ref="dialogRef" @success="handleSaved" />
    <CommercialBillDetailDrawer ref="drawerRef" />
    <FundExecutionDialog ref="fundExecutionRef" @success="refreshAll('update')" />
  </FinanceAccountingWorkspaceShell>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
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
  import { formatWithDayjs } from '@/utils/time'
  import { canViewField, mergeFieldAccessMaps } from '@/utils/field-permission'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    actCommercialBill,
    deleteCommercialBill,
    fetchAccountSetOptions,
    fetchCommercialBillList,
    fetchCommercialBillSummary
  } from '@/api/fms'
  import CommercialBillDialog from './modules/commercial-bill-dialog.vue'
  import CommercialBillDetailDrawer from './modules/commercial-bill-detail-drawer.vue'

  defineOptions({ name: 'FinanceCommercialBill' })

  type Bill = Api.Fms.CommercialBillRecord
  type SearchParams = Api.Fms.CommercialBillSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  interface DialogExpose {
    handleOpen: (row?: Bill) => Promise<void>
  }
  interface DrawerExpose {
    handleOpen: (row: Bill) => Promise<void>
  }
  interface FundExecutionExpose {
    handleOpen: (
      options: FundExecutionOptions,
      onSubmit: (payload: FundExecutionPayload) => Promise<void>
    ) => Promise<void>
  }

  const emptySummary = (): Api.Fms.CommercialBillSummary => ({
    totalCount: 0,
    activeCount: 0,
    receivableOutstanding: 0,
    payableOutstanding: 0,
    dueWithin30Days: 0,
    overdueCount: 0
  })

  const { confirmAction, promptReason } = useArtFeedback()
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const fundExecutionRef = ref<FundExecutionExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const currentRows = ref<Bill[]>([])
  const listFieldAccess = ref<Api.Fms.CommercialBillFieldAccessMap>({})
  const summary = ref<Api.Fms.CommercialBillSummary>(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, keyword: '', direction: undefined, status: undefined }
  })

  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess))
  )
  const canViewListField = (field: Api.Fms.CommercialBillFieldKey): boolean =>
    canViewField(effectiveFieldAccess.value, field)

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
      label: '票据方向',
      key: 'direction',
      type: 'select',
      props: {
        options: getDictMap.value.fmsBillDirection ?? [],
        clearable: true,
        placeholder: '全部方向'
      }
    },
    {
      label: '票据类型',
      key: 'billType',
      type: 'select',
      props: {
        options: getDictMap.value.fmsBillType ?? [],
        clearable: true,
        placeholder: '全部类型'
      }
    },
    {
      label: '票据状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsBillStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    },
    {
      label: '到期日期',
      key: 'dueDateRange',
      type: 'daterange',
      props: { valueFormat: 'YYYY-MM-DD' }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder:
          canViewListField('billParties') || canViewListField('billReferences')
            ? '票据号、承兑人或往来单位'
            : '票据编号'
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinanceCommercialBill:Add',
      type: 'add',
      label: '新建票据',
      onClick: () =>
        void runWithAccountSet(
          {
            actionLabel: '新建票据',
            activeRequired: true,
            accountSetId: table.search.accountSetId,
            foundationRequired: true,
            available: accountSetOptions.value.length > 0
          },
          () => dialogRef.value?.handleOpen()
        )
    }
  ])

  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'all',
      label: '票据总数',
      value: summary.value.totalCount,
      description: `${summary.value.activeCount} 张待处理`,
      icon: 'ri:bank-card-2-line',
      tone: 'primary',
      interactive: true,
      selected: !table.search.status
    },
    {
      key: 'receivable',
      label: '应收未结',
      value: formatProtectedAmount(summary.value.receivableOutstanding),
      description: '持有中应收票据',
      icon: 'ri:arrow-down-circle-line',
      tone: 'success',
      interactive: true,
      selected: table.search.direction === 'receivable'
    },
    {
      key: 'payable',
      label: '应付未结',
      value: formatProtectedAmount(summary.value.payableOutstanding),
      description: '持有中应付票据',
      icon: 'ri:arrow-up-circle-line',
      tone: 'warning',
      interactive: true,
      selected: table.search.direction === 'payable'
    },
    {
      key: 'due',
      label: '到期风险',
      value: summary.value.overdueCount,
      description: `${summary.value.dueWithin30Days} 张 30 天内到期`,
      icon: 'ri:alarm-warning-line',
      tone: summary.value.overdueCount ? 'danger' : 'info'
    }
  ])

  function columnsFactory(): ColumnOption<Bill>[] {
    return [
      {
        prop: 'billNo',
        label: '票据编号',
        minWidth: 176,
        fixed: 'left',
        formatter: (row) => (
          <button
            class="commercial-bill-link"
            type="button"
            onClick={() => void drawerRef.value?.handleOpen(row)}
          >
            <strong translate="no">{row.billNo}</strong>
            <small>
              {canViewField(row.fieldAccess, 'billReferences')
                ? row.externalBillNo || row.sourceNo || '内部登记'
                : '受保护票据信息'}
            </small>
          </button>
        )
      },
      {
        prop: 'direction',
        label: '方向',
        width: 100,
        dict: { code: 'fmsBillDirection', display: 'tag' }
      },
      {
        prop: 'billType',
        label: '票据类型',
        minWidth: 140,
        dict: { code: 'fmsBillType' }
      },
      ...(canViewListField('billParties')
        ? [
            {
              prop: 'acceptorName',
              label: '承兑人',
              minWidth: 180,
              showOverflowTooltip: true,
              formatter: (row: Bill) => row.acceptorName || '--'
            },
            {
              prop: 'counterpartyName',
              label: '往来单位',
              minWidth: 170,
              showOverflowTooltip: true,
              formatter: (row: Bill) => row.counterpartyName || '--'
            }
          ]
        : []),
      ...(canViewListField('billAmounts')
        ? [
            {
              prop: 'faceAmount',
              label: '票面金额',
              minWidth: 145,
              align: 'right' as const,
              formatter: (row: Bill) => formatProtectedAmount(row.faceAmount, row.currencyCode)
            }
          ]
        : []),
      {
        prop: 'dueDate',
        label: '到期日',
        width: 128,
        formatter: (row) => {
          const overdue = row.status === 'held' && dayjs(row.dueDate).isBefore(dayjs(), 'day')
          return (
            <span class={overdue ? 'commercial-bill-due is-overdue' : 'commercial-bill-due'}>
              {formatWithDayjs(row.dueDate, 'YYYY-MM-DD')}
            </span>
          )
        }
      },
      {
        prop: 'status',
        label: '状态',
        width: 105,
        dict: { code: 'fmsBillStatus', display: 'tag' }
      },
      {
        prop: 'operation',
        label: '操作',
        width: 156,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable
              type="view"
              permission="FinanceCommercialBill:View"
              onClick={() => void drawerRef.value?.handleOpen(row)}
            />
            {row.status === 'draft' ? (
              <ArtButtonTable
                type="edit"
                permission="FinanceCommercialBill:Edit"
                onClick={() => void dialogRef.value?.handleOpen(row)}
              />
            ) : null}
            {getActionItems(row).length ? (
              <ArtButtonMore
                list={getActionItems(row)}
                onClick={(item: ButtonMoreItem) => void handleAction(item, row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }

  function getActionItems(row: Bill): ButtonMoreItem[] {
    if (row.status === 'draft') {
      return [
        {
          auth:
            row.direction === 'receivable'
              ? 'FinanceCommercialBill:Receive'
              : 'FinanceCommercialBill:Issue',
          key: row.direction === 'receivable' ? 'receive' : 'issue',
          label: row.direction === 'receivable' ? '确认收票' : '确认出票',
          icon: row.direction === 'receivable' ? 'ri:inbox-archive-line' : 'ri:send-plane-line',
          color: 'var(--el-color-success)'
        },
        {
          auth: 'FinanceCommercialBill:Delete',
          key: 'delete',
          label: '删除草稿',
          icon: 'ri:delete-bin-line',
          color: 'var(--el-color-danger)'
        }
      ]
    }
    if (row.status === 'held') {
      const actions: ButtonMoreItem[] = []
      if (row.transferable) {
        actions.push({
          auth: 'FinanceCommercialBill:Endorse',
          key: 'endorse',
          label: '背书转让',
          icon: 'ri:exchange-line',
          color: 'var(--el-color-warning)'
        })
      }
      if (row.direction === 'receivable') {
        actions.push({
          auth: 'FinanceCommercialBill:Discount',
          key: 'discount',
          label: '票据贴现',
          icon: 'ri:discount-percent-line',
          color: 'var(--el-color-primary)'
        })
      }
      actions.push(
        {
          auth: 'FinanceCommercialBill:Settle',
          key: 'settle',
          label: '到期结算',
          icon: 'ri:checkbox-circle-line',
          color: 'var(--el-color-success)'
        },
        {
          auth: 'FinanceCommercialBill:Cancel',
          key: 'cancel',
          label: '取消票据',
          icon: 'ri:close-circle-line',
          color: 'var(--el-color-danger)'
        }
      )
      return actions
    }
    return []
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchCommercialBillList({ ...params, from, to })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data ?? []
    return result
  }

  async function loadSummary(): Promise<void> {
    if (!table.search.accountSetId) {
      summary.value = emptySummary()
      return
    }
    const { data } = await fetchCommercialBillSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
    if (data?.fieldAccess) listFieldAccess.value = data.fieldAccess
  }

  function toFiniteNumber(
    value: Api.Tms.BasicData.SensitiveNumber | undefined | null
  ): number | undefined {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : undefined
  }

  function getRemainingAmount(row: Bill): number | undefined {
    const faceAmount = toFiniteNumber(row.faceAmount)
    const settledAmount = toFiniteNumber(row.settledAmount)
    return faceAmount === undefined || settledAmount === undefined
      ? undefined
      : faceAmount - settledAmount
  }

  function formatProtectedAmount(
    value: Api.Tms.BasicData.SensitiveNumber | undefined | null,
    currency = 'CNY'
  ): string {
    if (value === null || value === undefined || value === '') return '--'
    return formatCurrencyValue(value, currency)
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    if (metric.key === 'all') {
      table.search.direction = undefined
      table.search.status = undefined
    } else if (metric.key === 'receivable' || metric.key === 'payable') {
      table.search.direction = metric.key
      table.search.status = undefined
    }
    void tableRef.value?.getData()
  }

  async function handleAction(item: ButtonMoreItem, row: Bill): Promise<void> {
    try {
      if (item.key === 'delete') {
        await confirmAction(`确定删除票据草稿“${row.billNo}”吗？`, '删除票据', {
          type: 'warning',
          confirmButtonText: '确认删除'
        })
        await deleteCommercialBill(row.id)
        await refreshAll('delete')
        return
      }
      const remainingAmount = getRemainingAmount(row)
      if (
        ['endorse', 'discount', 'settle'].includes(String(item.key)) &&
        remainingAmount === undefined
      ) {
        ElMessage.warning('当前字段权限无法读取票据金额，不能执行该票据操作')
        return
      }
      if (item.key === 'discount' || item.key === 'settle') {
        const amount = remainingAmount!
        const direction =
          item.key === 'discount' || row.direction === 'receivable' ? 'inflow' : 'outflow'
        await runWithAccountSet(
          {
            actionLabel: item.label,
            accountSetId: row.accountSetId,
            available: true,
            foundationRequired: true,
            fundAccountRequired: true
          },
          () =>
            fundExecutionRef.value?.handleOpen(
              {
                accountSetId: row.accountSetId,
                amount,
                direction,
                title: `${item.label} · ${row.billNo}`,
                subtitle: '选择实际资金账户，系统会同步登记资金日记账和票据会计凭证',
                confirmText: `${item.label}并入账`,
                accountLabel: direction === 'inflow' ? '入账账户' : '扣款账户'
              },
              async (payload) => {
                await actCommercialBill(row.id, item.key as Api.Fms.CommercialBillAction, {
                  amount,
                  eventDate: payload.actionDate,
                  fundAccountId: payload.fundAccountId,
                  referenceNo: payload.referenceNo
                })
              }
            )
        )
        return
      }
      let remark: string | undefined
      if (item.key === 'cancel') {
        remark = await promptReason('请填写取消原因和后续处理说明。', '取消商业票据', {
          confirmButtonText: '确认取消',
          emptyMessage: '取消原因不能为空',
          placeholder: '填写可审计的业务原因'
        })
      } else {
        const actionMessages: Record<string, string> = {
          receive: '确认后票据进入持有状态，并触发应收票据自动入账事件。',
          issue: '确认后票据进入持有状态，并触发应付票据自动入账事件。',
          endorse: '背书将按票面未结金额全额转让，操作后不可撤回编辑。',
          discount: '贴现将按票面未结金额全额终止确认，并触发贴现入账事件。',
          settle: '结算将按票面未结金额全额结清，并触发到期结算入账事件。'
        }
        await confirmAction(actionMessages[String(item.key)], item.label, {
          type: ['endorse', 'discount', 'settle'].includes(String(item.key)) ? 'warning' : 'info',
          confirmButtonText: item.label
        })
      }
      await actCommercialBill(row.id, item.key as Api.Fms.CommercialBillAction, {
        amount: remainingAmount,
        eventDate: dayjs().format('YYYY-MM-DD'),
        remark
      })
      await refreshAll('update')
    } catch {
      // 用户取消确认或数据库业务约束阻止时不重复提示。
    }
  }

  async function refreshAll(mode: 'add' | 'edit' | 'update' | 'delete'): Promise<void> {
    const refresh =
      mode === 'add'
        ? tableRef.value?.refreshCreate()
        : mode === 'delete'
          ? tableRef.value?.refreshRemove()
          : tableRef.value?.refreshUpdate()
    await Promise.all([refresh, loadSummary()])
  }

  async function handleSaved(type: 'add' | 'edit'): Promise<void> {
    await refreshAll(type)
  }

  watch(
    () => table.search.accountSetId,
    async () => {
      await loadSummary()
    }
  )

  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    table.search.accountSetId = accountSetOptions.value[0]?.value
    await loadSummary()
    await tableRef.value?.getData()
  })
</script>

<style scoped lang="scss">
  :deep(.commercial-bill-link) {
    display: grid;
    gap: 3px;
    max-width: 100%;
    padding: 0;
    color: var(--el-color-primary);
    text-align: left;
    cursor: pointer;
    background: none;
    border: 0;

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

  :deep(.commercial-bill-due.is-overdue) {
    font-weight: 600;
    color: var(--el-color-danger);
  }
</style>
