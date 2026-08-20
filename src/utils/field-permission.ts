export type FieldAccessLevel = 'hidden' | 'masked' | 'read' | 'edit'

export type FieldAccessMap<TKey extends string = string> = Partial<Record<TKey, FieldAccessLevel>>

const MASK_PLACEHOLDER = '***'
const FIELD_ACCESS_RANK: Record<FieldAccessLevel, number> = {
  hidden: 0,
  masked: 1,
  read: 2,
  edit: 3
}

export const mergeFieldAccessMaps = <TKey extends string>(
  ...maps: Array<FieldAccessMap<TKey> | null | undefined>
): FieldAccessMap<TKey> => {
  const result: FieldAccessMap<TKey> = {}
  maps.forEach((access) => {
    if (!access) return
    ;(Object.entries(access) as Array<[TKey, FieldAccessLevel]>).forEach(([key, level]) => {
      const current = result[key]
      if (!current || FIELD_ACCESS_RANK[level] > FIELD_ACCESS_RANK[current]) {
        result[key] = level
      }
    })
  })
  return result
}

export const getFieldAccess = <TKey extends string>(
  access: FieldAccessMap<TKey> | null | undefined,
  field: TKey,
  fallback: FieldAccessLevel = 'hidden'
): FieldAccessLevel => access?.[field] ?? fallback

export const canViewField = <TKey extends string>(
  access: FieldAccessMap<TKey> | null | undefined,
  field: TKey,
  fallback: FieldAccessLevel = 'hidden'
): boolean => getFieldAccess(access, field, fallback) !== 'hidden'

export const canEditField = <TKey extends string>(
  access: FieldAccessMap<TKey> | null | undefined,
  field: TKey,
  fallback: FieldAccessLevel = 'hidden'
): boolean => getFieldAccess(access, field, fallback) === 'edit'

export const isMaskedValue = (value: unknown): value is string =>
  typeof value === 'string' && value.trim() === MASK_PLACEHOLDER

export const formatSensitiveNumber = (
  value: number | string | null | undefined,
  options: Intl.NumberFormatOptions = { minimumFractionDigits: 2, maximumFractionDigits: 2 }
): string => {
  if (value === null || value === undefined) return '--'
  if (typeof value === 'string') {
    if (!value.trim()) return '--'
    if (isMaskedValue(value)) return MASK_PLACEHOLDER
  }
  const numericValue = Number(value)
  if (!Number.isFinite(numericValue)) return '--'
  return numericValue.toLocaleString('zh-CN', options)
}

export const omitNonEditableFields = <
  TRecord extends Record<string, unknown>,
  TKey extends Extract<keyof TRecord, string>
>(
  record: TRecord,
  access: FieldAccessMap<TKey> | null | undefined,
  fields: readonly TKey[],
  fallback: FieldAccessLevel = 'hidden'
): TRecord => {
  const result = { ...record }
  fields.forEach((field) => {
    if (!canEditField(access, field, fallback)) delete result[field]
  })
  return result
}
