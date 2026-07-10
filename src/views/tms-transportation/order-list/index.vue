<template>
  <div class="art-full-height order-list">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
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
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import { ElMessageBox } from 'element-plus'
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
  import {
    deleteOrder,
    deleteOrderBatch,
    exportOrderList,
    fetchOrderList,
    fetchStationOptions
  } from '@/api/tms'
  import FreightDialog from './modules/freight-dialog.vue'

  defineOptions({ name: 'TmsOrderList' })

  type OrderRecord = Api.Tms.Order.OrderRecord
  type SearchParams = Api.Tms.Order.OrderSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface FreightDialogExpose {
    handleOpen: (row: OrderRecord) => Promise<void>
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
    orderStatusOptions: ComputedRef<StatusTab[]>
    paymentMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    statusTabs: ComputedRef<StatusTab[]>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<OrderRecord>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const freightDialogRef = ref<FreightDialogExpose>()

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
    orderStatusOptions: computed(() => {
      const orderStatusDict = getDictMap.value.tmsOrderStatus ?? []
      return orderStatusTabValues
        .map((value) => orderStatusDict.find((item) => item.value === value))
        .filter((item): item is Api.DataCenter.DictListItem => Boolean(item))
        .map((item) => ({ label: item.label || item.name, value: item.value }))
    }),
    paymentMethodOptions: computed(() => getDictMap.value.tmsOrderPaymentMethod ?? []),
    statusTabs: computed<StatusTab[]>(() => [
      { label: '全部', value: '' },
      ...table.orderStatusOptions
    ]),
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
        type: 'delete',
        content: ({ selectedCount }: { selectedCount: number }) =>
          `确定删除选中的 ${selectedCount} 条订单吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          await deleteOrderBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
          await tableQueryRef.value?.refreshRemove()
        }
      }
    ]),
    columnsFactory: (): ColumnOption<OrderRecord>[] => [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { prop: 'cargoNo', label: '货号', fixed: 'left', width: 130, showOverflowTooltip: true },
      { prop: 'orderNo', label: '运单号', fixed: 'left', width: 140, showOverflowTooltip: true },
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
        width: 110,
        dict: { code: 'tmsOrderStatus', display: 'badge' },
        fixed: 'right'
      },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center">
            <ArtButtonTable type="view" onClick={() => openDetail(row)} />
            <ArtButtonMore
              list={getMoreActions()}
              onClick={(item: ButtonMoreItem) => handleMoreAction(item, row)}
            />
          </div>
        )
      }
    ]
  })

  onActivated(() => {
    void tableQueryRef.value?.getData()
  })

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchOrderList({ ...params, from, to })
  }

  function handleStatusTabChange(status: string | number | boolean): void {
    table.searchQuery.orderStatus = String(status)
    void tableQueryRef.value?.getData()
  }

  function openOrderOpen(): void {
    void router.push({ name: 'TmsOrderOpen' })
  }

  function openDetail(row: OrderRecord): void {
    if (!row.id) return
    void router.push({
      name: 'TmsOrderDetail',
      params: { id: row.id }
    })
  }

  function openFreight(row: OrderRecord): void {
    void freightDialogRef.value?.handleOpen(row)
  }

  function getMoreActions(): ButtonMoreItem[] {
    return [
      {
        key: 'freight',
        label: '修改运费',
        icon: 'ri:money-cny-circle-line'
      },
      {
        key: 'delete',
        label: '删除',
        icon: 'ri:delete-bin-line',
        color: 'var(--el-color-danger)'
      }
    ]
  }

  function handleMoreAction(item: ButtonMoreItem, row: OrderRecord): void {
    const actionMap: Record<string, () => void> = {
      freight: () => openFreight(row),
      delete: () => void handleDelete(row)
    }

    actionMap[String(item.key)]?.()
  }

  function handleFreightSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  async function handleDelete(row: OrderRecord): Promise<void> {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(`确定删除订单“${row.orderNo}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteOrder(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时不需要提示。
    }
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
