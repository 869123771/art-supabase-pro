import defaultVehicleImage from '@/assets/images/tms/vehicles/default.svg?url'
import largeCityBusImage from '@/assets/images/tms/vehicles/large-city-bus.svg?url'
import mediumBusImage from '@/assets/images/tms/vehicles/medium-bus.svg?url'
import smallBusImage from '@/assets/images/tms/vehicles/small-bus.svg?url'
import specialVehicleImage from '@/assets/images/tms/vehicles/special-vehicle.svg?url'
import truckImage from '@/assets/images/tms/vehicles/truck.svg?url'
import type { MonitorMode, RegionOption } from './monitor-types'
export const INITIAL_MAP_ZOOM = 5
export const MAP_MIN_ZOOM = 4
export const MAP_MAX_ZOOM = 18
export const DEFAULT_SCREEN_DESIGN_WIDTH = 1440
export const DEFAULT_SCREEN_DESIGN_HEIGHT = 810
export const AMAP_PLUGINS = ['AMap.Scale', 'AMap.Driving', 'AMap.Geocoder']
export const INITIAL_POI_CONCURRENCY = 4
export const VEHICLE_TYPE_DICT_CODE = 'vehicleType'
export const MONITOR_STATUS_DICT_CODE = 'tmsInTransitMonitorStatus'

const VEHICLE_IMAGE_MAP: Record<string, string> = {
  'large-city-bus': largeCityBusImage,
  'medium-bus': mediumBusImage,
  'small-bus': smallBusImage,
  'special-vehicle': specialVehicleImage,
  truck: truckImage
}

export const REALTIME_WAYBILL_STATUSES = new Set([
  'transporting',
  'in_transit',
  'running',
  'processing',
  'in_progress',
  'ongoing'
])

export const monitorTabs: Array<{ label: string; value: MonitorMode }> = [
  { label: '实时监控', value: 'realtime' },
  { label: '运单监控', value: 'waybill' },
  { label: '车辆监控', value: 'vehicle' }
]

export const regionOptions: RegionOption[] = [
  {
    label: '华东区域',
    value: 'east',
    keywords: ['上海', '杭州', '南京', '苏州', '义乌', '金华']
  },
  { label: '华北区域', value: 'north', keywords: ['北京', '天津', '太原', '石家庄'] },
  { label: '华中区域', value: 'central', keywords: ['郑州', '武汉', '长沙', '南昌'] },
  { label: '华南区域', value: 'south', keywords: ['广州', '深圳', '佛山', '赣州'] },
  { label: '西南区域', value: 'southwest', keywords: ['成都', '重庆', '贵阳', '昆明'] },
  { label: '西北区域', value: 'northwest', keywords: ['西安', '兰州', '银川', '乌鲁木齐'] }
]

export const getVehicleImage = (vehicleTypeCode: string): string =>
  VEHICLE_IMAGE_MAP[vehicleTypeCode] ?? defaultVehicleImage
