import { computed, type ComputedRef, type Ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
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
import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
import { ColumnOption } from '@/types'
import { pageInfoHandler } from '@/utils/table/tableUtils'
import { formatWithDayjs } from '@/utils/time'
import { useUserStore } from '@/store/modules/user'
import {
  cancelWaybillOrder,
  exportWaybillList,
  fetchStationOptions,
  fetchWaybillList
} from '@/api/tms'

export type WaybillMode = 'pending' | 'loaded'
export type WaybillRecord = Api.Tms.Waybill.WaybillRecord
export type WaybillSearchParams = Api.Tms.Waybill.WaybillSearchParams
export type TableParams = WaybillSearchParams &
  Pick<Api.Common.PaginationParams, 'current' | 'size'>

export interface WaybillDialogExpose {
  handleOpen: (data: { rows: WaybillRecord[]; mode: 'single' | 'batch' }) => Promise<void>
}

export interface WaybillListContext {
  mode: WaybillMode
  router: Router
  tableQueryRef: Ref<
    { refreshData: () => Promise<void>; refreshUpdate: () => Promise<void> } | undefined
  >
  dispatchDialogRef: Ref<WaybillDialogExpose | undefined>
}

export const pendingDispatchStatuses = ['pending']

const waybillDispatchStatusFallbackMap: Record<string, Api.DataCenter.DictListItem> = {
  pending: {
    name: '待运载',
    code: 'pending',
    status: '1',
    label: '待运载',
    value: 'pending',
    color: 'var(--el-color-primary)'
  },
  loaded: {
    name: '待发车',
    code: 'loaded',
    status: '1',
    label: '待发车',
    value: 'loaded',
    color: 'var(--el-color-primary)'
  },
  transporting: {
    name: '运输中',
    code: 'transporting',
    status: '1',
    label: '运输中',
    value: 'transporting',
    color: 'var(--el-color-primary)'
  },
  completed: {
    name: '已完成',
    code: 'completed',
    status: '1',
    label: '已完成',
    value: 'completed',
    color: 'var(--el-color-success)'
  },
  cancelled: {
    name: '已取消',
    code: 'cancelled',
    status: '1',
    label: '已取消',
    value: 'cancelled',
    color: 'var(--el-color-danger)'
  }
}

export const createInitialWaybillSearch = (): WaybillSearchParams => ({
  cargoKeyword: '',
  shippingKeyword: '',
  receivingKeyword: '',
  paymentMethod: '',
  originStationId: '',
  destinationStationId: '',
  transferStationId: '',
  vehicleKeyword: '',
  plannedTimeRange: [],
  createTimeRange: []
})

export const waybillExcelColumns: ArtTableQueryExcelColumn[] = [
  { key: 'cargoNo', title: '货号' },
  { key: 'orderNo', title: '运单号' },
  { key: 'shippingContactName', title: '发货人' },
  { key: 'shippingContactPhone', title: '发货人电话' },
  { key: 'shippingAddressDetail', title: '发货人地址' },
  { key: 'originStation', title: '发货站' },
  { key: 'destinationStation', title: '到货站' },
  { key: 'transferStation', title: '中转站' },
  { key: 'dispatchPlateNo', title: '配载车辆' },
  { key: 'dispatchDriverName', title: '司机' },
  { key: 'plannedDepartureTime', title: '计划发车时间' },
  { key: 'plannedArrivalTime', title: '计划到达时间' },
  { key: 'dispatchStatus', title: '配载状态' },
  { key: 'createTime', title: '开单时间' }
]

export const createWaybillSearchItems = (
  paymentMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>,
  includeLoadedFilters = false
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
    ]

    if (includeLoadedFilters) {
      items.splice(
        4,
        0,
        {
          label: '车辆司机',
          key: 'vehicleKeyword',
          type: 'input',
          props: { clearable: true, placeholder: '车牌号、车型、司机或电话' }
        },
        {
          label: '发车日期',
          key: 'plannedTimeRange',
          type: 'date',
          props: {
            type: 'daterange',
            valueFormat: 'YYYY-MM-DD',
            startPlaceholder: '计划发车开始',
            endPlaceholder: '计划发车结束',
            rangeSeparator: '至'
          }
        }
      )
    }

    return items
  })

