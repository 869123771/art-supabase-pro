export interface WmsMaterialUnits {
  baseUnitId?: string | null
  unitConversions?: readonly {
    sourceUnitId: string
    sourceFactor: number
    baseFactor: number
  }[]
}

function baseUnitsPerUnit(material: WmsMaterialUnits, unitId: string): number | null {
  if (unitId === material.baseUnitId) return 1
  const conversion = material.unitConversions?.find((item) => item.sourceUnitId === unitId)
  if (!conversion || conversion.sourceFactor <= 0 || conversion.baseFactor <= 0) return null
  return conversion.baseFactor / conversion.sourceFactor
}

/** Return the quantity in the requested unit, or null when the material lacks a valid conversion. */
export function convertWmsMaterialQuantity(
  material: WmsMaterialUnits,
  quantity: number,
  fromUnitId: string,
  toUnitId: string
): number | null {
  if (!material.baseUnitId || !Number.isFinite(quantity) || quantity < 0) return null
  const sourceFactor = baseUnitsPerUnit(material, fromUnitId)
  const targetFactor = baseUnitsPerUnit(material, toUnitId)
  if (sourceFactor === null || targetFactor === null) return null
  return Math.round((quantity * sourceFactor * 1_000_000) / targetFactor) / 1_000_000
}
