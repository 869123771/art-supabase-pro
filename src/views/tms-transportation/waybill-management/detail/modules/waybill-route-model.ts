import { meanBy, uniqBy } from 'lodash-es'

export type WaybillLocationSource = 'gps' | 'operation' | 'address' | 'expense'
export type WaybillPointKind = 'business' | 'energy' | 'stop' | 'endpoint'

export interface WaybillLocationPoint {
  id: string
  label: string
  markerLabel: string
  kind: WaybillPointKind
  time?: string | null
  endTime?: string | null
  durationMinutes?: number | null
  address?: string | null
  longitude: number
  latitude: number
  source: WaybillLocationSource
  sourceLabel: string
  isDerived: boolean
  accuracyM?: number | null
  distanceM?: number | null
  insideGeofence?: boolean | null
}

export interface WaybillGpsTrackPoint {
  address?: string | null
  capturedAt: string
  latitude: number
  longitude: number
  speedKmh?: number | null
}

const STOP_RADIUS_M = 200
const STOP_DUPLICATE_RADIUS_M = 250
const STOP_MIN_DURATION_MINUTES = 5
const STOP_MAX_SPEED_KMH = 5

const eventLabelMap: Record<string, string> = {
  accepted: '接单',
  loading_checked_in: '装货签到',
  loaded: '装货完成',
  departed: '发车',
  arrived: '到达',
  unloaded: '卸货完成',
  signed: '签收',
  completed: '完成'
}

const eventMarkerMap: Record<string, string> = {
  accepted: '接',
  loading_checked_in: '装',
  loaded: '装',
  departed: '发',
  arrived: '到',
  unloaded: '卸',
  signed: '签',
  completed: '完'
}

export function buildWaybillLocationPoints(
  waybill: Api.Tms.Waybill.WaybillDetailRecord
): WaybillLocationPoint[] {
  const loadingOperation = findOperation(waybill, 'loading')
  const unloadingOperation = findOperation(waybill, 'unloading')
  const eventPoints = waybill.events.flatMap((event) => {
    const directCoordinate = toCoordinate(event.longitude, event.latitude)
    const directCoordinateMeta = directCoordinate ? getEventCoordinateMeta(event) : null
    const fallback = directCoordinate ? null : resolveEventFallback(waybill, event.eventType)
    const coordinate = directCoordinate ?? fallback?.coordinate
    if (!coordinate) return []

    return [
      {
        id: `event-${event.id}`,
        label: getWaybillEventLabel(event.eventType),
        markerLabel: eventMarkerMap[event.eventType] || '点',
        kind: 'business' as const,
        time: event.eventTime,
        address: event.locationText || fallback?.address,
        ...coordinate,
        source: directCoordinate
          ? (directCoordinateMeta?.source ?? ('gps' as const))
          : (fallback?.source ?? 'address'),
        sourceLabel: directCoordinate
          ? (directCoordinateMeta?.sourceLabel ?? '事件定位')
          : (fallback?.sourceLabel ?? '地址档案'),
        isDerived: directCoordinate ? (directCoordinateMeta?.isDerived ?? false) : true
      }
    ]
  })
  const operationPoints = waybill.cargoOperations.flatMap((operation) => {
    const coordinate = toCoordinate(operation.longitude, operation.latitude)
    if (!coordinate) return []
    const isLoading = operation.operationType === 'loading'
    return [
      {
        id: `operation-${operation.id}`,
        label: isLoading ? '装货签到' : '卸货签到',
        markerLabel: isLoading ? '装' : '卸',
        kind: 'business' as const,
        time: operation.checkinTime,
        address: operation.locationText,
        ...coordinate,
        source: 'operation' as const,
        sourceLabel: '装卸打卡',
        isDerived: false,
        accuracyM: operation.locationAccuracyM,
        distanceM: operation.distanceM,
        insideGeofence: operation.insideGeofence
      }
    ]
  })
  const expensePoints = (waybill.expenseLocations ?? []).map(createExpensePoint)
  const endpointPoints = [
    createEndpointPoint(
      'shipper',
      '发货地址',
      '发',
      waybill.createTime,
      waybill.shipperAddress,
      waybill.shipperLongitude,
      waybill.shipperLatitude
    ),
    createEndpointPoint(
      'receiver',
      '收货地址',
      '收',
      waybill.completedAt || waybill.plannedUnloadTime,
      waybill.receiverAddress,
      waybill.receiverLongitude,
      waybill.receiverLatitude
    )
  ].filter((point): point is WaybillLocationPoint => point !== null)

  const businessPoints = uniqLocationPoints([
    ...endpointPoints,
    ...eventPoints,
    ...operationPoints,
    ...expensePoints
  ])
  const stopPoints = buildAutomaticStopPoints(waybill, businessPoints)

  return [...businessPoints, ...stopPoints].sort(
    (left, right) => getTimeValue(left.time) - getTimeValue(right.time)
  )

  function resolveEventFallback(
    detail: Api.Tms.Waybill.WaybillDetailRecord,
    eventType: string
  ): {
    coordinate: { longitude: number; latitude: number }
    address?: string | null
    source: WaybillLocationSource
    sourceLabel: string
  } | null {
    if (eventType === 'accepted') {
      return createAddressFallback(
        detail.shipperLongitude,
        detail.shipperLatitude,
        detail.shipperAddress
      )
    }
    if (['departed', 'loaded', 'loading_checked_in'].includes(eventType)) {
      return createOperationFallback(loadingOperation)
    }
    if (['arrived', 'unloaded', 'signed'].includes(eventType)) {
      return createOperationFallback(unloadingOperation)
    }
    if (eventType === 'completed') {
      return (
        createOperationFallback(unloadingOperation) ??
        createAddressFallback(
          detail.receiverLongitude,
          detail.receiverLatitude,
          detail.receiverAddress
        )
      )
    }
    return null
  }
}