export function fetchWaybillTableData(params: TableParams, mode: WaybillMode) {
  const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
  const modeParams =
    mode === 'pending'
      ? { dispatchStatuses: pendingDispatchStatuses }
      : { dispatchStatus: 'loaded' }
  return fetchWaybillList({ ...params, ...modeParams, from, to })
}

export const createWaybillHeaderActions = (
  context: WaybillListContext
): ComputedRef<ArtTableQueryHeaderAction[]> =>
  computed<ArtTableQueryHeaderAction[]>(() => {
    const actions: ArtTableQueryHeaderAction[] = [
      {
        key: 'batch-dispatch',
        label: '批量配载',
        icon: 'ri:truck-line',
        selectionRequired: true,
        buttonProps: { type: 'primary' },
        hidden: context.mode !== 'pending',
        onClick: async ({ selectedRows }) => {
          await context.dispatchDialogRef.value?.handleOpen({
            rows: selectedRows as WaybillRecord[],
            mode: 'batch'
          })
        }
      },
      {
        type: 'export',
        exportFilename: context.mode === 'pending' ? '待运载运单' : '已配载运单',
        exportSheetName: context.mode === 'pending' ? '待运载运单' : '已配载运单',
        exportColumns: waybillExcelColumns,
        exportApi: ({ selectedIds, searchParams, maxRows }) => {
          const modeParams =
            context.mode === 'pending'
              ? { dispatchStatuses: pendingDispatchStatuses }
              : { dispatchStatus: 'loaded' }
          return exportWaybillList({
            ...(searchParams as WaybillSearchParams),
            ...modeParams,
            ids: selectedIds.map(String),
            maxRows
          })
        }
      }
    ]

    return actions
  })

