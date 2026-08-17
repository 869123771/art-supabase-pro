import { computed, type ComputedRef, type Ref } from 'vue'
import { ElLink } from 'element-plus'
import type { Router } from 'vue-router'
import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
import type {
  ArtTableQueryExcelColumn,
  ArtTableQueryHeaderAction
} from '@/components/core/tables/art-table-query/index.vue'
import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
import ArtButtonMore, {
  type ButtonMoreItem
} from '@/components/core/forms/art-button-more/index.vue'
import type { ColumnOption } from '@/types'
import { pageInfoHandler } from '@/utils/table/tableUtils'
import { exportDeliveryList, fetchDeliveryList } from '@/api/tms'

export type DeliveryMode = 'delivery' | 'transit'
export type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
export type DeliverySearchParams = Api.Tms.Delivery.DeliverySearchParams
export type TableParams = DeliverySearchParams &
  Pick<Api.Common.PaginationParams, 'current' | 'size'>

export interface DeliveryReceiptArchiveDialogExpose {
  handleOpen: (row: DeliveryRecord) => Promise<void>
}

export interface DeliveryListContext {
  mode: DeliveryMode
  router: Router
  tableQueryRef: Ref<
    { refreshData: () => Promise<void>; refreshUpdate: () => Promise<void> } | undefined
  >
  receiptArchiveDialogRef?: Ref<DeliveryReceiptArchiveDialogExpose | undefined>
}

export const DELIVERY_STATUS_ALL = '__all__'
export const deliveryOrderStatuses = ['signed', 'completed']
const transitOrderStatuses = ['pending_pickup', 'transporting']

export const createInitialDeliverySearch = (): DeliverySearchParams => ({
  cargoKeyword: '',
  shippingKeyword: '',
  receivingKeyword: '',
  paymentMethod: '',
  signedTimeRange: [],
  createTimeRange: [],
  deliveryStatus: DELIVERY_STATUS_ALL
})

export const deliveryExcelColumns: ArtTableQueryExcelColumn[] = [
  { key: 'cargoNo', title: '货号' },
  { key: 'orderNo', title: '运单号' },
  { key: 'receivingContactName', title: '收货人' },
  { key: 'receivingContactPhone', title: '收货人电话' },
  { key: 'receivingAddressDetail', title: '收货人地址' },
  { key: 'shippingContactName', title: '发货人' },
  { key: 'shippingContactPhone', title: '发货人电话' },
  { key: 'shippingAddressDetail', title: '发货人地址' },
  { key: 'cargoItems', title: '货物类型' },
  { key: 'cargoQuantityTotal', title: '总数量' },
  { key: 'cargoVolumeTotal', title: '总体积(方)' },
  { key: 'cargoWeightTotal', title: '总重量(KG)' },
  { key: 'paymentMethod', title: '付款方式' },
  { key: 'declaredValue', title: '声明价值' },
  { key: 'insuranceFee', title: '保费' },
  { key: 'deliveryFee', title: '配送费' },
  { key: 'unloadingFee', title: '卸货费' },
  { key: 'codAmount', title: '代收货款' },
  { key: 'orderStatus', title: '状态' }
]

export const createDeliverySearchItems = (
  paymentMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>,
  includeSignedTime = false
): ComputedRef<SearchFormItem[]> =>
  computed<SearchFormItem[]>(() => {
    const items: SearchFormItem[] = [
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
        label: '付款方式',
        key: 'paymentMethod',
        type: 'select',
        props: { options: paymentMethodOptions.value, clearable: true, placeholder: '请选择' }
      }
    ]

    if (includeSignedTime) {
      items.push({
        label: '签收日期',
        key: 'signedTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          rangeSeparator: '至'
        }
      })
    }

    return items
  })

export function fetchDeliveryTableData(params: TableParams, mode: DeliveryMode) {
  const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
  return fetchDeliveryList({
    ...params,
    orderStatuses: getModeStatuses(mode, params.deliveryStatus),
    from,
    to
  })
}