export function buildWaybillGpsTrackPoints(
  waybill: Pick<Api.Tms.Waybill.WaybillDetailRecord, 'routePoints'>
): WaybillGpsTrackPoint[] {
  if (!Array.isArray(waybill.routePoints)) return []

  return uniqBy(
    waybill.routePoints.flatMap((point) => {
      const coordinate = toCoordinate(point.longitude, point.latitude)
      const capturedAt = String(point.capturedAt || '').trim()
      if (!coordinate || !capturedAt || !Number.isFinite(new Date(capturedAt).getTime())) return []
      return [
        {
          ...coordinate,
          capturedAt,
          address: point.address,
          speedKmh: point.speedKmh
        }
      ]
    }),
    (point) => `${point.capturedAt}:${point.longitude.toFixed(6)}:${point.latitude.toFixed(6)}`
  ).sort((left, right) => getTimeValue(left.capturedAt) - getTimeValue(right.capturedAt))
}

export function buildDrivingRoutePoints(
  locationPoints: WaybillLocationPoint[]
): WaybillLocationPoint[] {
  const shipper = locationPoints.find((point) => point.id === 'shipper')
  const receiver = locationPoints.find((point) => point.id === 'receiver')
  const measuredPoints = locationPoints.filter(
    (point) => !point.isDerived && point.source !== 'address'
  )

  const routePoints = uniqBy(
    [shipper, ...measuredPoints, receiver].filter(
      (point): point is WaybillLocationPoint => point !== undefined
    ),
    (point) => `${point.longitude.toFixed(4)}:${point.latitude.toFixed(4)}`
  )
  if (routePoints.length <= 18) return routePoints
  const destination = routePoints.at(-1)
  return destination ? [...routePoints.slice(0, 17), destination] : routePoints.slice(0, 18)
}

export function isValidMapCoordinate(
  longitude?: number | string | null,
  latitude?: number | string | null
): boolean {
  if (longitude == null || latitude == null || longitude === '' || latitude === '') return false
  const numericLongitude = Number(longitude)
  const numericLatitude = Number(latitude)
  return (
    Number.isFinite(numericLongitude) &&
    Number.isFinite(numericLatitude) &&
    numericLongitude >= -180 &&
    numericLongitude <= 180 &&
    numericLatitude >= -90 &&
    numericLatitude <= 90 &&
    !(numericLongitude === 0 && numericLatitude === 0)
  )
}

