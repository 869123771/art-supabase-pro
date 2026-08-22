import dayjs from 'dayjs'
import { isEmpty, isNil } from 'lodash-es'
import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
import type { InfoItem } from './types'

export const EMPTY_TEXT = '--'

export const formatValue = (value?: unknown, suffix = ''): string => {
  if (isNil(value) || value === '') return EMPTY_TEXT
  if (Array.isArray(value) && isEmpty(value)) return EMPTY_TEXT
  return `${value}${suffix}`
}

export const formatDate = (value?: string | null): string => {
  if (isNil(value) || value === '') return EMPTY_TEXT
  return dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD') : EMPTY_TEXT
}

export const formatDateTime = (value?: string | null): string => {
  if (isNil(value) || value === '') return EMPTY_TEXT
  return dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD HH:mm:ss') : EMPTY_TEXT
}

export const formatMileage = (value?: number | null): string => {
  if (isNil(value)) return EMPTY_TEXT
  return `${Number(value).toLocaleString()}公里`
}

export const formatNumber = (value?: number | null, suffix = ''): string => {
  if (isNil(value)) return EMPTY_TEXT
  return `${Number(value).toLocaleString()}${suffix}`
}

export const formatMoney = (value?: number | null): string => {
  if (isNil(value)) return EMPTY_TEXT
  return Number(value).toFixed(1)
}

export const formatBoolean = (value?: boolean | null): string => {
  if (isNil(value)) return EMPTY_TEXT
  return value ? '是' : '否'
}

export const toFiniteNumber = (value?: number | string | null): number | null => {
  if (isNil(value) || value === '') return null
  const numericValue = Number(value)
  return Number.isFinite(numericValue) ? numericValue : null
}

export const createDescriptionItems = (items: InfoItem[]): ArtDescriptionItem[] =>
  items.map((item, index) => ({
    key: `${item.label}-${index}`,
    label: item.label,
    value: item.value,
    dictCode: item.dictCode,
    formatter: item.dictCode ? undefined : () => formatValue(item.value, item.suffix)
  }))

export const getLatestByDate = <TRecord>(
  records: TRecord[],
  getDate: (record: TRecord) => string | null | undefined
): TRecord | undefined =>
  [...records].sort((first, second) => {
    const firstDate = getDate(first)
    const secondDate = getDate(second)
    const firstTime = firstDate && dayjs(firstDate).isValid() ? dayjs(firstDate).valueOf() : 0
    const secondTime = secondDate && dayjs(secondDate).isValid() ? dayjs(secondDate).valueOf() : 0
    return secondTime - firstTime
  })[0]

export const getExpireDateByYears = (
  startDate?: string | null,
  years?: number | null
): string | null => {
  if (isNil(startDate) || startDate === '' || isNil(years)) return null
  if (!dayjs(startDate).isValid()) return null
  return dayjs(startDate).add(years, 'year').format('YYYY-MM-DD')
}
