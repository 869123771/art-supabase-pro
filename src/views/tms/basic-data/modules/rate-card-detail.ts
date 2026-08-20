import { formatWithDayjs } from '@/utils/time'
import { formatSensitiveNumber } from '@/utils/field-permission'

export function formatRateNumber(
  value?: number | string | null,
  maximumFractionDigits = 2
): string {
  return formatSensitiveNumber(value, { maximumFractionDigits })
}

export function formatRateMoney(value?: number | string | null): string {
  return formatSensitiveNumber(value, {
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