export function getWaybillEventLabel(type: string): string {
  return eventLabelMap[type] || '运输节点'
}

function buildAutomaticStopPoints(
  waybill: Api.Tms.Waybill.WaybillDetailRecord,
  businessPoints: WaybillLocationPoint[]
): WaybillLocationPoint[] {
  const gpsPoints = buildWaybillGpsTrackPoints(waybill)
  const candidates: WaybillLocationPoint[] = []
  let cluster: WaybillGpsTrackPoint[] = []

  const finishCluster = (): void => {
    if (cluster.length < 2) {
      cluster = []
      return
    }
    const first = cluster[0]
    const last = cluster.at(-1)
    if (!last) return
    const durationMinutes = Math.round(
      (getTimeValue(last.capturedAt) - getTimeValue(first.capturedAt)) / 60_000
    )
    if (durationMinutes >= STOP_MIN_DURATION_MINUTES) {
      const longitude = meanBy(cluster, 'longitude')
      const latitude = meanBy(cluster, 'latitude')
      const overlapsBusinessNode = businessPoints.some(
        (point) =>
          getDistanceMeters([longitude, latitude], [point.longitude, point.latitude]) <=
          STOP_DUPLICATE_RADIUS_M
      )
      if (!overlapsBusinessNode) {
        candidates.push({
          id: `stop-${first.capturedAt}`,
          label: '停车',
          markerLabel: 'P',
          kind: 'stop',
          time: first.capturedAt,
          endTime: last.capturedAt,
          durationMinutes,
          address: cluster.findLast((point) => Boolean(point.address))?.address,
          longitude,
          latitude,
          source: 'gps',
          sourceLabel: 'GPS 自动识别',
          isDerived: false
        })
      }
    }
    cluster = []
  }

  gpsPoints.forEach((point, index) => {
    const previous = gpsPoints[index - 1]
    if (!isStationarySample(point, previous)) {
      finishCluster()
      return
    }
    if (!cluster.length) {
      cluster = [point]
      return
    }
    const center: [number, number] = [meanBy(cluster, 'longitude'), meanBy(cluster, 'latitude')]
    if (getDistanceMeters(center, [point.longitude, point.latitude]) <= STOP_RADIUS_M) {
      cluster.push(point)
      return
    }
    finishCluster()
    cluster = [point]
  })
  finishCluster()

  return candidates.map((point, index) => ({ ...point, label: `停车 P${index + 1}` }))
}

function isStationarySample(point: WaybillGpsTrackPoint, previous?: WaybillGpsTrackPoint): boolean {
  if (point.speedKmh != null && Number.isFinite(point.speedKmh)) {
    return point.speedKmh <= STOP_MAX_SPEED_KMH
  }
  if (!previous) return false
  const elapsedHours =
    (getTimeValue(point.capturedAt) - getTimeValue(previous.capturedAt)) / 3_600_000
  if (elapsedHours <= 0) return false
  const speedKmh =
    getDistanceMeters([previous.longitude, previous.latitude], [point.longitude, point.latitude]) /
    1000 /
    elapsedHours
  return speedKmh <= STOP_MAX_SPEED_KMH
}

function createExpensePoint(
  expense: Api.Tms.Waybill.WaybillExpenseLocationRecord
): WaybillLocationPoint {
  const itemText = `${expense.expenseItem?.itemCode || ''} ${expense.expenseItem?.itemName || ''} ${expense.expenseItem?.businessCategory || ''}`
  const isCharging = /(charging|charge|充电)/i.test(itemText)
  return {
    id: `expense-${expense.id}`,
    label: isCharging ? '充电' : '加油',
    markerLabel: isCharging ? '充' : '油',
    kind: 'energy',
    time: expense.occurredOn,
    address: expense.expenseLocation,
    longitude: expense.expenseLongitude,
    latitude: expense.expenseLatitude,
    source: 'expense',
    sourceLabel: '费用上报定位',
    isDerived: false
  }
}

