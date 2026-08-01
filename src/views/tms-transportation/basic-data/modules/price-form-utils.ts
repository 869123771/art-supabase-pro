import { differenceBy, round, sumBy, toNumber as lodashToNumber, uniqBy } from 'lodash-es'

type NumericValue = number | string | null | undefined

export interface PriceCargoMetrics {
  quantity?: NumericValue
  volumeM3?: NumericValue
  weightKg?: NumericValue
}

export interface CargoSummary {
  quantity: number
  volume: number
  weight: number
}

export interface NamedCargo {
  cargoName?: string | null
}

export interface MergeCargoSelectionsResult<TItem> {
  items: TItem[]
  addedCount: number
}

export function getResponseData<TRecord>(result: unknown): TRecord[] {
  if (!result || typeof result !== 'object') return []
  const data = (result as { data?: unknown }).data
  return Array.isArray(data) ? (data as TRecord[]) : []
}

export function toNumber(value: NumericValue): number {
  const numberValue = lodashToNumber(value ?? 0)
  return Number.isNaN(numberValue) ? 0 : numberValue
}

export function roundNumber(value: number, precision = 2): number {
  return round(value, precision)
}

export function calculateCargoSummary(items: readonly PriceCargoMetrics[]): CargoSummary {
  return {
    quantity: roundNumber(
      sumBy(items, (item) => toNumber(item.quantity)),
      2
    ),
    volume: roundNumber(
      sumBy(items, (item) => toNumber(item.volumeM3)),
      3
    ),
    weight: roundNumber(
      sumBy(items, (item) => toNumber(item.weightKg)),
      2
    )
  }
}

export function mergeCargoSelections<TItem extends NamedCargo, TSelection extends NamedCargo>(
  currentItems: readonly TItem[],
  selectedCargoes: readonly TSelection[],
  createItem: (cargo: TSelection) => TItem,
  isPlaceholder: (item: TItem) => boolean = (item) => !normalizeRequiredText(item.cargoName)
): MergeCargoSelectionsResult<TItem> {
  const cargoNameKey = (item: NamedCargo): string => normalizeRequiredText(item.cargoName)
  const uniqueSelections = uniqBy(selectedCargoes.filter(cargoNameKey), cargoNameKey)
  const additions = differenceBy(uniqueSelections, currentItems, cargoNameKey).map(createItem)

  if (!additions.length) {
    return { items: [...currentItems], addedCount: 0 }
  }

  const shouldReplacePlaceholder = currentItems.length === 1 && isPlaceholder(currentItems[0])
  return {
    items: shouldReplacePlaceholder ? additions : [...currentItems, ...additions],
    addedCount: additions.length
  }
}

export function formatNumber(value: NumericValue, precision = 2): string {
  const numberValue = lodashToNumber(value ?? 0)
  if (Number.isNaN(numberValue)) return '0'
  return numberValue
    .toFixed(precision)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*?)0+$/, '$1')
}

export function splitRegionPath(region?: string | null): string[] {
  return String(region ?? '')
    .split('/')
    .map((item) => item.trim())
    .filter(Boolean)
}

export function joinRegionPath(regionPath?: readonly string[]): string {
  return (regionPath ?? []).filter(Boolean).join('/')
}

export function normalizeText(value?: string | null): string | null {
  const text = String(value ?? '').trim()
  return text || null
}

export function normalizeRequiredText(value?: string | null): string {
  return String(value ?? '').trim()
}

export function normalizeNullableNumber(value: NumericValue): number | null {
  if (value === null || value === undefined || value === '') return null
  const numberValue = lodashToNumber(value)
  return Number.isNaN(numberValue) ? null : numberValue
}

export function normalizeMoney(value: NumericValue): number {
  return roundNumber(normalizeNullableNumber(value) ?? 0, 2)
}
