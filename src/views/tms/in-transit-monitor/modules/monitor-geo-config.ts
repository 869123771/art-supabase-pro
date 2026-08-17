import type { GeoCoord, StationGeoPosition } from './monitor-types'

export const INITIAL_MAP_CENTER: GeoCoord = [105.5, 34.2]

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
