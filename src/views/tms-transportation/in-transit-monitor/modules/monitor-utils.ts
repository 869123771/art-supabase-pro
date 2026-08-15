import dayjs from 'dayjs'
import { clamp, escape, uniqBy } from 'lodash-es'
import { formatWithDayjs } from '@/utils/time'
import type { GeoCoord, InTransitRecord, TransitStatus } from './monitor-types'
import { INITIAL_MAP_CENTER, stationGeoPositions } from './monitor-geo-config'

export const getMonitorRecordId = (row: InTransitRecord): string => String(row.id || row.waybillNo)

export const getRoutePosition = (path: GeoCoord[], progress: number): { coord: GeoCoord } => {
  if (path.length === 0) return { coord: INITIAL_MAP_CENTER }
  if (path.length === 1) return { coord: path[0] }

  const targetIndex = clamp(Math.round((progress / 100) * (path.length - 1)), 0, path.length - 1)

  return {
    coord: path[targetIndex]
  }
}

export const splitRoutePath = (
  routePath: GeoCoord[],
  current: GeoCoord,
  progress: number
): { passedPath: GeoCoord[]; remainingPath: GeoCoord[] } => {
  if (routePath.length <= 1) {
    return {
      passedPath: [current],
      remainingPath: [current]
    }
  }

  const segmentIndex = clamp(
    Math.floor((progress / 100) * (routePath.length - 1)),
    0,
    routePath.length - 2
  )

  return {
    passedPath: dedupeGeoPath([...routePath.slice(0, segmentIndex + 1), current]),
    remainingPath: dedupeGeoPath([current, ...routePath.slice(segmentIndex + 1)])
  }
}

export const resolveEndpointGeo = (
  row: InTransitRecord,
  endpoint: 'origin' | 'destination',
  longitude: number | string | null | undefined,
  latitude: number | string | null | undefined,
  fallbackText: string
): GeoCoord => {
  const directGeo = toGeoCoord(longitude, latitude)
  if (directGeo) return directGeo

  const routePointGeo = getRoutePointGeo(row, endpoint)
  if (routePointGeo) return routePointGeo

  return resolveStationGeo(fallbackText)
}

export const toGeoCoord = (
  longitude: number | string | null | undefined,
  latitude: number | string | null | undefined
): GeoCoord | undefined => {
  const lng = Number(longitude)
  const lat = Number(latitude)
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return undefined
  if (Math.abs(lng) > 180 || Math.abs(lat) > 90) return undefined
  return [Number(lng.toFixed(6)), Number(lat.toFixed(6))]
}

export const resolveActualTrackPath = (row: InTransitRecord): GeoCoord[] => {
  const routePoints = Array.isArray(row.routePoints) ? row.routePoints : []
  const hasGpsEvidence = routePoints.some((point) => {
    const sourceText = `${point.type || ''} ${point.source || ''}`.toLowerCase()
    return (
      Boolean(point.capturedAt || point.timestamp || point.recordedAt) ||
      /(gps|track|trajectory|telemetry|location)/.test(sourceText)
    )
  })
  if (!hasGpsEvidence) return []

  return dedupeGeoPath(
    routePoints.flatMap((point) => {
      const coordinate = toGeoCoord(point.longitude ?? point.lng, point.latitude ?? point.lat)
      return coordinate ? [coordinate] : []
    })
  )
}

export const resolveProgress = (
  row: InTransitRecord,
  seed: string,
  status: TransitStatus,
  liveTick: number
): number => {
  if (status === 'pending') return 0
  if (status === 'arrived') return 100

  const departure = dayjs(row.loadedAt || row.plannedLoadTime || row.order?.plannedDepartureTime)
  const arrival = dayjs(row.plannedUnloadTime || row.order?.plannedArrivalTime)
  if (departure.isValid() && arrival.isValid() && arrival.isAfter(departure)) {
    const total = arrival.diff(departure)
    const elapsed = dayjs().diff(departure)
    const liveOffset = ((liveTick + hashText(seed)) % 8) * 0.45
    return clamp(Math.round((elapsed / total) * 100 + liveOffset), 32, 94)
  }

  return clamp(48 + (hashText(row.waybillNo) % 36) + (liveTick % 6), 32, 94)
}

export const resolveCurrentLabel = (row: InTransitRecord, progress: number): string => {
  const status = resolveTransitStatus(row, isDelayed(row))
  if (status === 'pending') return row.originCity || '待处理'
  if (status === 'arrived') return row.destinationCity || '已到达'
  if (progress > 80) return row.destinationCity || '目的地附近'
  if (progress > 48 && row.order?.transferStation) return row.order.transferStation
  return '在途'
}

export const isDelayed = (row: InTransitRecord): boolean => {
  const plannedUnloadTime = row.plannedUnloadTime || row.order?.plannedArrivalTime
  const waybillStatus = String(row.status ?? '').toLowerCase()
  const orderStatus = String(row.order?.orderStatus ?? '').toLowerCase()
  if (
    !plannedUnloadTime ||
    row.unloadedAt ||
    waybillStatus === 'completed' ||
    ['signed', 'completed'].includes(orderStatus)
  ) {
    return false
  }
  const arrival = dayjs(plannedUnloadTime)
  return arrival.isValid() && dayjs().isAfter(arrival)
}

