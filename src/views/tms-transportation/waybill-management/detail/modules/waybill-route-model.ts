import { uniqBy } from 'lodash-es'

export type WaybillLocationSource = 'gps' | 'operation' | 'address'

export interface WaybillLocationPoint {
  id: string
  label: string
  time?: string | null
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
    return [
      {
        id: `operation-${operation.id}`,
        label: operation.operationType === 'loading' ? '装货签到' : '卸货签到',
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
  const endpointPoints = [
    createEndpointPoint(
      'shipper',
      '发货地址',
      waybill.createTime,
      waybill.shipperAddress,
      waybill.shipperLongitude,
      waybill.shipperLatitude
    ),
    createEndpointPoint(
      'receiver',
      '收货地址',
      waybill.completedAt || waybill.plannedUnloadTime,
      waybill.receiverAddress,
      waybill.receiverLongitude,
      waybill.receiverLatitude
    )
  ].filter((point): point is WaybillLocationPoint => point !== null)

  const points = uniqBy(
    [...endpointPoints, ...eventPoints, ...operationPoints],
    (point) => `${point.longitude.toFixed(6)}:${point.latitude.toFixed(6)}:${point.label}`
  )

  return points.sort((left, right) => getTimeValue(left.time) - getTimeValue(right.time))

  function resolveEventFallback(
    detail: Api.Tms.Waybill.WaybillDetailRecord,
    eventType: string
  ): {
    coordinate: { longitude: number; latitude: number }
    address?: string | null
    source: WaybillLocationSource
    sourceLabel: string
  } | null {
    if (['accepted'].includes(eventType)) {
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
