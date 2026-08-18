<template>
  <div class="business-workspace-page art-full-height fms-accounting-page commercial-bill-page">
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
    />

    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户票据台账；新增、编辑和票据流转仅平台超级管理员可执行。"
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
        emptyText: '暂无商业票据',
        emptyDescription: isPlatformSuper
          ? '新建票据草稿，并按业务方向确认收票或出票。'
          : '当前租户暂无可查看的商业票据记录。'
      }"
      focusable
    />

    <CommercialBillDialog ref="dialogRef" @success="handleSaved" />
    <CommercialBillDetailDrawer ref="drawerRef" />
  </div>
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

  const emptySummary = (): Api.Fms.CommercialBillSummary => ({
    totalCount: 0,
    activeCount: 0,
    receivableOutstanding: 0,
    payableOutstanding: 0,
    dueWithin30Days: 0,
    overdueCount: 0
  })

  const { confirmAction, promptReason } = useArtFeedback()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const summary = ref<Api.Fms.CommercialBillSummary>(emptySummary())
  const table = reactive<{ search: SearchParams }>({
    search: { accountSetId: undefined, keyword: '', direction: undefined, status: undefined }
  })

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
      props: { clearable: true, placeholder: '票据号、承兑人或往来单位' }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [
          {
            type: 'add',
            label: '新建票据',
            onClick: () => void dialogRef.value?.handleOpen()
          }
        ]
      : []
  )

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
      value: formatCurrencyValue(summary.value.receivableOutstanding),
      description: '持有中应收票据',
      icon: 'ri:arrow-down-circle-line',
      tone: 'success',
      interactive: true,
      selected: table.search.direction === 'receivable'
    },
    {
      key: 'payable',
      label: '应付未结',
      value: formatCurrencyValue(summary.value.payableOutstanding),
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
            <small>{row.externalBillNo || row.sourceNo || '内部登记'}</small>
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
      {
        prop: 'acceptorName',
        label: '承兑人',
        minWidth: 180,
        showOverflowTooltip: true
      },
      {
        prop: 'counterpartyName',
        label: '往来单位',
        minWidth: 170,
        showOverflowTooltip: true,
        formatter: (row) => row.counterpartyName || '--'
      },
      {
        prop: 'faceAmount',
        label: '票面金额',
        minWidth: 145,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.faceAmount, row.currencyCode)
      },
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
        width: isPlatformSuper.value ? 156 : 76,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="view" onClick={() => void drawerRef.value?.handleOpen(row)} />
            {isPlatformSuper.value && row.status === 'draft' ? (
              <ArtButtonTable type="edit" onClick={() => void dialogRef.value?.handleOpen(row)} />
            ) : null}
            {isPlatformSuper.value && getActionItems(row).length ? (
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
          key: row.direction === 'receivable' ? 'receive' : 'issue',
          label: row.direction === 'receivable' ? '确认收票' : '确认出票',
          icon: row.direction === 'receivable' ? 'ri:inbox-archive-line' : 'ri:send-plane-line',
          color: 'var(--el-color-success)'
        },
        {
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
          key: 'endorse',
          label: '背书转让',
          icon: 'ri:exchange-line',
          color: 'var(--el-color-warning)'
        })
      }
      if (row.direction === 'receivable') {
        actions.push({
          key: 'discount',
          label: '票据贴现',
          icon: 'ri:discount-percent-line',
          color: 'var(--el-color-primary)'
        })
      }
      actions.push(
        {
          key: 'settle',
          label: '到期结算',
          icon: 'ri:checkbox-circle-line',
          color: 'var(--el-color-success)'
        },
        {
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
    return await fetchCommercialBillList({ ...params, from, to })
  }

  async function loadSummary(): Promise<void> {
    if (!table.search.accountSetId) {
      summary.value = emptySummary()
      return
    }
    const { data } = await fetchCommercialBillSummary(table.search.accountSetId)
    summary.value = data ?? emptySummary()
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
        amount: row.faceAmount - row.settledAmount,
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
  @use '../modules/accounting-workspace.scss' as accounting;

  .commercial-bill-page {
    @include accounting.accounting-workspace-layout;
  }

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
