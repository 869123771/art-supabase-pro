import { formatWithDayjs, isValidDateTimeValue } from '@/utils/time'

export type ArtValueFormat = 'text' | 'number' | 'money' | 'date' | 'datetime' | 'boolean'

export interface ArtValueFormatOptions {
  currency?: string
  emptyText?: string
  locale?: string
  trueText?: string
  falseText?: string
}

export interface DateTimeValueFormatOptions {
  emptyText?: string
  format?: string
  invalidText?: string
  timezone?: string
}

export interface PercentValueFormatOptions {
  emptyText?: string
  fractionDigits?: number
}

const isEmptyValue = (value: unknown): boolean =>
  value === undefined || value === null || value === ''

export function formatNumberValue(value: unknown, locale = 'zh-CN'): string {
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue.toLocaleString(locale) : String(value)
}

export function formatCurrencyValue(value: unknown, currency = 'CNY', locale = 'zh-CN'): string {
  const numberValue = Number(value)
  if (!Number.isFinite(numberValue)) return String(value)

  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(numberValue)
}

/** Format CNY values with the application-wide currency style; blank AI values mean zero. */
export function formatCnyCurrencyValue(value: unknown): string {
  return formatCurrencyValue(value ?? 0)
}

export function formatPercentValue(
  value: unknown,
  options: PercentValueFormatOptions = {}
): string {
  const emptyText = options.emptyText ?? '--'
  if (isEmptyValue(value)) return emptyText
  const numberValue = Number(value)
  if (!Number.isFinite(numberValue)) return String(value)
  return `${numberValue.toFixed(options.fractionDigits ?? 1)}%`
}

export function formatDateTimeValue(
  value: string | Date | null | undefined,
  options: DateTimeValueFormatOptions = {}
): string {
  const emptyText = options.emptyText ?? '--'
  if (value == null || value === '') return emptyText
  if (options.invalidText !== undefined && !isValidDateTimeValue(value)) {
    return options.invalidText
  }
  return (
    formatWithDayjs(value, options.format ?? 'YYYY-MM-DD HH:mm:ss', options.timezone) ?? emptyText
  )
}

/** Create a view formatter while keeping date parsing and invalid-value policy centralized. */
export function createDateTimeFormatter(options: DateTimeValueFormatOptions = {}) {
  return (value: string | Date | null | undefined): string => formatDateTimeValue(value, options)
}

export function formatArtValue(
  value: unknown,
  format: ArtValueFormat = 'text',
  options: ArtValueFormatOptions = {}
): string {
  const emptyText = options.emptyText ?? '--'
  if (isEmptyValue(value)) return emptyText

  switch (format) {
    case 'number':
      return formatNumberValue(value, options.locale)
    case 'money':
      return formatCurrencyValue(value, options.currency, options.locale)
    case 'date':
      return formatWithDayjs(String(value), 'YYYY-MM-DD') ?? emptyText
    case 'datetime':
      return formatWithDayjs(String(value), 'YYYY-MM-DD HH:mm:ss') ?? emptyText
    case 'boolean':
      return value ? (options.trueText ?? '是') : (options.falseText ?? '否')
    default:
      return String(value)
  }
}
