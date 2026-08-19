<template>
  <div class="business-workspace-page art-full-height order-list">
    <MasterDeleteProcessingNotice action-hint="当前订单已自动定位；业务历史需按流程处理或保留。" />
    <BusinessWorkspaceHeader
      eyebrow="ORDER COMMAND CENTER"
      title="运输订单"
      description="集中跟踪订单状态、运输线路、客户需求与费用进度，快速识别待处理业务。"
      icon="ri:file-list-3-line"
      :tags="[
        { label: '全流程订单', type: 'primary' },
        { label: '状态可追踪', type: 'success' }
      ]"
      :metrics="workspaceMetrics"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无运输订单',
        emptyDescription: '可前往开单创建订单，或调整状态、线路、客户和时间条件后重新查询。'
      }"
      focusable
    >
      <template #table-header-top>
        <div class="order-list__status-tabs">
          <ElSegmented
            :model-value="table.searchQuery.orderStatus"
            :options="table.statusTabs"
            @change="handleStatusTabChange"
          />
        </div>
      </template>
    </ArtTableQuery>

    <FreightDialog ref="freightDialogRef" @success="handleFreightSuccess" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleDeleteDependenciesCleared" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElLink, ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { financeRouteNames } from '@/router/business-paths'
  import {
    deleteOrder,
    deleteOrderBatch,
    cancelWaybillOrder,
    cancelWaybillOrderBatch,
    exportOrderList,
    fetchOrderList,
    fetchOrderStatusCounts,
    fetchStationOptions
  } from '@/api/tms'
  import FreightDialog from './modules/freight-dialog.vue'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'

  defineOptions({ name: 'TmsOrderList' })

  const { confirmAction } = useArtFeedback()

  type OrderRecord = Api.Tms.Order.OrderRecord
  type SearchParams = Api.Tms.Order.OrderSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface FreightDialogExpose {
    handleOpen: (row: OrderRecord) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  interface StatusTab {
    label: string
    value: string
  }

  const orderStatusTabValues = [
    'pending_load',
    'pending_order',
    'pending_pickup',
    'transporting',
    'signed',
    'completed',
    'cancelled'
  ]

  interface TableGroup {
    searchQuery: SearchParams
    statusCounts: Record<string, number>
    orderStatusOptions: ComputedRef<StatusTab[]>
    paymentMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    statusTabs: ComputedRef<StatusTab[]>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<OrderRecord>[]
  }

  const router = useRouter()
  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const freightDialogRef = ref<FreightDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()
  const statusCountRequestId = ref(0)

  const orderExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'cargoNo', title: '货号' },
    { key: 'orderNo', title: '运单号' },
    { key: 'shippingContactName', title: '发货人' },
    { key: 'shippingContactPhone', title: '发货人电话' },
    { key: 'shippingAddressDetail', title: '发货人地址' },
    { key: 'receivingContactName', title: '收货人' },
    { key: 'receivingContactPhone', title: '收货人电话' },
    { key: 'originStation', title: '发货站' },
    { key: 'destinationStation', title: '到货站' },
    { key: 'transferStation', title: '中转站' },
    { key: 'orderStatus', title: '订单状态' },
    { key: 'paymentMethod', title: '付款方式' },
    { key: 'totalFee', title: '总运费' },
    { key: 'createTime', title: '开单时间' }
  ]

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : '',
      cargoKeyword: '',
      shippingKeyword: '',
      receivingKeyword: '',
      orderStatus: '',
      paymentMethod: '',
      originStationId: '',
      destinationStationId: '',
      transferStationId: '',
      createTimeRange: []
    },
    statusCounts: {},
    orderStatusOptions: computed(() => {
      const orderStatusDict = getDictMap.value.tmsOrderStatus ?? []
      return orderStatusTabValues
        .map((value) => orderStatusDict.find((item) => item.value === value))
        .filter((item): item is Api.DataCenter.DictListItem => Boolean(item))
        .map((item) => ({ label: item.label || item.name, value: item.value }))
    }),
    paymentMethodOptions: computed(() => getDictMap.value.tmsOrderPaymentMethod ?? []),
    statusTabs: computed<StatusTab[]>(() => {
      const total = orderStatusTabValues.reduce(
        (sum, status) => sum + (table.statusCounts[status] ?? 0),
        0
      )
      return [
        { label: `全部 (${total})`, value: '' },
        ...table.orderStatusOptions.map((item) => ({
          ...item,
          label: `${item.label} (${table.statusCounts[item.value] ?? 0})`
        }))
      ]
    }),
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '货号',
        key: 'cargoKeyword',
        type: 'input',
        props: { clearable: true, placeholder: '货号 / 运单号' }
      },
      {
        label: '发货人',
        key: 'shippingKeyword',
        type: 'input',
        props: { clearable: true, placeholder: '发货人姓名、电话或地址' }
      },
      {
        label: '收货人',
        key: 'receivingKeyword',
        type: 'input',
        props: { clearable: true, placeholder: '收货人姓名、电话或地址' }
      },
      {
        label: '订单状态',
        key: 'orderStatus',
        type: 'select',
        props: { options: table.orderStatusOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '付款方式',
        key: 'paymentMethod',
        type: 'select',
        props: { options: table.paymentMethodOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '发货站',
        key: 'originStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        beforeFetch: (params) => ({ ...params, stationType: 'shipping' }),
        props: { filterable: true, clearable: true, placeholder: '请选择' }
      },
      {
        label: '到货站',
        key: 'destinationStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        beforeFetch: (params) => ({ ...params, stationType: 'arrival' }),
        props: { filterable: true, clearable: true, placeholder: '请选择' }
      },
      {
        label: '中转站',
        key: 'transferStationId',
        type: 'select',
        api: fetchStationOptions,
        resultField: 'data',
        labelField: 'stationName',
        valueField: 'id',
        beforeFetch: (params) => ({ ...params, stationType: 'transfer' }),
        props: { filterable: true, clearable: true, placeholder: '请选择' }
      },
      {
        label: '开单日期',
        key: 'createTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          rangeSeparator: '至'
        }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      { type: 'add', label: '开单', onClick: openOrderOpen },
      {
        type: 'export',
        exportFilename: 'TMS订单列表',
        exportSheetName: '订单列表',
        exportColumns: orderExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportOrderList({
            ...(searchParams as SearchParams),
            ids: selectedIds.map(String),
            maxRows
          })
      },
      {
        key: 'batch-cancel',
        label: '批量取消',
        icon: 'ri:close-circle-line',
        selectionRequired: true,
        buttonProps: { type: 'warning', plain: true },
        onClick: async ({ selectedRows }) => {
          const rows = selectedRows as OrderRecord[]
          if (rows.some((row) => !canCancelOrder(row))) {
            ElMessage.warning('已签收、已完成或已取消的订单不能取消')
            return
          }
          await confirmAction(
            `确定取消选中的 ${rows.length} 条订单及其关联运单吗？取消后大屏将不再展示。`,
            '取消订单',
            {
              confirmButtonText: '确认取消',
              cancelButtonText: '关闭',
              type: 'warning'
            }
          )
          await cancelWaybillOrderBatch(rows.map((row) => String(row.id)).filter(Boolean))
          await tableQueryRef.value?.refreshUpdate()
        }
      },
      {
        type: 'delete',
        content: ({ selectedCount }: { selectedCount: number }) =>
          `确定永久删除选中的 ${selectedCount} 条订单及其关联数据吗？删除后无法恢复。`,
        disabled: ({ selectedRows }) =>
          (selectedRows as OrderRecord[]).some((row) => !canDeleteOrder(row)),
        onClick: async ({ selectedRows }) => {
          const rows = selectedRows as OrderRecord[]
          const blocked = await deleteGuardRef.value?.inspect({
            resourceType: 'order',
            resourceLabel: '运输订单',
            resources: rows
              .filter((row) => Boolean(row.id))
              .map((row) => ({ id: String(row.id), label: row.orderNo }))
          })
          if (blocked) return
          await deleteOrderBatch(rows.map((row) => String(row.id)).filter(Boolean))
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: (): ColumnOption<OrderRecord>[] => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { prop: 'cargoNo', label: '货号', fixed: 'left', width: 130, showOverflowTooltip: true },
      {
        prop: 'orderNo',
        label: '运单号',
        fixed: 'left',
        width: 140,
        formatter: (row) => (
          <ElLink type="primary" underline="never" onClick={() => openDetail(row)}>
            {row.orderNo}
          </ElLink>
        )
      },
      { prop: 'shippingContactName', label: '发货人', width: 110 },
      { prop: 'shippingContactPhone', label: '发货人电话', width: 140 },
      {
        prop: 'shippingAddressDetail',
        label: '发货人地址',
        minWidth: 220,
        showOverflowTooltip: true
      },
      { prop: 'originStation', label: '发货站', width: 120, showOverflowTooltip: true },
      { prop: 'destinationStation', label: '到货站', width: 120, showOverflowTooltip: true },
      {
        prop: 'transferStation',
        label: '中转站',
        width: 120,
        formatter: (row) => row.transferStation || '-'
      },

      {
        prop: 'paymentMethod',
        label: '付款方式',
        width: 110,
        dict: { code: 'tmsOrderPaymentMethod', display: 'tag' }
      },
      {
        prop: 'totalFee',
        label: '总运费',
        width: 110,
        formatter: (row) => `¥${formatMoney(row.totalFee)}`
      },
      {
        prop: 'createTime',
        label: '开单时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.createTime) || '-'
      },
      {
        prop: 'orderStatus',
        label: '状态',
        width: 90,
        dict: { code: 'tmsOrderStatus', display: 'badge' },
        fixed: 'right'
      },
      {
        prop: 'operation',
        label: '操作',
        width: 100,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="view" onClick={() => openDetail(row)} />
            <ArtButtonMore
              list={getMoreActions(row)}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ]
  })

  const workspaceMetrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      label: '订单总量',
      value: orderStatusTabValues.reduce(
        (sum, status) => sum + (table.statusCounts[status] ?? 0),
        0
      ),
      description: '当前筛选范围内的运输订单',
      icon: 'ri:file-list-3-line'
    },
    {
      label: '待执行',
      value: ['pending_load', 'pending_order', 'pending_pickup'].reduce(
        (sum, status) => sum + (table.statusCounts[status] ?? 0),
        0
      ),
      description: '等待装载、调度或提货',
      icon: 'ri:timer-line',
      tone: 'warning'
    },
    {
      label: '运输中',
      value: table.statusCounts.transporting ?? 0,
      description: '正在执行运输任务',
      icon: 'ri:truck-line',
      tone: 'success'
    }
  ])

  onActivated(() => {
    void tableQueryRef.value?.getData()
  })

  watch(
    () => route.query.recordId,
    (recordId) => {
      table.searchQuery.recordId = typeof recordId === 'string' ? recordId : ''
      void tableQueryRef.value?.getData()
    }
  )

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    void loadStatusCounts(params)
    return fetchOrderList({ ...params, from, to })
  }

  async function loadStatusCounts(params: TableParams): Promise<void> {
    const requestId = ++statusCountRequestId.value
    const counts = await fetchOrderStatusCounts(params)
    if (requestId === statusCountRequestId.value) table.statusCounts = counts
  }

  function handleStatusTabChange(status: string | number | boolean): void {
    table.searchQuery.orderStatus = String(status)
    void tableQueryRef.value?.getData()
  }

  function openOrderOpen(): void {
    void router.push({ name: 'TmsOrderOpen' })
  }

  function openOrderEdit(row: OrderRecord): void {
    if (!canEditOrder(row)) return
    void router.push({ name: 'TmsOrderOpen', query: { id: row.id } })
  }

  function openDetail(row: OrderRecord): void {
    if (!row.id) return
    void router.push({
      name: 'TmsOrderDetail',
      params: { id: row.id }
    })
  }

  function openFreight(row: OrderRecord): void {
    if (!canEditFreight(row)) return
    void freightDialogRef.value?.handleOpen(row)
  }

  function getMoreActions(row: OrderRecord): ButtonMoreItem[] {
    return [
      {
        key: 'waybillExpense',
        label: '新增运单费用',
        icon: 'ri:gas-station-line',
        disabled: !canAddWaybillExpense(row)
      },
      {
        key: 'edit',
        label: '编辑',
        icon: 'ri:edit-line',
        disabled: !canEditOrder(row)
      },
      {
        key: 'freight',
        label: '修改运费',
        icon: 'ri:money-cny-circle-line',
        disabled: !canEditFreight(row)
      },
      {
        key: 'cancel',
        label: '取消订单',
        icon: 'ri:close-circle-line',
        color: 'var(--el-color-warning)',
        disabled: !canCancelOrder(row)
      },
      {
        key: 'delete',
        label: '永久删除',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)',
        disabled: !canDeleteOrder(row)
      }
    ].filter((item) => !item.disabled)
  }

  function handleMoreAction(item: ButtonMoreItem, row: OrderRecord): void {
    const actionMap: Record<string, () => void> = {
      waybillExpense: () => openWaybillExpense(row),
      edit: () => openOrderEdit(row),
      freight: () => openFreight(row),
      cancel: () => void handleCancel(row),
      delete: () => void handleDelete(row)
    }

    actionMap[String(item.key)]?.()
  }

  function openWaybillExpense(row: OrderRecord): void {
    if (!row.id || !canAddWaybillExpense(row)) return
    void router.push({ name: financeRouteNames.waybillCost, query: { orderId: row.id } })
  }

  function canAddWaybillExpense(row: OrderRecord): boolean {
    return (
      Boolean(row.id) &&
      !['pending_load', 'pending_order', 'cancelled'].includes(String(row.orderStatus || ''))
    )
  }

  function handleFreightSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  function canEditFreight(row: OrderRecord): boolean {
    return (
      ['created', 'pending_load'].includes(String(row.orderStatus || '')) ||
      String(row.dispatchStatus || '') === 'pending'
    )
  }

  function canEditOrder(row: OrderRecord): boolean {
    return Boolean(row.id) && row.orderStatus === 'pending_load'
  }

  function canDeleteOrder(row: OrderRecord): boolean {
    return (
      Boolean(row.id) &&
      row.orderStatus === 'pending_load' &&
      String(row.dispatchStatus || '') === 'pending'
    )
  }

  function canCancelOrder(row: OrderRecord): boolean {
    return !['cancelled', 'signed', 'completed'].includes(String(row.orderStatus || ''))
  }

  async function handleCancel(row: OrderRecord): Promise<void> {
    if (!row.id || !canCancelOrder(row)) return
    try {
      await confirmAction(
        `确定取消订单“${row.orderNo}”及其关联运单吗？取消后大屏将不再展示。`,
        '取消订单',
        {
          confirmButtonText: '确认取消',
          cancelButtonText: '关闭',
          type: 'warning'
        }
      )
      await cancelWaybillOrder(row.id)
      await tableQueryRef.value?.refreshUpdate()
    } catch {
      // 用户取消操作时不提示。
    }
  }

  async function handleDelete(row: OrderRecord): Promise<void> {
    if (!row.id || !canDeleteOrder(row)) return
    try {
      const blocked = await deleteGuardRef.value?.inspect({
        resourceType: 'order',
        resourceLabel: '运输订单',
        resources: [{ id: row.id, label: row.orderNo }]
      })
      if (blocked) return

      await confirmAction(
        `确定永久删除待配载订单“${row.orderNo}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteOrder(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时不需要提示。
    }
  }

  function handleDeleteDependenciesCleared(): void {
    void tableQueryRef.value?.refreshData()
  }

  function formatMoney(value?: number | string | null): string {
    const numericValue = Number(value ?? 0)
    return Number.isFinite(numericValue) ? numericValue.toFixed(2) : '0.00'
  }
</script>

<style scoped lang="scss">
  .order-list {
    &__status-tabs {
      display: flex;
      flex-wrap: wrap;
      align-items: center;

      :deep(.el-segmented) {
        --el-segmented-item-selected-color: var(--el-color-white);
        --el-segmented-item-selected-bg-color: var(--el-color-primary);

        max-width: 100%;

        .el-segmented__group {
          flex-wrap: wrap;
        }

        .el-segmented__item {
          color: var(--el-color-primary);

          &.is-selected {
            color: var(--el-color-white);
          }
        }
      }
    }
  }
</style>
