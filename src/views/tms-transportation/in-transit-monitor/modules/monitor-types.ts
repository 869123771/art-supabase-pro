export type InTransitRecord = Api.Tms.InTransit.MonitorRecord

export type TransitStatus = 'pending' | 'transporting' | 'arrived' | 'delayed'

export type MonitorMode = 'realtime' | 'waybill' | 'vehicle'

export type GeoCoord = [number, number]

export interface MonitorOrder {
  arrivalDelayed: boolean
  arrivalText: string
  cargoBoxes: number
  cargoSummary: Array<{ label: string; value: string }>
  completedKm: number
  currentLabel: string
  delayed: boolean
  delayText: string
  destination: string
  destinationGeo: GeoCoord
  driverName: string
  driverPhone: string
  id: string
  latitude: number
  longitude: number
  orderNo: string
  origin: string
  originGeo: GeoCoord
  plateNo: string
  plannedArrivalTime?: string | null
  plannedDepartureTime?: string | null
  passedPath: GeoCoord[]
  progress: number
  remainingKm: number
  remainingPath: GeoCoord[]
  routePath: GeoCoord[]
  routeName: string
  source: InTransitRecord
  speed: number
  status: TransitStatus
  statusColor: string
  statusLabel: string
  totalKm: number
  vehicleType: string
  vehicleTypeCode: string
  vehicleTypeLabel: string
  vehicleImage: string
}

export interface MonitorOverview {
  cargoCount: number
  delayedCount: number
  growthRate: number
  onTimeRate: number
  routeCount: number
  todayCount: number
  transporting: number
  vehicleCount: number
}

export interface RegionOption {
  keywords: string[]
  label: string
  value: string
}

export interface StationGeoPosition {
  coord: GeoCoord
  keywords: string[]
}

export interface ScreenState {
  error: Error | null
  keyword: string
  lastRefreshTime?: string
  loading: boolean
  loaded: boolean
  orders: InTransitRecord[]
  region: string
  selectedOrderId?: string
  status: TransitStatus | ''
}

export interface MonitorKeywordState {
  vehicle: string
  waybill: string
}

export interface AlertItem {
  content: string
  key: string
  level: 'danger' | 'warning' | 'info'
  time: string
  title: string
}

export interface ScreenScaleState {
  viewportHeight: number
  viewportWidth: number
}

export interface VehiclePoiState {
  coordinateKey: string
  label: string
  loading: boolean
}

export interface ReverseGeocodeResult {
  regeocode?: {
    formattedAddress?: string
    formatted_address?: string
    pois?: Array<{ name?: string }>
  }
}