function uniqLocationPoints(points: WaybillLocationPoint[]): WaybillLocationPoint[] {
  return uniqBy(
    points,
    (point) => `${point.longitude.toFixed(6)}:${point.latitude.toFixed(6)}:${point.label}`
  )
}

function toCoordinate(
  longitude?: number | string | null,
  latitude?: number | string | null
): { longitude: number; latitude: number } | null {
  if (!isValidMapCoordinate(longitude, latitude)) return null
  return { longitude: Number(longitude), latitude: Number(latitude) }
}

function createEndpointPoint(
  id: 'shipper' | 'receiver',
  label: string,
  markerLabel: string,
  time: string | null | undefined,
  address: string | null | undefined,
  longitude: number | string | null | undefined,
  latitude: number | string | null | undefined
): WaybillLocationPoint | null {
  const coordinate = toCoordinate(longitude, latitude)
  if (!coordinate) return null
  return {
    id,
    label,
    markerLabel,
    kind: 'endpoint',
    time,
    address,
    ...coordinate,
    source: 'address',
    sourceLabel: '地址档案',
    isDerived: false
  }
}

function findOperation(
  waybill: Api.Tms.Waybill.WaybillDetailRecord,
  operationType: Api.Tms.Waybill.CargoOperationType
): Api.Tms.Waybill.CargoOperationRecord | undefined {
  return waybill.cargoOperations.find((operation) => operation.operationType === operationType)
}

function createOperationFallback(operation?: Api.Tms.Waybill.CargoOperationRecord): {
  coordinate: { longitude: number; latitude: number }
  address?: string | null
  source: 'operation'
  sourceLabel: string
} | null {
  const coordinate = toCoordinate(operation?.longitude, operation?.latitude)
  return coordinate
    ? { coordinate, address: operation?.locationText, source: 'operation', sourceLabel: '关联打卡' }
    : null
}

function createAddressFallback(
  longitude: number | string | null | undefined,
  latitude: number | string | null | undefined,
  address: string | null | undefined
): {
  coordinate: { longitude: number; latitude: number }
  address?: string | null
  source: 'address'
  sourceLabel: string
} | null {
  const coordinate = toCoordinate(longitude, latitude)
  return coordinate ? { coordinate, address, source: 'address', sourceLabel: '关联地址' } : null
}

function getTimeValue(value?: string | null): number {
  const time = value ? new Date(value).getTime() : Number.MAX_SAFE_INTEGER
  return Number.isFinite(time) ? time : Number.MAX_SAFE_INTEGER
}

function getDistanceMeters(start: [number, number], end: [number, number]): number {
  const radius = 6_371_000
  const toRadians = (value: number) => (value * Math.PI) / 180
  const latitudeDelta = toRadians(end[1] - start[1])
  const longitudeDelta = toRadians(end[0] - start[0])
  const startLatitude = toRadians(start[1])
  const endLatitude = toRadians(end[1])
  const factor =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(startLatitude) * Math.cos(endLatitude) * Math.sin(longitudeDelta / 2) ** 2
  return radius * 2 * Math.atan2(Math.sqrt(factor), Math.sqrt(1 - factor))
}

function getEventCoordinateMeta(event: Api.Tms.Waybill.WaybillEventRecord): {
  source: WaybillLocationSource
  sourceLabel: string
  isDerived: boolean
} | null {
  if (event.payload.coordinateDerived !== true) return null
  const coordinateSource = event.payload.coordinateSource
  if (coordinateSource === 'loading_operation' || coordinateSource === 'unloading_operation') {
    return { source: 'operation', sourceLabel: '关联打卡', isDerived: true }
  }
  if (coordinateSource === 'shipper_address' || coordinateSource === 'receiver_address') {
    return { source: 'address', sourceLabel: '关联地址', isDerived: true }
  }
  return { source: 'address', sourceLabel: '推导坐标', isDerived: true }
}
