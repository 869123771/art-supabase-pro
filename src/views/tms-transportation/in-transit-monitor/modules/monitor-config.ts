import defaultVehicleImage from '@/assets/images/tms/vehicles/default.svg?url'
import largeCityBusImage from '@/assets/images/tms/vehicles/large-city-bus.svg?url'
import mediumBusImage from '@/assets/images/tms/vehicles/medium-bus.svg?url'
import smallBusImage from '@/assets/images/tms/vehicles/small-bus.svg?url'
import specialVehicleImage from '@/assets/images/tms/vehicles/special-vehicle.svg?url'
import truckImage from '@/assets/images/tms/vehicles/truck.svg?url'
import type { GeoCoord, MonitorMode, RegionOption, StationGeoPosition } from './monitor-types'

export const INITIAL_MAP_CENTER: GeoCoord = [105.5, 34.2]
export const INITIAL_MAP_ZOOM = 5
export const MAP_MIN_ZOOM = 4
export const MAP_MAX_ZOOM = 18
export const DEFAULT_SCREEN_DESIGN_WIDTH = 1920
export const DEFAULT_SCREEN_DESIGN_HEIGHT = 1080
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

export const stationGeoPositions: StationGeoPosition[] = [
  { keywords: ['北京', '京'], coord: [116.4074, 39.9042] },
  { keywords: ['天津'], coord: [117.2009, 39.0842] },
  { keywords: ['太原', '晋'], coord: [112.5492, 37.8706] },
  { keywords: ['郑州', '豫'], coord: [113.6254, 34.7466] },
  { keywords: ['西安', '陕'], coord: [108.9402, 34.3416] },
  { keywords: ['上海', '沪'], coord: [121.4737, 31.2304] },
  { keywords: ['南京', '宁'], coord: [118.7969, 32.0603] },
  { keywords: ['苏州', '苏'], coord: [120.5853, 31.2989] },
  { keywords: ['杭州', '杭'], coord: [120.1551, 30.2741] },
  { keywords: ['义乌', '金华'], coord: [120.0751, 29.3068] },
  { keywords: ['武汉', '鄂'], coord: [114.3054, 30.5931] },
  { keywords: ['长沙', '湘'], coord: [112.9388, 28.2282] },
  { keywords: ['南昌', '赣'], coord: [115.8582, 28.682] },
  { keywords: ['赣州'], coord: [114.935, 25.8311] },
  { keywords: ['广州', '粤'], coord: [113.2644, 23.1291] },
  { keywords: ['成都', '川'], coord: [104.0665, 30.5723] },
  { keywords: ['重庆', '渝'], coord: [106.5516, 29.563] },
  { keywords: ['贵阳', '黔'], coord: [106.6302, 26.647] },
  { keywords: ['昆明', '滇'], coord: [102.8329, 24.8801] }
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
