import { isNil } from 'lodash-es'
import { formatWithDayjs } from '@/utils/time'

export function formatRateNumber(
  value?: number | string | null,
  maximumFractionDigits = 2
): string {
  if (isNil(value) || value === '' || Number.isNaN(Number(value))) return '--'
  return Number(value).toLocaleString('zh-CN', { maximumFractionDigits })
}

export function formatRateMoney(value?: number | string | null): string {
  if (isNil(value) || value === '' || Number.isNaN(Number(value))) return '--'
  return Number(value).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })
}

export function formatRateDateTime(value?: string | null): string {
  return value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '--') : '--'
}

export function formatRateAddress(region?: string | null, address?: string | null): string {
  return [region, address].filter(Boolean).join(' ') || '--'
}
