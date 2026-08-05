import { formatWithDayjs } from '@/utils/time'

export type ArtValueFormat = 'text' | 'number' | 'money' | 'date' | 'datetime' | 'boolean'

export interface ArtValueFormatOptions {
  currency?: string
  emptyText?: string
  locale?: string
  trueText?: string
  falseText?: string
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
