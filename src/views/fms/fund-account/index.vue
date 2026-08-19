<template>
  <div class="business-workspace-page art-full-height fms-accounting-page fund-account-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="TREASURY FOUNDATION"
      title="资金账户"
      description="统一管理银行账户、现金账户与数字钱包，以受控账户主数据承接收付款、资金调拨、日记账和银行对账。"
      icon="ri:bank-card-line"
      :tags="[
        { label: '账号脱敏', type: 'primary' },
        { label: '多币种隔离', type: 'success' },
        { label: '余额可追溯', type: 'info' }
      ]"
      :metrics="metrics"
      @metric-click="handleMetricClick"
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
      title="当前账号处于资金只读模式，可查看本租户账户与余额；账户配置、冻结和关闭仅平台超级管理员可执行。"
    />

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
        emptyText: '暂无资金账户',
        emptyDescription: isPlatformSuper
          ? '创建首个资金账户后，收付款、资金调拨与银行对账即可关联实际账户。'
          : '当前租户尚未配置可查看的资金账户。'
      }"
      focusable
    />

    <FundAccountDialog ref="dialogRef" @success="handleSaved" />
  </div>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
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
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteFundAccount,
    fetchAccountSetOptions,
    fetchFundAccountList,
    fetchFundAccountOverview
  } from '@/api/fms'
  import FundAccountDialog from './modules/fund-account-dialog.vue'

  defineOptions({ name: 'FinanceFundAccount' })

  type Account = Api.Fms.FundAccountRecord
  type SearchParams = Api.Fms.FundAccountSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  interface DialogExpose {
    handleOpen: (row?: Account) => Promise<void>
  }

  const { confirmAction } = useArtFeedback()
  const { runWithAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const overview = ref<Api.Fms.FundAccountOverview>()
  const table = reactive<{ search: SearchParams }>({
    search: { keyword: '', accountSetId: undefined, accountType: undefined, status: undefined }
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
        placeholder: '全部账套'
      }
    },
    {
      label: '账户类型',
      key: 'accountType',
      type: 'select',
      props: {
        options: getDictMap.value.fmsFundAccountType ?? [],
        clearable: true,
        placeholder: '全部类型'
      }
    },
    {
      label: '账户状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.fmsFundAccountStatus ?? [],
        clearable: true,
        placeholder: '全部状态'
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '账户编码、名称、开户行或账号尾号' }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() =>
    isPlatformSuper.value
      ? [
          {
            type: 'add',
            label: '新建资金账户',
            onClick: () =>
              void runWithAccountSet(
                {
                  actionLabel: '新建资金账户',
                  activeRequired: true,
                  available: accountSetOptions.value.length > 0
                },
                () => dialogRef.value?.handleOpen()
              )
          }
        ]
      : []
  )

  const metrics = computed<BusinessWorkspaceMetric[]>(() => {
    const value = overview.value
    return [
      {
        key: 'all',
        label: '资金账户',
        value: value?.accountCount ?? 0,
        description: '当前可见账户总数',
        icon: 'ri:bank-card-line',
        tone: 'primary',
        interactive: true,
        selected: !table.search.status
      },
      {
        key: 'active',
        label: '正常账户',
        value: value?.activeAccountCount ?? 0,
        description: '可承接日常资金业务',
        icon: 'ri:checkbox-circle-line',
        tone: 'success',
        interactive: true,
        selected: table.search.status === 'active'
      },
      {
        key: 'balance',
        label: '本位币余额',
        value: formatCurrencyValue(value?.baseCurrencyCurrentBalance ?? 0),
        description: '不跨币种直接相加',
        icon: 'ri:money-cny-circle-line',
        tone: 'primary'
      },
      {
        key: 'available',
        label: '本位币可用',
        value: formatCurrencyValue(value?.baseCurrencyAvailableBalance ?? 0),
        description: `外币账户 ${value?.foreignCurrencyAccountCount ?? 0} 个`,
        icon: 'ri:safe-2-line',
        tone: 'warning'
      }
    ]
  })

  function columnsFactory(): ColumnOption<Account>[] {
    return [
      {
        prop: 'accountName',
        label: '资金账户',
        minWidth: 230,
        fixed: 'left',
        formatter: (row) => (
          <div class="fund-account-identity">
            <div>
              <strong title={row.accountName}>{row.accountName}</strong>
              {row.isDefault ? <ElTag size="small">默认</ElTag> : null}
            </div>
            <small translate="no">
              {row.accountCode} · {row.accountNoMasked}
            </small>
          </div>
        )
      },
      {
        prop: 'accountSet',
        label: '所属账套',
        minWidth: 180,
        formatter: (row) => row.accountSet?.accountSetName || '--'
      },
      {
        prop: 'accountType',
        label: '类型',
        width: 115,
        dict: { code: 'fmsFundAccountType', display: 'tag' }
      },
      {
        prop: 'bankName',
        label: '开户机构',
        minWidth: 160,
        showOverflowTooltip: true,
        formatter: (row) => row.bankName || (row.accountType === 'cash' ? '企业现金' : '--')
      },
      {
        prop: 'currency',
        label: '币种',
        width: 100,
        align: 'center',
        formatter: (row) => row.currency?.currencyCode || '--'
      },
      {
        prop: 'currentBalance',
        label: '当前余额',
        minWidth: 145,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.currentBalance, row.currency?.currencyCode)
      },
      {
        prop: 'availableBalance',
        label: '可用余额',
        minWidth: 145,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.availableBalance, row.currency?.currencyCode)
      },
      {
        prop: 'ledgerEntryCount',
        label: '流水数',
        width: 90,
        align: 'right'
      },
      {
        prop: 'status',
        label: '状态',
        width: 100,
        dict: { code: 'fmsFundAccountStatus', display: 'tag' }
      },
      {
        prop: 'latestBalanceDate',
        label: '余额日期',
        width: 120,
        formatter: (row) => formatWithDayjs(row.latestBalanceDate, 'YYYY-MM-DD') || '--'
      },
      {
        prop: 'operation',
        label: '操作',
        width: isPlatformSuper.value ? 104 : 70,
        fixed: 'right',
        formatter: (row) =>
          isPlatformSuper.value ? (
            <div class="flex items-center">
              <ArtButtonTable type="edit" onClick={() => void dialogRef.value?.handleOpen(row)} />
              <ArtButtonTable
                type="delete"
                disabled={row.ledgerEntryCount > 0}
                onClick={() => void handleDelete(row)}
              />
            </div>
          ) : (
            <span class="text-sm text-g-500">只读</span>
          )
      }
    ]
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return await fetchFundAccountList({ ...params, from, to })
  }

  async function loadOverview(): Promise<void> {
    const { data } = await fetchFundAccountOverview(table.search.accountSetId)
    overview.value = data ?? undefined
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    if (metric.key !== 'all' && metric.key !== 'active') return
    table.search.status = metric.key === 'active' ? 'active' : undefined
    void Promise.all([tableRef.value?.getData(), loadOverview()])
  }

  async function handleDelete(row: Account): Promise<void> {
    try {
      await confirmAction(
        `确定删除资金账户“${row.accountName}”吗？已有业务或流水的账户不能删除，应改为关闭。`,
        '删除资金账户',
        { type: 'warning', confirmButtonText: '确认删除' }
      )
      await deleteFundAccount(row.id)
      await Promise.all([tableRef.value?.refreshRemove(), loadOverview()])
    } catch {
      // 用户取消或业务约束阻止时不重复提示。
    }
  }

  async function handleSaved(type: 'add' | 'edit'): Promise<void> {
    await Promise.all([
      type === 'add' ? tableRef.value?.refreshCreate() : tableRef.value?.refreshUpdate(),
      loadOverview()
    ])
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

  .fund-account-page {
    @include accounting.accounting-workspace-layout;
  }

  :deep(.fund-account-identity) {
    min-width: 0;

    > div {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;
    }

    strong,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      margin-top: 3px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }
</style>