export const createDeliveryHeaderActions = (
  context: DeliveryListContext
): ComputedRef<ArtTableQueryHeaderAction[]> =>
  computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'export',
      exportFilename: context.mode === 'delivery' ? '配送管理' : '在途监控',
      exportSheetName: context.mode === 'delivery' ? '配送管理' : '在途监控',
      exportColumns: deliveryExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportDeliveryList({
          ...(searchParams as DeliverySearchParams),
          orderStatuses: getModeStatuses(
            context.mode,
            (searchParams as DeliverySearchParams).deliveryStatus
          ),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

export const createDeliveryColumns = (
  context: DeliveryListContext
): ColumnOption<DeliveryRecord>[] => [
  { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
  { prop: 'cargoNo', label: '货号', fixed: 'left', width: 130, showOverflowTooltip: true },
  {
    prop: 'orderNo',
    label: '运单号',
    fixed: 'left',
    width: 140,
    formatter: (row) => (
      <ElLink type="primary" underline="never" onClick={() => openDetail(context, row)}>
        {row.orderNo}
      </ElLink>
    )
  },
  { prop: 'receivingContactName', label: '收货人', width: 110, showOverflowTooltip: true },
  { prop: 'receivingContactPhone', label: '收货人电话', width: 140, showOverflowTooltip: true },
  {
    prop: 'receivingAddressDetail',
    label: '收货人地址',
    minWidth: 220,
    showOverflowTooltip: true
  },
  { prop: 'shippingContactName', label: '发货人', width: 110, showOverflowTooltip: true },
  { prop: 'shippingContactPhone', label: '发货人电话', width: 140, showOverflowTooltip: true },
  {
    prop: 'shippingAddressDetail',
    label: '发货人地址',
    minWidth: 220,
    showOverflowTooltip: true
  },
  {
    prop: 'cargoItems',
    label: '货物类型',
    width: 120,
    formatter: (row) => formatCargoType(row)
  },
  {
    prop: 'cargoQuantityTotal',
    label: '总数量',
    width: 100,
    formatter: (row) => formatNumber(row.cargoQuantityTotal, 0)
  },
  {
    prop: 'cargoVolumeTotal',
    label: '总体积(方)',
    width: 120,
    formatter: (row) => formatNumber(row.cargoVolumeTotal)
  },
  {
    prop: 'cargoWeightTotal',
    label: '总重量(KG)',
    width: 120,
    formatter: (row) => formatNumber(row.cargoWeightTotal)
  },
  {
    prop: 'paymentMethod',
    label: '付款方式',
    width: 110,
    dict: { code: 'tmsOrderPaymentMethod', display: 'tag' }
  },
  {
    prop: 'declaredValue',
    label: '声明价值',
    width: 110,
    formatter: (row) => formatMoney(row.declaredValue)
  },
  {
    prop: 'insuranceFee',
    label: '保费',
    width: 100,
    formatter: (row) => formatMoney(row.insuranceFee)
  },
  {
    prop: 'deliveryFee',
    label: '配送费',
    width: 100,
    formatter: (row) => formatMoney(row.deliveryFee)
  },
  {
    prop: 'unloadingFee',
    label: '卸货费',
    width: 100,
    formatter: (row) => formatMoney(row.unloadingFee)
  },
  {
    prop: 'codAmount',
    label: '代收货款',
    width: 110,
    formatter: (row) => formatMoney(row.codAmount)
  },
  {
    prop: 'orderStatus',
    label: '状态',
    width: 100,
    fixed: 'right',
    dict: { code: 'tmsOrderStatus', display: 'badge' }
  },
  {
    prop: 'operation',
    label: '操作',
    width: 100,
    fixed: 'right',
    formatter: (row) => (
      <div class="flex items-center">
        <ArtButtonTable type="view" onClick={() => openDetail(context, row)} />
        <ArtButtonMore
          list={getMoreActions(context, row)}
          onClick={(item: ButtonMoreItem) => handleMoreAction(context, row, item)}
        />
      </div>
    )
  }
]

function getModeStatuses(mode: DeliveryMode, deliveryStatus?: string): string[] {
  if (mode === 'transit') return transitOrderStatuses
  return deliveryStatus && deliveryStatus !== DELIVERY_STATUS_ALL
    ? [deliveryStatus]
    : deliveryOrderStatuses
}

function openDetail(context: DeliveryListContext, row: DeliveryRecord): void {
  if (!row.id) return
  void context.router.push({
    name: 'TmsOrderDetail',
    params: { id: row.id }
  })
}

function openReceiptArchiveDialog(context: DeliveryListContext, row: DeliveryRecord): void {
  if (!['signed', 'completed'].includes(String(row.orderStatus))) return
  void context.receiptArchiveDialogRef?.value?.handleOpen(row)
}

function getMoreActions(context: DeliveryListContext, row: DeliveryRecord): ButtonMoreItem[] {
  if (context.mode !== 'delivery') return []

  const canArchiveReceipt = ['signed', 'completed'].includes(String(row.orderStatus))
  if (!canArchiveReceipt) return []

  return [
    {
      key: 'archive-receipt',
      label: row.receiptImageUrls?.length ? '复核回单' : '归档回单',
      icon: 'ri:archive-2-line',
      color: 'var(--el-color-primary)'
    }
  ]
}

function handleMoreAction(
  context: DeliveryListContext,
  row: DeliveryRecord,
  item: ButtonMoreItem
): void {
  if (item.key === 'archive-receipt') openReceiptArchiveDialog(context, row)
}

function formatCargoType(row: DeliveryRecord): string {
  const cargoName = row.cargoItems?.map((item) => item.cargoName).find(Boolean)
  return formatValue(cargoName)
}

function formatMoney(value?: number | string | null): string {
  const numericValue = Number(value ?? 0)
  return Number.isFinite(numericValue) ? String(numericValue) : '0'
}

function formatNumber(value?: number | string | null, precision = 2): string {
  const numericValue = Number(value ?? 0)
  if (!Number.isFinite(numericValue)) return '0'

  return numericValue
    .toFixed(precision)
    .replace(/(\.\d*?)0+$/, '$1')
    .replace(/\.$/, '')
}

function formatValue(value?: string | number | null): string {
  const text = String(value ?? '').trim()
  return text || '-'
}
