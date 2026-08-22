<template>
  <div class="business-workspace-page art-full-height fms-accounting-page account-set-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="财务基础 · 核算主体"
      title="账套管理"
      description="以法人主体为边界统一会计准则、本位币和期间治理，为凭证、账簿、报表及业务自动记账提供核算底座。"
      icon="ri:book-2-line"
      :tags="[
        { label: '多账套隔离', type: 'primary' },
        { label: '期间强管控', type: 'success' },
        { label: '全链路审计', type: 'info' }
      ]"
      :metrics="overview.metrics"
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
      :search-bar-props="{
        span: 8,
        gutter: 16,
        labelPosition: 'left',
        labelWidth: '76px',
        showExpand: false,
        buttonLeftLimit: 0
      }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无账套',
        emptyDescription:
          '创建首个企业账套后，系统会自动生成本位币、辅助核算类型和首个会计年度期间。'
      }"
      focusable
    />

    <AccountSetDialog ref="dialogRef" @success="handleSaved" />
    <AccountingPeriodDrawer ref="periodDrawerRef" />
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
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    canViewField,
    getFieldAccess,
    isMaskedValue,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAccountSetList,
    fetchAccountSetOverview,
    initializeAccountingDefaults,
    setAccountSetStatus
  } from '@/api/fms'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import AccountSetDialog from './modules/account-set-dialog.vue'
  import AccountingPeriodDrawer from './modules/accounting-period-drawer.vue'

  defineOptions({ name: 'FinanceAccountSet' })

  type AccountSet = Api.Fms.AccountSetRecord
  type SearchParams = Api.Fms.AccountSetSearchParams
  type TableParams = SearchParams & { current: number; size: number }

  interface AccountSetDialogExpose {
    handleOpen: (row?: AccountSet) => Promise<void>
  }

  interface PeriodDrawerExpose {
    handleOpen: (row: AccountSet) => Promise<void>
  }

  interface TableGroup {
    search: SearchParams
    tenantOptions: Array<{ label: string; value: string }>
  }

  interface OverviewGroup {
    loading: boolean
    metrics: BusinessWorkspaceMetric[]
  }

  const { confirmAction, promptReason } = useArtFeedback()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const dialogRef = ref<AccountSetDialogExpose>()
  const periodDrawerRef = ref<PeriodDrawerExpose>()
  const tableRef = ref<ArtTableQueryExpose>()
  const currentRows = ref<AccountSet[]>([])
  const listFieldAccess = ref<Api.Fms.AccountSetFieldAccessMap>({})
  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(listFieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess))
  )
  const canViewListField = (field: Api.Fms.AccountSetFieldKey): boolean =>
    canViewField(effectiveFieldAccess.value, field)
  const table = reactive<TableGroup>({
    search: { keyword: '', tenantId: undefined, status: undefined },
    tenantOptions: []
  })
  const overview = reactive<OverviewGroup>({ loading: true, metrics: [] })

  const searchItems = computed<SearchFormItem[]>(() => [
    ...(isPlatformSuper.value
      ? [
          {
            label: '所属租户',
            key: 'tenantId',
            type: 'select' as const,
            props: {
              clearable: true,
              filterable: true,
              options: table.tenantOptions,
              placeholder: '全部租户'
            }
          }
        ]
      : []),
    {
      label: '账套状态',
      key: 'status',
      type: 'select',
      props: {
        clearable: true,
        options: getDictMap.value.fmsAccountSetStatus ?? [],
        placeholder: '全部状态'
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: ['read', 'edit'].includes(
          getFieldAccess(listFieldAccess.value, 'taxRegistration')
        )
          ? '账套编码、名称、法人主体或信用代码'
          : '账套编码、名称或法人主体'
      }
    }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinanceAccountSet:Add',
      type: 'add',
      label: '新建企业账套',
      onClick: () => void dialogRef.value?.handleOpen()
    }
  ])

  function columnsFactory(): ColumnOption<AccountSet>[] {
    return [
      {
        prop: 'accountSetName',
        label: '账套',
        minWidth: 230,
        fixed: 'left',
        formatter: (row) => (
          <div class="account-set-identity">
            <div>
              <strong title={row.accountSetName}>{row.accountSetName}</strong>
              {row.isDefault ? (
                <ElTag size="small" type="primary">
                  默认
                </ElTag>
              ) : null}
            </div>
            <small title={row.accountSetCode} translate="no">
              {row.accountSetCode}
            </small>
          </div>
        )
      },
      ...(isPlatformSuper.value
        ? [
            {
              prop: 'tenant',
              label: '所属租户',
              minWidth: 190,
              formatter: (row: AccountSet) => (
                <div class="account-set-tenant">
                  <strong title={row.tenant?.tenantName || '未识别租户'}>
                    {row.tenant?.tenantName || '未识别租户'}
                  </strong>
                  <small title={row.tenant?.tenantCode || row.tenantId} translate="no">
                    {row.tenant?.tenantCode || row.tenantId}
                  </small>
                </div>
              )
            } satisfies ColumnOption<AccountSet>
          ]
        : []),
      {
        prop: 'legalEntityName',
        label: '法人主体',
        minWidth: 210,
        showOverflowTooltip: true
      },
      ...(canViewListField('accountingPolicy')
        ? ([
            {
              prop: 'accountingStandard',
              label: '会计准则',
              minWidth: 190,
              dict: { code: 'fmsAccountingStandard', display: 'text' }
            },
            {
              prop: 'baseCurrencyCode',
              label: '本位币',
              width: 90,
              align: 'center'
            },
            {
              prop: 'enabledOn',
              label: '启用日期',
              width: 120,
              formatter: (row: AccountSet) =>
                isMaskedValue(row.enabledOn)
                  ? row.enabledOn
                  : formatWithDayjs(row.enabledOn, 'YYYY-MM-DD') || '--'
            }
          ] as ColumnOption<AccountSet>[])
        : []),
      ...(canViewListField('taxRegistration')
        ? ([
            {
              prop: 'vatTaxpayerType',
              label: '纳税人类型',
              width: 135,
              dict: { code: 'fmsVatTaxpayerType', display: 'tag' }
            }
          ] as ColumnOption<AccountSet>[])
        : []),
      {
        prop: 'status',
        label: '状态',
        width: 105,
        dict: { code: 'fmsAccountSetStatus', display: 'tag' }
      },
      ...(canViewListField('administrativeAudit')
        ? ([
            {
              prop: 'updateTime',
              label: '最近更新',
              width: 165,
              formatter: (row: AccountSet) =>
                isMaskedValue(row.updateTime)
                  ? row.updateTime
                  : formatWithDayjs(row.updateTime, 'YYYY-MM-DD HH:mm') || '--'
            }
          ] as ColumnOption<AccountSet>[])
        : []),
      {
        prop: 'operation',
        label: '操作',
        width: 150,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable
              type="view"
              permission="FinanceAccountSet:View"
              label="查看会计期间"
              onClick={() => void periodDrawerRef.value?.handleOpen(row)}
            />
            <ArtButtonTable
              type="edit"
              permission="FinanceAccountSet:Edit"
              label="编辑账套"
              disabled={row.status === 'archived'}
              onClick={() => void dialogRef.value?.handleOpen(row)}
            />
            {getStatusActions(row).length ? (
              <ArtButtonMore
                list={getStatusActions(row)}
                onClick={(item: ButtonMoreItem) => void handleStatusAction(item, row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }

  function getStatusActions(row: AccountSet): ButtonMoreItem[] {
    if (row.status === 'archived') return []
    if (row.status === 'draft') {
      return [
        {
          key: 'active',
          label: '启用账套',
          icon: 'ri:play-circle-line'
        },
        {
          auth: 'FinanceAccountSet:Archived',
          key: 'archived',
          label: '归档账套',
          icon: 'ri:archive-line',
          color: 'var(--el-color-danger)'
        }
      ]
    }
    if (row.status === 'active') {
      return [
        {
          auth: 'FinanceAccountSet:Suspended',
          key: 'suspended',
          label: '停用账套',
          icon: 'ri:pause-circle-line'
        },
        {
          auth: 'FinanceAccountSet:Archived',
          key: 'archived',
          label: '归档账套',
          icon: 'ri:archive-line',
          color: 'var(--el-color-danger)'
        }
      ]
    }
    return [
      {
        auth: 'FinanceAccountSet:Active',
        key: 'active',
        label: '恢复启用',
        icon: 'ri:restart-line'
      },
      {
        auth: 'FinanceAccountSet:Archived',
        key: 'archived',
        label: '归档账套',
        icon: 'ri:archive-line',
        color: 'var(--el-color-danger)'
      }
    ]
  }

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchAccountSetList({ ...params, from, to })
    listFieldAccess.value = result.fieldAccess
    currentRows.value = result.data ?? []
    return result
  }

  async function loadOverview(): Promise<void> {
    overview.loading = true
    try {
      const { data } = await fetchAccountSetOverview(table.search.tenantId)
      const values = data ?? { totalCount: 0, activeCount: 0, draftCount: 0, suspendedCount: 0 }
      const selectedStatus = table.search.status
      overview.metrics = [
        {
          key: 'all',
          label: '全部账套',
          value: values.totalCount,
          description: '当前可见核算主体',
          icon: 'ri:book-2-line',
          tone: 'primary',
          interactive: true,
          selected: !selectedStatus,
          loading: false
        },
        {
          key: 'active',
          label: '启用账套',
          value: values.activeCount,
          description: '允许进入日常核算',
          icon: 'ri:checkbox-circle-line',
          tone: 'success',
          interactive: true,
          selected: selectedStatus === 'active',
          loading: false
        },
        {
          key: 'draft',
          label: '待配置',
          value: values.draftCount,
          description: '需要完成核算初始化',
          icon: 'ri:draft-line',
          tone: 'warning',
          interactive: true,
          selected: selectedStatus === 'draft',
          loading: false
        },
        {
          key: 'suspended',
          label: '已停用',
          value: values.suspendedCount,
          description: '保留数据但暂停使用',
          icon: 'ri:pause-circle-line',
          tone: 'danger',
          interactive: true,
          selected: selectedStatus === 'suspended',
          loading: false
        }
      ]
    } finally {
      overview.loading = false
    }
  }

  function handleMetricClick(metric: BusinessWorkspaceMetric): void {
    table.search.status =
      metric.key === 'active' || metric.key === 'draft' || metric.key === 'suspended'
        ? metric.key
        : undefined
    void tableRef.value?.getData()
    void loadOverview()
  }

  async function handleStatusAction(item: ButtonMoreItem, row: AccountSet): Promise<void> {
    const status = item.key as Api.Fms.AccountSetStatus
    try {
      let reason: string | undefined
      if (status === 'suspended' || status === 'archived') {
        reason = await promptReason(
          status === 'archived'
            ? '归档后账套不可恢复，但历史财务数据仍保留可查。'
            : '停用后账套暂停新增核算业务，历史数据仍保留可查。',
          status === 'archived' ? '归档账套' : '停用账套',
          {
            confirmButtonText: status === 'archived' ? '确认归档' : '确认停用',
            emptyMessage: '请填写状态变更原因',
            placeholder: '请说明原因和后续处理安排'
          }
        )
      } else {
        await confirmAction(
          `启用“${row.accountSetName}”时会同步补齐缺失的核心科目、默认制证规则和财务报表映射；已有配置不会被覆盖。`,
          '初始化并启用账套',
          {
            type: 'success',
            confirmButtonText: '初始化并启用',
            cancelButtonText: '取消'
          }
        )
        await initializeAccountingDefaults(row.id)
      }
      await setAccountSetStatus(row.id, status, reason)
      await Promise.all([tableRef.value?.refreshUpdate(), loadOverview()])
    } catch {
      // 用户取消或数据库业务约束阻止时，不重复提示。
    }
  }

  async function handleSaved(type: 'add' | 'edit'): Promise<void> {
    await Promise.all([
      type === 'add' ? tableRef.value?.refreshCreate() : tableRef.value?.refreshUpdate(),
      loadOverview()
    ])
  }

  async function loadTenantOptions(): Promise<void> {
    if (!isPlatformSuper.value) return
    const { data } = await fetchGetEnableTenantList()
    table.tenantOptions = (data ?? [])
      .filter((tenant): tenant is Api.SystemManage.TenantListItem & { id: string } =>
        Boolean(tenant.id)
      )
      .map((tenant) => ({
        label: `${tenant.tenantName}（${tenant.tenantCode}）`,
        value: tenant.id
      }))
  }

  watch(
    () => table.search.tenantId,
    () => void loadOverview()
  )

  onMounted(() => {
    void Promise.all([loadTenantOptions(), loadOverview()])
  })
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .account-set-page {
    @include accounting.accounting-workspace-layout;

    &__permission {
      flex: 0 0 auto;
    }
  }

  :deep(.account-set-identity),
  :deep(.account-set-tenant) {
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

    strong {
      min-width: 0;
      color: var(--el-text-color-primary);
    }

    small {
      margin-top: 3px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }
</style>
