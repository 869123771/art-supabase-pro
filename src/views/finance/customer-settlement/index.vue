<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="CUSTOMER SETTLEMENT"
      title="客户对账"
      description="按客户汇总运输应收、对账周期与单据状态，推动确认、开票和回款流程衔接。"
      icon="ri:bill-line"
      :tags="[
        { label: '应收对账', type: 'primary' },
        { label: '回款前置', type: 'success' }
      ]"
    />

    <MasterDeleteProcessingNotice
      v-if="customerDeleteContext.active"
      :customer-id="customerDeleteContext.customerId"
      :customer-name="customerDeleteContext.customerName"
      action-hint="已定位到关联对账单。草稿可直接删除；其他状态请先按现有审核、驳回或作废规则处理。"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无客户对账单',
        emptyDescription: '可创建客户对账单，或调整客户、状态、周期和单号后重新查询。'
      }"
      focusable
    />

    <CustomerStatementDialog ref="dialogRef" @success="handleCreateSuccess" />
    <CustomerStatementDetailDrawer ref="drawerRef" />
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
    deleteCustomerStatement,
    exportCustomerStatementList,
    fetchCustomerOptions,
    fetchCustomerStatementList,
    updateCustomerStatementStatus
  } from '@/api/finance'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import CustomerStatementDialog from './modules/customer-statement-dialog.vue'
  import CustomerStatementDetailDrawer from './modules/customer-statement-detail-drawer.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'

  defineOptions({ name: 'FinanceCustomerSettlement' })

  type CustomerStatement = Api.Finance.CustomerStatementRecord
  type SearchParams = Api.Finance.CustomerStatementSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: () => Promise<void>
  }

  interface DrawerExpose {
    handleOpen: (row: CustomerStatement) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const { promptReason, confirmAction } = useArtFeedback()
  const route = useRoute()
  const customerDeleteContext = useMasterDataDeleteProcessingContext()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const drawerRef = ref<DrawerExpose>()
  const customerOptions = ref<Array<{ label: string; value: string }>>([])
  const searchQuery = reactive<SearchParams>({
    customerId: customerDeleteContext.value.customerId,
    keyword: '',
    periodRange: [],
    recordId: customerDeleteContext.value.recordId,
    status: ''
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '对账客户',
      key: 'customerId',
      type: 'select',
      props: {
        options: customerOptions.value,
        filterable: true,
        clearable: true,
        placeholder: '请选择客户'
      }
    },
    {
      label: '对账状态',
      key: 'status',
      type: 'select',
      props: {
        options: getDictMap.value.tmsSettlementStatus ?? [],
        clearable: true
      }
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
      props: {
        clearable: true,
        placeholder: '对账单号、客户或备注'
      }
    }
  ])

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const columnsFactory = (): ColumnOption<CustomerStatement>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'customerName',
      label: '对账客户',
      minWidth: 200,
      showOverflowTooltip: true
    },
    {
      prop: 'period',
      label: '对账账期',
      width: 205,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'waybillCount',
      label: '运单数',
      width: 90,
      align: 'center',
      formatter: (row) => `${row.waybillCount} 单`
    },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.statementAmount)
    },
    {
      prop: 'settledAmount',
      label: '已结金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.settledAmount)
    },
    {
      prop: 'outstandingAmount',
      label: '未结金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.outstandingAmount)
    },
    {
      prop: 'status',
      label: '状态',
      width: 115,
      dict: { code: 'tmsSettlementStatus', display: 'tag' }
    },
    { prop: 'createBy', label: '创建人', width: 120, showOverflowTooltip: true },
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
          <ElButton link type="primary" onClick={() => void drawerRef.value?.handleOpen(row)}>
            查看
          </ElButton>
          {renderStatusActions(row)}
        </div>
      )
    }
  ]

  const renderStatusActions = (row: CustomerStatement) => {
    if (row.status === 'draft') {
      return (
        <>
          <ElButton link type="primary" onClick={() => void handleSubmitReview(row)}>
            提交审核
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleDelete(row)}>
            删除
          </ElButton>
        </>
      )
    }
    if (row.status === 'pending_review') {
      return (
        <>
          <ElButton link type="success" onClick={() => void handleApprove(row)}>
            审核通过
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleReject(row)}>
            驳回
          </ElButton>
        </>
      )
    }
    if (row.status === 'confirmed') {
      return (
        <ElButton link type="danger" onClick={() => void handleVoid(row)}>
          作废
        </ElButton>
      )
    }
    return null
  }

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'statementNo', title: '对账单号' },
    { key: 'customerName', title: '对账客户' },
    { key: 'periodStart', title: '账期开始' },
    { key: 'periodEnd', title: '账期结束' },
    { key: 'waybillCount', title: '运单数' },
    { key: 'statementAmount', title: '对账金额' },
    { key: 'settledAmount', title: '已结金额' },
    { key: 'outstandingAmount', title: '未结金额' },
    { key: 'status', title: '状态' },
    { key: 'createBy', title: '创建人' },
    { key: 'createTime', title: '创建时间' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: '生成客户对账单',
      onClick: () => void dialogRef.value?.handleOpen()
    },
    {
      type: 'export',
      exportFilename: 'TMS客户对账单',
      exportSheetName: '客户对账单',
      exportColumns: excelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCustomerStatementList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCustomerStatementList({ ...params, from, to })
  }

  async function loadCustomerOptions(): Promise<void> {
    const { data } = await fetchCustomerOptions()
    customerOptions.value = (data ?? []).map((item) => ({
      label: item.customerName,
      value: item.id
    }))
  }

  function handleCreateSuccess(): void {
    void tableQueryRef.value?.refreshCreate()
  }

  async function handleSubmitReview(row: CustomerStatement): Promise<void> {
    try {
      await confirmAction(
        `提交后将锁定 ${row.waybillCount} 条运单明细，确定提交审核吗？`,
        '提交审核',
        {
          type: 'warning',
          confirmButtonText: '提交',
          cancelButtonText: '取消'
        }
      )
      await updateCustomerStatementStatus({ id: row.id, status: 'pending_review' })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleApprove(row: CustomerStatement): Promise<void> {
    try {
      await confirmAction(
        `确认对账金额 ${formatMoney(row.statementAmount)} 无误并审核通过吗？`,
        '审核通过',
        {
          type: 'success',
          confirmButtonText: '通过',
          cancelButtonText: '取消'
        }
      )
      await updateCustomerStatementStatus({ id: row.id, status: 'confirmed' })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleReject(row: CustomerStatement): Promise<void> {
    try {
      const reason = await promptReason('请填写驳回原因', '驳回对账单', {
        confirmButtonText: '确认驳回',
        emptyMessage: '驳回原因不能为空',
        placeholder: '请说明对账单被驳回的原因'
      })
      await updateCustomerStatementStatus({
        id: row.id,
        status: 'draft',
        reviewRemark: reason
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleVoid(row: CustomerStatement): Promise<void> {
    try {
      const reason = await promptReason(
        '作废后会释放关联运单，可重新生成对账单；历史记录仍保留。',
        '作废对账单',
        {
          confirmButtonText: '确认作废',
          placeholder: '请填写作废原因',
          emptyMessage: '作废原因不能为空'
        }
      )
      await updateCustomerStatementStatus({
        id: row.id,
        status: 'voided',
        voidReason: reason
      })
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function handleDelete(row: CustomerStatement): Promise<void> {
    try {
      await confirmAction('仅草稿对账单可删除，删除后无法恢复。', '删除对账单', {
        type: 'warning',
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteCustomerStatement(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消时无需提示。
    }
  }

  function syncCustomerDeleteRoute(forceRefresh = false): void {
    const context = customerDeleteContext.value
    if (!context.active) return
    const changed =
      searchQuery.customerId !== context.customerId || searchQuery.recordId !== context.recordId
    Object.assign(searchQuery, {
      customerId: context.customerId,
      recordId: context.recordId
    })
    if (changed || forceRefresh) {
      void nextTick().then(() => tableQueryRef.value?.getData())
    }
  }

  watch(
    () => route.fullPath,
    () => syncCustomerDeleteRoute(),
    { flush: 'post' }
  )

  onActivated(() => syncCustomerDeleteRoute(true))

  onMounted(() => void loadCustomerOptions())
</script>
