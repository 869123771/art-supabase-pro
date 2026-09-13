/**
 * Normalize text for a database column that does not accept NULL.
 * Blank form values remain an empty string so an explicit payload cannot bypass the column default.
 */
export function normalizeNonNullableText(value: string | null | undefined): string {
  return value?.trim() ?? ''
}

/** Normalize text for a database column where blank input means NULL. */
export function normalizeNullableText(value: string | null | undefined): string | null {
  return normalizeNonNullableText(value) || null
}

/** Normalize a form value into a finite number, using NULL for blank or invalid input. */
export function normalizeNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : null
}

/** Normalize one or many select keys into the string array used by multi-select models. */
export function normalizeStringList(value: unknown | readonly unknown[]): string[] {
  return (Array.isArray(value) ? value : value == null ? [] : [value]).map(String)
}