export const createWaybillColumns = (
  context: WaybillListContext
): ColumnOption<WaybillRecord>[] => {
  const orderColumns: ColumnOption<WaybillRecord>[] = [
    { prop: 'shippingContactPhone', label: '发货人电话', width: 140, showOverflowTooltip: true },
    {
      prop: 'shippingAddressDetail',
      label: '发货人地址',
      minWidth: 220,
      showOverflowTooltip: true
    },
    { prop: 'originStation', label: '发货站', width: 110, showOverflowTooltip: true },
    {
      prop: 'transferStation',
      label: '中转站',
      width: 110,
      formatter: (row) => row.transferStation || '-'
    },
    { prop: 'destinationStation', label: '到达站', width: 110, showOverflowTooltip: true },
    { prop: 'receivingContactName', label: '收货人', width: 110, showOverflowTooltip: true },
    {
      prop: 'receivingContactPhone',
      label: '收货人电话',
      width: 140,
      showOverflowTooltip: true
    },
    {
      prop: 'receivingAddressDetail',
      label: '收货人地址',
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
      prop: 'totalFee',
      label: '总运费',
      width: 110,
      formatter: (row) => formatMoney(row.totalFee)
    },
    { prop: 'createBy', label: '开单人', width: 110, showOverflowTooltip: true },
    {
      prop: 'createByPhone',
      label: '开单人电话',
      width: 140,
      formatter: (row) => formatValue(getRecordValue(row, 'createByPhone'))
    },
    {
      prop: 'createTime',
      label: '开单时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime) || '-'
    }
  ]
  const columns: ColumnOption<WaybillRecord>[] = [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { prop: 'cargoNo', label: '货号', fixed: 'left', width: 130, showOverflowTooltip: true },
    { prop: 'orderNo', label: '运单号', fixed: 'left', width: 140, showOverflowTooltip: true }
  ]

  if (context.mode === 'pending') {
    columns.push(...orderColumns)
  } else {
    columns.push(
      ...orderColumns,
      { prop: 'dispatchDriverName', label: '司机', width: 100, showOverflowTooltip: true },
      { prop: 'dispatchDriverPhone', label: '司机电话', width: 130, showOverflowTooltip: true },
      {
        prop: 'originStation',
        label: '线路',
        width: 140,
        formatter: (row) => formatRoute(row)
      },
      { prop: 'dispatchPlateNo', label: '车牌', width: 130, showOverflowTooltip: true },
      {
        prop: 'plannedDepartureTime',
        label: '发车时间',
        width: 170,
        formatter: (row) => formatWithDayjs(row.plannedDepartureTime) || '-'
      }
    )
  }

  columns.push(
    {
      prop: 'dispatchStatus',
      label: context.mode === 'pending' ? '状态' : '发车状态',
      width: 100,
      fixed: 'right',
      formatter: (row) => formatWaybillDispatchStatus(row)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
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
  )

  return columns
}

function formatWaybillDispatchStatus(row: WaybillRecord) {
  const status = String(row.dispatchStatus || '').trim()
  const userStore = useUserStore()
  const fallbackItem = userStore.getDictItemByValue('tmsWaybillDispatchStatus', status)
    ? undefined
    : waybillDispatchStatusFallbackMap[status]

  return (
    <ArtDictDisplay
      dictCode="tmsWaybillDispatchStatus"
      value={status}
      item={fallbackItem}
      display="badge"
    />
  )
}

function getMoreActions(context: WaybillListContext, row: WaybillRecord): ButtonMoreItem[] {
  if (context.mode === 'pending') {
    return [
      {
        key: 'dispatch',
        label: '配载',
        icon: 'ri:truck-line',
        disabled: row.dispatchStatus !== 'pending'
      },
      {
        key: 'cancel-order',
        label: '取消订单',
        icon: 'ri:close-circle-line',
        color: 'var(--el-color-danger)'
      }
    ]
  }

  return [
    {
      key: 'confirm-departure',
      label: '确认发车',
      icon: 'ri:send-plane-line',
      disabled: row.dispatchStatus !== 'loaded'
    },
    {
      key: 'print',
      label: '打印',
      icon: 'ri:printer-line',
      disabled: row.dispatchStatus !== 'loaded'
    },
    {
      key: 'cancel-order',
      label: '取消订单',
      icon: 'ri:close-circle-line',
      color: 'var(--el-color-danger)'
    }
  ]
}

function handleMoreAction(
  context: WaybillListContext,
  row: WaybillRecord,
  item: ButtonMoreItem
): void {
  const actionMap: Record<string, () => void> = {
    dispatch: () => openDispatch(context, row),
    'confirm-departure': () => handleConfirmDeparture(row),
    print: () => handlePrint(row),
    'cancel-order': () => void handleCancelOrder(context, row)
  }

  actionMap[String(item.key)]?.()
}

function openDispatch(context: WaybillListContext, row: WaybillRecord): void {
  void context.dispatchDialogRef.value?.handleOpen({ rows: [row], mode: 'single' })
}

function openDetail(context: WaybillListContext, row: WaybillRecord): void {
  if (!row.id) return
  void context.router.push({
    name: 'TmsOrderDetail',
    params: { id: row.id }
  })
}

async function handleCancelOrder(context: WaybillListContext, row: WaybillRecord): Promise<void> {
  if (!row.id) return
  try {
    await ElMessageBox.confirm(`确定取消运单“${row.orderNo}”吗？`, '取消运单', {
      confirmButtonText: '取消运单',
      cancelButtonText: '关闭',
      type: 'warning',
      confirmButtonClass: 'el-button--danger'
    })
    await cancelWaybillOrder(row.id)
    await context.tableQueryRef.value?.refreshUpdate()
  } catch {
    // 用户取消操作时不提示。
  }
}

function handleConfirmDeparture(row: WaybillRecord): void {
  if (row.dispatchStatus !== 'loaded') return
  ElMessage.info('确认发车接口未接入')
}

function handlePrint(row: WaybillRecord): void {
  if (row.dispatchStatus !== 'loaded') return
  ElMessage.info('运单打印接口未接入')
}

function formatCargoType(row: WaybillRecord): string {
  const cargoName = row.cargoItems?.map((item) => item.cargoName).find(Boolean)
  return formatValue(cargoName)
}

function formatRoute(row: WaybillRecord): string {
  return [row.originStation, row.transferStation, row.destinationStation].filter(Boolean).join('-')
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

function getRecordValue(row: WaybillRecord, key: string): string | number | null {
  const value = (row as unknown as Record<string, unknown>)[key]
  if (typeof value === 'string' || typeof value === 'number') return value
  return null
}
