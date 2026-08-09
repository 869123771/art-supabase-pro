import { computed, watch, type Ref } from 'vue'
import { meanBy, sumBy, uniq } from 'lodash-es'
import {
  getVehicleImage,
  MONITOR_STATUS_DICT_CODE,
  REALTIME_WAYBILL_STATUSES,
  regionOptions,
  VEHICLE_TYPE_DICT_CODE
} from './monitor-config'
import type {
  AlertItem,
  GeoCoord,
  InTransitRecord,
  MonitorMode,
  MonitorOrder,
  ScreenState,
  TransitStatus
} from './monitor-types'

const maskPhone = (value?: string | null): string => {
  const phone = String(value ?? '').trim()
  if (!phone) return '未登记电话'
  if (phone.length <= 7) return `${phone.slice(0, 2)}***${phone.slice(-2)}`
  return `${phone.slice(0, 3)}****${phone.slice(-4)}`
}
import {
  estimateDistanceKm,
  formatDateTime,
  formatNumber,
  formatRefreshTime,
  formatText,
  getDelayText,
  getMonitorRecordId,
  getRoutePosition,
  isDelayed,
  isRouteVisibleStatus,
  normalizeVehicleTypeCode,
  percentOf,
  resolveArrivalPerformance,
  resolveCurrentLabel,
  resolveEndpointGeo,
  resolveProgress,
  resolveSpeed,
  resolveTransitStatus,
  splitRoutePath
} from './monitor-utils'

interface UseMonitorOrdersOptions {
  activeMode: Ref<MonitorMode>
  drivingRoutePaths: ReadonlyMap<string, GeoCoord[]>
  getDictOptions: (dictCode: string) => readonly Api.DataCenter.DictListItem[]
  liveTick: Ref<number>
  screen: ScreenState
}

