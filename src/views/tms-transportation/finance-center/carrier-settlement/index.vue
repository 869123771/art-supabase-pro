<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
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
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import CarrierStatementDialog from './modules/carrier-statement-dialog.vue'
  import CarrierStatementDetailDrawer from './modules/carrier-statement-detail-drawer.vue'

  defineOptions({ name: 'TmsCarrierSettlement' })

  type Statement = Api.Tms.Finance.CarrierStatementRecord
  type SearchParams = Api.Tms.Finance.CarrierStatementSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  const { getDictMap } = storeToRefs(useUserStore())
  const { promptReason, confirmAction } = useArtFeedback()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<{ handleOpen: () => Promise<void> }>()
  const drawerRef = ref<{ handleOpen: (row: Statement) => Promise<void> }>()
  const carrierOptions = ref<Array<{ label: string; value: string }>>([])
  const searchQuery = reactive<SearchParams>({
    carrierId: '',
    keyword: '',
    periodRange: [],
    status: ''
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

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

  const renderStatusActions = (row: Statement) => {
    if (row.status === 'draft')
      return (
        <>
          <ElButton link type="primary" onClick={() => void changeStatus(row, 'pending_review')}>
            提交审核
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleDelete(row)}>
            删除
          </ElButton>
        </>
      )
    if (row.status === 'pending_review')
      return (
        <>
          <ElButton link type="success" onClick={() => void changeStatus(row, 'confirmed')}>
            审核通过
          </ElButton>
          <ElButton link type="danger" onClick={() => void handleReject(row)}>
            驳回
          </ElButton>
        </>
      )
    if (row.status === 'confirmed')
      return (
        <ElButton link type="danger" onClick={() => void handleVoid(row)}>
          作废
        </ElButton>
      )
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
    {
      prop: 'statementAmount',
      label: '应付金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.statementAmount)
    },
    {
      prop: 'settledAmount',
      label: '已付金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.settledAmount)
    },
    {
      prop: 'outstandingAmount',
      label: '未付金额',
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

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'statementNo', title: '对账单号' },
    { key: 'carrierName', title: '对账承运商' },
    { key: 'periodStart', title: '账期开始' },
    { key: 'periodEnd', title: '账期结束' },
    { key: 'costCount', title: '费用数' },
    { key: 'waybillCount', title: '运单数' },
    { key: 'statementAmount', title: '应付金额' },
    { key: 'settledAmount', title: '已付金额' },
    { key: 'outstandingAmount', title: '未付金额' },
    { key: 'status', title: '状态' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', label: '生成承运商对账单', onClick: () => void dialogRef.value?.handleOpen() },
    {
      type: 'export',
      exportFilename: 'TMS承运商对账单',
      exportSheetName: '承运商对账单',
      exportColumns: excelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCarrierStatementList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCarrierStatementList({ ...params, from, to })
  }

  async function changeStatus(row: Statement, status: Api.Tms.Finance.CustomerStatementStatus) {
    const label = status === 'pending_review' ? '提交审核' : '审核通过'
    try {
      await confirmAction(`确定${label}对账单 ${row.statementNo} 吗？`, label, {
        type: 'warning'
      })
      await updateCarrierStatementStatus({ id: row.id, status })
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
        reviewRemark: reason
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
  onMounted(() => void loadCarrierOptions())
</script>