export const getDelayText = (value?: string | null): string => {
  const arrival = dayjs(value)
  if (!arrival.isValid()) return ''
  const hours = Math.max(1, dayjs().diff(arrival, 'hour'))
  return `${hours}h`
}

export const resolveArrivalPerformance = (
  row: InTransitRecord
): { delayed: boolean; text: string } => {
  const planned = dayjs(row.plannedUnloadTime || row.order?.plannedArrivalTime)
  const actual = dayjs(row.unloadedAt || row.order?.signedAt || row.updateTime)
  if (!planned.isValid() || !actual.isValid()) return { delayed: false, text: '准时' }

  const delayedMinutes = actual.diff(planned, 'minute')
  if (delayedMinutes <= 0) return { delayed: false, text: '准时' }

  const delayText =
    delayedMinutes < 60 ? `${delayedMinutes}m` : `${Number((delayedMinutes / 60).toFixed(1))}h`
  return { delayed: true, text: `延误${delayText}` }
}

export const resolveTransitStatus = (row: InTransitRecord, delayed: boolean): TransitStatus => {
  if (delayed) return 'delayed'

  const rawStatus = String(row.status || row.order?.orderStatus || '')
    .trim()
    .toLowerCase()
  if (['completed', 'signed'].includes(rawStatus) || row.unloadedAt) return 'arrived'

  const runningStatuses = [
    'accepted',
    'loading',
    'transporting',
    'unloading',
    'in_transit',
    'running',
    'processing',
    'in_progress',
    'ongoing'
  ]
  return runningStatuses.includes(rawStatus) ? 'transporting' : 'pending'
}

export const isRouteVisibleStatus = (status: TransitStatus): boolean =>
  ['transporting', 'delayed'].includes(status)

export const resolveSpeed = (row: InTransitRecord, status: TransitStatus, seed: string): number => {
  const speed = Number(row.speedKmh)
  if (Number.isFinite(speed) && speed >= 0) return Math.round(speed)
  return ['transporting', 'delayed'].includes(status) ? 58 + (hashText(seed) % 28) : 0
}

export const estimateDistanceKm = (origin: GeoCoord, destination: GeoCoord): number => {
  const radius = 6371
  const toRad = (value: number) => (value * Math.PI) / 180
  const lngDiff = toRad(destination[0] - origin[0])
  const latDiff = toRad(destination[1] - origin[1])
  const startLat = toRad(origin[1])
  const endLat = toRad(destination[1])
  const factor =
    Math.sin(latDiff / 2) ** 2 + Math.cos(startLat) * Math.cos(endLat) * Math.sin(lngDiff / 2) ** 2

  return Math.max(30, Math.round(radius * 2 * Math.atan2(Math.sqrt(factor), Math.sqrt(1 - factor))))
}

export const formatDateTime = (value?: string | null): string =>
  formatWithDayjs(value, 'HH:mm') || '--'

export const formatRefreshTime = (value?: string): string =>
  formatWithDayjs(value, 'HH:mm:ss') || '--'

export const formatNumber = (value?: number | string | null, precision = 2): string => {
  const numeric = Number(value ?? 0)
  if (!Number.isFinite(numeric)) return '0'
  return numeric
    .toFixed(precision)
    .replace(/(\.\d*?)0+$/, '$1')
    .replace(/\.$/, '')
}

export const formatText = (value?: string | number | null, fallback = '-'): string => {
  const text = String(value ?? '').trim()
  return text || fallback
}

export const normalizeVehicleTypeCode = (value?: string | number | null): string =>
  String(value ?? '').trim()

export const dedupeGeoPath = (path: GeoCoord[]): GeoCoord[] =>
  uniqBy(path, ([longitude, latitude]) => `${longitude},${latitude}`)

export const escapeHtml = escape

export const percentOf = (value: number, total: number): number =>
  total > 0 ? clamp(Math.round((value / total) * 100), 0, 100) : 0

export const hashText = (value?: string | number | null): number =>
  Array.from(String(value ?? '')).reduce((hash, char) => hash + char.charCodeAt(0), 0)

const getRoutePointGeo = (
  row: InTransitRecord,
  endpoint: 'origin' | 'destination'
): GeoCoord | undefined => {
  const point = row.routePoints?.find((item) => {
    const type = String(item.type ?? '').toLowerCase()
    if (endpoint === 'origin') return ['shipper', 'origin', 'start', 'load'].includes(type)
    return ['receiver', 'destination', 'end', 'unload'].includes(type)
  })
  if (!point) return undefined
  return toGeoCoord(point.longitude ?? point.lng, point.latitude ?? point.lat)
}

const resolveStationGeo = (text: string): GeoCoord => {
  const normalized = text.trim()
  const matched = stationGeoPositions.find((item) =>
    item.keywords.some((keyword) => normalized.includes(keyword))
  )
  if (matched) return matched.coord

  const hash = hashText(normalized)
  return [86 + (hash % 36), 22 + ((hash >> 3) % 20)]
}