export function useMonitorOrders(options: UseMonitorOrdersOptions) {
  const monitorStatusOptions = computed<Api.DataCenter.DictListItem[]>(() => [
    ...options.getDictOptions(MONITOR_STATUS_DICT_CODE)
  ])

  const monitorOrders = computed<MonitorOrder[]>(() =>
    options.screen.orders.map(createMonitorOrder)
  )

  const realtimeOrders = computed<MonitorOrder[]>(() =>
    monitorOrders.value.filter(isRealtimeMonitorOrder)
  )

  const modeOrders = computed<MonitorOrder[]>(() =>
    options.activeMode.value === 'realtime' ? realtimeOrders.value : monitorOrders.value
  )

  const filteredOrders = computed<MonitorOrder[]>(() => {
    const keyword = options.screen.keyword.trim().toLowerCase()

    return realtimeOrders.value.filter((item) => {
      const matchesStatus = !options.screen.status || item.status === options.screen.status
      const matchesRegion = matchesSelectedRegion(item)
      const matchesKeyword =
        !keyword ||
        [item.plateNo, item.orderNo, item.driverName, item.driverPhone, item.routeName]
          .join(' ')
          .toLowerCase()
          .includes(keyword)

      return matchesStatus && matchesRegion && matchesKeyword
    })
  })

  const activeOrder = computed<MonitorOrder | undefined>(() => {
    return (
      modeOrders.value.find((item) => item.id === options.screen.selectedOrderId) ??
      (options.activeMode.value === 'realtime' ? filteredOrders.value[0] : modeOrders.value[0])
    )
  })

  const mapRouteOrder = computed<MonitorOrder | undefined>(() => {
    const active = activeOrder.value
    return active && isRouteVisibleStatus(active.status) ? active : undefined
  })

  const averageProgress = computed(() =>
    modeOrders.value.length ? Math.round(meanBy(modeOrders.value, 'progress')) : 0
  )

  const overview = computed(() => {
    const orders = modeOrders.value
    const transporting = orders.filter(isRealtimeMonitorOrder).length
    const delayed = orders.filter((item) => item.delayed).length
    const routeCount = uniq(orders.map((item) => item.routeName)).length
    const vehicleCount = uniq(orders.map((item) => item.plateNo)).length
    const total = orders.length

    return {
      cargoCount: sumBy(orders, 'cargoBoxes'),
      delayedCount: delayed,
      growthRate: Math.max(4, Math.min(18, routeCount + transporting)),
      onTimeRate: total > 0 ? Math.round(((total - delayed) / total) * 100) : 100,
      routeCount,
      todayCount: total,
      transporting,
      vehicleCount
    }
  })

  const overviewBars = computed(() => [
    {
      color: '#4c7dff',
      label: '在途车辆',
      percent: percentOf(overview.value.transporting, Math.max(overview.value.todayCount, 1)),
      value: `${overview.value.transporting}/${overview.value.todayCount}`
    },
    {
      color: '#23d18b',
      label: '准时运输',
      percent: overview.value.onTimeRate,
      value: `${overview.value.onTimeRate}%`
    },
    {
      color: '#ff9f43',
      label: '运输完成率',
      percent: averageProgress.value,
      value: `${averageProgress.value}%`
    }
  ])

  const alertItems = computed<AlertItem[]>(() => {
    const delayedAlerts = realtimeOrders.value
      .filter((item) => item.delayed)
      .map((item) => ({
        content: `${item.orderNo} 预计到达 ${formatDateTime(item.plannedArrivalTime)}`,
        key: `delay-${item.id}`,
        level: 'danger' as const,
        time: formatRefreshTime(options.screen.lastRefreshTime),
        title: `${item.plateNo} 路线偏离或延误`
      }))

    const missingVehicleAlerts = realtimeOrders.value
      .filter((item) => item.plateNo === '未配车')
      .map((item) => ({
        content: `${item.orderNo} 已进入在途池，请补充配载车辆信息`,
        key: `vehicle-${item.id}`,
        level: 'warning' as const,
        time: formatRefreshTime(options.screen.lastRefreshTime),
        title: '车辆信息缺失'
      }))

    return [...delayedAlerts, ...missingVehicleAlerts].slice(0, 6)
  })

  watch(filteredOrders, (items) => {
    if (options.activeMode.value !== 'realtime' || !items.length) return
    if (!items.some((item) => item.id === options.screen.selectedOrderId)) {
      options.screen.selectedOrderId = items[0].id
    }
  })

  watch(modeOrders, (items) => {
    if (!items.some((item) => item.id === options.screen.selectedOrderId)) {
      options.screen.selectedOrderId = items[0]?.id
    }
  })

  function createMonitorOrder(row: InTransitRecord): MonitorOrder {
    const id = getMonitorRecordId(row)
    const order = row.order
    const origin = formatText(row.originCity || order?.originStation)
    const destination = formatText(row.destinationCity || order?.destinationStation)
    const originGeo = resolveEndpointGeo(
      row,
      'origin',
      row.shipperLongitude ?? order?.shippingLongitude,
      row.shipperLatitude ?? order?.shippingLatitude,
      origin
    )
    const destinationGeo = resolveEndpointGeo(
      row,
      'destination',
      row.receiverLongitude ?? order?.receivingLongitude,
      row.receiverLatitude ?? order?.receivingLatitude,
      destination
    )
    const delayed = isDelayed(row)
    const status = resolveTransitStatus(row, delayed)
    const arrivalPerformance = resolveArrivalPerformance(row)
    const progress = resolveProgress(row, id, status, options.liveTick.value)
    const routePath = options.drivingRoutePaths.get(id) ?? []
    const currentGeo =
      routePath.length > 1
        ? getRoutePosition(routePath, progress).coord
        : status === 'arrived'
          ? destinationGeo
          : originGeo
    const routeSegments = splitRoutePath(routePath, currentGeo, progress)
    const distance = estimateDistanceKm(originGeo, destinationGeo)
    const vehicleTypeCode = normalizeVehicleTypeCode(
      row.vehicle?.vehicleType || order?.dispatchVehicleType
    )
    const vehicleTypeLabel = getDictLabel(
      VEHICLE_TYPE_DICT_CODE,
      vehicleTypeCode,
      vehicleTypeCode || '运输车辆'
    )
    const cargoWeightText =
      row.cargoWeightTon !== null && row.cargoWeightTon !== undefined
        ? `${formatNumber(row.cargoWeightTon)} 吨`
        : `${formatNumber(order?.cargoWeightTotal)} kg`

    return {
      arrivalDelayed: arrivalPerformance.delayed,
      arrivalText: arrivalPerformance.text,
      cargoBoxes: Number(row.cargoQuantity ?? order?.cargoQuantityTotal ?? 0),
      cargoSummary: [
        {
          label: '货物类型',
          value:
            row.cargoName || order?.cargoItems?.map((item) => item.cargoName).find(Boolean) || '-'
        },
        {
          label: '总数量',
          value: `${formatNumber(row.cargoQuantity ?? order?.cargoQuantityTotal, 0)} 件`
        },
        { label: '总重量', value: cargoWeightText },
        {
          label: '总体积',
          value: `${formatNumber(row.cargoVolumeM3 ?? order?.cargoVolumeTotal, 3)} 方`
        }
      ],
      completedKm: Math.round(distance * (progress / 100)),
      currentLabel: resolveCurrentLabel(row, progress),
      delayed,
      delayText: getDelayText(row.plannedUnloadTime ?? order?.plannedArrivalTime),
      destination,
      destinationGeo,
      driverName: formatText(row.driver?.driverName || order?.dispatchDriverName, '未派司机'),
      driverPhone: maskPhone(row.driver?.phone || order?.dispatchDriverPhone),
      id,
      latitude: currentGeo[1],
      longitude: currentGeo[0],
      orderNo: formatText(row.waybillNo || order?.orderNo),
      origin,
      originGeo,
      passedPath: routeSegments.passedPath,
      plannedArrivalTime: row.plannedUnloadTime ?? order?.plannedArrivalTime,
      plannedDepartureTime: row.plannedLoadTime ?? order?.plannedDepartureTime,
      plateNo: formatText(row.vehicle?.plateNo || order?.dispatchPlateNo, '未配车'),
      progress,
      remainingKm: Math.max(0, Math.round(distance * (1 - progress / 100))),
      remainingPath: routeSegments.remainingPath,
      routeName: [origin, order?.transferStation, destination].filter(Boolean).join(' - '),
      routePath,
      source: row,
      speed: resolveSpeed(row, status, id),
      status,
      statusColor: getMonitorStatusColor(status),
      statusLabel: getMonitorStatusLabel(status),
      totalKm: distance,
      vehicleImage: getVehicleImage(vehicleTypeCode),
      vehicleType: vehicleTypeCode,
      vehicleTypeCode,
      vehicleTypeLabel
    }
  }

  function matchesSelectedRegion(item: MonitorOrder): boolean {
    if (!options.screen.region) return true
    const region = regionOptions.find((option) => option.value === options.screen.region)
    if (!region) return true

    const routeText = [item.origin, item.destination, item.routeName, item.currentLabel].join('')
    return region.keywords.some((keyword) => routeText.includes(keyword))
  }

  function isRealtimeMonitorOrder(item: MonitorOrder): boolean {
    const waybillStatus = String(item.source.status ?? '')
      .trim()
      .toLowerCase()
    return REALTIME_WAYBILL_STATUSES.has(waybillStatus)
  }

  function getPreferredMonitorRecordId(rows: InTransitRecord[]): string | undefined {
    const preferred = rows.find((row) => {
      const status = resolveTransitStatus(row, isDelayed(row))
      return ['transporting', 'delayed'].includes(status)
    })
    const row = preferred ?? rows.find((item) => resolveTransitStatus(item, false) === 'arrived')
    return row ? getMonitorRecordId(row) : rows[0] ? getMonitorRecordId(rows[0]) : undefined
  }

  function getMonitorStatusItem(status: TransitStatus) {
    return monitorStatusOptions.value.find((item) => String(item.value) === status)
  }

  function getMonitorStatusLabel(status: TransitStatus): string {
    return getMonitorStatusItem(status)?.label || status
  }

  function getMonitorStatusColor(status: TransitStatus): string {
    return getMonitorStatusItem(status)?.color || '#409EFF'
  }

  function getDictLabel(dictCode: string, value?: string | number | null, fallback = '-'): string {
    const normalizedValue = String(value ?? '').trim()
    if (!normalizedValue) return fallback

    const dictItem = options
      .getDictOptions(dictCode)
      .find(
        (item) => String(item.value) === normalizedValue || String(item.code) === normalizedValue
      )
    return dictItem?.label || dictItem?.name || fallback
  }

  return {
    activeOrder,
    alertItems,
    filteredOrders,
    getPreferredMonitorRecordId,
    mapRouteOrder,
    modeOrders,
    monitorOrders,
    monitorStatusOptions,
    overview,
    overviewBars,
    realtimeOrders
  }
}
