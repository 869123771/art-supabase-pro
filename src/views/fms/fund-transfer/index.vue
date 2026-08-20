<template>
  <div class="business-workspace-page art-full-height fms-accounting-page fund-transfer-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="TREASURY CONTROL"
      title="资金调拨"
      description="以审批、余额校验和双边资金流水管控企业内部账户调拨，执行与冲销均保留完整操作轨迹。"
      icon="ri:swap-2-line"
      :tags="[
        { label: '同账套同币种', type: 'primary' },
        { label: '审批后执行', type: 'success' },
        { label: '可审计冲销', type: 'info' }
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
        emptyText: '暂无资金调拨',
        emptyDescription: '创建调拨草稿，经提交、审批和执行后自动形成双边资金流水。'
      }"
      focusable
    />

    <FundTransferDialog ref="dialogRef" @success="handleSaved" />
    <FundTransferDetailDrawer ref="drawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { storeToRefs } from 'pinia'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteFundTransfer,
    fetchAccountSetOptions,
    fetchFundAccountOptions,
    fetchFundTransferList,
    transitionFundTransfer
  } from '@/api/fms'
  import FundTransferDialog from './modules/fund-transfer-dialog.vue'
  import FundTransferDetailDrawer from './modules/fund-transfer-detail-drawer.vue'

  defineOptions({ name: 'FinanceFundTransfer' })

  type Transfer = Api.Fms.FundTransferRecord
  type SearchParams = Api.Fms.FundTransferSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  interface DialogExpose {
    handleOpen: (row?: Transfer) => Promise<void>
  }
  interface DrawerExpose {
    handleOpen: (row: Transfer) => Promise<void>
  }

  const { confirmAction, promptReason } = useArtFeedback()
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])
  const overviewRows = ref<Transfer[]>([])
  const table = reactive<{ search: SearchParams }>({
    search: { keyword: '', accountSetId: undefined, status: undefined }
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
      label: '调拨账户',
      key: 'sourceAccountId',
      type: 'select',
      props: {
        options: accountOptions.value,
        clearable: true,
        filterable: true,
        placeholder: '全部转出账户'
      }
    },
    {
      label: '调拨状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsFundTransferStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    },
    {
      label: '调拨日期',
      key: 'transferDateRange',
      type: 'daterange',
      props: { valueFormat: 'YYYY-MM-DD' }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '调拨单号、用途、银行参考号或账户名称' }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinanceFundTransfer:Add',
      type: 'add',
      label: '新建资金调拨',
      onClick: () =>
        void runWithAccountSet(
          {
            actionLabel: '新建资金调拨',
            activeRequired: true,
            accountSetId: table.search.accountSetId,
            foundationRequired: true,
            fundAccountRequired: true,
            available: accountSetOptions.value.length > 0
          },
          () => dialogRef.value?.handleOpen()
        )
    }
  ])

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const selected = table.search.status
    const count = (status: Api.Fms.FundTransferStatus) =>
      overviewRows.value.filter((row) => row.status === status).length
    const completedAmount = overviewRows.value
      .filter((row) => row.status === 'completed')
      .reduce((sum, row) => sum + Number(row.amount || 0), 0)
    return [
      {
        key: 'all',
        label: '全部调拨',
        value: overviewRows.value.length,
        description: '当前可见调拨单',
        icon: 'ri:swap-2-line',
        tone: 'primary',
        interactive: true,
        selected: !selected
      },
      {
        key: 'pending_review',
        label: '待审批',
        value: count('pending_review'),
        description: '等待资金审批',
        icon: 'ri:time-line',
        tone: 'warning',
        interactive: true,
        selected: selected === 'pending_review'
      },
      {
        key: 'approved',
        label: '待执行',
        value: count('approved'),
        description: '已审批未入账',
        icon: 'ri:play-circle-line',
        tone: 'primary',
        interactive: true,
        selected: selected === 'approved'
      },
      {
        key: 'completed',
        label: '已完成金额',
        value: formatCurrencyValue(completedAmount),
        description: `${count('completed')} 笔已入账`,
        icon: 'ri:checkbox-circle-line',
        tone: 'success',
        interactive: true,
        selected: selected === 'completed'
      }
    ]
  })

  function columnsFactory(): ColumnOption<Transfer>[] {
    return [
      {
        prop: 'transferNo',
        label: '调拨单号',
        minWidth: 175,
        fixed: 'left',
        formatter: (row) => (
          <button
            class="fund-transfer-link"
            type="button"
            onClick={() => void drawerRef.value?.handleOpen(row)}
          >
            <strong translate="no">{row.transferNo}</strong>
            <small>{formatWithDayjs(row.transferDate, 'YYYY-MM-DD')}</small>
          </button>
        )
      },
      {
        prop: 'sourceAccountName',
        label: '转出账户',
        minWidth: 190,
        formatter: (row) => (
          <div class="fund-transfer-account">
            <strong>{row.sourceAccountName}</strong>
            <small>{row.sourceAccountNoMasked}</small>
          </div>
        )
      },
      {
        prop: 'targetAccountName',
        label: '转入账户',
        minWidth: 190,
        formatter: (row) => (
          <div class="fund-transfer-account">
            <strong>{row.targetAccountName}</strong>
            <small>{row.targetAccountNoMasked}</small>
          </div>
        )
      },
      {
        prop: 'amount',
        label: '调拨金额',
        minWidth: 145,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.amount, row.currencyCode)
      },
      {
        prop: 'feeAmount',
        label: '手续费',
        width: 120,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.feeAmount, row.currencyCode)
      },
      { prop: 'purpose', label: '调拨用途', minWidth: 200, showOverflowTooltip: true },
      {
        prop: 'status',
        label: '状态',
        width: 105,
        dict: { code: 'fmsFundTransferStatus', display: 'tag' }
      },
      {
        prop: 'updateTime',
        label: '最近更新',
        width: 165,
        formatter: (row) => formatWithDayjs(row.updateTime, 'YYYY-MM-DD HH:mm') || '--'
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
              permission="FinanceFundTransfer:View"
              onClick={() => void drawerRef.value?.handleOpen(row)}
            />
            {['draft', 'rejected'].includes(row.status) ? (
              <ArtButtonTable
                type="edit"
                permission="FinanceFundTransfer:Edit"
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

  function getActionItems(row: Transfer): ButtonMoreItem[] {
    if (['draft', 'rejected'].includes(row.status)) {
      return [
        {
          auth: 'FinanceFundTransfer:Submit',
          key: 'submit',
          label: '提交审批',
          icon: 'ri:send-plane-line',
          color: 'var(--el-color-primary)'
        },
        {
          auth: 'FinanceFundTransfer:Delete',
          key: 'delete',
          label: '删除草稿',
          icon: 'ri:delete-bin-line',
          color: 'var(--el-color-danger)'
        }
      ]
    }
    if (row.status === 'pending_review') {
      return [
        {
          auth: 'FinanceFundTransfer:Approve',
          key: 'approve',
          label: '审批通过',
          icon: 'ri:check-line',
          color: 'var(--el-color-success)'
        },
        {
          auth: 'FinanceFundTransfer:Reject',
          key: 'reject',
          label: '驳回',
          icon: 'ri:close-line',
          color: 'var(--el-color-danger)'
        }
      ]
    }
    if (row.status === 'approved') {
      return [
        {
          auth: 'FinanceFundTransfer:Execute',
          key: 'execute',
          label: '执行入账',
          icon: 'ri:play-line',
          color: 'var(--el-color-success)'
        }
      ]
    }
    if (row.status === 'completed') {
      return [
        {
          auth: 'FinanceFundTransfer:Reverse',
          key: 'reverse',
          label: '冲销调拨',
          icon: 'ri:arrow-go-back-line',
          color: 'var(--el-color-warning)'
        }
      ]
    }
    return []
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchFundTransferList({ ...params, from, to })
  }

  async function loadOverview(): Promise<void> {
    const { data } = await fetchFundTransferList({
      accountSetId: table.search.accountSetId,
      from: 0,
      to: 999
    })
    overviewRows.value = data ?? []
  }

  async function loadAccountOptions(accountSetId?: string): Promise<void> {
    table.search.sourceAccountId = undefined
    if (!accountSetId) {
      accountOptions.value = []
      return
    }
    const { data } = await fetchFundAccountOptions({ accountSetId, status: 'active' })
    accountOptions.value = data ?? []
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    table.search.status =
      metric.key === 'all' ? undefined : (metric.key as Api.Fms.FundTransferStatus)
    void tableRef.value?.getData()
  }

  async function handleAction(item: ButtonMoreItem, row: Transfer): Promise<void> {
    try {
      if (item.key === 'delete') {
        await confirmAction(`确定删除调拨草稿“${row.transferNo}”吗？`, '删除资金调拨', {
          type: 'warning',
          confirmButtonText: '确认删除'
        })
        await deleteFundTransfer(row.id)
        await refreshAll('delete')
        return
      }
      let reason: string | undefined
      if (item.key === 'reject' || item.key === 'reverse') {
        reason = await promptReason(
          item.key === 'reject'
            ? '请说明驳回原因和修改要求。'
            : '冲销会生成反向资金流水，请说明业务原因。',
          item.key === 'reject' ? '驳回资金调拨' : '冲销资金调拨',
          { emptyMessage: '请填写原因', placeholder: '填写可审计的处理原因' }
        )
      } else {
        const messages: Record<string, string> = {
          submit: '提交后将进入资金审批流程。',
          approve: '审批通过后仍需执行入账，当前操作不会立即改变余额。',
          execute: `执行后将从“${row.sourceAccountName}”扣减 ${formatCurrencyValue(row.amount + row.feeAmount, row.currencyCode)}。`
        }
        await confirmAction(messages[item.key] || '确定执行该操作吗？', item.label, {
          type: item.key === 'execute' ? 'warning' : 'info',
          confirmButtonText: item.label
        })
      }
      await transitionFundTransfer(
        row.id,
        item.key as Exclude<Api.Fms.FundTransferAction, 'create' | 'edit'>,
        {
          reason,
          executionDate: ['execute', 'reverse'].includes(String(item.key))
            ? dayjs().format('YYYY-MM-DD')
            : null,
          version: row.version
        }
      )
      await refreshAll('update')
    } catch {
      // 用户取消或数据库业务约束阻止时不重复提示。
    }
  }

  async function refreshAll(mode: 'add' | 'edit' | 'update' | 'delete'): Promise<void> {
    const refresh =
      mode === 'add'
        ? tableRef.value?.refreshCreate()
        : mode === 'delete'
          ? tableRef.value?.refreshRemove()
          : tableRef.value?.refreshUpdate()
    await Promise.all([refresh, loadOverview()])
  }

  async function handleSaved(type: 'add' | 'edit'): Promise<void> {
    await refreshAll(type)
  }

  watch(
    () => table.search.accountSetId,
    () => void loadOverview()
  )

  onMounted(async () => {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    await loadOverview()
  })
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .fund-transfer-page {
    @include accounting.accounting-workspace-layout;
  }

  :deep(.fund-transfer-link) {
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

  :deep(.fund-transfer-account) {
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
