import type { GeoCoord, ReverseGeocodeResult } from './monitor-types'

export interface MonitorAmapLngLatLike {
  lng?: number
  lat?: number
  getLng?: () => number
  getLat?: () => number
}

export interface MonitorAmapMarkerInstance {
  setContent: (content: string) => void
  setPosition: (position: GeoCoord) => void
  setzIndex?: (zIndex: number) => void
}

export interface MonitorAmapPolylineInstance {
  setOptions?: (options: Record<string, unknown>) => void
  setPath: (path: MonitorAmapLngLatLike[]) => void
}

export type MonitorAmapOverlay = MonitorAmapMarkerInstance | MonitorAmapPolylineInstance

export interface MonitorAmapMapInstance {
  add: (overlay: MonitorAmapOverlay | unknown) => void
  addControl: (control: unknown) => void
  destroy?: () => void
  getZoom?: () => number
  on: (event: string, handler: () => void) => void
  remove?: (overlay: MonitorAmapOverlay) => void
  resize?: () => void
  setCenter?: (center: GeoCoord) => void
  setFitView?: (overlays?: MonitorAmapOverlay[], immediately?: boolean, avoid?: number[]) => void
  setStatus?: (status: Record<string, boolean>) => void
  setZoom?: (zoom: number) => void
  setZoomAndCenter?: (zoom: number, center: GeoCoord) => void
  zoomIn?: () => void
  zoomOut?: () => void
}

export interface MonitorAmapGeocoderInstance {
  getAddress: (
    position: GeoCoord,
    callback: (status: string, result: ReverseGeocodeResult) => void
  ) => void
}

export interface MonitorAmapDrivingResult {
  routes?: Array<{
    steps?: Array<{
      path?: MonitorAmapLngLatLike[]
    }>
  }>
}

export interface MonitorAmapDrivingInstance {
  search: (
    origin: MonitorAmapLngLatLike,
    destination: MonitorAmapLngLatLike,
    callback: (status: string, result: MonitorAmapDrivingResult) => void
  ) => void
}

export interface MonitorAmapNamespace {
  Driving: new (options: Record<string, unknown>) => MonitorAmapDrivingInstance
  DrivingPolicy?: {
    LEAST_TIME?: unknown
  }
  Geocoder: new (options: Record<string, unknown>) => MonitorAmapGeocoderInstance
  LngLat: new (lng: number, lat: number) => MonitorAmapLngLatLike
  Map: new (container: HTMLElement, options: Record<string, unknown>) => MonitorAmapMapInstance
  Marker: new (options: Record<string, unknown>) => MonitorAmapMarkerInstance
  Pixel: new (x: number, y: number) => unknown
  Polyline: new (options: Record<string, unknown>) => MonitorAmapPolylineInstance
  Scale: new () => unknown
  [key: string]: unknown
}
