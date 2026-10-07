import { normalizeNullableNumber } from '@/utils/form/normalize'

/** Validate every row before looking up materials or changing the current draft. */
export function readWmsDocumentImportRows(rows: Array<Record<string, unknown>>) {
  if (!rows.length || rows.length > 500)
    throw new Error('请选择包含 1 至 500 行明细的文件；必填列为物料编码、数量')
  return rows.map((row, index) => {
    const fileRow = index + 2
    const code = String(row['物料编码'] ?? row.materialCode ?? '').trim()
    if (!code) throw new Error(`第 ${fileRow} 行请填写物料编码`)
    return { row, code, fileRow, amounts: readWmsDocumentImportAmounts(row, fileRow) }
  })
}

/** Sales and purchase imports enter positive quantities; return direction belongs to the document. */
export function readWmsDocumentImportAmounts(row: Record<string, unknown>, fileRow: number) {
  const quantity = normalizeNullableNumber(row['数量'] ?? row.quantity)
  const unitPrice = normalizeNullableNumber(row['单价(元)'] ?? row.unitPrice ?? 0)
  const taxRate = normalizeNullableNumber(row['税率(%)'] ?? row.taxRate ?? 13)
  if (quantity === null || quantity <= 0) throw new Error(`第 ${fileRow} 行数量必须为大于零的数字`)
  if (unitPrice === null || unitPrice < 0)
    throw new Error(`第 ${fileRow} 行单价必须为不小于零的数字`)
  if (taxRate === null || taxRate < 0 || taxRate > 100)
    throw new Error(`第 ${fileRow} 行税率必须为 0 至 100 的数字`)
  return { quantity, unitPrice, taxRate }
}
