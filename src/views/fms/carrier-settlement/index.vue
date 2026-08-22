<template>
  <div class="business-workspace-page art-full-height">
    <MasterDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已自动定位关联对账单；财务历史不可随主数据级联删除。"
    />
    <BusinessWorkspaceHeader
      eyebrow="CARRIER SETTLEMENT"
      title="承运商对账"
      description="归集承运成本与结算周期，跟踪账单确认、付款申请和供应商结算进度。"
      icon="ri:hand-coin-line"
      :tags="[
        { label: '应付对账', type: 'primary' },
        { label: '成本核验', type: 'warning' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无承运商对账单',
        emptyDescription: '可创建承运商对账单，或调整承运商、状态、周期和单号后查询。'
      }"
      focusable
    />
    <CarrierStatementDialog ref="dialogRef" @success="handleCreateSuccess" />
    <CarrierStatementDetailDrawer ref="drawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    deleteCarrierStatement,
    exportCarrierStatementList,
    fetchCarrierOptions,
    fetchCarrierStatementList,
    updateCarrierStatementStatus
  } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import {
    canViewField,
    formatSensitiveNumber,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import CarrierStatementDialog from './modules/carrier-statement-dialog.vue'
  import CarrierStatementDetailDrawer from './modules/carrier-statement-detail-drawer.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'FinanceCarrierSettlement' })

  type Statement = Api.Fms.CarrierStatementRecord
  type StatementFieldKey = Api.Fms.CarrierStatementFieldKey
  type SearchParams = Api.Fms.CarrierStatementSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  const { getDictMap } = storeToRefs(useUserStore())
  const { promptReason, confirmAction } = useArtFeedback()
  const { hasAuth } = useAuth()
  const route = useRoute()
  const deleteContext = useMasterDataDeleteProcessingContext()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Statement) => Promise<void> }>()
  const carrierOptions = ref<Array<{ label: string; value: string }>>([])
  const fieldAccess = ref<Api.Fms.CarrierStatementFieldAccessMap>({})
  const currentRows = ref<Statement[]>([])
  const searchQuery = reactive<SearchParams>({
    carrierId: deleteContext.value.carrierId,
    keyword: '',
    periodRange: [],
    recordId: deleteContext.value.recordId,
    status: typeof route.query.status === 'string' ? route.query.status : ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '对账承运商',
      key: 'carrierId',
      type: 'select',
      props: {
        options: carrierOptions.value,
        filterable: true,
        clearable: true,
        placeholder: '请选择承运商'
      }
    },
    {
      label: '对账状态',
      key: 'status',
      type: 'select',
      props: { options: getDictMap.value.tmsSettlementStatus ?? [], clearable: true }
    },
    {
      label: '对账账期',
      key: 'periodRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至'
      }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '对账单号、承运商或备注' }
    }
  ])

  const formatMoney = (value?: number | string | null): string => {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
  }

  const renderStatusActions = (row: Statement) => {
    if (row.status === 'draft')
      return (
        <>
          {hasAuth('FinanceCarrierSettlement:Submit') ? (
            <ElButton link type="primary" onClick={() => void changeStatus(row, 'pending_review')}>
              提交审核
            </ElButton>
          ) : null}
          {hasAuth('FinanceCarrierSettlement:Delete') ? (
            <ElButton link type="danger" onClick={() => void handleDelete(row)}>
              删除
            </ElButton>
          ) : null}
        </>
      )
    if (row.status === 'pending_review')
      return (
        <>
          {hasAuth('FinanceCarrierSettlement:Approve') ? (
            <ElButton link type="success" onClick={() => void changeStatus(row, 'confirmed')}>
              审核通过
            </ElButton>
          ) : null}
          {hasAuth('FinanceCarrierSettlement:Reject') ? (
            <ElButton link type="danger" onClick={() => void handleReject(row)}>
              驳回
            </ElButton>
          ) : null}
        </>
      )
    if (row.status === 'confirmed')
      return hasAuth('FinanceCarrierSettlement:Void') ? (
        <ElButton link type="danger" onClick={() => void handleVoid(row)}>
          作废
        </ElButton>
      ) : null
    return null
  }

  const columnsFactory = (): ColumnOption<Statement>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'statementNo', label: '对账单号', width: 190 },
    { prop: 'carrierName', label: '对账承运商', minWidth: 210, showOverflowTooltip: true },
    {
      prop: 'period',
      label: '对账账期',
      width: 205,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'costCount',
      label: '费用数',
      width: 90,
      align: 'center',
      formatter: (row) => `${row.costCount} 笔`
    },
    {
      prop: 'waybillCount',
      label: '运单数',
      width: 90,
      align: 'center',
      formatter: (row) => `${row.waybillCount} 单`
    },
    ...(canViewListField('statementAmounts')
      ? [
          {
            prop: 'statementAmount',
            label: '应付金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: Statement) => formatMoney(row.statementAmount)
          }
        ]
      : []),
    ...(canViewListField('settlementAmounts')
      ? [
          {
            prop: 'settledAmount',
            label: '已付金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: Statement) => formatMoney(row.settledAmount)
          },
          {
            prop: 'outstandingAmount',
            label: '未付金额',
            width: 135,
            align: 'right' as const,
            formatter: (row: Statement) => formatMoney(row.outstandingAmount)
          }
        ]
      : []),
    {
      prop: 'status',
      label: '状态',
      width: 115,
      dict: { code: 'tmsSettlementStatus', display: 'tag' }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 260,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          {hasAuth('FinanceCarrierSettlement:View') ? (
            <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
              查看
            </ElButton>
          ) : null}
          {renderStatusActions(row)}
        </div>
      )
    }
  ]

  const excelColumns = computed<ArtTableQueryExcelColumn[]>(() => [
    { key: 'statementNo', title: '对账单号' },
    { key: 'carrierName', title: '对账承运商' },
    { key: 'periodStart', title: '账期开始' },
    { key: 'periodEnd', title: '账期结束' },
    { key: 'costCount', title: '费用数' },
    { key: 'waybillCount', title: '运单数' },
    ...(canViewListField('statementAmounts')
      ? [{ key: 'statementAmount', title: '应付金额' }]
      : []),
    ...(canViewListField('settlementAmounts')
      ? [
          { key: 'settledAmount', title: '已付金额' },
          { key: 'outstandingAmount', title: '未付金额' }
        ]
      : []),
    { key: 'status', title: '状态' }
  ])

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: 'FinanceCarrierSettlement:Add',
      type: 'add',
      label: '生成承运商对账单',
      onClick: () => void dialogRef.value?.handleOpen()
    },
    {
      permission: 'FinanceCarrierSettlement:Export',
      type: 'export',
      exportFilename: 'TMS承运商对账单',
      exportSheetName: '承运商对账单',
      exportColumns: excelColumns.value,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCarrierStatementList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  async function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchCarrierStatementList({ ...params, from, to })
    const previousVisibility = getSensitiveColumnVisibility()
    fieldAccess.value = result.fieldAccess
    currentRows.value = result.data
    if (previousVisibility !== getSensitiveColumnVisibility()) {
      await nextTick()
      tableQueryRef.value?.resetColumns()
    }
    return result
  }

  const canViewListField = (field: StatementFieldKey): boolean =>
    canViewField(
      mergeFieldAccessMaps(fieldAccess.value, ...currentRows.value.map((row) => row.fieldAccess)),
      field
    )

  const getSensitiveColumnVisibility = (): string =>
    `${canViewListField('statementAmounts')}:${canViewListField('settlementAmounts')}`

  async function changeStatus(row: Statement, status: Api.Fms.CustomerStatementStatus) {
    const label = status === 'pending_review' ? '提交审核' : '审核通过'
    try {
      await confirmAction(`确定${label}对账单 ${row.statementNo} 吗？`, label, {
        type: 'warning'
      })
      await updateCarrierStatementStatus({
        id: row.id,
        status,
        businessTitle: `承运商对账单 ${row.statementNo}`
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      /* 用户取消 */
    }
  }

  async function handleReject(row: Statement) {
    try {
      const reason = await promptReason('请填写驳回原因', '驳回对账单', {
        confirmButtonText: '确认驳回',
        emptyMessage: '驳回原因不能为空',
        placeholder: '请说明对账单被驳回的原因'
      })
      await updateCarrierStatementStatus({
        id: row.id,
        status: 'draft',
        reviewRemark: reason,
        businessTitle: `承运商对账单 ${row.statementNo}`
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      /* 用户取消 */
    }
  }

  async function handleVoid(row: Statement) {
    try {
      const reason = await promptReason('作废后会释放费用，可重新生成对账单。', '作废对账单', {
        confirmButtonText: '确认作废',
        emptyMessage: '作废原因不能为空',
        placeholder: '请填写作废原因'
      })
      await updateCarrierStatementStatus({ id: row.id, status: 'voided', voidReason: reason })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      /* 用户取消 */
    }
  }

  async function handleDelete(row: Statement) {
    try {
      await confirmAction('仅草稿可删除，删除后无法恢复。', '删除对账单', {
        type: 'warning'
      })
      await deleteCarrierStatement(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      /* 用户取消 */
    }
  }

  async function loadCarrierOptions() {
    const { data } = await fetchCarrierOptions()
    carrierOptions.value = (data ?? []).map((item) => ({ label: item.companyName, value: item.id }))
  }

  function handleCreateSuccess() {
    void tableQueryRef.value?.refreshCreate()
  }
  function syncMasterDeleteRoute(forceRefresh = false): void {
    const context = deleteContext.value
    if (!context.active || !context.carrierId) return
    const changed =
      searchQuery.carrierId !== context.carrierId || searchQuery.recordId !== context.recordId
    Object.assign(searchQuery, {
      carrierId: context.carrierId,
      recordId: context.recordId,
      keyword: ''
    })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }
  watch(
    () => route.fullPath,
    () => syncMasterDeleteRoute(),
    { flush: 'post' }
  )

  watch(
    () => route.query.status,
    (value) => {
      if (typeof value !== 'string' || searchQuery.status === value) return
      searchQuery.status = value
      void tableQueryRef.value?.getData()
    }
  )
  onActivated(() => syncMasterDeleteRoute(true))
  onMounted(() => void loadCarrierOptions())
</script>
